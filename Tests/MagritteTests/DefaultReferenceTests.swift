import Foundation
import Magritte
import XCTest

private final class ReferenceContainerOverride: Description {
  var calls = 0
  override func descriptionContainer() throws -> Description {
    calls += 1
    return Description(id: "custom.container", className: "MAContainer")
  }
}
final class DefaultReferenceTests: XCTestCase {
  func node(_ id: String, _ cls: String = "MAStringDescription") -> Description {
    Description(id: id, className: cls, key: id)
  }
  func fixture() throws -> [String: Any] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "default-reference-scenarios", withExtension: "json", subdirectory: "Fixtures")
    )
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }
  func register(_ data: [String: Any]) throws {
    for row in try XCTUnwrap(data["cases"] as? [[String: Any]]) {
      let name = try XCTUnwrap(row["className"] as? String)
      let base = try XCTUnwrap(row["base"] as? String)
      if name != base {
        try ClassRegistry.shared.registerClass(
          ClassInfo(name: name, superclass: base, label: "Child"))
      }
    }
    for row in try XCTUnwrap(data["classes"] as? [[String: String]]) {
      try ClassRegistry.shared.registerClass(
        ClassInfo(name: row["name"]!, superclass: row["superclass"]!, label: row["label"]!))
    }
  }
  func testSharedDefaultAndRelationSemantics() throws {
    let data = try fixture()
    try register(data)
    for r in try XCTUnwrap(data["cases"] as? [[String: Any]]) {
      let d = node("owner", try XCTUnwrap(r["className"] as? String))
      XCTAssertNil(d.reference)
      if r["self"] as? Bool == true {
        d.display("asString")
        XCTAssertTrue(try d.referenceDescription() === d)
        XCTAssertNil(d.reference)
        let copy = try copyDescription(d, newID: "boolean.copy")
        XCTAssertTrue(try copy.root.referenceDescription() === copy.root)
        continue
      }
      let copy = try copyDescription(d, newID: "uninitialized.copy")
      XCTAssertNil(d.reference)
      XCTAssertNil(copy.root.reference)
      d.display("asString")
      var ref: Description? = try d.referenceDescription()
      XCTAssertEqual(ref?.className, "MAStringDescription")
      XCTAssertFalse(try XCTUnwrap(ref).id.isEmpty)
      XCTAssertTrue(try d.referenceDescription() === ref)
      XCTAssertEqual(try ref?.property("displayBlockOrSymbol"), .symbol("asString"))
      try d.setReference(ref)
      weak var weak = ref
      ref = nil
      XCTAssertNotNil(weak)
      var original = weak
      original?.properties["label"] = .string("Kept")
      var copied: Description!
      do {
        let result = try copyDescription(d, newID: "materialized.copy")
        copied = result.root
      }
      let child = try XCTUnwrap(copied.reference)
      XCTAssertFalse(child === original)
      XCTAssertEqual(try child.property("label"), .string("Kept"))
      let isolated = try copy.root.referenceDescription()
      XCTAssertFalse(isolated === original)
      XCTAssertNotEqual(isolated.id, original?.id)
      var old = original
      try d.setReference(nil)
      XCTAssertNil(d.reference)
      let fresh = try d.referenceDescription()
      XCTAssertFalse(fresh === old)
      XCTAssertNotEqual(fresh.id, old?.id)
      old = nil
      original = nil
      XCTAssertNil(weak)
      var explicit: Description? = node("explicit")
      try d.setReference(explicit)
      XCTAssertTrue(try d.referenceDescription() === explicit)
      explicit = nil
      XCTAssertThrowsError(try d.referenceDescription())
      try d.setReference(nil)
      if d.isOption {
        try d.setUndefined(.string("missing"))
        XCTAssertEqual(try d.referenceDescription().property("undefined"), .string("missing"))
      }
    }
    var boolean: Description? = node("boolean", "MABooleanDescription")
    weak var weak = boolean
    var selfReference: Description? = try boolean?.referenceDescription()
    boolean = nil
    XCTAssertNotNil(weak)
    XCTAssertNotNil(selfReference)
    selfReference = nil
    XCTAssertNil(weak)
    XCTAssertThrowsError(try node("unsupported").referenceDescription())
    for r in try XCTUnwrap(data["relations"] as? [[String: Any]]) {
      let relation = node("relation", "MAToManyRelationDescription")
      relation.classes = try XCTUnwrap(r["classes"] as? [String])
      let before = relation.classes
      XCTAssertEqual(try relation.allClasses(), try XCTUnwrap(r["ordered"] as? [String]))
      XCTAssertEqual(relation.classes, before)
      switch try relation.commonClass() {
      case .classValue(let name): XCTAssertEqual(name, r["common"] as? String)
      case .container(let container):
        XCTAssertTrue(r["common"] is NSNull)
        XCTAssertEqual(container.className, "MAPriorityContainer")
        XCTAssertTrue(container.children.isEmpty)
        XCTAssertEqual(try container.property("label"), .string("1:m Relation"))
        if case .container(let again) = try relation.commonClass() {
          XCTAssertFalse(again === container)
        } else {
          XCTFail("Expected container")
        }
      }
      XCTAssertEqual(try relation.referenceDescription().className, "MAStringDescription")
    }
    let custom = ReferenceContainerOverride(id: "custom", className: "MAToOneRelationDescription")
    if case .container(let result) = try custom.commonClass() {
      XCTAssertEqual(result.id, "custom.container")
      XCTAssertEqual(custom.calls, 1)
    } else {
      XCTFail("Expected custom container")
    }
    let bad = node("bad", "MAToOneRelationDescription")
    bad.classes = ["UnknownRefClass"]
    XCTAssertThrowsError(try bad.allClasses())
    XCTAssertThrowsError(try bad.commonClass())
  }
  func testConsumersMetadataAndInterchange() throws {
    let data = try fixture()
    try register(data)
    let option = node("option", "DefaultChildSingleOptionDescription")
    option.options = [.string("Ada")]
    XCTAssertTrue(try Magritte.validateValue(.string("Ada"), using: option).isEmpty)
    XCTAssertNil(option.reference)
    option.properties["extensible"] = .boolean(true)
    XCTAssertTrue(try Magritte.validateValue(.string("new"), using: option).isEmpty)
    XCTAssertNotNil(option.reference)
    XCTAssertEqual(
      try readString("a,b", using: node("token", "MATokenDescription")),
      .array([.string("a"), .string("b")]))
    let session = RecursiveDescriptionModel()
    let target = node("target", "MAToOneRelationDescription")
    let schema = try session.describeReflective(target)
    let binding = try session.bind(target)
    let field = try XCTUnwrap(session.resolver.descriptions[schema.id + ".reference"])
    XCTAssertTrue(try binding.respondsToSelector("allClasses"))
    XCTAssertEqual(
      try binding.readSlot(strategy: "MASelectorAccessor", name: "allClasses"), .array([]))
    if case .reference = try binding.readSlot(strategy: "MASelectorAccessor", name: "commonClass") {
    } else {
      XCTFail("Expected container binding")
    }
    let booleanBinding = try session.bind(node("bound.boolean", "MABooleanDescription"))
    XCTAssertEqual(
      try booleanBinding.readSlot(strategy: "MASelectorAccessor", name: "reference"),
      .reference("bound.boolean"))
    let first = try binding.read(using: field)
    XCTAssertNotNil(target.reference)
    try binding.write(.undefined, using: field)
    XCTAssertNil(target.reference)
    let second = try binding.read(using: field)
    XCTAssertNotEqual(first, second)
    if case .reference(let id) = second {
      XCTAssertNotNil(session.resolver.nativeObjects[id])
    } else {
      XCTFail("Expected reference")
    }
    let root = node("root", "MAContainer")
    let unset = node("unset", "MAToOneRelationDescription")
    unset.classes = ["String"]
    let selected = node("selected", "DefaultChildSingleOptionDescription")
    selected.options = [.string("Ada")]
    let generated = try selected.referenceDescription()
    generated.id = "generated"
    generated.accessor = Accessor(className: "MANullAccessor")
    let flag = node("flag", "DefaultChildBooleanDescription")
    XCTAssertTrue(try flag.referenceDescription() === flag)
    root.children = [unset, selected, flag]
    let graph = Graph(
      root: "root",
      descriptions: [
        "root": root, "unset": unset, "selected": selected, "generated": generated, "flag": flag,
      ])
    graph.format = "magritte.graph/4"
    let wire = try graph.encode()
    XCTAssertNil(unset.reference)
    let decoded = try Graph.decode(wire)
    XCTAssertNil(decoded.descriptions["unset"]?.reference)
    XCTAssertEqual(
      try decoded.descriptions["unset"]?.referenceDescription().className, "MAStringDescription")
    let copied = try copyDescription(unset, newID: "nil.copy")
    XCTAssertNil(unset.reference)
    XCTAssertNil(copied.root.reference)
    for format in ["magritte.graph/1", "magritte.graph/2", "magritte.graph/3"] {
      graph.format = format
      XCTAssertThrowsError(try graph.encode())
    }
    graph.format = "magritte.graph/4"
    graph.descriptions.removeValue(forKey: "generated")
    XCTAssertThrowsError(try graph.encode())
    graph.descriptions["generated"] = generated
    let plain = node("canonical", "MAContainer")
    plain.children = [unset]
    let canonical = Graph(root: "canonical", descriptions: ["canonical": plain, "unset": unset])
    canonical.format = "magritte.graph/4"
    var nullable = try XCTUnwrap(
      JSONSerialization.jsonObject(with: canonical.encode()) as? [String: Any])
    nullable["format"] = "magritte.graph/3"
    XCTAssertThrowsError(try Graph.decode(JSONSerialization.data(withJSONObject: nullable)))
    let relation = node("limited", "MAToOneRelationDescription")
    relation.classes = ["RefLeft", "RefRight"]
    var low = Limits()
    low.items = 1
    XCTAssertThrowsError(try relation.allClasses(limits: low))
    low = Limits()
    low.bytes = 1
    XCTAssertThrowsError(try relation.allClasses(limits: low))
    let callback = node("callback", "MASingleOptionDescription")
    callback.display(DisplayBlock { "local" })
    plain.children = [callback]
    canonical.descriptions = ["canonical": plain, "callback": callback]
    XCTAssertThrowsError(try canonical.encode())
    XCTAssertNil(callback.reference)
    let propagated = try callback.referenceDescription()
    XCTAssertTrue(propagated.displayBlock === callback.displayBlock)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_DEFAULT_REFERENCE_OUTPUT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_DEFAULT_REFERENCE_INPUT"] {
      let peer = try Graph.decode(Data(contentsOf: URL(fileURLWithPath: path)))
      XCTAssertEqual(
        try JSONSerialization.jsonObject(with: peer.encode()) as? NSDictionary,
        try JSONSerialization.jsonObject(with: wire) as? NSDictionary)
    }
  }
}
