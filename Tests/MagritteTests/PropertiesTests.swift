import Foundation
import Magritte
import XCTest

final class PropertiesTests: XCTestCase {
  let key = "metadata:key"
  func value(_ object: Any?) throws -> Value {
    try decodeValue(JSONSerialization.data(withJSONObject: XCTUnwrap(object)))
  }
  func testSharedPropertyCases() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "properties-scenarios", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    for row in try XCTUnwrap(fixture["cases"] as? [[String: Any]]) {
      let d = Description(id: "sample")
      if !(row["initial"] is NSNull) { d.properties[key] = try value(row["initial"]) }
      var trace: [String] = []
      func absent() -> Value {
        trace.append("absent")
        return .string("fallback")
      }
      func present(_ v: Value) throws -> Value {
        XCTAssertEqual(v, try d.propertyAt(key))
        trace.append("present")
        return .string("present")
      }
      func run() throws -> Value {
        switch row["operation"] as? String {
        case "get": return try d.propertyAt(key)
        case "fallback": return try d.propertyAt(key, ifAbsent: absent)
        case "absentPut": return try d.propertyAtIfAbsentPut(key, absent)
        case "present": return try d.propertyAtIfPresent(key, present)
        case "presentElse":
          return try d.propertyAtIfPresentOrElse(key, present: present, absent: absent)
        case "presentPut":
          return try d.propertyAtIfPresentOrPut(key, present: present, absent: absent)
        case "put": return try d.propertyPut(key, .string("replacement"))
        case "putNil": return try d.propertyPut(key, .undefined)
        case "removingSet": return try d.propertyPutRemovingNil(key, .string("replacement"))
        default: return try d.propertyPutRemovingNil(key, .undefined)
        }
      }
      if row["result"] is NSNull {
        XCTAssertThrowsError(try run())
      } else {
        XCTAssertEqual(try run(), try value(row["result"]))
      }
      XCTAssertEqual(trace, row["trace"] as? [String])
      XCTAssertEqual(d.hasProperty(key), row["hasProperty"] as? Bool)
      if d.hasProperty(key) { XCTAssertEqual(try d.propertyAt(key), try value(row["stored"])) }
    }
  }
  func testAbsenceDefaultsReentrancyAndFailures() throws {
    let d = Description(id: "special")
    XCTAssertFalse(d.hasProperty("visible"))
    XCTAssertEqual(try d.property("visible"), .boolean(true))
    XCTAssertThrowsError(try d.propertyAt("visible"))
    XCTAssertEqual(try d.propertyAt("visible", ifAbsent: { .boolean(false) }), .boolean(false))
    XCTAssertFalse(d.hasProperty("visible"))
    try d.propertyPut(key, .undefined)
    XCTAssertEqual(try d.propertyAtIfAbsentPut(key, { throw MagritteError("unused") }), .undefined)
    XCTAssertEqual(
      try d.propertyAtIfPresentOrElse(
        key, present: { $0 }, absent: { throw MagritteError("unused") }), .undefined)
    try d.propertyPutRemovingNil(key, .undefined)
    XCTAssertEqual(
      try d.propertyAtIfPresent(key, { _ in throw MagritteError("unused") }), .undefined)
    XCTAssertThrowsError(try d.propertyAtIfAbsentPut(key, { throw MagritteError("callback") }))
    XCTAssertFalse(d.hasProperty(key))
    func reentrant() throws -> Value {
      try d.propertyPut(key, .string("inner"))
      return .string("outer")
    }
    XCTAssertEqual(try d.propertyAt(key, ifAbsent: reentrant), .string("outer"))
    XCTAssertEqual(try d.propertyAt(key), .string("inner"))
    try d.propertyPutRemovingNil(key, .undefined)
    XCTAssertEqual(try d.propertyAtIfAbsentPut(key, reentrant), .string("outer"))
    XCTAssertEqual(try d.propertyAt(key), .string("outer"))
    XCTAssertEqual(
      try d.propertyAtIfPresent(
        key,
        { v in
          d.properties.removeAll()
          return v
        }), .string("outer"))
    XCTAssertFalse(d.hasProperty(key))
  }
  func testAccessorAndLocalSlotBoundaries() throws {
    let d = Description(id: "special")
    var property = Accessor(className: "MAPropertyAccessor", name: key)
    XCTAssertEqual(try property.read(d), .undefined)
    try property.write(.boolean(false), to: d)
    XCTAssertTrue(d.hasProperty(key))
    XCTAssertEqual(try d.propertyAt(key), .boolean(false))
    d.display(DisplayBlock { "local" })
    XCTAssertTrue(d.hasProperty("displayBlockOrSymbol"))
    XCTAssertThrowsError(try d.propertyAt("displayBlockOrSymbol"))
    XCTAssertThrowsError(try d.propertyPutRemovingNil("displayBlockOrSymbol", .undefined))
    XCTAssertNotNil(d.displayBlock)
    property.name = "displayBlockOrSymbol"
    try property.write(.symbol("asString"), to: d)
    XCTAssertNil(d.displayBlock)
    XCTAssertEqual(try d.propertyAt("displayBlockOrSymbol"), .symbol("asString"))
    let owner = Description(id: "owner", className: "MASingleOptionDescription")
    let reference = Description(id: "reference")
    owner.reference = reference
    reference.properties["undefined"] = .string("old")
    try owner.propertyPut("undefined", .string("raw"))
    XCTAssertEqual(try reference.property("undefined"), .string("old"))
    try owner.setUndefined(.string("setter"))
    XCTAssertEqual(try reference.property("undefined"), .string("setter"))
    XCTAssertThrowsError(try d.propertyPut("propertyAnnouncer", .undefined))
    XCTAssertFalse(d.hasProperty("propertyAnnouncer"))
    d.properties["propertyAnnouncer"] = .undefined
    XCTAssertThrowsError(try d.propertyPut(key, .integer(7)))
  }
  func testCopyWireAndBounds() throws {
    let d = Description(id: "data", key: "data")
    try d.propertyPut(key, .undefined)
    let copy = try copyDescription(d, newID: "copied")
    XCTAssertTrue(copy.root.hasProperty(key))
    try copy.root.propertyPut(key, .string("copy"))
    XCTAssertEqual(try d.propertyAt(key), .undefined)
    let root = Description(id: "root", className: "MAContainer")
    root.children = [d]
    let g = Graph(root: root.id, descriptions: [root.id: root, d.id: d])
    g.format = "magritte.graph/4"
    let wire = try g.encode()
    let imported = try Graph.decode(wire)
    XCTAssertTrue(try XCTUnwrap(imported.descriptions[d.id]).hasProperty(key))
    XCTAssertEqual(try imported.descriptions[d.id]?.propertyAt(key), .undefined)
    XCTAssertEqual(try imported.encode(), wire)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_PROPERTIES_EXPORT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
    try d.propertyPut("customSemantic", .boolean(true))
    XCTAssertThrowsError(try g.encode())
    d.properties.removeValue(forKey: "customSemantic")
    var low = Limits()
    low.visits = 1
    XCTAssertThrowsError(try d.propertyAtIfAbsentPut(key, { .undefined }, limits: low))
    XCTAssertThrowsError(try d.propertyPut("bad key", .undefined))
    XCTAssertThrowsError(try d.propertyPut("", .undefined))
  }
}
