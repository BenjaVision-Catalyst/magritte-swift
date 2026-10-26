import Foundation
import Magritte
import XCTest

private final class LazyTrace: Model {
  var writes: [Value] = []
  var fail = false
  func read(using description: Description) throws -> Value {
    throw MagritteError("Lazy initializer must not read model")
  }
  func write(_ value: Value, using description: Description) throws {
    writes.append(value)
    if fail { throw MagritteError("write") }
  }
}

final class LazyTests: XCTestCase {
  func value(_ object: Any?) throws -> Value {
    try decodeValue(JSONSerialization.data(withJSONObject: XCTUnwrap(object)))
  }
  func testSharedLazyAndInitialAnswerCases() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "lazy-scenarios", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    for row in try XCTUnwrap(fixture["lazy"] as? [[String: Any]]) {
      let d = Description(id: "field", className: try XCTUnwrap(row["className"] as? String))
      d.properties = [
        "default": try value(row["default"]), "initialAnswer": .string("answer"),
        "undefinedValue": .symbol("unset"), "readOnly": .boolean(true), "visible": .boolean(false),
      ]
      if let cache = row["cache"] as? Bool { d.properties["shouldCacheDefault"] = .boolean(cache) }
      let model = LazyTrace()
      XCTAssertEqual(
        try d.lazilyInitializeFrom(value(row["current"]), for: model), try value(row["result"]))
      XCTAssertEqual(model.writes.count, row["writes"] as? Int)
      if let written = model.writes.first { XCTAssertEqual(written, try d.property("default")) }
    }
    for row in try XCTUnwrap(fixture["answers"] as? [[String: Any]]) {
      let d = Description(id: "answer")
      d.properties["default"] = try value(row["default"])
      if !(row["answer"] is NSNull) {
        XCTAssertTrue(try d.setInitialAnswer(value(row["answer"])) === d)
      }
      let expected = try value(row["result"])
      XCTAssertEqual(try d.initialAnswer(), expected)
      XCTAssertEqual(try d.property("initialAnswer"), expected)
      XCTAssertEqual(
        try d.readSlot(strategy: "MASelectorAccessor", name: "initialAnswer"), expected)
      XCTAssertEqual(d.hasProperty("initialAnswer"), !(row["answer"] is NSNull))
    }
  }
  func testNilWritesFailuresAndCallableBoundary() throws {
    let d = Description(id: "lazy")
    let model = LazyTrace()
    d.properties["shouldCacheDefault"] = .boolean(true)
    XCTAssertEqual(try d.lazilyInitializeFrom(.undefined, for: model), .undefined)
    XCTAssertEqual(try d.lazilyInitializeFrom(.undefined, for: model), .undefined)
    XCTAssertEqual(model.writes.count, 2)
    model.fail = true
    XCTAssertThrowsError(try d.lazilyInitializeFrom(.undefined, for: model))
    XCTAssertEqual(model.writes.count, 3)
    model.fail = false
    var calls = 0
    d.defaultFunction = {
      calls += 1
      return .string("factory")
    }
    XCTAssertEqual(try d.lazilyInitializeFrom(.boolean(false), for: model), .boolean(false))
    XCTAssertEqual(calls, 0)
    XCTAssertThrowsError(try d.lazilyInitializeFrom(.undefined, for: model))
    XCTAssertThrowsError(try d.initialAnswer())
    XCTAssertEqual(calls, 0)
    try d.setInitialAnswer(.undefined)
    XCTAssertEqual(try d.initialAnswer(), .undefined)
    XCTAssertEqual(try d.defaultValue(), .string("factory"))
    XCTAssertEqual(calls, 1)
  }
  func testRawPropertyBridgeAndReferenceIdentity() throws {
    let target = Description(id: "target")
    let field = Description(id: "field")
    field.accessor = Accessor(className: "MASelectorAccessor", name: "label", writeName: "label:")
    field.properties["default"] = .string("seed")
    XCTAssertEqual(try target.maLazyPropertyUsing(field), .string("seed"))
    XCTAssertFalse(target.hasProperty("label"))
    field.properties["shouldCacheDefault"] = .boolean(true)
    XCTAssertEqual(try target.maLazyPropertyUsing(field), .string("seed"))
    XCTAssertEqual(try target.propertyAt("label"), .string("seed"))
    try target.propertyPut("label", .boolean(false))
    XCTAssertEqual(try target.maLazyPropertyUsing(field), .boolean(false))
    try target.propertyPutRemovingNil("label", .undefined)
    field.accessor?.writeName = "comment:"
    XCTAssertEqual(try target.maLazyPropertyUsing(field), .string("seed"))
    XCTAssertFalse(target.hasProperty("label"))
    XCTAssertEqual(try target.propertyAt("comment"), .string("seed"))
    field.accessor?.writeName = ""
    XCTAssertThrowsError(try target.maLazyPropertyUsing(field))
    field.properties["shouldCacheDefault"] = .boolean(false)
    XCTAssertEqual(try target.maLazyPropertyUsing(field), .string("seed"))
    field.accessor?.name = ""
    XCTAssertThrowsError(try target.maLazyPropertyUsing(field))
    field.accessor = Accessor()
    XCTAssertThrowsError(try target.maLazyPropertyUsing(field))
    let reference = Description(id: "reference")
    reference.properties = ["default": .reference("object"), "shouldCacheDefault": .boolean(true)]
    let adaptive = AdaptiveModel(id: "adaptive", description: reference)
    let result = try reference.lazilyInitializeFrom(.undefined, for: adaptive)
    XCTAssertEqual(result, try reference.property("default"))
    XCTAssertEqual(adaptive.values[reference.id], result)
  }
  func testMetadataCopyWireAndBounds() throws {
    let data = Description(id: "data", key: "data")
    let root = Description(id: "root", className: "MAContainer")
    data.properties["default"] = .string("seed")
    try data.writeSlot(strategy: "MASelectorAccessor", name: "initialAnswer:", value: .undefined)
    XCTAssertTrue(data.hasProperty("initialAnswer"))
    let copy = try copyDescription(data, newID: "copy")
    XCTAssertEqual(try copy.root.initialAnswer(), .undefined)
    try copy.root.setInitialAnswer(.string("copy"))
    XCTAssertEqual(try data.initialAnswer(), .undefined)
    root.children = [data]
    let g = Graph(root: root.id, descriptions: [root.id: root, data.id: data])
    g.format = "magritte.graph/4"
    let wire = try g.encode()
    let imported = try Graph.decode(wire)
    XCTAssertEqual(try imported.descriptions[data.id]?.initialAnswer(), .undefined)
    XCTAssertEqual(try imported.encode(), wire)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_LAZY_EXPORT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
    g.format = "magritte.graph/3"
    XCTAssertEqual(try Graph.decode(g.encode()).descriptions[data.id]?.initialAnswer(), .undefined)
    g.format = "magritte.graph/2"
    XCTAssertThrowsError(try g.encode())
    root.properties["initialAnswer"] = .undefined
    g.format = "magritte.graph/4"
    XCTAssertThrowsError(try g.encode())
    XCTAssertThrowsError(try root.initialAnswer())
    XCTAssertThrowsError(try root.lazilyInitializeFrom(.string("current"), for: LazyTrace()))
    var low = Limits()
    low.bytes = 1
    XCTAssertThrowsError(
      try data.lazilyInitializeFrom(.string("too long"), for: LazyTrace(), limits: low))
  }
}
