import Foundation
import Magritte
import XCTest

private final class ModelTraceLog { var events: [String] = [] }
private final class ProtocolTrace: Model {
  let name: String, log: ModelTraceLog
  var values: [String: Value] = [:], readable = true
  var beforeRead: ((Description) throws -> Void)?, afterWrite: ((Description) throws -> Void)?
  init(_ name: String, _ log: ModelTraceLog) {
    self.name = name
    self.log = log
  }
  func respondsToSelector(_ s: String) throws -> Bool {
    log.events.append(name + ":can:" + s)
    return readable
  }
  func read(using d: Description) throws -> Value {
    log.events.append(name + ":read:" + d.id)
    try beforeRead?(d)
    return values[d.id] ?? .undefined
  }
  func write(_ v: Value, using d: Description) throws {
    log.events.append(name + ":write:" + d.id)
    values[d.id] = v
    try afterWrite?(d)
  }
}
private final class ProtocolEqual: Model {
  var calls = 0, arguments: [Value] = [], answer: Value = .boolean(true)
  func binaryMessage(_ selector: String, argument: Value, graph: Graph?) throws -> Value {
    guard selector == "=" else { throw MagritteError("selector") }
    calls += 1
    arguments.append(argument)
    return answer
  }
  func read(using d: Description) throws -> Value { .undefined }
  func write(_ value: Value, using d: Description) throws {}
}
final class ModelProtocolTests: XCTestCase {
  func field(_ id: String) -> Description { Description(id: id, key: id) }
  func selector(_ d: Description) {
    d.accessor = Accessor(className: "MASelectorAccessor", name: d.id, writeName: d.id + ":")
  }
  func value(_ raw: Any?) throws -> Value {
    try decodeValue(JSONSerialization.data(withJSONObject: XCTUnwrap(raw)))
  }
  func testSharedInitializationAndComparison() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "model-protocol-scenarios", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let root = Description(id: "root", className: "MAContainer")
    for row in try XCTUnwrap(fixture["initialization"] as? [[String: Any]]) {
      let d = field("data")
      root.children = [d]
      d.properties = [
        "default": try value(row["default"]),
        "readOnly": .boolean(try XCTUnwrap(row["readOnly"] as? Bool)),
        "visible": .boolean(try XCTUnwrap(row["visible"] as? Bool)),
        "shouldCacheDefault": .boolean(try XCTUnwrap(row["shouldCacheDefault"] as? Bool)),
        "required": .boolean(true), "initialAnswer": .string("answer"),
      ]
      let log = ModelTraceLog()
      let model = ProtocolTrace("model", log)
      model.values[d.id] = .string("prior")
      XCTAssertTrue(try initializeMagritte(model, using: root) === model)
      XCTAssertEqual(model.values[d.id], try value(row["result"]))
      XCTAssertEqual(
        log.events, (row["writes"] as? [Any])?.isEmpty == true ? [] : ["model:write:data"])
    }
    for row in try XCTUnwrap(fixture["comparison"] as? [[String: Any]]) {
      let d = field("data")
      selector(d)
      root.children = [d]
      d.properties = [
        "default": try value(row["default"]), "readOnly": .boolean(true),
        "visible": .boolean(false), "undefinedValue": .symbol("unset"),
        "initialAnswer": .string("answer"), "shouldCacheDefault": .boolean(true),
      ]
      let log = ModelTraceLog()
      let left = ProtocolTrace("left", log)
      let right = ProtocolTrace("right", log)
      left.values[d.id] = try value(row["left"])
      right.values[d.id] = try value(row["right"])
      let before = d.properties
      XCTAssertEqual(try isSameAs(left, right, using: root), row["result"] as? Bool)
      XCTAssertEqual(log.events, ["right:can:data", "left:read:data", "right:read:data"])
      XCTAssertEqual(d.properties, before)
    }
  }
  func testInitializationPartialWritesAndProviders() throws {
    let root = Description(id: "root", className: "MAContainer")
    let a = field("a")
    let b = field("b")
    let c = field("c")
    root.children = [a, b, c]
    a.className = "MANumberDescription"
    a.properties = ["default": .string("A"), "visible": .boolean(false)]
    b.properties["default"] = .string("B")
    c.properties = ["default": .string("C"), "readOnly": .boolean(true)]
    let log = ModelTraceLog()
    let model = ProtocolTrace("left", log)
    try initializeMagritte(model, using: root)
    XCTAssertEqual(log.events, ["left:write:a", "left:write:b"])
    XCTAssertEqual(model.values["a"], .string("A"))
    XCTAssertEqual(model.values["b"], .string("B"))
    XCTAssertNil(model.values["c"])
    c.properties.removeValue(forKey: "readOnly")
    model.afterWrite = { d in if d.id == "b" { throw MagritteError("write") } }
    log.events.removeAll()
    XCTAssertThrowsError(try initializeMagritte(model, using: root))
    XCTAssertEqual(log.events, ["left:write:a", "left:write:b"])
    XCTAssertNil(model.values["c"])
    model.afterWrite = { d in
      if d.id == "a" {
        b.properties["default"] = .string("changed")
        c.properties["readOnly"] = .boolean(true)
      }
    }
    try initializeMagritte(model, using: root)
    XCTAssertEqual(model.values["b"], .string("changed"))
    XCTAssertNil(model.values["c"])
    model.afterWrite = nil
    root.children = []
    var providers = 0
    func provider() -> Description {
      providers += 1
      return root
    }
    XCTAssertTrue(try initializeMagritte(model, using: provider) === model)
    XCTAssertEqual(providers, 1)
    XCTAssertTrue(try isSameAs(model, model, using: provider))
    XCTAssertEqual(providers, 2)
    XCTAssertThrowsError(try initializeMagritte(model, using: { throw MagritteError("provider") }))
    let nested = field("nested")
    nested.className = "MAContainer"
    nested.properties["undefinedValue"] = .string("container-default")
    nested.children = [c]
    root.children = [nested]
    log.events.removeAll()
    try initializeMagritte(model, using: root)
    XCTAssertEqual(log.events, ["left:write:nested"])
    XCTAssertEqual(model.values["nested"], .string("container-default"))
    let peer = ProtocolTrace("peer", log)
    model.values["nested"] = .undefined
    peer.values["nested"] = .string("container-default")
    XCTAssertTrue(try isSameAs(model, peer, using: root))

  }
  func testReadOrderAndCallableDefaultBoundary() throws {
    let root = Description(id: "root", className: "MAContainer")
    let a = field("a")
    let b = field("b")
    selector(a)
    selector(b)
    root.children = [a, b]
    a.properties["default"] = .string("A")
    b.properties["default"] = .string("B")
    let log = ModelTraceLog()
    let left = ProtocolTrace("left", log)
    let right = ProtocolTrace("right", log)
    left.values = ["a": .string("same"), "b": .string("left")]
    right.values = ["a": .string("different"), "b": .string("right")]
    XCTAssertFalse(try isSameAs(left, right, using: root))
    XCTAssertEqual(log.events, ["right:can:a", "left:read:a", "right:read:a"])
    root.children = [a]
    right.readable = false
    log.events.removeAll()
    XCTAssertFalse(try isSameAs(left, right, using: root))
    XCTAssertEqual(log.events, ["right:can:a"])
    right.readable = true
    left.readable = false
    right.values["a"] = .string("same")
    log.events.removeAll()
    XCTAssertTrue(try isSameAs(left, right, using: root))
    XCTAssertEqual(log.events, ["right:can:a", "left:read:a", "right:read:a"])
    left.beforeRead = { _ in throw MagritteError("left read") }
    log.events.removeAll()
    XCTAssertThrowsError(try isSameAs(left, right, using: root))
    XCTAssertEqual(log.events, ["right:can:a", "left:read:a"])
    left.beforeRead = nil
    right.beforeRead = { _ in throw MagritteError("right read") }
    log.events.removeAll()
    XCTAssertThrowsError(try isSameAs(left, right, using: root))
    XCTAssertEqual(log.events, ["right:can:a", "left:read:a", "right:read:a"])
    right.beforeRead = nil
    let accessor = try AccessorObject.fromAccessor(id: "shared", XCTUnwrap(a.accessor))
    a.accessorObject = accessor
    left.beforeRead = { _ in
      accessor.value.name = "new"
      a.properties["default"] = .string("new default")
    }
    right.beforeRead = { d in XCTAssertEqual(try d.effectiveAccessor.name, "new") }
    left.values["a"] = .undefined
    right.values["a"] = .string("new default")
    XCTAssertTrue(try isSameAs(left, right, using: root))
    left.beforeRead = nil
    right.beforeRead = nil
    a.accessorObject = nil
    var calls = 0
    a.defaultFunction = {
      calls += 1
      return .string("factory")
    }
    a.properties["readOnly"] = .boolean(true)
    log.events.removeAll()
    try initializeMagritte(left, using: root)
    XCTAssertTrue(log.events.isEmpty)
    a.properties["readOnly"] = .boolean(false)
    XCTAssertThrowsError(try initializeMagritte(left, using: root))
    XCTAssertEqual(calls, 0)
    log.events.removeAll()
    XCTAssertThrowsError(try isSameAs(left, right, using: root))
    XCTAssertEqual(log.events, ["right:can:a", "left:read:a", "right:read:a"])
    XCTAssertEqual(calls, 0)
    right.readable = false
    XCTAssertFalse(try isSameAs(left, right, using: root))
    XCTAssertEqual(calls, 0)
    XCTAssertEqual(try a.defaultValue(), .string("factory"))
    XCTAssertEqual(calls, 1)
    a.defaultFunction = nil
  }
  func testReferenceEqualityBoundsAndPortableModels() throws {
    let root = Description(id: "root", className: "MAContainer")
    let a = field("a")
    selector(a)
    root.children = [a]
    let log = ModelTraceLog()
    let left = ProtocolTrace("left", log)
    let right = ProtocolTrace("right", log)
    let object = ProtocolEqual()
    let resolver = Graph(root: "unused")
    resolver.nativeObjects = ["one": object, "alias": object]
    left.values["a"] = .reference("one")
    right.values["a"] = .reference("alias")
    XCTAssertTrue(try isSameAs(left, right, using: root, graph: resolver))
    XCTAssertEqual(object.calls, 1)
    object.answer = .boolean(false)
    XCTAssertFalse(try isSameAs(left, right, using: root, graph: resolver))
    object.answer = .string("bad")
    XCTAssertThrowsError(try isSameAs(left, right, using: root, graph: resolver))
    object.answer = .boolean(true)
    a.properties["default"] = .reference("one")
    left.values["a"] = .reference("alias")
    right.values["a"] = .undefined
    object.calls = 0
    XCTAssertTrue(try isSameAs(left, right, using: root, graph: resolver))
    XCTAssertEqual(object.calls, 1)
    XCTAssertThrowsError(try isSameAs(left, right, using: root))
    XCTAssertThrowsError(try initializeMagritte(left, using: Description(id: "invalid")))
    var items = Limits()
    items.items = 0
    log.events.removeAll()
    XCTAssertThrowsError(try initializeMagritte(left, using: root, limits: items))
    XCTAssertTrue(log.events.isEmpty)
    a.properties["default"] = .string(String(repeating: "x", count: 200))
    var low = Limits()
    low.visits = 100
    XCTAssertThrowsError(try initializeMagritte(left, using: root, limits: low))
    XCTAssertEqual(left.values["a"], .reference("alias"))
    let name = field("name")
    let enabled = field("enabled")
    name.properties["default"] = .string("Ada")
    enabled.className = "MABooleanDescription"
    enabled.properties["default"] = .boolean(false)
    root.children = [name, enabled]
    let g = Graph(root: root.id, descriptions: [root.id: root, name.id: name, enabled.id: enabled])
    g.format = "magritte.graph/4"
    let model = AdaptiveModel(
      id: "initialized", description: root,
      values: [name.id: .string("Before"), enabled.id: .boolean(true)])
    try initializeMagritte(model, using: root)
    let peer = AdaptiveModel(
      id: "peer", description: root, values: [name.id: .undefined, enabled.id: .undefined])
    XCTAssertTrue(try isSameAs(model, peer, using: root))
    XCTAssertTrue(try validate(model, using: root).isEmpty)
    g.objects[model.id] = model
    g.objects[peer.id] = peer
    let wire = try g.encode()
    let imported = try Graph.decode(wire)
    let schema = try XCTUnwrap(imported.descriptions[root.id])
    let first = try XCTUnwrap(imported.objects[model.id])
    let second = try XCTUnwrap(imported.objects[peer.id])
    XCTAssertTrue(try isSameAs(first, second, using: schema, graph: imported))
    try initializeMagritte(first, using: schema)
    XCTAssertEqual(try imported.encode(), wire)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_MODEL_PROTOCOL_EXPORT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
  }
}
