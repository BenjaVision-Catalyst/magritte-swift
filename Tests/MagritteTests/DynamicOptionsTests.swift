import Foundation
import XCTest

@testable import Magritte

final class DynamicOptionsTests: XCTestCase {
  func object(_ j: Any?) throws -> [String: Any] { try XCTUnwrap(j as? [String: Any]) }
  func rows(_ j: Any?) throws -> [[String: Any]] { try XCTUnwrap(j as? [[String: Any]]) }
  func text(_ j: Any?) throws -> String { try XCTUnwrap(j as? String) }
  func bool(_ j: Any?) throws -> Bool { try XCTUnwrap(j as? Bool) }
  func data(_ j: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: j, options: .sortedKeys)
  }
  func value(_ j: Any?) throws -> Value { try decodeValue(data(XCTUnwrap(j))) }
  func fixture() throws -> [String: Any] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "dynamic-options-reference", withExtension: "json", subdirectory: "Fixtures"))
    return try object(JSONSerialization.jsonObject(with: Data(contentsOf: url)))
  }
  func field(_ id: String, _ cls: String) -> Description {
    let d = Description(id: id, className: cls, key: id)
    d.properties["label"] = .string(id == "reference" ? "Reference" : "Choice")
    return d
  }
  func testLiveProvidersValidationCopyAndCompletionAgainstGT() throws {
    let f = try fixture()
    var state = ["alpha", "alpine", "beta", "Alpha"]
    var calls: [Value] = []
    var queries: [String] = []
    let source = DynamicOptions { query in
      queries.append(query)
      return .array(state.filter { $0.utf8.starts(with: query.utf8) }.map(Value.string))
    }
    source.includesBlock = { value in
      calls.append(value)
      return value == .string("member") || value == .integer(42)
    }
    let reference = field("reference", "MANumberDescription")
    reference.properties["min"] = .integer(10)
    reference.properties["max"] = .integer(20)
    let choice = field("choice", "MASingleOptionDescription")
    choice.reference = reference
    choice.options = .dynamic(source)
    for (i, row) in try rows(f["queries"]).enumerated() {
      if i == 4 { state.append("altar") }
      XCTAssertEqual(
        try choice.allOptions().selectMatching(text(row["query"])), try value(row["value"]))
    }
    let readers = try rows(f["readers"])
    XCTAssertEqual(try source.detect(.string("alpine")), try value(readers[0]["value"]))
    source.reader = { v in
      guard case .string(let s) = v else { throw MagritteError("Expected string") }
      return .string(s.uppercased())
    }
    XCTAssertEqual(try source.detect(.string("alpine")), try value(readers[1]["value"]))
    let copied = try copyDescription(choice, newID: "copied")
    let clone = source.copy()
    XCTAssertFalse(try copied.root.options.provider() === source)
    XCTAssertFalse(copied.root.reference === reference)
    XCTAssertFalse(clone === source)
    source.reader = { v in
      guard case .string(let s) = v else { throw MagritteError("Expected string") }
      return .string("new-" + s)
    }
    XCTAssertEqual(
      try copied.root.options.provider().detect(.string("alpine")), try value(readers[2]["value"]))
    XCTAssertEqual(try source.detect(.string("alpine")), try value(readers[3]["value"]))
    XCTAssertTrue(try choice.allOptions().provider() === source)
    XCTAssertTrue(source.allOptionsFor(choice) === source)
    for row in try rows(f["allOptions"]) {
      choice.className = try text(row["class"])
      choice.properties["required"] = .boolean(try bool(row["required"]))
      choice.properties["extensible"] = .boolean(try bool(row["extensible"]))
      choice.properties["sorted"] = .boolean(try bool(row["sorted"]))
      calls = []
      queries = []
      XCTAssertTrue(try choice.allOptions().provider() === source)
      XCTAssertEqual(calls, try XCTUnwrap(row["includes"] as? [Any]).map(value))
      XCTAssertEqual(queries, row["queries"] as? [String])
    }
    for row in try rows(f["validation"]) {
      choice.className = try text(row["class"])
      choice.properties["required"] = .boolean(try bool(row["required"]))
      choice.properties["extensible"] = .boolean(try bool(row["extensible"]))
      calls = []
      queries = []
      let errors = try Magritte.validateValue(value(row["input"]), using: choice).map {
        ["class": $0.code, "description": $0.descriptionID == "choice" ? "Choice" : "Reference"]
      }
      XCTAssertEqual(try data(errors), try data(XCTUnwrap(row["errors"])))
      XCTAssertEqual(calls, try XCTUnwrap(row["includes"] as? [Any]).map(value))
      XCTAssertEqual(queries, row["queries"] as? [String])
    }
    let prepSource = DynamicOptions()
    var memberCalls: [String] = []
    prepSource.includesBlock = { v in
      guard case .string(let s) = v else { throw MagritteError("Expected string") }
      memberCalls.append(s)
      return s == "known"
    }
    choice.className = "MASingleOptionDescription"
    choice.options = .dynamic(prepSource)
    for row in try rows(f["allOptionsWith"]) {
      choice.className = try text(row["class"])
      choice.properties["required"] = .boolean(try bool(row["required"]))
      choice.properties["extensible"] = .boolean(try bool(row["extensible"]))
      choice.properties["sorted"] = .boolean(try bool(row["sorted"]))
      let current: Value =
        try text(row["current"]) == "nil" ? .undefined : .string(text(row["current"]))
      memberCalls = []
      let expected = try XCTUnwrap(row["result"] as? [String])
      if expected.first == "MessageNotUnderstood" {
        XCTAssertThrowsError(try choice.allOptionsWith(current))
      } else {
        let result = try choice.allOptionsWith(current)
        let entries = try result.entries()
        XCTAssertEqual(entries.count, expected.count)
        guard case .provider(let copy) = entries.last else {
          return XCTFail("Expected copied provider")
        }
        XCTAssertFalse(copy === prepSource)
        if entries.count == 2 { XCTAssertEqual(entries.first, .value(.undefined)) }
        XCTAssertThrowsError(try result.values())
      }
      XCTAssertEqual(memberCalls, row["calls"] as? [String])
    }
    let fixed: Options = [.string("alpha"), .string("alpine"), .string("beta"), .string("Alpha")]
    for row in try rows(f["staticMatching"]) {
      XCTAssertEqual(try fixed.selectMatching(text(row["query"])), try value(row["value"]))
    }
    // Copies keep the closure environment shared, while the property slot is independent.
    var n: Int64 = 0
    let counter = DynamicOptions { _ in
      n += 1
      return .integer(n)
    }
    let shared = counter.copy()
    XCTAssertEqual(try counter.selectMatching(""), .integer(1))
    XCTAssertEqual(try shared.selectMatching(""), .integer(2))
    let missing = DynamicOptions()
    XCTAssertThrowsError(try missing.selectMatching(""))
    XCTAssertThrowsError(try missing.includes(.string("x")))
    XCTAssertEqual(try missing.detect(.undefined), .undefined)
    let scalar = DynamicOptions { _ in .integer(3) }
    XCTAssertEqual(try scalar.selectMatching(""), .integer(3))
    var tiny = Limits()
    tiny.bytes = 8
    XCTAssertThrowsError(try source.selectMatching("long query", limits: tiny))
    tiny = Limits()
    tiny.items = 1
    XCTAssertThrowsError(try source.selectMatching("", limits: tiny))
    let bad = DynamicOptions { _ in throw MagritteError("callback failed") }
    XCTAssertThrowsError(try bad.selectMatching(""))
    withExtendedLifetime(copied) {}
  }
  func testLocalBoundaryTextualReplacementAndExport() throws {
    let f = try fixture()
    let source = DynamicOptions { _ in .array([.string("member"), .integer(42)]) }
    var queryCount = 0
    source.block = { _ in
      queryCount += 1
      return .array([.string("member"), .integer(42)])
    }
    source.includesBlock = { $0 == .string("member") || $0 == .integer(42) }
    let reference = field("reference", "MANumberDescription")
    reference.properties["min"] = .integer(10)
    reference.properties["max"] = .integer(20)
    let choice = field("choice", "MASingleOptionDescription")
    let many = field("many", "MAMultipleOptionDescription")
    choice.reference = reference
    many.reference = reference
    choice.options = .dynamic(source)
    many.options = .dynamic(source)
    let app = field("app", "MAContainer")
    let kind = field("kind", "MAClassDescription")
    app.properties["label"] = .string("Options")
    app.children = [choice, many, kind]
    let graph = Graph(root: "app")
    graph.format = "magritte.graph/4"
    for d in [app, choice, many, reference, kind] { graph.descriptions[d.id] = d }
    XCTAssertThrowsError(try graph.encode())
    XCTAssertEqual(queryCount, 0)
    choice.properties["visible"] = .boolean(false)
    XCTAssertThrowsError(try graph.encode())
    choice.properties["visible"] = .boolean(true)
    let sample = AdaptiveModel(
      id: "sample", description: app,
      values: [
        "choice": .integer(42), "many": .array([.integer(42), .string("member")]),
        "kind": .classValue("MADynamicOptions"),
      ])
    XCTAssertTrue(try Magritte.validate(sample, using: app).isEmpty)
    XCTAssertEqual(queryCount, 0)
    let snapshot = try source.selectMatching("").elements()
    choice.options = Options(snapshot)
    many.options = Options(snapshot)
    graph.objects["sample"] = sample
    XCTAssertTrue(try Magritte.validate(sample, using: app).isEmpty)
    let context = RecursiveDescriptionModel()
    let binding = try context.bind(choice)
    let schema = try context.describeReflective(choice)
    let textField = try XCTUnwrap(context.resolver.descriptions[schema.id + ".optionsTextual"])
    choice.options = .dynamic(source)
    XCTAssertThrowsError(try binding.read(using: textField))
    reference.className = "MAStringDescription"
    reference.properties.removeValue(forKey: "min")
    reference.properties.removeValue(forKey: "max")
    try binding.write(.string("first\rsecond"), using: textField)
    XCTAssertFalse(choice.options.isDynamic)
    XCTAssertEqual(
      try Value.array(choice.options.values()), try value(object(f["textual"])["after"]))
    choice.options = .dynamic(source)
    reference.className = "MANumberDescription"
    reference.properties["min"] = .integer(10)
    reference.properties["max"] = .integer(20)
    XCTAssertThrowsError(try binding.write(.string("not-a-number"), using: textField))
    XCTAssertTrue(try choice.options.provider() === source)
    choice.options = Options(snapshot)
    let info = try XCTUnwrap(ClassRegistry.shared.find("MADynamicOptions"))
    let cls = try object(f["class"])
    XCTAssertEqual(info.superclass, try text(cls["superclass"]))
    XCTAssertEqual(info.label, try text(cls["label"]))
    XCTAssertFalse(info.isAbstract)
    let relation = field("relation", "MAToOneRelationDescription")
    relation.reference = reference
    let registryMetadata = RecursiveDescriptionModel()
    let registrySchema = try registryMetadata.describeReflective(relation)
    XCTAssertTrue(
      try XCTUnwrap(registryMetadata.resolver.descriptions[registrySchema.id + ".classes"]).options
        .values().contains(.classValue("MADynamicOptions")))
    let roundtripURL = try XCTUnwrap(
      Bundle.module.url(
        forResource: "dynamic-options-roundtrip-reference", withExtension: "json",
        subdirectory: "Fixtures"))
    let roundtrip = try rows(JSONSerialization.jsonObject(with: Data(contentsOf: roundtripURL)))
    XCTAssertEqual(
      try writeString(sample, using: app), try text(rows(roundtrip[0]["reads"])[0]["text"]))
    let encoded = try graph.encode()
    XCTAssertEqual(try Graph.decode(encoded).encode(), encoded)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_OPTIONS_EXPORT"] {
      try encoded.write(to: URL(fileURLWithPath: path))
    }
  }
}
