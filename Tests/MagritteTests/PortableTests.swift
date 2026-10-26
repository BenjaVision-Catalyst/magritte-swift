import Foundation
import XCTest

@testable import Magritte

final class PortableTests: XCTestCase {
  func fixture(_ name: String) throws -> Data {
    try Data(
      contentsOf: XCTUnwrap(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
  }
  func json(_ name: String) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: fixture(name)) as? [String: Any])
  }
  func data(_ any: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: any, options: .sortedKeys)
  }
  func value(_ any: Any?) throws -> Value { try decodeValue(data(XCTUnwrap(any))) }
  func cases(_ report: [String: Any], _ name: String) throws -> [[String: Any]] {
    try XCTUnwrap(report[name] as? [[String: Any]])
  }
  func graph() throws -> Graph { try Graph.decode(fixture("portable-v3")) }
  func testGTConditionsScalarsReadersAndWriters() throws {
    let g = try graph()
    let report = try json("portable-reference")
    let upstream = try cases(json("portable-upstream"), "reads")
    let validations = try cases(report, "cases")
    let reads = try cases(report, "reads")
    let writes = try cases(report, "writes")
    let predicates = try cases(report, "predicates")
    XCTAssertEqual(validations.count, 106)
    XCTAssertEqual(reads.count, 144)
    XCTAssertEqual(writes.count, 72)
    XCTAssertEqual(predicates.count, 60)
    for c in validations {
      let d = try XCTUnwrap(g.descriptions[c["description"] as? String ?? ""])
      let v = try value(c["input"])
      let expected = try XCTUnwrap(c["errors"] as? [String])
      if expected == ["runtimeError"] {
        XCTAssertThrowsError(try Magritte.validateValue(v, using: d, graph: g))
        continue
      }
      XCTAssertEqual(
        try Magritte.validateValue(v, using: d, graph: g).map(\.code), expected,
        "GT validation: \(c)")
    }
    for c in reads {
      let d = try XCTUnwrap(g.descriptions[c["description"] as? String ?? ""])
      let input = try XCTUnwrap(c["text"] as? String)
      let expected =
        upstream.first {
          ($0["description"] as? String) == (c["description"] as? String)
            && ($0["text"] as? String) == input
        } ?? c
      if expected["error"] != nil {
        XCTAssertThrowsError(try readString(input, using: d), "GT read error: \(c)")
      } else {
        XCTAssertEqual(
          try readString(input, using: d), try value(expected["value"]), "GT read: \(c)")
      }
    }
    for c in writes {
      let d = try XCTUnwrap(g.descriptions[c["description"] as? String ?? ""])
      XCTAssertEqual(
        try writeString(value(c["input"]), using: d, graph: g), c["text"] as? String,
        "GT write: \(c)")
    }
    for c in predicates {
      let p = try decodePredicate(data(XCTUnwrap(c["predicate"])))
      let v = try value(c["input"])
      if c["error"] != nil {
        XCTAssertThrowsError(try p.evaluate(v))
      } else {
        XCTAssertEqual(try p.evaluate(v), c["result"] as? Bool, "GT predicate: \(c)")
      }
      XCTAssertEqual(
        try encodePredicate(decodePredicate(encodePredicate(p))), try encodePredicate(p))
    }
  }
  func testGTAccessorBindingsAndIdentity() throws {
    final class Host { var value: Value = .string("Before") }
    let g = try graph()
    let report = try json("portable-reference")
    for c in try cases(report, "accessors") {
      let d = try XCTUnwrap(g.descriptions[c["description"] as? String ?? ""])
      let a = try d.effectiveAccessor
      let encoded = try encodeAccessor(a)
      XCTAssertEqual(try encodeAccessor(decodeAccessor(encoded)), encoded)
      let dictionary = DictionaryModel()
      let properties = Description(id: "properties")
      let native = NativeModel(Host())
      native.readers["MASelectorAccessor:value"] = { ($0 as! Host).value }
      native.writers["MASelectorAccessor:value:"] = { ($0 as! Host).value = $1 }
      native.readers["MAVariableAccessor:value"] = native.readers["MASelectorAccessor:value"]
      native.writers["MAVariableAccessor:value"] = native.writers["MASelectorAccessor:value:"]
      var target: Model = native
      if d.id == "dictField" {
        dictionary.values[a.name] = try value(c["before"])
        target = dictionary
      } else if d.id == "propertyField" {
        properties.properties[a.name] = try value(c["before"])
        target = properties
      } else if d.id == "chainField" {
        let inner = NativeModel(native.object)
        inner.readers = native.readers
        inner.writers = native.writers
        g.nativeObjects["inner"] = inner
        native.readers["MASelectorAccessor:value"] = { _ in .reference("inner") }
      }
      XCTAssertEqual(try a.read(target, graph: g), try value(c["before"]))
      try a.write(value(c["after"]), to: target, graph: g)
      XCTAssertEqual(try a.read(target, graph: g), try value(c["after"]))
      g.nativeObjects.removeAll()
    }
    let sample = try XCTUnwrap(g.objects["sample"])
    let identity = try XCTUnwrap(g.descriptions["identityField"]).effectiveAccessor
    XCTAssertTrue(try g.resolve(identity.read(sample, graph: g)) === sample)
    XCTAssertThrowsError(try identity.write(.undefined, to: sample, graph: g))
    let null = try XCTUnwrap(g.descriptions["nullField"]).effectiveAccessor
    XCTAssertThrowsError(try null.read(sample, graph: g))
    XCTAssertThrowsError(try null.write(.undefined, to: sample, graph: g))
    XCTAssertEqual(
      try encodeAccessor(decodeAccessor(encodeAccessor(null))), try encodeAccessor(null))
    // Model entry points apply strategy records; adaptive models keep description identity keys.
    let field = Description(id: "bound")
    field.accessor = Accessor(className: "MASelectorAccessor", name: "value", writeName: "value:")
    let bound = NativeModel(Host())
    bound.readers["MASelectorAccessor:value"] = { ($0 as! Host).value }
    bound.writers["MASelectorAccessor:value:"] = { ($0 as! Host).value = $1 }
    try bound.write(.string("Bound"), using: field)
    XCTAssertEqual(try bound.read(using: field), .string("Bound"))
  }
  func testStrictPortableGraphsAndInterpreterBounds() throws {
    let g = try graph()
    let invalid = try XCTUnwrap(
      JSONSerialization.jsonObject(with: fixture("portable-invalid")) as? [[String: Any]])
    XCTAssertEqual(invalid.count, 24)
    for c in invalid {
      XCTAssertThrowsError(
        try Graph.decode(data(XCTUnwrap(c["graph"]))), c["name"] as? String ?? "case")
    }
    let encoded = try g.encode()
    XCTAssertEqual(try Graph.decode(encoded).encode(), encoded)
    let p = try XCTUnwrap(g.descriptions["composite"]?.portableConditions.first?.predicate)
    var limits = Limits()
    limits.visits = 5
    XCTAssertThrowsError(try p.evaluate(.string("Ada"), limits: limits))
    limits = Limits()
    limits.depth = 1
    XCTAssertThrowsError(try p.evaluate(.string("Ada"), limits: limits))
    let string = try XCTUnwrap(g.descriptions["string"])
    limits = Limits()
    limits.bytes = 2
    XCTAssertThrowsError(try g.descriptions["one"]!.labelForOption(.integer(1), limits: limits))
    XCTAssertThrowsError(try readString("long", using: string, limits: limits))
    XCTAssertThrowsError(try writeString(.string("long"), using: string, limits: limits))
    let hiddenConfig = Description(id: "hiddenConfig")
    hiddenConfig.properties["visible"] = .boolean(false)
    var deep = Predicate(selector: "isNil")
    for _ in 0..<10 {
      var outer = Predicate()
      outer.className = "MANegationCondition"
      outer.children = [deep]
      deep = outer
    }
    hiddenConfig.portableConditions = [PortableCondition(label: "bounded", predicate: deep)]
    var smallWork = Limits()
    smallWork.visits = 5
    XCTAssertThrowsError(
      try Magritte.validateValue(.undefined, using: hiddenConfig, limits: smallWork))
    let cycle = Description(id: "cycle", className: "MATokenDescription")
    cycle.reference = cycle
    XCTAssertThrowsError(try readString("a", using: cycle))
    let hidden = Description(id: "hidden")
    hidden.properties["visible"] = .boolean(false)
    hidden.portableConditions = [
      PortableCondition(label: "bad", predicate: Predicate(selector: "evaluate:"))
    ]
    let root = Description(id: "root", className: "MAContainer")
    root.children = [hidden]
    XCTAssertThrowsError(try validate(DictionaryModel(), using: root))
  }
  func testGTNumericAndPresentationEdges() throws {
    let edges = try json("portable-edges")
    let g = try graph()
    let number = Description(id: "number", className: "MANumberDescription")
    for c in try cases(edges, "floats") {
      let v = try value(c["value"])
      XCTAssertEqual(try writeString(v, using: number), c["text"] as? String)
      XCTAssertEqual(
        try data(JSONSerialization.jsonObject(with: encodeValue(v))),
        try data(XCTUnwrap(c["value"])))
    }
    for c in try cases(edges, "reads") {
      let input = try XCTUnwrap(c["text"] as? String)
      if c["error"] != nil {
        XCTAssertThrowsError(try readString(input, using: number))
      } else {
        XCTAssertEqual(
          try encodeValue(readString(input, using: number)), try encodeValue(value(c["value"])))
      }
    }
    let policy = try XCTUnwrap(json("portable-upstream")["comparisonPolicy"] as? [String: Any])
    for (i, c) in try cases(edges, "comparisons").enumerated() {
      let left = try value(c["left"])
      let right = try value(c["right"])
      XCTAssertEqual(left == right, c["equal"] as? Bool)
      for (selector, key) in [("<", "less"), (">", "greater")] {
        XCTAssertEqual(
          try Predicate(selector: selector, arguments: [right]).evaluate(left),
          (i == 0 ? policy[key] : c[key]) as? Bool)
      }
    }
    let password = Description(id: "password", className: "MAPasswordDescription")
    for c in try cases(edges, "passwords") {
      let v = try value(c["input"])
      XCTAssertEqual(try password.obfuscated(v), c["obfuscated"] as? String)
      XCTAssertEqual(try password.isObfuscated(v), c["isObfuscated"] as? Bool)
    }
    let boolean = try XCTUnwrap(g.descriptions["boolean"])
    XCTAssertEqual(try Value.array(boolean.allOptions().values()), try value(edges["booleanOptions"]))
    for c in try cases(edges, "booleanLabels") {
      XCTAssertEqual(try boolean.labelForOption(value(c["input"])), c["label"] as? String)
    }
    let token = Description(id: "token", className: "MATokenDescription")
    token.reference = number
    token.properties["separators"] = .string("")
    for c in try cases(edges, "emptySeparatorWrites") {
      XCTAssertEqual(try writeString(value(c["input"]), using: token), c["text"] as? String)
    }
    let container = Description(id: "container", className: "MAContainer")
    for key in ["first", "hidden", "last"] {
      let d = Description(id: key, key: key)
      if key == "hidden" { d.properties["visible"] = .boolean(false) }
      container.children.append(d)
    }
    XCTAssertEqual(
      try writeString(
        DictionaryModel(["first": .string("A"), "last": .string("Z")]), using: container),
      edges["containerText"] as? String)
  }
  func testExactNumericSemanticsAndNativeExport() throws {
    XCTAssertEqual(Value.integer(1), .float(1.0))
    XCTAssertEqual(Value.string("ready"), .symbol("ready"))
    XCTAssertNotEqual(Value.integer(9_007_199_254_740_993), .float(9_007_199_254_740_992))
    XCTAssertTrue(
      try Predicate(selector: ">", arguments: [.float(9_007_199_254_740_992)]).evaluate(
        .integer(9_007_199_254_740_993)))
    XCTAssertThrowsError(
      try readString(
        "1.0e-400", using: Description(id: "underflow", className: "MANumberDescription")))
    XCTAssertThrowsError(try encodeValue(.float(.infinity)))
    XCTAssertThrowsError(try encodeValue(.float(.nan)))
    let g = try graph()
    let sample = try XCTUnwrap(g.objects["sample"])
    let number = try XCTUnwrap(g.descriptions["number"])
    XCTAssertEqual(
      try readString("9007199254740993e0", using: number), .integer(9_007_199_254_740_993))
    try sample.write(.float(2.5), using: number)
    try sample.write(.symbol("next"), using: XCTUnwrap(g.descriptions["symbol"]))
    try sample.write(.integer(2), using: XCTUnwrap(g.descriptions["positive"]))
    XCTAssertTrue(try validate(sample, using: sample.description, graph: g).isEmpty)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_PORTABLE_EXPORT"] {
      try g.encode().write(to: URL(fileURLWithPath: path))
    }
  }
}
