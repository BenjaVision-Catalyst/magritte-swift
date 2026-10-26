import Foundation
import Magritte
import XCTest

final class CompositeTests: XCTestCase {
  func object(_ v: Any?) throws -> [String: Any] { try XCTUnwrap(v as? [String: Any]) }
  func rows(_ v: Any?) throws -> [[String: Any]] { try XCTUnwrap(v as? [[String: Any]]) }
  func data(_ v: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: v, options: .sortedKeys)
  }
  func local(_ v: Any) throws -> Value {
    let j = try object(v)
    if j["type"] as? String == "conflict" {
      return .conflict(
        CompositeConflict(kind: j["kind"] as? String, string: j["string"] as? String))
    }
    return try decodeValue(data(j))
  }
  func wire(_ v: Value) throws -> Any {
    if let c = v.conflict {
      return ["type": "conflict", "kind": c.kind as Any? ?? NSNull(), "string": c.string]
        as [String: Any]
    }
    return try JSONSerialization.jsonObject(with: encodeValue(v))
  }
  func attempt(_ body: () throws -> Value) -> [String: Any] {
    do { return ["value": try wire(body())] } catch { return ["error": true] }
  }
  func normalized(_ v: Any) -> Any {
    if var j = v as? [String: Any] {
      if j["error"] != nil {
        j["error"] = true
        return j
      }
      return j.mapValues(normalized)
    }
    if let a = v as? [Any] { return a.map(normalized) }
    return v
  }
  func same(_ a: [String: Any], _ b: Any, file: StaticString = #filePath, line: UInt = #line) throws
  {
    XCTAssertEqual(
      NSDictionary(dictionary: a), NSDictionary(dictionary: try object(normalized(b))), file: file,
      line: line)
  }
  func fixture() throws -> [String: Any] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "composite-reference", withExtension: "json", subdirectory: "Fixtures"))
    return try object(JSONSerialization.jsonObject(with: Data(contentsOf: url)))
  }
  func dict(_ name: String) -> Accessor { Accessor(name: name) }
  func testAccessorReadWriteCapabilitiesAgainstGT() throws {
    for row in try rows(fixture()["cases"]) {
      let g = Graph(root: "")
      let root = DictionaryModel()
      var models: [DictionaryModel] = []
      var trace: [String] = []
      let values = try XCTUnwrap(row["values"] as? [Any])
      for (i, v) in values.enumerated() {
        let m = DictionaryModel()
        m.values = ["value": try local(v), "index": .integer(Int64(i))]
        g.nativeObjects[String(i)] = m
        models.append(m)
      }
      let refs = try XCTUnwrap(row["order"] as? [Int]).map { Value.reference(String($0)) }
      let hr: Accessor.ReadBlock? =
        row["headRead"] as? Bool == true
        ? Accessor.ReadBlock { _ in
          trace.append("head")
          switch row["headResult"] as? String {
          case "error": throw MagritteError("head")
          case "nil": return .undefined
          case "scalar": return .integer(42)
          default:
            return row["collection"] as? String == "array"
              ? .array(refs)
              : .collection(kind: try XCTUnwrap(row["collection"] as? String), elements: refs)
          }
        } : nil
      let hw: Accessor.WriteBlock? =
        row["headWrite"] as? Bool == true
        ? Accessor.WriteBlock { _, _ in trace.append("head-write") } : nil
      let nr: Accessor.ReadBlock? =
        row["nextRead"] as? Bool == true
        ? Accessor.ReadBlock { m in
          guard
            case .integer(let i) = try m.readSlot(strategy: "MADictionaryAccessor", name: "index")
          else { throw MagritteError("index") }
          trace.append("read:" + String(i))
          if i == Int64(row["readFailure"] as? Int ?? -1) { throw MagritteError("read") }
          return try m.readSlot(strategy: "MADictionaryAccessor", name: "value")
        } : nil
      let nw: Accessor.WriteBlock? =
        row["nextWrite"] as? Bool == true
        ? Accessor.WriteBlock { m, v in
          guard
            case .integer(let i) = try m.readSlot(strategy: "MADictionaryAccessor", name: "index")
          else { throw MagritteError("index") }
          trace.append("write:" + String(i))
          if i == Int64(row["writeFailure"] as? Int ?? -1) { throw MagritteError("write") }
          try m.writeSlot(strategy: "MADictionaryAccessor", name: "value", value: v)
        } : nil
      let a = Accessor.composite(
        head: .pluggable(read: hr, write: hw), next: .pluggable(read: nr, write: nw),
        kind: row["kind"] as? String)
      for op in ["canRead", "canWrite", "read", "write"] {
        trace = []
        let result = attempt {
          switch op {
          case "canRead": return .boolean(try a.canRead(root, graph: g))
          case "canWrite": return .boolean(try a.canWrite(root, graph: g))
          case "read": return try a.read(root, graph: g)
          default:
            try a.write(local(try XCTUnwrap(row["writeValue"])), to: root, graph: g)
            return .undefined
          }
        }
        try same(["outcome": result, "trace": trace], try XCTUnwrap(row[op]))
      }
      let after = try models.map { try wire(XCTUnwrap($0.values["value"])) }
      XCTAssertEqual(try data(after), try data(XCTUnwrap(row["after"])))
    }
  }
  func testConflictAndViaProtocolsAgainstGT() throws {
    let f = try fixture()
    for row in try rows(f["conflicts"]) {
      let c = CompositeConflict(kind: row["kind"] as? String)
      let other = CompositeConflict(kind: "Boolean", string: "Other")
      XCTAssertEqual(c.string, row["print"] as? String)
      XCTAssertEqual(c, other)
      XCTAssertEqual(c.hashValue, other.hashValue)
      XCTAssertFalse(c.copy() === c)
      XCTAssertEqual(c.copy(), c)
      XCTAssertEqual(Value.conflict(c), Value.conflict(other))
      XCTAssertFalse(Value.conflict(c).isNil)
      XCTAssertFalse(Value.conflict(c).isCollection)
      XCTAssertEqual(
        [
          "Object", "MACompositeConflict", "String", "Collection", "SequenceableCollection",
          "Number", "Integer", "Boolean",
        ].map(c.kindOf), row["kinds"] as? [Bool])
      for (selector, key) in [
        ("isEmpty", "isEmptyMessage"), ("aCompletelyUnknownCompositeMessage", "unknownMessage"),
      ] {
        let result = attempt {
          .string(
            try c.doesNotUnderstand(selector) { kind, sel in
              sel == "isEmpty" && ClassRegistry.shared.includesBehavior(kind, "Collection")
            })
        }
        try same(result, try XCTUnwrap(row[key]))
      }
      for name in [
        "stringValidation", "numberValidation", "numberRangeValidation", "stringWriter",
        "numberWriter", "booleanWriter",
      ] {
        let d = Description(
          id: "field",
          className: name == "booleanWriter"
            ? "MABooleanDescription"
            : name.hasPrefix("number") ? "MANumberDescription" : "MAStringDescription", key: "value"
        )
        if name == "numberRangeValidation" { d.properties["min"] = .integer(0) }
        let result = attempt {
          if name.contains("Writer") { return .string(try writeString(.conflict(c), using: d)) }
          let errors = try Magritte.validateValue(.conflict(c), using: d)
          if !errors.isEmpty { throw MagritteError("Validation") }
          return .boolean(true)
        }
        try same(result, try XCTUnwrap(row[name]))
      }
      c.stringValue = ""
      XCTAssertEqual(c.string, row["emptyString"] as? String)
      c.stringValue = nil
      XCTAssertEqual(c.string, row["resetString"] as? String)
      XCTAssertThrowsError(try encodeValue(.conflict(c)))
    }
    for row in try rows(f["defaultKinds"]) {
      let d = Description(id: "kind", className: try XCTUnwrap(row["class"] as? String))
      XCTAssertEqual(try d.property("kind"), .classValue(try XCTUnwrap(row["kind"] as? String)))
    }
    for row in try rows(f["declaredKinds"]) {
      let d = Description(id: "declared", key: "name")
      d.properties["kind"] = (row["kind"] as? String).map(Value.classValue) ?? .undefined
      let a = try Accessor.compositeVia(dict("people"), using: d)
      XCTAssertEqual(a.kind, row["kind"] as? String)
      let result = attempt {
        if try !Magritte.validateValue(.integer(0), using: d).isEmpty {
          throw MagritteError("Validation")
        }
        return .boolean(true)
      }
      try same(result, try XCTUnwrap(row["validation"]))
    }
    for row in try rows(f["labels"]) {
      let d = Description(id: "field", key: "name")
      if let label = row["input"] as? String { d.properties["label"] = .string(label) }
      let a = try Accessor.compositeVia(dict("people"), using: d)
      XCTAssertEqual(try d.property("label"), .string(try XCTUnwrap(row["label"] as? String)))
      XCTAssertEqual(try a.accessorName(), .symbol(try XCTUnwrap(row["name"] as? String)))
      XCTAssertEqual(a.kind, row["kind"] as? String)
      var copy = a
      copy.kind = "Boolean"
      XCTAssertTrue(try accessorEqual(a, copy))
      let object = try AccessorObject.fromAccessor(id: "accessor", a)
      let cloned = try AccessorObject.fromAccessor(id: "copy", object.snapshot())
      XCTAssertFalse(object.accessor === cloned.accessor)
      XCTAssertFalse(object.next === cloned.next)
      let session = RecursiveDescriptionModel()
      let schema = try session.describe(object)
      let keys = try schema.orderedChildren().map { try $0.effectiveAccessor.accessorName() }
      XCTAssertEqual(keys, try XCTUnwrap(row["schema"] as? [String]).map(Value.symbol))
    }
  }
  func testMementosCopiesBoundsAndInterchange() throws {
    let f = try fixture()
    let g = Graph(root: "")
    let root = DictionaryModel()
    let p0 = DictionaryModel()
    let p1 = DictionaryModel()
    p0.values["name"] = .string("a")
    p1.values["name"] = .string("b")
    g.nativeObjects = ["0": p0, "1": p1]
    root.resolver = g
    root.values["people"] = .array([.reference("0"), .reference("1")])
    let a = Accessor.composite(head: dict("people"), next: dict("name"), kind: "String")
    let field = Description(id: "field")
    let schema = Description(id: "root", className: "MAContainer")
    field.accessor = a
    schema.children = [field]
    let editor = try CachedMemento(model: root, description: schema, graph: g)
    func snapshot() throws -> [String: Any] {
      return [
        "cached": try wire(editor.read(using: field)), "changed": try editor.hasChanges(),
        "values": [p0.values["name"], p1.values["name"]].map { v -> String in
          if case .string(let s) = v { return s }
          return "unexpected"
        },
      ]
    }
    let expected = try rows(f["editing"])
    try same(snapshot(), expected[0])
    try editor.commit()
    try same(snapshot(), expected[1])
    try editor.write(.string("all"), using: field)
    try same(snapshot(), expected[2])
    try editor.commit()
    try same(snapshot(), expected[3])
    let c = CompositeConflict(kind: "String")
    try editor.write(.conflict(c), using: field)
    XCTAssertTrue(try editor.read(using: field).conflict === c)
    try editor.commit()
    XCTAssertEqual(p0.values["name"], .string("all"))
    let chain = Accessor(className: "MAChainAccessor", steps: [dict("nested"), dict("name")])
    let binary = Accessor.composite(head: dict("people"), next: chain)
    let object = try AccessorObject.fromAccessor(id: "binary", binary)
    XCTAssertTrue(try accessorEqual(object.snapshot(), binary))
    XCTAssertTrue(try accessorEqual(decodeAccessor(encodeAccessor(binary)), binary))
    var bad = binary
    bad.steps.append(dict("extra"))
    XCTAssertThrowsError(try bad.check())
    bad = a
    bad.kind = "UnregisteredCompositeKind"
    XCTAssertThrowsError(try bad.check())
    var low = Limits()
    low.items = 1
    XCTAssertThrowsError(try a.read(root, graph: g, limits: low))
    let alias = Value.conflict(c)
    c.stringValue = "Changed"
    XCTAssertEqual(alias.conflict?.string, "Changed")
    let copied = c.copy()
    copied.kind = "Number"
    copied.stringValue = "Other"
    XCTAssertEqual(copied, c)
    XCTAssertEqual(c.kind, "String")
    XCTAssertThrowsError(try encodeValue(.array([.conflict(c)])))

    let callback = Accessor.pluggable(
      read: Accessor.ReadBlock { _ in .conflict(c) },
      write: Accessor.WriteBlock { _, v in XCTAssertTrue(v.conflict === c) })
    XCTAssertTrue(try callback.read(root).conflict === c)
    try callback.write(.conflict(c), to: root)
    XCTAssertThrowsError(
      try callback.write(
        .collection(kind: "set", elements: [.conflict(c), .conflict(c.copy())]), to: root))
    let mixedSet = Value.collection(
      kind: "set",
      elements: [.conflict(c), .array([.string(c.string), .string(try XCTUnwrap(c.kind))])])
    let setCallback = Accessor.pluggable(read: Accessor.ReadBlock { _ in mixedSet })
    XCTAssertEqual(try setCallback.read(root), mixedSet)
    let options = DynamicOptions { _ in .conflict(c) }
    XCTAssertTrue(try options.selectMatching("x").conflict === c)
    let portable = Graph(root: schema.id)
    portable.format = "magritte.graph/4"
    portable.descriptions = [schema.id: schema, field.id: field]
    field.accessor = binary
    let graphWire = try portable.encode()
    XCTAssertEqual(try Graph.decode(graphWire).encode(), graphWire)
    var legacy = try self.object(JSONSerialization.jsonObject(with: graphWire))
    legacy["format"] = "magritte.graph/3"
    XCTAssertThrowsError(try Graph.decode(data(legacy)))
    field.accessor = a
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_COMPOSITE_EXPORT"] {
      var untyped = a
      untyped.kind = nil
      let delegated = Accessor(className: "MADelegatorAccessor", steps: [a])
      let accessors = try [a, untyped, binary, delegated].map {
        try JSONSerialization.jsonObject(with: encodeAccessor($0))
      }
      try data(["accessors": accessors]).write(to: URL(fileURLWithPath: path))
    }
  }
  func testNativeConfigurationsRoundTrippedThroughGT() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "composite-roundtrip-reference", withExtension: "json",
        subdirectory: "Fixtures"))
    for port in try rows(JSONSerialization.jsonObject(with: Data(contentsOf: url))) {
      let accessors = try rows(port["accessors"])
      let cases = try rows(port["cases"])
      for (i, config) in accessors.enumerated() {
        let a = try decodeAccessor(data(config))
        let g = Graph(root: "")
        let model = DictionaryModel()
        let one = DictionaryModel()
        let two = DictionaryModel()
        let n0 = DictionaryModel()
        let n1 = DictionaryModel()
        one.values = ["name": .string("a"), "nested": .reference("n0")]
        two.values = ["name": .string("b"), "nested": .reference("n1")]
        n0.values["name"] = .string("a")
        n1.values["name"] = .string("b")
        g.nativeObjects = ["0": one, "1": two, "n0": n0, "n1": n1]
        model.values["people"] = .array([.reference("0"), .reference("1")])
        let name = try a.accessorName()
        guard case .symbol(let text) = name else { throw MagritteError("Name") }
        var actual: [String: Any] = [
          "canRead": try a.canRead(model, graph: g), "canWrite": try a.canWrite(model, graph: g),
          "before": try wire(a.read(model, graph: g)), "name": text,
          "label": try a.defaultLabel(for: Description(id: "field")),
        ]
        try a.write(.string("all"), to: model, graph: g)
        actual["after"] = try wire(a.read(model, graph: g))
        try same(actual, cases[i])
        XCTAssertEqual(try data(config), try encodeAccessor(a))
      }
    }
  }

}
