import Foundation
import Magritte
import XCTest

final class ContainerEnumerationTests: XCTestCase {
  func field(_ key: String, _ priority: Int64 = 0, _ cls: String = "MAStringDescription")
    -> Description
  {
    let d = Description(id: key, className: cls, key: key)
    d.properties["priority"] = .integer(priority)
    return d
  }
  func testContainerProtocolAgainstGT() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "container-protocol-reference", withExtension: "json", subdirectory: "Fixtures"
      ))
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    for expected in try XCTUnwrap(fixture["cases"] as? [[String: Any]]) {
      let cls = try XCTUnwrap(expected["class"] as? String)
      let empty = try XCTUnwrap(expected["empty"] as? Bool)
      let d = Description(id: "root", className: cls)
      if !empty { d.children = [field("a", 30), field("b", 10), field("c", 20)] }
      let fallback = field("fallback")
      var row: [String: Any] = ["class": cls, "empty": empty]
      var trace: [Any] = []
      try forEachDescription(d) { trace.append($0.key) }
      row["each"] = trace
      trace = []
      try forEachDescriptionSeparated(
        d, { trace.append($0.key) }, separator: { trace.append("separator") })
      row["separated"] = trace
      trace = []
      try forEachDescriptionIndexed(d) { trace.append([$0, $1.key]) }
      row["indexed"] = trace
      row["fold"] = try reduceDescriptions(d, initial: "start") { $0 + ":" + $1.key }
      var other = Array(1..<(d.children.count + 1))
      trace = []
      try forEachDescriptionPaired(d, with: other) { trace.append([$0.key, $1]) }
      row["paired"] = trace
      var missing = 0
      var first = try childAt(d, index: 0) {
        missing += 1
        return fallback
      }
      row["first"] = first?.key as Any
      row["firstFallbackCalls"] = missing
      missing = 0
      first = try childAt(d, index: d.children.count) {
        missing += 1
        return fallback
      }
      row["absent"] = first?.key as Any
      row["absentFallbackCalls"] = missing
      let equal = field("a")
      equal.properties["label"] = .string("Different label")
      row["includesEqual"] = try includesDescription(d, equal)
      row["includesOther"] = try includesDescription(d, field("a", 0, "MANumberDescription"))
      for op in ["all", "any", "none", "detect", "missing"] {
        trace = []
        missing = 0
        let predicate: (Description) throws -> Bool = { item in
          trace.append(item.key)
          return try op != "missing" && item.priority() >= 20
        }
        let answer: Any
        switch op {
        case "all": answer = try allDescriptionsSatisfy(d, predicate)
        case "any": answer = try anyDescriptionSatisfies(d, predicate)
        case "none": answer = try noDescriptionSatisfies(d, predicate)
        default:
          answer =
            try detectDescription(
              d, where: predicate,
              ifNone: {
                missing += 1
                return fallback
              }
            ).map { $0.key } as Any
        }
        row[op] = ["result": answer, "trace": trace, "fallbackCalls": missing]
      }
      trace = []
      do {
        try forEachDescription(d) {
          trace.append($0.key)
          if $0.key == "b" { throw MagritteError("callback") }
        }
        row["callbackError"] = false
      } catch { row["callbackError"] = true }
      row["callbackTrace"] = trace
      trace = []
      other.append(42)
      do {
        try forEachDescriptionPaired(d, with: other) { trace.append($1) }
        row["pairSizeError"] = false
      } catch { row["pairSizeError"] = true }
      row["pairSizeTrace"] = trace
      do {
        _ = try childAt(d, index: d.children.count)
        row["atError"] = false
      } catch { row["atError"] = true }
      do {
        _ = try detectDescription(d) { _ in false }
        row["detectError"] = false
      } catch { row["detectError"] = true }
      XCTAssertEqual(NSDictionary(dictionary: row), NSDictionary(dictionary: expected))
    }
  }
  func testIdentityLimitsAndErrors() throws {
    let d = Description(id: "root", className: "MAContainer")
    let a = field("a")
    let b = field("b")
    d.children = [a, b, a]
    XCTAssertTrue(try childAt(d, index: 0) === a)
    XCTAssertTrue(try childAt(d, index: 2) === a)
    XCTAssertTrue(try detectDescription(d) { $0.key == "a" } === a)
    var visits = 0
    try forEachDescription(d) { _ in visits += 1 }
    XCTAssertEqual(visits, 3)
    XCTAssertEqual(try reduceDescriptions(d, initial: 0) { n, _ in n + 1 }, 3)
    var small = Limits()
    small.items = 2
    XCTAssertThrowsError(try forEachDescription(d, limits: small) { _ in visits += 1 })
    XCTAssertEqual(visits, 3)
    small = Limits()
    small.visits = 2
    XCTAssertThrowsError(try anyDescriptionSatisfies(d, limits: small) { _ in true })
    small = Limits()
    small.visits = 3
    XCTAssertThrowsError(try includesDescription(d, field("absent"), limits: small))
    XCTAssertThrowsError(try enumerationChildren(field("scalar")))
    XCTAssertNil(try childAt(d, index: 99) { nil })
    XCTAssertNil(try detectDescription(d, where: { _ in false }, ifNone: { nil }))
    XCTAssertThrowsError(try childAt(d, index: -1))
    XCTAssertThrowsError(try childAt(d, index: 99) { throw MagritteError("fallback") })
    XCTAssertThrowsError(try detectDescription(d) { _ in throw MagritteError("predicate") })
    XCTAssertThrowsError(
      try forEachDescriptionSeparated(d, { _ in }, separator: { throw MagritteError("separator") }))
    XCTAssertThrowsError(
      try reduceDescriptions(d, initial: 0) { _, _ in throw MagritteError("fold") })
    XCTAssertThrowsError(
      try forEachDescriptionPaired(d, with: [1, 2, 3]) { _, _ in throw MagritteError("pair") })
    let nested = Description(id: "nested", className: "MAContainer")
    nested.children = [a]
    d.children = [nested]
    visits = 0
    try forEachDescription(d) {
      XCTAssertTrue($0 === nested)
      visits += 1
    }
    XCTAssertEqual(visits, 1)
  }
}
