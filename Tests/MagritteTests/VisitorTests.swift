import Foundation
import XCTest

@testable import Magritte

private class Probe: Visitor {
  var events: [[String]] = []
  var stopAt = ""
  var failAt = ""
  var recurse = false
  func record(_ name: String, _ d: Description) throws -> Bool {
    guard case .string(let label) = d.property("label") else {
      throw MagritteError("Missing label")
    }
    events.append([name, label])
    if name == failAt { throw MagritteError("visitor failure") }
    return name != stopAt
  }
  override func visitDescription(_ d: Description) throws {
    if try record("visitDescription:", d) { try super.visitDescription(d) }
  }
  override func visitContainer(_ d: Description) throws {
    if try record("visitContainer:", d) {
      try super.visitContainer(d)
      if recurse { try visitAll(d.orderedChildren()) }
    }
  }
  override func visitPriorityContainer(_ d: Description) throws {
    if try record("visitPriorityContainer:", d) { try super.visitPriorityContainer(d) }
  }
  override func visitElementDescription(_ d: Description) throws {
    if try record("visitElementDescription:", d) { try super.visitElementDescription(d) }
  }
  override func visitBooleanDescription(_ d: Description) throws {
    if try record("visitBooleanDescription:", d) { try super.visitBooleanDescription(d) }
  }
  override func visitClassDescription(_ d: Description) throws {
    if try record("visitClassDescription:", d) { try super.visitClassDescription(d) }
  }
  override func visitStringDescription(_ d: Description) throws {
    if try record("visitStringDescription:", d) { try super.visitStringDescription(d) }
  }
  override func visitMemoDescription(_ d: Description) throws {
    if try record("visitMemoDescription:", d) { try super.visitMemoDescription(d) }
  }
  override func visitPasswordDescription(_ d: Description) throws {
    if try record("visitPasswordDescription:", d) { try super.visitPasswordDescription(d) }
  }
  override func visitSymbolDescription(_ d: Description) throws {
    if try record("visitSymbolDescription:", d) { try super.visitSymbolDescription(d) }
  }
  override func visitMagnitudeDescription(_ d: Description) throws {
    if try record("visitMagnitudeDescription:", d) { try super.visitMagnitudeDescription(d) }
  }
  override func visitNumberDescription(_ d: Description) throws {
    if try record("visitNumberDescription:", d) { try super.visitNumberDescription(d) }
  }
  override func visitReferenceDescription(_ d: Description) throws {
    if try record("visitReferenceDescription:", d) { try super.visitReferenceDescription(d) }
  }
  override func visitTokenDescription(_ d: Description) throws {
    if try record("visitTokenDescription:", d) { try super.visitTokenDescription(d) }
  }
  override func visitOptionDescription(_ d: Description) throws {
    if try record("visitOptionDescription:", d) { try super.visitOptionDescription(d) }
  }
  override func visitSingleOptionDescription(_ d: Description) throws {
    if try record("visitSingleOptionDescription:", d) { try super.visitSingleOptionDescription(d) }
  }
  override func visitMultipleOptionDescription(_ d: Description) throws {
    if try record("visitMultipleOptionDescription:", d) {
      try super.visitMultipleOptionDescription(d)
    }
  }
  override func visitRelationDescription(_ d: Description) throws {
    if try record("visitRelationDescription:", d) { try super.visitRelationDescription(d) }
  }
  override func visitToOneRelationDescription(_ d: Description) throws {
    if try record("visitToOneRelationDescription:", d) {
      try super.visitToOneRelationDescription(d)
    }
  }
  override func visitToManyRelationDescription(_ d: Description) throws {
    if try record("visitToManyRelationDescription:", d) {
      try super.visitToManyRelationDescription(d)
    }
  }
  override func visitToManyScalarRelationDescription(_ d: Description) throws {
    if try record("visitToManyScalarRelationDescription:", d) {
      try super.visitToManyScalarRelationDescription(d)
    }
  }
}
private class Builder: DescriptionBuilder {
  var events: [String] = []
  var fail = false
  override func visitStringDescription(_ d: Description) throws {
    guard case .string(let label) = d.property("label") else {
      throw MagritteError("Missing label")
    }
    events.append(label)
    if fail { throw MagritteError("builder failure") }
    d.properties["label"] = .string("Built " + label)
    try super.visitStringDescription(d)
  }
}
final class VisitorTests: XCTestCase {
  struct Tree {
    let root: Description
    var retained: [Description]
  }
  func object(_ j: Any?) throws -> [String: Any] { try XCTUnwrap(j as? [String: Any]) }
  func rows(_ j: Any?) throws -> [[String: Any]] { try XCTUnwrap(j as? [[String: Any]]) }
  func text(_ j: Any?) throws -> String { try XCTUnwrap(j as? String) }
  func canonical(_ j: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: j, options: .sortedKeys)
  }
  func fixture() throws -> [String: Any] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "visitor-reference", withExtension: "json", subdirectory: "Fixtures"))
    return try object(JSONSerialization.jsonObject(with: Data(contentsOf: url)))
  }
  func tree(_ j: [String: Any], _ id: String) throws -> Tree {
    let d = Description(id: id, className: try text(j["class"]), key: try text(j["key"]))
    d.properties["label"] = .string(try text(j["label"]))
    d.properties["priority"] = .integer(try XCTUnwrap(j["priority"] as? Int64))
    var owners = [d]
    for row in try rows(j["children"]) {
      let c = try tree(row, id + ".child." + String(d.children.count))
      d.children.append(c.root)
      owners += c.retained
    }
    if d.isReference {
      let reference = Description(id: id + ".reference")
      reference.properties["label"] = .string("Reference")
      reference.accessor = Accessor(className: "MANullAccessor")
      d.reference = reference
      owners.append(reference)
      if d.isOption { d.options = [.string("a"), .string("b")] }
    }
    return Tree(root: d, retained: owners)
  }
  func snapshot(_ d: Description) throws -> [String: Any] {
    let children = try d.isContainer ? d.orderedChildren().map(snapshot) : []
    guard case .string(let label) = d.property("label") else {
      throw MagritteError("Missing label")
    }
    return [
      "class": d.className, "key": try d.effectiveAccessor.name, "label": label,
      "priority": try d.priority(), "children": children,
    ]
  }
  func testDispatchAndBuilderAgainstGT() throws {
    let f = try fixture()
    for row in try rows(f["dispatch"]) {
      let d = Description(id: "dispatch", className: try text(row["class"]))
      d.properties["label"] = .string(d.className)
      let p = Probe()
      try p.visit(d)
      XCTAssertEqual(p.events, row["events"] as? [[String]], d.className)
      p.events = []
      try d.acceptMagritte(p)
      XCTAssertEqual(p.events, row["events"] as? [[String]], d.className)
    }
    let builders = try rows(f["builders"])
    let input = try tree(object(builders[0]["source"]), "source")
    input.root.children[2] = input.root.children[0]
    let a = input.root.children[0]
    let b = input.root.children[1]
    let expected = try object(f["visiting"])
    let p = Probe()
    try p.visit(input.root)
    XCTAssertEqual(p.events, expected["plainContainer"] as? [[String]])
    p.events = []
    p.recurse = true
    try p.visit(input.root)
    XCTAssertEqual(p.events, expected["recursiveContainer"] as? [[String]])
    p.events = []
    p.recurse = false
    p.stopAt = "visitStringDescription:"
    try p.visitAll([a, b, a])
    XCTAssertEqual(p.events, expected["stoppedBatch"] as? [[String]])
    a.properties["visible"] = .boolean(false)
    a.properties["readOnly"] = .boolean(true)
    p.events = []
    p.stopAt = ""
    try p.visit(a)
    XCTAssertEqual(p.events, expected["hiddenReadOnly"] as? [[String]])
    p.events = []
    p.failAt = "visitStringDescription:"
    XCTAssertThrowsError(try p.visitAll([a, b]))
    XCTAssertEqual(p.events, expected["failedBatch"] as? [[String]])
    p.failAt = ""
    p.events = []
    try p.visit(b)
    XCTAssertEqual(p.events.count, 4)
    let target = DictionaryModel()
    target.values = ["first": .string("Ada"), "second": .integer(7), "choice": .string("a")]
    let graph = Graph(root: "")
    graph.format = "magritte.graph/4"
    for row in builders {
      let name = try text(row["case"])
      let source = try tree(object(row["source"]), "source." + name)
      let builder = Builder()
      let result = try XCTUnwrap(
        builder.buildFrom(source.root, newIDPrefix: "built." + name, target: target))
      XCTAssertEqual(
        try canonical(snapshot(result.root)), try canonical(XCTUnwrap(row["result"])), name)
      XCTAssertEqual(
        try canonical(snapshot(source.root)), try canonical(XCTUnwrap(row["sourceAfter"])), name)
      XCTAssertEqual(builder.events, row["events"] as? [String])
      XCTAssertEqual(result.root === source.root, row["sameRoot"] as? Bool)
      XCTAssertTrue(builder.target === target)
      XCTAssertNil(builder.model)
      XCTAssertEqual(builder.priority, 0)
      if name == "flat" {
        graph.root = result.root.id
        XCTAssertTrue(try Magritte.validate(target, using: result.root).isEmpty)
        try target.write(.string("Augusta"), using: result.root.children[0])
        XCTAssertEqual(try target.read(using: result.root.children[2]), .string("Augusta"))
        target.values["first"] = .string("Ada")
        let sample = AdaptiveModel(id: "sample", description: result.root)
        for d in result.root.children { try sample.write(target.read(using: d), using: d) }
        XCTAssertTrue(try Magritte.validate(sample, using: result.root).isEmpty)
        let url = try XCTUnwrap(
          Bundle.module.url(
            forResource: "visitor-roundtrip-reference", withExtension: "json",
            subdirectory: "Fixtures"))
        let roundtrip = try rows(JSONSerialization.jsonObject(with: Data(contentsOf: url)))
        XCTAssertEqual(
          try writeString(sample, using: result.root),
          try text(rows(roundtrip[0]["reads"])[0]["text"]))
        graph.objects[sample.id] = sample
        try Magritte.visit(result.root) { graph.descriptions[$0.id] = $0 }
        XCTAssertTrue(
          result.root.children.allSatisfy { c in !source.root.children.contains { $0 === c } })
        XCTAssertFalse(result.root.children[0] === result.root.children[2])
        let original = source.root.children.last!
        let copied = result.root.children.last!
        XCTAssertFalse(original.reference === copied.reference)
        try copied.options.append(.string("c"))
        XCTAssertEqual(try original.options.count, 2)
        try copied.options.removeLast()
        builder.model = target
        builder.priority = 9
        let reused = try XCTUnwrap(builder.buildFrom(b, newIDPrefix: "reused"))
        XCTAssertTrue(reused.root === result.root)
        XCTAssertEqual(
          reused.root.children.count, try object(f["identity"])["reuseContainerCount"] as? Int)
        XCTAssertTrue(builder.model === target)
        XCTAssertEqual(builder.priority, 9)
        reused.root.children.removeLast()
      }
      withExtendedLifetime(source.retained) {}
    }
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_VISITOR_EXPORT"] {
      try graph.encode().write(to: URL(fileURLWithPath: path))
    }
    withExtendedLifetime(input.retained) {}
  }
  func testRegistrationLimitsStateAndOwnership() throws {
    let f = try fixture()
    let builders = try rows(f["builders"])
    let input = try tree(object(builders[0]["source"]), "source")
    let a = input.root.children[0]
    let b = input.root.children[1]
    let scalar = DescriptionBuilder()
    XCTAssertTrue(try scalar.buildFrom(a, newIDPrefix: "one")?.root === a)
    XCTAssertThrowsError(try scalar.buildFrom(b, newIDPrefix: "two"))
    try scalar.setBuiltDescription(nil)
    XCTAssertTrue(try scalar.buildFrom(b, newIDPrefix: "three")?.root === b)
    XCTAssertThrowsError(try scalar.buildFrom(a, newIDPrefix: "bad prefix"))
    let fail = Builder()
    fail.fail = true
    XCTAssertThrowsError(try fail.buildFrom(input.root, newIDPrefix: "fail"))
    XCTAssertEqual(a.property("label"), .string("First"))
    fail.fail = false
    XCTAssertEqual(try fail.buildFrom(input.root, newIDPrefix: "recover")?.root.children.count, 4)
    let p = Probe()
    class CustomDescription: Description {
      override func acceptMagritte(_ visitor: Visitor) throws {
        try visitor.visitStringDescription(self)
      }
    }
    let custom = CustomDescription(id: "custom", className: "MANumberDescription")
    custom.properties["label"] = .string("Custom")
    let customProbe = Probe()
    try customProbe.visit(custom)
    XCTAssertEqual(customProbe.events.first?.first, "visitStringDescription:")
    let unknown = Description(id: "unknown", className: "MissingDescription")
    XCTAssertThrowsError(try p.visit(unknown))
    unknown.className = "Object"
    XCTAssertThrowsError(try p.visit(unknown))
    try ClassRegistry.shared.registerClass(
      ClassInfo(
        name: "VisitorInheritedMemo", superclass: "MAMemoDescription", isAbstract: false,
        label: "Inherited"))
    unknown.className = "VisitorInheritedMemo"
    unknown.properties["label"] = .string("Inherited")
    try p.visit(unknown)
    XCTAssertEqual(p.events.count, 4)
    XCTAssertEqual(p.events.first?.first, "visitMemoDescription:")
    let builderClass = try object(f["builderClass"])
    let info = ClassRegistry.shared.find("MADescriptionBuilder")
    XCTAssertEqual(info?.superclass, try text(builderClass["superclass"]))
    XCTAssertEqual(info?.label, try text(builderClass["label"]))
    XCTAssertEqual(info?.isAbstract, builderClass["abstract"] as? Bool)
    let classValue = Value.classValue("MADescriptionBuilder")
    XCTAssertEqual(try decodeValue(encodeValue(classValue)), classValue)
    let relation = Description(id: "visitor.relation", className: "MAToOneRelationDescription")
    let reference = Description(id: "visitor.reference", className: "MAContainer")
    relation.reference = reference
    let metadata = RecursiveDescriptionModel()
    let schema = try metadata.describeReflective(relation)
    XCTAssertTrue(
      try XCTUnwrap(metadata.resolver.descriptions[schema.id + ".classes"]).options.values().contains(
        classValue))
    var small = Limits()
    small.visits = 2
    let limited = Probe(limits: small)
    XCTAssertThrowsError(try limited.visitAll([a, b]))
    try limited.visit(a)
    small = Limits()
    small.items = 1
    let items = Probe(limits: small)
    XCTAssertThrowsError(try items.visitAll([a, b]))
    small = Limits()
    small.depth = 2
    let cycles = Probe(limits: small)
    cycles.recurse = true
    let cycle = Description(id: "cycle", className: "MAContainer")
    cycle.properties["label"] = .string("Cycle")
    cycle.children = [cycle]
    XCTAssertThrowsError(try cycles.visit(cycle))
    cycle.children = []
    try cycles.visit(cycle)
    small = Limits()
    small.nodes = 2
    let nodes = DescriptionBuilder(limits: small)
    XCTAssertThrowsError(try nodes.buildFrom(input.root, newIDPrefix: "nodes"))
    small = Limits()
    small.items = 1
    let children = DescriptionBuilder(limits: small)
    XCTAssertThrowsError(try children.buildFrom(input.root, newIDPrefix: "items"))
    let clash = try tree(object(builders[0]["source"]), "clash.1")
    XCTAssertThrowsError(try DescriptionBuilder().buildFrom(clash.root, newIDPrefix: "clash"))
    class Skip: DescriptionBuilder {
      override func visitDescription(_ description: Description) throws {}
    }
    XCTAssertNil(try Skip().buildFrom(a, newIDPrefix: "skip"))
    var result: DescriptionCopy?
    do {
      let source = try tree(object(builders[0]["source"]), "retained")
      result = try DescriptionBuilder().buildFrom(source.root, newIDPrefix: "owned")
    }
    XCTAssertNotNil(result?.root.children.last?.reference)
    withExtendedLifetime((input.retained, clash.retained)) {}
  }
}
