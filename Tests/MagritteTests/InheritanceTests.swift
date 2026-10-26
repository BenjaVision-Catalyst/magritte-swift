import Foundation
import Magritte
import XCTest

private final class InheritanceVisitor: Visitor {
  var dispatch = ""
  override func visitContainer(_ d: Description) throws { dispatch = "visitContainer" }
  override func visitPriorityContainer(_ d: Description) throws {
    dispatch = "visitPriorityContainer"
  }
  override func visitStringDescription(_ d: Description) throws {
    dispatch = "visitStringDescription"
  }
  override func visitSymbolDescription(_ d: Description) throws {
    dispatch = "visitSymbolDescription"
  }
  override func visitMemoDescription(_ d: Description) throws { dispatch = "visitMemoDescription" }
  override func visitPasswordDescription(_ d: Description) throws {
    dispatch = "visitPasswordDescription"
  }
  override func visitTokenDescription(_ d: Description) throws {
    dispatch = "visitTokenDescription"
  }
  override func visitNumberDescription(_ d: Description) throws {
    dispatch = "visitNumberDescription"
  }
  override func visitBooleanDescription(_ d: Description) throws {
    dispatch = "visitBooleanDescription"
  }
  override func visitToOneRelationDescription(_ d: Description) throws {
    dispatch = "visitToOneRelationDescription"
  }
  override func visitToManyRelationDescription(_ d: Description) throws {
    dispatch = "visitToManyRelationDescription"
  }
  override func visitToManyScalarRelationDescription(_ d: Description) throws {
    dispatch = "visitToManyScalarRelationDescription"
  }
  override func visitSingleOptionDescription(_ d: Description) throws {
    dispatch = "visitSingleOptionDescription"
  }
  override func visitMultipleOptionDescription(_ d: Description) throws {
    dispatch = "visitMultipleOptionDescription"
  }
  override func visitClassDescription(_ d: Description) throws {
    dispatch = "visitClassDescription"
  }
}
final class InheritanceTests: XCTestCase {
  func text(_ row: [String: Any], _ key: String) throws -> String {
    try XCTUnwrap(row[key] as? String)
  }
  func value(_ raw: Any?) throws -> Value {
    try decodeValue(JSONSerialization.data(withJSONObject: XCTUnwrap(raw)))
  }
  func families() throws -> [[String: Any]] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "inheritance-scenarios", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let rows = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
    var definitions: [ClassInfo] = []
    for r in rows {
      definitions.append(
        ClassInfo(
          name: try text(r, "middle"), superclass: try text(r, "base"), isAbstract: true,
          label: try text(r, "label")))
      definitions.append(
        ClassInfo(
          name: try text(r, "name"), superclass: try text(r, "middle"), label: try text(r, "label"))
      )
    }
    try ClassRegistry.shared.registerClasses(definitions)
    return rows
  }
  func testFamiliesAndInterchange() throws {
    let rows = try families()
    let root = Description(id: "root", className: "MAContainer")
    let graph = Graph(root: "root", descriptions: ["root": root])
    graph.format = "magritte.graph/4"
    for r in rows {
      let name = try text(r, "name")
      let base = try text(r, "base")
      let d = Description(id: name, className: name, key: name)
      for (key, raw) in try XCTUnwrap(r["properties"] as? [String: Any]) {
        d.properties[key] = try value(raw)
      }
      for (key, actual) in [
        ("container", d.isContainer), ("relation", d.isRelation), ("option", d.isOption),
        ("reference", d.isReference), ("multiple", d.isMultiple), ("sortable", d.isSortable),
      ] {
        XCTAssertEqual(actual, try XCTUnwrap(r[key] as? Bool), name + ":" + key)
      }
      XCTAssertEqual(try d.property("kind"), .classValue(try text(r, "kind")))
      XCTAssertEqual(try d.property("visible"), .boolean(true))
      XCTAssertEqual(try d.property("required"), .boolean(false))
      XCTAssertEqual(try d.property("shouldCacheDefault"), .boolean(d.isRelation && d.isMultiple))
      if d.isReference {
        let ref = Description(id: name + ".reference", key: name + ".reference")
        d.reference = ref
        graph.descriptions[ref.id] = ref
      }
      if d.isRelation { d.classes = ["String"] }
      if d.isOption { d.options = [.string("Ada"), .string("Bob")] }
      if base == "MASingleOptionDescription" {
        d.options = [.symbol("Ada"), .symbol("Bob")]
        d.labels = [(.symbol("Ada"), "Name")]
        d.reference?.className = "MASymbolDescription"
      }
      graph.descriptions[name] = d
      root.children.append(d)
      let sample = try value(r["sample"])
      XCTAssertTrue(try Magritte.validateValue(sample, using: d).isEmpty, name)
      if !(r["invalid"] is NSNull) {
        XCTAssertEqual(
          try Magritte.validateValue(value(r["invalid"]), using: d).map(\.code), ["MAKindError"])
      }
      XCTAssertEqual(try writeString(sample, using: d), try text(r, "output"))
      if let input = r["input"] as? String {
        XCTAssertEqual(try readString(input, using: d), sample)
      } else {
        XCTAssertThrowsError(try readString("nonempty", using: d))
      }
      let visitor = InheritanceVisitor()
      try d.acceptMagritte(visitor)
      XCTAssertEqual(visitor.dispatch, try text(r, "visitor"))
      let meta = try descriptionModelFor(d)
      for key in try XCTUnwrap(r["metadataFields"] as? [String]) {
        XCTAssertNotNil(meta.descriptions[meta.root + "." + key])
      }
      if base == "MABooleanDescription" { XCTAssertNil(meta.descriptions[meta.root + ".required"]) }
      let session = RecursiveDescriptionModel()
      let schema = try session.describeReflective(d)
      let model = try session.bind(d)
      for key in try XCTUnwrap(r["metadataFields"] as? [String]) {
        let field = try XCTUnwrap(session.resolver.descriptions[schema.id + "." + key])
        XCTAssertEqual(try model.read(using: field), try d.property(key))
      }
      if !d.isContainer && !d.isOption {
        XCTAssertEqual(meta.descriptions[meta.root + ".default"]?.className, name)
      }
      let type = try XCTUnwrap(session.resolver.descriptions[schema.id + ".type"])
      XCTAssertEqual(try model.read(using: type), .string(try text(r, "label")))
      let label = try XCTUnwrap(session.resolver.descriptions[schema.id + ".label"])
      try model.write(.string("Edited"), using: label)
      XCTAssertEqual(try d.property("label"), .string("Edited"))
      XCTAssertFalse(try session.bootstrap(d).descriptions.isEmpty)
      let copied = try copyDescription(d, newID: "copy." + name)
      XCTAssertEqual(copied.root.className, name)
      XCTAssertTrue(try descriptionEqual(copied.root, d))
      copied.root.className = base
      XCTAssertFalse(try descriptionEqual(copied.root, d))
    }
    let number = try XCTUnwrap(graph.descriptions["InheritedNumberDescription"])
    XCTAssertEqual(
      try Magritte.validateValue(.integer(11), using: number).map(\.code), ["MARangeError"])
    number.portableConditions = [
      PortableCondition(label: "integer", predicate: Predicate(selector: "isInteger"))
    ]
    XCTAssertEqual(
      try Magritte.validateValue(.float(5.5), using: number).map(\.code), ["MAConditionError"])
    number.portableConditions = []
    try ClassRegistry.shared.registerClass(
      ClassInfo(name: "InheritedNumberLeaf", superclass: number.className, label: "Host number"))
    let leaf = try copyDescription(number, newID: "number.leaf").root
    leaf.className = "InheritedNumberLeaf"
    leaf.properties["kind"] = .classValue("Integer")
    leaf.properties["min"] = .integer(5)
    XCTAssertEqual(
      try Magritte.validateValue(.integer(4), using: leaf).map(\.code), ["MARangeError"])
    XCTAssertEqual(
      try Magritte.validateValue(.float(5.5), using: leaf).map(\.code), ["MAKindError"])
    var calls = 0
    leaf.defaultFunction = {
      calls += 1
      return .integer(8)
    }
    XCTAssertEqual(try leaf.defaultValue(), .integer(8))
    XCTAssertEqual(calls, 1)
    let localRoot = Description(id: "local", className: "MAContainer")
    localRoot.children = [leaf]
    let local = Graph(root: "local", descriptions: ["local": localRoot, leaf.id: leaf])
    local.format = "magritte.graph/4"
    XCTAssertThrowsError(try local.encode())
    leaf.defaultFunction = nil
    XCTAssertEqual(
      try leaf.readSlot(strategy: "MASelectorAccessor", name: "type"), .string("Host number"))
    let priority = try XCTUnwrap(graph.descriptions["InheritedPriorityContainer"])
    let a = Description(id: "a", key: "a")
    let b = Description(id: "b", key: "b")
    a.className = "InheritedStringDescription"
    b.className = "InheritedStringDescription"
    a.properties["priority"] = .integer(2)
    b.properties["priority"] = .integer(1)
    priority.children = [a, b]
    XCTAssertTrue(try priority.orderedChildren()[0] === b)
    let model = DictionaryModel(["a": .string("A"), "b": .string("B")])
    XCTAssertTrue(try validate(model, using: priority).isEmpty)
    XCTAssertEqual(try writeString(model, using: priority), "B-A")
    let containerGraph = Graph(
      root: priority.id, descriptions: [priority.id: priority, "a": a, "b": b])
    containerGraph.format = "magritte.graph/4"
    let restoredContainer = try Graph.decode(containerGraph.encode())
    XCTAssertEqual(
      restoredContainer.descriptions[restoredContainer.root]?.className, priority.className)
    let memento = try CachedMemento(model: model, description: priority)
    try memento.write(.string("Changed"), using: a)
    try memento.commit()
    XCTAssertEqual(model.values["a"], .string("Changed"))
    priority.children = []
    let password = try XCTUnwrap(graph.descriptions["InheritedPasswordDescription"])
    XCTAssertEqual(try password.obfuscated(.string("secret")), "******")
    XCTAssertTrue(try password.isObfuscated(.string("***")))
    let boolean = try XCTUnwrap(graph.descriptions["InheritedBooleanDescription"])
    XCTAssertEqual(try boolean.labelForOption(.boolean(true)), "Yep")
    XCTAssertEqual(try boolean.allOptions().values().count, 2)
    let wire = try graph.encode()
    let imported = try Graph.decode(wire)
    for r in rows {
      let d = try XCTUnwrap(imported.descriptions[try text(r, "name")])
      XCTAssertEqual(d.className, try text(r, "name"))
      XCTAssertTrue(try Magritte.validateValue(value(r["sample"]), using: d).isEmpty)
      XCTAssertEqual(try writeString(value(r["sample"]), using: d), try text(r, "output"))
    }
    for format in ["magritte.graph/1", "magritte.graph/2", "magritte.graph/3"] {
      graph.format = format
      XCTAssertThrowsError(try graph.encode())
    }
    graph.format = "magritte.graph/4"
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_INHERITANCE_OUTPUT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_INHERITANCE_INPUT"] {
      let peer = try Graph.decode(Data(contentsOf: URL(fileURLWithPath: path)))
      XCTAssertEqual(
        try JSONSerialization.jsonObject(with: peer.encode()) as? NSDictionary,
        try JSONSerialization.jsonObject(with: wire) as? NSDictionary)
    }
  }
  func testRefusalsDoNotRegisterIncomingClasses() throws {
    _ = try families()
    let registry = ClassRegistry.shared
    try registry.registerClasses([
      ClassInfo(name: "UnimplementedDescription", superclass: "MAElementDescription"),
      ClassInfo(name: "NonDescription"),
    ])
    let names = registry.allClasses()
    for name in [
      "UnknownDescription", "UnimplementedDescription", "NonDescription",
      "InheritedAbstractStringDescription",
    ] {
      let bad = Description(id: "bad", className: name)
      XCTAssertThrowsError(try Magritte.validateValue(.undefined, using: bad))
      XCTAssertThrowsError(try descriptionModelFor(bad))
    }
    let unknown = """
      {"format":"magritte.graph/4","root":"root","descriptions":[{"id":"root","class":"WireInventedDescription","properties":{},"conditions":[],"children":[]}],"objects":[]}
      """
    XCTAssertThrowsError(try Graph.decode(Data(unknown.utf8)))
    XCTAssertEqual(registry.allClasses(), names)
  }
}
