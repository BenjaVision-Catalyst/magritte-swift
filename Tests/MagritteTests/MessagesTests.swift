import Foundation
import Magritte
import XCTest

final class MessagesTests: XCTestCase {
  func value(_ object: Any?) throws -> Value {
    try decodeValue(JSONSerialization.data(withJSONObject: XCTUnwrap(object)))
  }
  func testSharedMessagesAndValidation() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "messages-scenarios", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    for row in try XCTUnwrap(fixture["getters"] as? [[String: Any]]) {
      let d = Description(id: "sample", className: try XCTUnwrap(row["className"] as? String))
      for (key, v) in try XCTUnwrap(row["properties"] as? [String: Any]) {
        d.properties[key] = try value(v)
      }
      let key = try XCTUnwrap(row["key"] as? String)
      let before = d.properties
      XCTAssertEqual(try d.property(key), try value(row["result"]))
      XCTAssertEqual(
        try d.readSlot(strategy: "MASelectorAccessor", name: key), try value(row["result"]))
      XCTAssertEqual(d.properties, before)
    }
    for row in try XCTUnwrap(fixture["validations"] as? [[String: Any]]) {
      let d = Description(id: "sample", className: try XCTUnwrap(row["className"] as? String))
      for (key, v) in try XCTUnwrap(row["properties"] as? [String: Any]) {
        d.properties[key] = try value(v)
      }
      let reference = Description(id: "reference")
      if d.isReference { d.reference = reference }
      if d.isRelation { d.classes = ["String"] }
      let errors = try Magritte.validateValue(value(row["value"]), using: d)
      let expected = try XCTUnwrap(row["errors"] as? [[String: String]])
      XCTAssertEqual(errors.map { ["code": $0.code, "message": $0.message] }, expected)
      XCTAssertTrue(errors.allSatisfy { $0.descriptionID == d.id })
    }
  }
  func testGeneratedRangeTimingAndFailure() throws {
    let d = Description(id: "number", className: "MANumberDescription", key: "number")
    d.properties = ["min": .integer(2), "max": .integer(8)]
    var trace: [Value] = []
    d.display(
      DisplayBlock { v in
        trace.append(v)
        return "bound"
      })
    XCTAssertEqual(try d.rangeErrorMessage(), .string("Input must be between bound and bound"))
    XCTAssertEqual(trace, [.integer(2), .integer(8)])
    try d.setRangeErrorMessage(.string("override"))
    trace.removeAll()
    XCTAssertEqual(try d.rangeErrorMessage(), .string("override"))
    XCTAssertTrue(trace.isEmpty)
    d.properties.removeValue(forKey: "rangeErrorMessage")
    d.display(
      DisplayBlock { v in
        if trace.isEmpty { d.properties["max"] = .integer(9) }
        trace.append(v)
        return "b"
      })
    XCTAssertEqual(try d.rangeErrorMessage(), .string("Input must be between b and b"))
    XCTAssertEqual(trace, [.integer(2), .integer(9)])
    trace.removeAll()
    d.display(
      DisplayBlock { _ in
        d.properties["min"] = .undefined
        d.properties["max"] = .undefined
        return "b"
      })
    XCTAssertEqual(try d.rangeErrorMessage(), .undefined)
    d.display(DisplayBlock { throw MagritteError("writer") })
    d.properties["min"] = .integer(2)
    XCTAssertThrowsError(try d.rangeErrorMessage())
    try d.setRangeErrorMessage(.string("safe"))
    XCTAssertEqual(try d.rangeErrorMessage(), .string("safe"))
    // Remove callbacks retaining d before leaving this local probe.
    d.display("asString")
  }
  func testNilOverridesConditionsAndOptionChild() throws {
    let d = Description(id: "text", key: "text")
    XCTAssertTrue(try d.setRequiredErrorMessage(.string("required")) === d)
    XCTAssertTrue(try d.setKindErrorMessage(.string("kind")) === d)
    XCTAssertTrue(try d.setConflictErrorMessage(.string("conflict")) === d)
    try d.setKindErrorMessage(.undefined)
    XCTAssertEqual(try d.kindErrorMessage(), .undefined)
    XCTAssertThrowsError(try Magritte.validateValue(.boolean(true), using: d))
    XCTAssertTrue(try Magritte.validateValue(.string("ok"), using: d).isEmpty)
    d.properties["visible"] = .boolean(false)
    XCTAssertTrue(try Magritte.validateValue(.boolean(true), using: d).isEmpty)
    d.properties.removeValue(forKey: "visible")
    XCTAssertThrowsError(try d.setKindErrorMessage(.boolean(true)))
    XCTAssertEqual(try d.kindErrorMessage(), .undefined)
    XCTAssertThrowsError(try d.rangeErrorMessage())
    XCTAssertThrowsError(try d.setRangeErrorMessage(.string("x")))
    d.properties.removeValue(forKey: "kindErrorMessage")
    d.conditions = [Condition(label: "condition", test: { _ in false })]
    XCTAssertEqual(
      try Magritte.validateValue(.string("ok"), using: d).map(\.message), ["condition"])
    let option = Description(id: "option", className: "MASingleOptionDescription")
    let child = Description(id: "child", className: "MANumberDescription")
    try child.setKindErrorMessage(.string("child message"))
    option.reference = child
    option.properties["extensible"] = .boolean(true)
    try option.setKindErrorMessage(.string("parent message"))
    let errors = try Magritte.validateValue(.string("bad"), using: option)
    XCTAssertEqual(errors.count, 1)
    XCTAssertEqual(errors.first?.descriptionID, child.id)
    XCTAssertEqual(errors.first?.message, "child message")
  }
  func testConflictMetadataCopyWireAndLimits() throws {
    let root = Description(id: "root", className: "MAContainer")
    let field = Description(id: "data", key: "data")
    root.children = [field]
    let model = AdaptiveModel(description: root, values: [field.id: .string("old")])
    let editor = try CheckedMemento(model: model, description: root)
    try editor.write(.string("local"), using: field)
    model.values[field.id] = .string("remote")
    try root.setConflictErrorMessage(.string("concurrent"))
    let errors = try editor.validate()
    XCTAssertEqual(errors.count, 1)
    XCTAssertEqual(errors.first?.descriptionID, root.id)
    XCTAssertEqual(errors.first?.message, "concurrent")
    XCTAssertEqual(try editor.read(using: field), .string("remote"))
    XCTAssertFalse(try editor.hasChanges())
    try root.setConflictErrorMessage(.undefined)
    try editor.write(.string("local2"), using: field)
    model.values[field.id] = .string("remote2")
    XCTAssertThrowsError(try editor.validate())
    XCTAssertEqual(try editor.read(using: field), .string("remote2"))
    XCTAssertFalse(try editor.hasChanges())
    try root.setConflictErrorMessage(.string("concurrent"))
    try field.writeSlot(
      strategy: "MASelectorAccessor", name: "requiredErrorMessage:", value: .string("required"))
    try field.writeSlot(
      strategy: "MASelectorAccessor", name: "kindErrorMessage:", value: .string("kind"))
    let copy = try copyDescription(field, newID: "copy")
    try copy.root.setKindErrorMessage(.string("copied"))
    XCTAssertEqual(try field.kindErrorMessage(), .string("kind"))
    let numeric = Description(id: "score", className: "MANumberDescription", key: "score")
    try numeric.writeSlot(
      strategy: "MASelectorAccessor", name: "rangeErrorMessage:", value: .string("range"))
    root.children.append(numeric)
    let g = Graph(
      root: root.id, descriptions: [root.id: root, field.id: field, numeric.id: numeric])
    g.format = "magritte.graph/4"
    let wire = try g.encode()
    let imported = try Graph.decode(wire)
    XCTAssertEqual(try imported.encode(), wire)
    XCTAssertEqual(try imported.descriptions[numeric.id]?.rangeErrorMessage(), .string("range"))
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_MESSAGES_EXPORT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
    g.format = "magritte.graph/3"
    XCTAssertEqual(
      try Graph.decode(g.encode()).descriptions[root.id]?.conflictErrorMessage(),
      .string("concurrent"))
    g.format = "magritte.graph/2"
    XCTAssertThrowsError(try g.encode())
    field.properties["kindErrorMessage"] = .boolean(false)
    g.format = "magritte.graph/4"
    XCTAssertThrowsError(try g.encode())
    field.properties["kindErrorMessage"] = .undefined
    XCTAssertEqual(
      try Graph.decode(g.encode()).descriptions[field.id]?.kindErrorMessage(), .undefined)
    var low = Limits()
    low.bytes = 1
    XCTAssertThrowsError(try field.requiredErrorMessage(limits: low))
    XCTAssertThrowsError(try field.setRequiredErrorMessage(.string("too long"), limits: low))
    XCTAssertEqual(try field.requiredErrorMessage(), .string("required"))
  }
}
