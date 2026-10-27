import Foundation
import XCTest

@testable import Magritte

final class MutableCollectionTests: XCTestCase {
  func field(_ id: String, _ cls: String = "MAToManyScalarRelationDescription") -> Description {
    Description(id: id, className: cls, key: id)
  }
  func testNativeIdentityCyclesAndShallowCopies() throws {
    XCTAssertEqual(Value.string(String(repeating:"x",count:110_000)),Value.string(String(repeating:"x",count:110_000)))
    let store = CollectionStore()
    let nested = try store.create(kind: "ordered", id: "nested", elements: [.string("inner")])
    let value = try store.create(kind: "ordered", id: "value", elements: [nested])
    let alias = value
    let copy = try value.shallowCopy()
    XCTAssertTrue(try value.sameCollection(alias))
    XCTAssertFalse(try value.sameCollection(copy))
    XCTAssertTrue(try valuesEqual(value, copy))
    XCTAssertTrue(try copy.elements()[0].sameCollection(nested))
    try nested.mutableCollection().append(.string("changed"))
    XCTAssertEqual(try copy.elements()[0].elements().count, 2)
    try value.mutableCollection().append(value)
    XCTAssertTrue(try value.elements().last!.sameCollection(value))
    XCTAssertTrue(try valuesEqual(value, value))
    var notEmpty = Predicate()
    notEmpty.selector = "notEmpty"
    XCTAssertTrue(try notEmpty.evaluate(value))
    let stringDescription = field("string", "MAStringDescription")
    let stringValue = try store.string(id: "stringForValidation", text: "live")
    let stringModel = DictionaryModel(["string": stringValue])
    XCTAssertTrue(try validate(stringModel, using: stringDescription).isEmpty)
    XCTAssertEqual(try writeString(stringValue, using: stringDescription), "live")
    stringDescription.properties["metadata:mutable"] = value
    let propertyCopy = try copyDescription(stringDescription, newID: "propertyCopy")
    XCTAssertTrue(try propertyCopy.root.properties["metadata:mutable"]!.sameCollection(value))
    XCTAssertEqual(try SortBlock(selector: "=").value(value, value), .boolean(true))
    XCTAssertEqual(try SortBlock(selector: "<").value(stringValue, .string("z")), .boolean(true))
    stringDescription.display("yourself")
    XCTAssertEqual(try stringDescription.displayStringFor(stringValue), "live")
    stringDescription.display(DisplayBlock { v, _ in String(try v.collectionCount()) })
    XCTAssertEqual(try stringDescription.displayStringFor(value), "2")
    let schema = field("comparison", "MAContainer")
    try schema.setChildren([stringDescription])
    let first = DictionaryModel(["string": value])
    let second = DictionaryModel(["string": value])
    XCTAssertTrue(try isSameAs(first, second, using: schema))
    stringDescription.properties["default"] = value
    let initialized = DictionaryModel()
    try initializeMagritte(initialized, using: schema)
    XCTAssertTrue(try initialized.values["string"]!.sameCollection(value))
    let option = field("option", "MASingleOptionDescription")
    option.options = Options([value])
    option.properties["sorted"] = .boolean(false)
    option.properties["required"] = .boolean(true)
    let optionValues = try option.allOptionsWith(value).values()
    XCTAssertEqual(optionValues.count, 1)
    XCTAssertTrue(try optionValues[0].sameCollection(value))
    XCTAssertTrue(try valuesEqual(value, value.shallowCopy()))
    let x = try store.create(kind: "ordered", id: "x")
    let y = try store.create(kind: "ordered", id: "y")
    try x.mutableCollection().append(x)
    try y.mutableCollection().append(y)
    XCTAssertThrowsError(try valuesEqual(x, y))
    let fixed = try store.create(kind: "array", id: "fixed", elements: [.integer(1)])
    try fixed.mutableCollection().atPut(0, .integer(2))
    XCTAssertEqual(try fixed.elements()[0], .integer(2))
    XCTAssertThrowsError(try fixed.mutableCollection().append(.undefined))
    let text = try store.string(id: "text", text: "a😀")
    let textCopy = try text.shallowCopy()
    try text.mutableCollection().atPut(1, .character("z"))
    XCTAssertEqual(try text.mutableCollection().snapshot(), .string("az"))
    XCTAssertEqual(try textCopy.mutableCollection().snapshot(), .string("a😀"))
    for kind in ["set", "bag"] {
      let hashed = try store.create(kind: kind, id: kind, elements: [.integer(1), .integer(1)])
      XCTAssertEqual(try hashed.collectionCount(), kind == "set" ? 1 : 2)
      try hashed.mutableCollection().remove(.integer(1))
      XCTAssertEqual(try hashed.collectionCount(), kind == "set" ? 0 : 1)
      XCTAssertThrowsError(try hashed.mutableCollection().append(value))
    }
    let foreign = try CollectionStore().create(kind: "ordered", id: "foreign")
    XCTAssertThrowsError(try value.mutableCollection().append(foreign))
    XCTAssertThrowsError(try encodeValue(value))
    XCTAssertThrowsError(
      try decodeValue(Data(#"{"type":"collectionReference","value":"value"}"#.utf8)))
    var bytes = Limits()
    bytes.bytes = 100
    XCTAssertThrowsError(
      try store.string(id: "boundedString", text: String(repeating: "a", count: 101), limits: bytes)
    )
    var tiny = Limits()
    tiny.items = 0
    XCTAssertThrowsError(try nested.mutableCollection().append(.undefined, limits: tiny))
    XCTAssertEqual(try nested.collectionCount(), 2)
    weak var weakRoot: CollectionReference?
    do {
      let local = CollectionStore()
      let cyclic = try local.create(kind: "ordered", id: "released")
      try cyclic.mutableCollection().append(cyclic)
      weakRoot = try cyclic.mutableCollection()
    }
    XCTAssertNil(weakRoot)
    let survivor: Value
    do {
      let local = CollectionStore()
      survivor = try local.create(kind: "ordered", id: "survivor", elements: [.integer(1)])
    }
    XCTAssertEqual(try survivor.elements(), [.integer(1)])
  }
  func testHistoricalAliasesAndMementoCopyBoundaries() throws {
    let url = Bundle.module.url(
      forResource: "editing-boundaries-reference", withExtension: "json", subdirectory: "Fixtures")!
    let baseline = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    for row in baseline["mutableCollectionAlias"] as! [[String: Any]] {
      let store = CollectionStore()
      let value = try store.create(kind: "ordered", id: "live", elements: [.string("base")])
      let d = field("value")
      let root = field("root", "MAContainer")
      try root.setChildren([d])
      let model = DictionaryModel(["value": value])
      let m: CachedMemento =
        (row["memento"] as! String) == "MACheckedMemento"
        ? try CheckedMemento(model: model, description: root)
        : try CachedMemento(model: model, description: root)
      XCTAssertTrue(try m.read(using: d).sameCollection(value))
      try value.mutableCollection().append(.string("outside"))
      XCTAssertEqual(try m.hasChanges(), row["hasChanges"] as! Bool)
      func expected(_ key: String) throws -> Value {
        try decodeValue(JSONSerialization.data(withJSONObject: row[key]!))
      }
      XCTAssertEqual(try value.mutableCollection().snapshot(), try expected("raw"))
      XCTAssertEqual(try m.read(using: d).mutableCollection().snapshot(), try expected("cache"))
      if let checked = m as? CheckedMemento {
        XCTAssertEqual(
          try checked.original["value"]!.mutableCollection().snapshot(), try expected("original"))
        XCTAssertEqual(try checked.hasConflict(), row["hasConflict"] as! Bool)
        XCTAssertEqual(
          try checked.hasModelChangedElsewhere(), row["hasModelChangedElsewhere"] as! Bool)
      }
    }
    let casesURL = Bundle.module.url(
      forResource: "mutable-collection-scenarios", withExtension: "json", subdirectory: "Fixtures")!
    let scenarios =
      try JSONSerialization.jsonObject(with: Data(contentsOf: casesURL)) as! [String: Any]
    for scenario in scenarios["cases"] as! [[String: Any]] {
      let cls = scenario["class"] as! String
      let store = CollectionStore()
      let inner = try store.create(kind: "ordered", id: "inner", elements: [.string("base")])
      let value = try store.create(kind: "ordered", id: "live", elements: [inner])
      let d = field("value", cls)
      let root = field("root", "MAContainer")
      try root.setChildren([d])
      let model = DictionaryModel(["value": value])
      let m = try CheckedMemento(model: model, description: root)
      let copied = scenario["copyOriginal"] as! Bool
      XCTAssertNotEqual(try m.original["value"]!.sameCollection(value), copied)
      try inner.mutableCollection().append(.string("nested"))
      XCTAssertFalse(try m.hasModelChangedElsewhere())
      try value.mutableCollection().append(.string("outer"))
      XCTAssertEqual(try m.hasModelChangedElsewhere(), copied)
      XCTAssertFalse(try m.hasChanges())
      let replacement = try store.create(
        kind: "ordered", id: "replacement", elements: [.string("replacement")])
      try m.write(replacement, using: d)
      XCTAssertTrue(try m.hasChanges())
      XCTAssertEqual(try m.hasConflict(), copied)
      try m.commit()
      XCTAssertTrue(try model.values["value"]!.sameCollection(replacement))
      try m.reset()
      XCTAssertTrue(try m.read(using: d).sameCollection(replacement))
      XCTAssertFalse(try m.hasChanges())
      XCTAssertFalse(try m.hasModelChangedElsewhere())
      XCTAssertFalse(try m.hasConflict())
    }
  }
  func testOriginalCopyFailureKeepsPreviousOriginals() throws {
    let arena = CollectionStore()
    let live = try arena.create(kind: "ordered", id: "live", elements: [.string("base")])
    let d = field("value")
    let schema = field("schema", "MAContainer")
    try schema.setChildren([d])
    let model = DictionaryModel(["value": live])
    var cap = Limits()
    cap.nodes = 3
    let m = try CheckedMemento(model: model, description: schema, limits: cap)
    let previous = m.original["value"]!
    _ = try arena.create(kind: "ordered", id: "filler")
    try live.mutableCollection().append(.string("outside"))
    XCTAssertThrowsError(try m.reset())
    XCTAssertTrue(try m.original["value"]!.sameCollection(previous))
    XCTAssertTrue(try m.read(using: d).sameCollection(live))
  }
  func testNativeContainerBackingAndCopy() throws {
    let a = field("a")
    let b = field("b")
    let root = field("root", "MAContainer")
    let peer = field("peer", "MAContainer")
    let backing = DescriptionChildren([a, b])
    try root.setChildren(backing)
    try peer.setChildren(backing)
    try root.remove(b)
    XCTAssertEqual(peer.children.count, 1)
    XCTAssertEqual(backing.values.count, 1)
    try root.setChildren([a, b])
    XCTAssertEqual(backing.values.count, 1)
    try peer.setChildren(root.childCollection)
    let copied = try copyDescription(root, newID: "copy")
    XCTAssertFalse(copied.root.childCollection === root.childCollection)
    XCTAssertTrue(copied.root.children[0] === a)
    let priority = field("priority", "MAPriorityContainer")
    try priority.setChildren(root.childCollection)
    XCTAssertFalse(priority.childCollection === root.childCollection)
    try peer.setChildren(priority.childCollection)
    XCTAssertTrue(peer.childCollection === priority.childCollection)
    a.properties["priority"] = .integer(10)
    let c = field("c")
    c.properties["priority"] = .integer(20)
    try peer.add(c)
    XCTAssertEqual(priority.children.count, 3)
    try root.setChildren(DescriptionChildren([a, b], kind: "array"))
    XCTAssertThrowsError(try root.add(c))
    try root.moveDown(a)
    XCTAssertTrue(root.children[0] === b)
    try peer.setChildren([b, a])
    XCTAssertFalse(try descriptionEqual(root, peer))
    try root.removeAll()
    XCTAssertTrue(root.children.isEmpty)
  }
  func replay(_ g: Graph) throws {
    let m = g.objects["model"]!
    let v = m.values["a"]!
    XCTAssertTrue(try v.sameCollection(m.values["b"]!))
    XCTAssertTrue(try v.elements().last!.sameCollection(v))
    try v.mutableCollection().atPut(0, .string("cross-port"))
    XCTAssertEqual(try m.values["b"]!.elements()[0], .string("cross-port"))
    let root = g.descriptions["root"]!
    let peer = g.descriptions["peer"]!
    XCTAssertTrue(root.childCollection === peer.childCollection)
    try root.remove(g.descriptions["b"]!)
    XCTAssertEqual(peer.children.count, 1)
  }
  func testGraphIdentityAndCrossPortReplay() throws {
    let a = field("a")
    let b = field("b")
    let root = field("root", "MAContainer")
    let peer = field("peer", "MAContainer")
    try root.setChildren([a, b])
    try peer.setChildren(root.childCollection)
    let g = Graph(root: "root", descriptions: ["root": root, "peer": peer, "a": a, "b": b])
    g.format = "magritte.graph/4"
    let live = try g.collections.create(kind: "ordered", id: "live", elements: [.string("wire")])
    try live.mutableCollection().append(live)
    g.objects["model"] = AdaptiveModel(
      id: "model", description: root, values: ["a": live, "b": live])
    let fixtureURL = Bundle.module.url(
      forResource: "mutable-collection-graph", withExtension: "json", subdirectory: "Fixtures")!
    try replay(Graph.decode(Data(contentsOf: fixtureURL)))
    let encoded = try g.encode()
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_MUTABLE_OUTPUT"] {
      try encoded.write(to: URL(fileURLWithPath: path))
    }
    try replay(Graph.decode(encoded))
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_MUTABLE_INPUT"] {
      try replay(Graph.decode(Data(contentsOf: URL(fileURLWithPath: path))))
    }
    var malformed = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    var rows = malformed["collections"] as! [[String: Any]]
    var elements = rows[0]["elements"] as! [[String: Any]]
    elements[1]["value"] = "missing"
    rows[0]["elements"] = elements
    malformed["collections"] = rows
    XCTAssertThrowsError(try Graph.decode(JSONSerialization.data(withJSONObject: malformed)))
    let ext1 = try CollectionStore().create(kind: "ordered", id: "same", elements: [.string("one")])
    let ext2 = try CollectionStore().create(kind: "ordered", id: "same", elements: [.string("two")])
    g.objects["model"]!.values = ["a": ext1, "b": ext2]
    let adapted = try Graph.decode(g.encode())
    XCTAssertFalse(
      try adapted.objects["model"]!.values["a"]!.sameCollection(
        adapted.objects["model"]!.values["b"]!))
    g.format = "magritte.graph/3"
    XCTAssertThrowsError(try g.encode())
    malformed = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    malformed["format"] = "magritte.graph/3"
    XCTAssertThrowsError(try Graph.decode(JSONSerialization.data(withJSONObject: malformed)))
  }
}
