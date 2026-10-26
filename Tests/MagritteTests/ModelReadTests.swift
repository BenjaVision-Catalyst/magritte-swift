import Foundation
import Magritte
import XCTest

private final class ReadBox {
  var value: Value
  var reads = 0
  init(_ value: Value = .undefined) { self.value = value }
}
private final class ReadSlots: Model {
  let box: ReadBox
  init(_ value: Value) { box = ReadBox(value) }
  func readSlot(strategy: String, name: String) throws -> Value {
    box.reads += 1
    return box.value
  }
  func write(_ value: Value, using d: Description) throws {
    throw MagritteError("Unexpected write")
  }
}
private final class ReadOverride: Model {
  func read(using d: Description) throws -> Value { .undefined }
  func write(_ value: Value, using d: Description) throws {}
}
final class ModelReadTests: XCTestCase {
  func slot(_ cls: String, _ name: String) -> Accessor {
    Accessor(className: cls, name: name, writeName: cls == "MASelectorAccessor" ? name + ":" : "")
  }
  func value(_ raw: Any?) throws -> Value {
    try decodeValue(JSONSerialization.data(withJSONObject: XCTUnwrap(raw)))
  }
  func fixture() throws -> [String: Any] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "model-read-scenarios", withExtension: "json", subdirectory: "Fixtures"))
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }
  func testSharedAdapterFallbackCases() throws {
    let fixture = try fixture()
    for row in try XCTUnwrap(fixture["cases"] as? [[String: Any]]) {
      let d = Description(id: "field", key: "field")
      let current = try value(row["current"])
      let fallback = try value(row["undefinedValue"])
      d.properties = [
        "undefinedValue": fallback, "default": .string("unused"),
        "initialAnswer": .string("answer"), "required": .boolean(true), "readOnly": .boolean(true),
        "visible": .boolean(false), "shouldCacheDefault": .boolean(true),
      ]
      var defaults = 0
      d.defaultFunction = {
        defaults += 1
        return .string("evaluated")
      }
      let before = d.properties
      let kind = try XCTUnwrap(row["adapter"] as? String)
      let actual: Value
      if kind == "generic" {
        let m = ReadSlots(current)
        actual = try m.read(using: d)
        XCTAssertEqual(m.box.reads, 1)
        XCTAssertEqual(m.box.value, current)
      } else if kind == "dictionary" {
        let m = DictionaryModel([d.key: current])
        actual = try m.read(using: d)
        XCTAssertEqual(m.values[d.key], current)
      } else if kind.hasPrefix("native-") {
        let box = ReadBox(current)
        let m = NativeModel(box)
        if kind == "native-direct" {
          d.nativeRead = { p in
            let b = p as! ReadBox
            b.reads += 1
            return b.value
          }
        } else {
          let strategy =
            kind == "native-selector"
            ? "MASelectorAccessor"
            : kind == "native-variable" ? "MAVariableAccessor" : "MAPropertyAccessor"
          d.accessor = slot(strategy, "field")
          m.readers[strategy + ":field"] = { p in
            let b = p as! ReadBox
            b.reads += 1
            return b.value
          }
        }
        actual = try m.read(using: d)
        XCTAssertEqual(box.reads, 1)
        XCTAssertEqual(box.value, current)
      } else {
        let m = Description(id: "metadata")
        let key = kind == "description-selector" ? "undefinedValue" : "metadata:value"
        m.properties[key] = current
        if kind == "description-direct" {
          d.key = key
        } else {
          d.accessor = slot(
            kind == "description-selector" ? "MASelectorAccessor" : "MAPropertyAccessor", key)
        }
        actual = try m.read(using: d)
        XCTAssertEqual(m.properties[key], current)
      }
      XCTAssertEqual(actual, try value(row["result"]))
      XCTAssertEqual(defaults, 0)
      XCTAssertEqual(d.properties, before)
    }
  }
  func testAdaptiveAndMementoOverrides() throws {
    let d = Description(id: "field", key: "field")
    let root = Description(id: "root", className: "MAContainer")
    root.children = [d]
    d.properties["default"] = .string("default")
    for row in try XCTUnwrap(fixture()["editing"] as? [[String: Any]]) {
      d.properties["undefinedValue"] = try value(row["undefinedValue"])
      let generic = DictionaryModel()
      let adaptive = AdaptiveModel(description: root)
      XCTAssertEqual(try generic.read(using: d), try value(row["generic"]))
      XCTAssertEqual(try adaptive.read(using: d), try value(row["adaptive"]))
      let gs = try StraightMemento(model: generic, description: root)
      let asM = try StraightMemento(model: adaptive, description: root)
      let gc = try CachedMemento(model: generic, description: root)
      let ac = try CachedMemento(model: adaptive, description: root)
      let checked = try CheckedMemento(model: generic, description: root)
      XCTAssertEqual(try gs.read(using: d), try value(row["straightGeneric"]))
      XCTAssertEqual(try asM.read(using: d), try value(row["straightAdaptive"]))
      XCTAssertEqual(try gc.read(using: d), try value(row["cachedGeneric"]))
      XCTAssertEqual(try ac.read(using: d), try value(row["cachedAdaptive"]))
      XCTAssertEqual(checked.original[d.id], try value(row["generic"]))
      try gc.write(.undefined, using: d)
      XCTAssertEqual(try gc.read(using: d), .undefined)
      XCTAssertTrue(generic.values.isEmpty)
    }
    let dictionary = DictionaryModel()
    d.properties["undefinedValue"] = .symbol("unset")
    XCTAssertEqual(try dictionary.read(using: d), .symbol("unset"))
    XCTAssertTrue(dictionary.values.isEmpty)
    dictionary.values[d.key] = .undefined
    XCTAssertEqual(try dictionary.read(using: d), .symbol("unset"))
    XCTAssertEqual(dictionary.values[d.key], .undefined)
    XCTAssertEqual(try d.effectiveAccessor.read(dictionary), .undefined)
    let custom: Model = ReadOverride()
    XCTAssertEqual(try custom.read(using: d), .undefined)
  }
  func testOrderingErrorsChainsAndConsumers() throws {
    let d = Description(id: "field", key: "field")
    let root = Description(id: "root", className: "MAContainer")
    root.children = [d]
    let box = ReadBox()
    let native = NativeModel(box)
    d.nativeRead = { p in
      let b = p as! ReadBox
      b.reads += 1
      d.properties["undefinedValue"] = .string("after")
      return b.value
    }
    XCTAssertEqual(try native.read(using: d), .string("after"))
    XCTAssertEqual(box.reads, 1)
    box.value = .boolean(false)
    XCTAssertEqual(try native.read(using: d), .boolean(false))
    XCTAssertEqual(box.reads, 2)
    d.nativeRead = { _ in throw MagritteError("read failed") }
    XCTAssertThrowsError(try native.read(using: d))
    d.nativeRead = nil
    d.accessor = slot("MASelectorAccessor", "value")
    XCTAssertThrowsError(try native.read(using: d))
    native.readers["MASelectorAccessor:value"] = { ($0 as! ReadBox).value }
    box.value = .undefined
    XCTAssertEqual(try d.effectiveAccessor.read(native), .undefined)
    XCTAssertEqual(try native.read(using: d), .string("after"))
    let resolver = Graph(root: "unused")
    let target = DictionaryModel()
    resolver.nativeObjects["target"] = target
    native.resolver = resolver
    var links = 0
    var linked = false
    native.readers["MASelectorAccessor:next"] = { _ in
      links += 1
      return linked ? .reference("target") : .undefined
    }
    let chain = Accessor(
      className: "MAChainAccessor",
      steps: [slot("MASelectorAccessor", "next"), slot("MADictionaryAccessor", "value")])
    d.accessor = chain
    d.properties["undefinedValue"] = .string("outer")
    XCTAssertThrowsError(try native.read(using: d))
    XCTAssertEqual(links, 1)
    linked = true
    XCTAssertEqual(try native.read(using: d), .string("outer"))
    XCTAssertEqual(links, 2)
    XCTAssertEqual(try chain.read(native, graph: resolver), .undefined)
    XCTAssertEqual(links, 3)
    d.accessor = nil
    d.properties = [
      "undefinedValue": .symbol("unset"), "default": .string("default"), "required": .boolean(true),
    ]
    let dictionary = DictionaryModel()
    let adaptive = AdaptiveModel(description: root)
    XCTAssertTrue(try validate(dictionary, using: root).isEmpty)
    XCTAssertEqual(
      try validate(adaptive, using: root).map(\.code), ["MARequiredError", "MAKindError"])
    XCTAssertEqual(try d.readToString(dictionary), "unset")
    let printed = PrintStream()
    try d.printFor(dictionary, on: printed)
    XCTAssertEqual(printed.contents, "unset")
    let defaulted = DictionaryModel([d.key: .string("default")])
    XCTAssertFalse(try isSameAs(dictionary, defaulted, using: root))
    let defaultedAdaptive = AdaptiveModel(description: root, values: [d.id: .string("default")])
    XCTAssertTrue(try isSameAs(adaptive, defaultedAdaptive, using: root))
  }
  func testReflectiveFallbacksLifetimeLimitsAndWire() throws {
    let session = RecursiveDescriptionModel()
    let metadata = Description(id: "metadata")
    let bound = try session.bind(metadata)
    let query = Description(id: "query")
    query.accessor = slot("MASelectorAccessor", "group")
    query.properties["undefinedValue"] = .string("metadata fallback")
    XCTAssertEqual(try query.effectiveAccessor.read(bound, graph: session.resolver), .undefined)
    XCTAssertEqual(try bound.read(using: query), .string("metadata fallback"))
    let accessor = try AccessorObject.fromAccessor(id: "accessor", slot("MASelectorAccessor", ""))
    let boundAccessor = try session.bind(accessor)
    query.accessor = slot("MASelectorAccessor", "selector")
    XCTAssertEqual(try boundAccessor.read(using: query), .string("metadata fallback"))
    let condition = ConditionObject(id: "condition", predicate: Predicate(selector: "isNil"))
    let boundCondition = try session.bind(condition)
    query.accessor = .pluggable(read: Accessor.ReadBlock { _ in .undefined })
    XCTAssertEqual(try boundCondition.read(using: query), .string("metadata fallback"))
    var expired: Model?
    do {
      let temporary = RecursiveDescriptionModel()
      expired = try temporary.bind(metadata)
    }
    XCTAssertThrowsError(try expired?.read(using: query))
    var low = Limits()
    low.bytes = 128
    let bounded = RecursiveDescriptionModel(limits: low)
    let boundedModel = try bounded.bind(metadata)
    query.properties["undefinedValue"] = .string(String(repeating: "x", count: 300))
    XCTAssertThrowsError(try boundedModel.read(using: query))
    let d = Description(id: "field", key: "field")
    let root = Description(id: "root", className: "MAContainer")
    d.properties = ["undefinedValue": .string("missing"), "default": .string("default")]
    root.children = [d]
    let g = Graph(root: root.id, descriptions: [root.id: root, d.id: d])
    g.format = "magritte.graph/4"
    let object = AdaptiveModel(id: "object", description: root)
    g.objects[object.id] = object
    let wire = try g.encode()
    let imported = try Graph.decode(wire)
    let dictionary = DictionaryModel()
    let field = try XCTUnwrap(imported.descriptions[d.id])
    XCTAssertEqual(try dictionary.read(using: field), .string("missing"))
    XCTAssertEqual(try imported.objects["object"]?.read(using: field), .undefined)
    XCTAssertEqual(try field.effectiveAccessor.read(dictionary), .undefined)
    XCTAssertEqual(try imported.encode(), wire)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_MODEL_READ_EXPORT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
  }
}
