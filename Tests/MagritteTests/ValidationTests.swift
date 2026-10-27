import Foundation
import XCTest

@testable import Magritte

final class ValidationTests: XCTestCase {
  func fixture() throws -> [String: Any] {
    let url = Bundle.module.url(
      forResource: "validation-protocol-scenarios", withExtension: "json", subdirectory: "Fixtures")!
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  }
  func data(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
  }
  func descriptor(_ id: String, _ cls: String = "MAStringDescription") -> Description {
    let d = Description(id: id, className: cls, key: id)
    d.properties["label"] = .string(id)
    return d
  }
  func node(_ error: ValidationIssue?, _ g: Graph) throws -> Any {
    guard let e = error else { return NSNull() }
    XCTAssertTrue(g.descriptions[e.tag.id] === e.tag)
    XCTAssertTrue(e.kindOf("MAValidationError"))
    XCTAssertTrue(e.kindOf("MAError"))
    XCTAssertTrue(e.isResumable)
    return [
      "class": e.code, "description": e.tag.id, "signalText": e.signalText as Any? ?? NSNull(),
      "collection": try e.collection.map { try node($0, g) }, "isResumable": e.isResumable,
    ] as [String: Any]
  }
  func run(_ g: Graph, _ entry: [String: Any]) throws -> ValidationResult {
    if let id = entry["object"] as? String {
      return try validateDetailed(g.objects[id]!, using: g.descriptions[g.root]!, graph: g)
    }
    return try validateValueDetailed(
      decodeValue(data(entry["value"]!)), using: g.descriptions[entry["description"] as! String]!,
      graph: g)
  }
  func report(_ r: ValidationResult, _ g: Graph) throws -> [String: Any] {
    [
      "error": try node(r.error, g),
      "flat": try r.flatErrors().map {
        ["description": $0.descriptionID, "code": $0.code, "message": $0.message]
      }, "print": try r.error?.printString() ?? "",
    ]
  }
  func replay(_ input: [String: Any]) throws -> [String: Any] {
    var output = input
    var rows: [[String: Any]] = []
    for row in input["cases"] as! [[String: Any]] {
      var row = row
      let g = try Graph.decode(data(row["graph"]!))
      let entry = row["entry"] as! [String: Any]
      let result = try run(g, entry)
      XCTAssertEqual(
        try data(report(result, g)), try data(row["expected"]!), row["name"] as! String)
      let wire = try g.encode()
      let clone = try Graph.decode(wire)
      XCTAssertEqual(
        try data(report(run(clone, entry), clone)), try data(row["expected"]!), "Graph roundtrip")
      row["graph"] = try JSONSerialization.jsonObject(with: wire)
      rows.append(row)
    }
    output["cases"] = rows
    return output
  }
  func testSharedSourceCasesAndCrossPortReplay() throws {
    let f = try fixture()
    try ClassRegistry.shared.registerClasses(
      (f["registrations"] as! [[String: String]]).map {
        ClassInfo(name: $0["name"]!, superclass: $0["superclass"]!)
      })
    let exported = try replay(f)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_VALIDATION_OUTPUT"] {
      try data(exported).write(to: URL(fileURLWithPath: path))
    }
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_VALIDATION_INPUT"] {
      let other =
        try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)))
        as! [String: Any]
      _ = try replay(other)
    }
  }
  func testContinuationErrorIdentityAndLifetimes() throws {
    let field = descriptor("field")
    let context = ValidationContext(field)
    var resumed = false
    var skipped = false
    var passed = false
    var signaled: ValidationIssue?
    try context.tryValidation(
      { c in
        signaled = try c.signal("MAKindError", text: nil)
        resumed = true
      }, ifPass: { _ in skipped = true })
    try context.tryValidation({ _ in }, ifPass: { _ in passed = true })
    let result = try context.finish()
    XCTAssertTrue(resumed)
    XCTAssertFalse(skipped)
    XCTAssertTrue(passed)
    XCTAssertTrue(result.error!.collection[0] === signaled)
    XCTAssertNil(signaled!.signalText)
    XCTAssertEqual(signaled!.messageText, "")
    XCTAssertThrowsError(try result.raiseIfInvalid()) { error in
      XCTAssertTrue((error as? ValidationFailure)?.error === result.error)
    }
    field.properties["label"] = .string("Changed")
    XCTAssertEqual(try result.error!.printString(), "Changed: ")
    XCTAssertEqual(result.error!.signalText, "field")
    field.conditions = [Condition(label: nil, test: { _ in false })]
    let nilCondition = try validateValueDetailed(.string("ok"), using: field)
    XCTAssertNil(nilCondition.error!.collection[0].signalText)
    XCTAssertEqual(try nilCondition.flatErrors()[0].message, "")
    field.conditions = []
    try ClassRegistry.shared.registerClass(
      ClassInfo(name: "ValidationLeaf", superclass: "MAValidationError"))
    let custom = ValidationContext(field)
    try custom.signal("ValidationLeaf", text: "custom")
    XCTAssertTrue(try custom.finish().error!.collection[0].kindOf("MAError"))
    XCTAssertThrowsError(try context.signal("Object", text: "bad"))
    weak var weakTag: Description?
    var retained = ValidationResult()
    do {
      let owned = descriptor("owned")
      weakTag = owned
      retained = try validateValueDetailed(.boolean(true), using: owned)
    }
    XCTAssertNotNil(weakTag)
    retained = ValidationResult()
    XCTAssertNil(weakTag)
    XCTAssertTrue(retained.passed)
  }
  func testActualModelTargetsGatesAndContinuation() throws {
    final class State {
      var value: Value = .integer(3)
      var reads = 0, conditions = 0, modelConditions = 0
      var absent = false
    }
    let schema = descriptor("schema", "MAContainer")
    let number = descriptor("number", "MANumberDescription")
    let state = State()
    let model = NativeModel(state)
    try schema.setChildren([number])
    number.properties["min"] = .integer(7)
    try number.setRangeErrorMessage(.string("range"))
    number.nativeRead = { object in
      let s = object as! State
      s.reads += 1
      return s.value
    }
    number.conditions = [
      Condition(
        label: "number condition",
        test: { _ in
          state.conditions += 1
          return false
        })
    ]
    schema.conditions = [
      Condition(
        label: "model condition",
        modelTest: { m in
          XCTAssertTrue(m === model)
          state.modelConditions += 1
          return false
        })
    ]
    var predicate = Predicate()
    predicate.selector = "notEmpty"
    schema.portableConditions = [PortableCondition(label: "portable model", predicate: predicate)]
    model.readers["MASelectorAccessor:notEmpty"] = { _ in .boolean(true) }
    model.binaryReaders["="] = { _, _, _ in .boolean(state.absent) }
    let native = try validateDetailed(model, using: schema)
    let leaves = try native.flatErrors()
    XCTAssertEqual(leaves.count, 3)
    XCTAssertEqual(leaves[0].descriptionID, "schema")
    XCTAssertEqual(leaves[1].code, "MARangeError")
    XCTAssertEqual(leaves[2].code, "MAConditionError")
    XCTAssertEqual(state.modelConditions, 1)
    XCTAssertEqual(state.reads, 1)
    XCTAssertEqual(state.conditions, 1)
    model.readers["MASelectorAccessor:notEmpty"] = { _ in .string("not Boolean") }
    XCTAssertThrowsError(try validateDetailed(model, using: schema))
    model.readers["MASelectorAccessor:notEmpty"] = { _ in .boolean(true) }
    number.properties["readOnly"] = .boolean(true)
    let savedReads = state.reads
    XCTAssertTrue(try validateDetailed(model, using: number).passed)
    XCTAssertEqual(state.reads, savedReads)
    number.properties.removeValue(forKey: "readOnly")
    number.properties["visible"] = .boolean(false)
    _ = try validateDetailed(model, using: schema)
    XCTAssertEqual(state.reads, 2)
    XCTAssertEqual(state.conditions, 1)
    schema.properties["readOnly"] = .boolean(true)
    XCTAssertTrue(try validateDetailed(model, using: schema).passed)
    XCTAssertEqual(state.reads, 2)
    schema.properties.removeValue(forKey: "readOnly")
    number.properties.removeValue(forKey: "visible")
    schema.properties["kind"] = .classValue("String")
    var before = state.modelConditions
    XCTAssertEqual(try validateDetailed(model, using: schema).flatErrors().count, 3)
    XCTAssertEqual(state.modelConditions, before)
    XCTAssertEqual(state.reads, 3)
    schema.properties.removeValue(forKey: "kind")
    state.absent = true
    before = state.modelConditions
    XCTAssertEqual(try validateDetailed(model, using: schema).flatErrors().count, 2)
    XCTAssertEqual(state.modelConditions, before)
    XCTAssertEqual(state.reads, 4)
    state.absent = false
    schema.conditions = []
    predicate.index = 1
    predicate.arguments = [.boolean(true)]
    predicate.selector = "="
    schema.portableConditions = [PortableCondition(label: "unsupported", predicate: predicate)]
    XCTAssertThrowsError(try validateDetailed(model, using: schema))
    schema.portableConditions = []
    schema.conditions = [
      Condition(label: "throws", modelTest: { _ in throw MagritteError("host failure") })
    ]
    XCTAssertThrowsError(try validateDetailed(model, using: schema))
    schema.conditions = []
    XCTAssertFalse(try isSatisfiedBy(.integer(3), using: number))
    XCTAssertTrue(try isSatisfiedBy(.string("ok"), using: descriptor("field")))
    var tiny = Limits()
    tiny.items = 1
    XCTAssertThrowsError(try validateValueDetailed(.integer(3), using: number, limits: tiny))
    tiny = Limits()
    tiny.depth = 0
    XCTAssertThrowsError(try native.flatErrors(limits: tiny))
    tiny = Limits()
    tiny.bytes = 1
    XCTAssertThrowsError(try native.error!.printString(limits: tiny))
  }
  func testMementoNestedValidationAndNilConflict() throws {
    let schema = descriptor("edit", "MAContainer")
    let field = descriptor("data")
    try schema.setChildren([field])
    let model = AdaptiveModel(description: schema, values: ["data": .string("old")])
    let editor = try CheckedMemento(model: model, description: schema)
    var editorChecks = 0
    schema.conditions = [
      Condition(
        label: "editor",
        modelTest: { [weak editor] m in
          XCTAssertTrue(m === editor)
          editorChecks += 1
          return true
        })
    ]
    try editor.write(.string("local"), using: field)
    model.values["data"] = .string("remote")
    try schema.setConflictErrorMessage(.undefined)
    let conflict = try editor.validateDetailed()
    XCTAssertEqual(editorChecks, 0)
    XCTAssertEqual(conflict.error?.code, "MAConflictError")
    XCTAssertTrue(conflict.error?.tag === schema)
    XCTAssertNil(conflict.error?.signalText)
    XCTAssertEqual(try conflict.flatErrors().first?.message, "")
    XCTAssertEqual(try editor.read(using: field), .string("remote"))
    XCTAssertFalse(try editor.hasChanges())
    field.properties["required"] = .boolean(true)
    try editor.write(.undefined, using: field)
    let regular = try editor.validateDetailed()
    XCTAssertEqual(editorChecks, 1)
    XCTAssertEqual(regular.error?.code, "MAMultipleErrors")
    XCTAssertTrue(regular.error?.collection[0].tag === field)
  }
}
