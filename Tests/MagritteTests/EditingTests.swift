import Foundation
import XCTest

@testable import Magritte

final class EditingTests: XCTestCase {
  func testNativeAccessorsAndDefaultEvaluation() throws {
    final class State {
      var value: Value = .undefined
      var reads = 0, writes = 0, defaults = 0
    }
    for mode in 0..<3 {
      let state = State()
      let root = Description(id: "root", className: "MAContainer")
      let d = Description(id: "value", className: "MANumberDescription")
      root.children = [d]
      d.nativeRead = { object in
        let s = object as! State
        s.reads += 1
        return s.value
      }
      d.nativeWrite = { object, value in
        let s = object as! State
        s.writes += 1
        s.value = value
      }
      d.defaultFunction = {
        state.defaults += 1
        return .integer(5)
      }
      let model = NativeModel(state)
      let m: Memento
      if mode == 0 {
        m = try StraightMemento(model: model, description: root)
      } else if mode == 1 {
        m = try CachedMemento(model: model, description: root)
      } else {
        m = try CheckedMemento(model: model, description: root)
      }
      XCTAssertEqual(state.reads, mode == 0 ? 0 : mode == 1 ? 1 : 2)
      XCTAssertEqual(state.defaults, mode == 0 ? 0 : 1)
      XCTAssertEqual(try m.read(using: d), .integer(5))
      XCTAssertEqual(try m.read(using: d), .integer(5))
      XCTAssertEqual(state.defaults, mode == 0 ? 2 : 1)
      try m.write(.integer(8), using: d)
      try m.commit()
      XCTAssertEqual(state.value, .integer(8))
      XCTAssertEqual(state.writes, 1)
    }
  }
  func testEditingBoundsAndDescriptorChanges() throws {
    let root = Description(id: "root", className: "MAContainer")
    let a = Description(id: "a", key: "a")
    let b = Description(id: "b", key: "b")
    a.properties["default"] = .string("Default")
    root.children = [a, b]
    let model = DictionaryModel(["a": .string("Default")])
    let cache = try CachedMemento(model: model, description: root)
    try cache.write(.undefined, using: a)
    XCTAssertFalse(try cache.hasChanges())
    try cache.commit()
    XCTAssertEqual(model.values["a"], .string("Default"))
    let foreign = Description(id: "a", key: "a")
    XCTAssertThrowsError(try cache.read(using: foreign))
    XCTAssertThrowsError(try cache.write(.string("x"), using: foreign))
    var tiny = Limits()
    tiny.visits = 1
    XCTAssertThrowsError(try CachedMemento(model: model, description: root, limits: tiny))
    root.children.append(root)
    XCTAssertThrowsError(try CachedMemento(model: model, description: root))
    root.children.removeLast()
    root.children.append(Description(id: "nested", className: "MAContainer"))
    XCTAssertThrowsError(try CachedMemento(model: model, description: root))
    root.children.removeLast()
    root.children.append(a)
    XCTAssertThrowsError(try CachedMemento(model: model, description: root))
    root.children.removeLast()
    root.children[0] = foreign
    XCTAssertThrowsError(try cache.hasChanges())
    try cache.reset()
    XCTAssertEqual(try cache.read(using: foreign), .string("Default"))
    root.children[0] = a
    try cache.reset()
    var aggregate = Limits()
    aggregate.visits = 100
    let bounded = try CachedMemento(model: model, description: root, limits: aggregate)
    try bounded.write(.string(String(repeating: "x", count: 60)), using: a)
    XCTAssertThrowsError(try bounded.write(.string(String(repeating: "y", count: 60)), using: b))
    XCTAssertEqual(try bounded.read(using: b), .undefined)
    weak var retained: DictionaryModel?
    var owner: CachedMemento?
    do {
      let local = DictionaryModel()
      retained = local
      owner = try CachedMemento(model: local, description: root)
    }
    XCTAssertNotNil(retained)
    XCTAssertNotNil(owner)
    owner = nil
    XCTAssertNil(retained)
  }
  func testCommitFailurePreservesPendingEdits() throws {
    final class State { var values: [String: Value] = [:] }
    let state = State()
    let root = Description(id: "root", className: "MAContainer")
    let a = Description(id: "a")
    let b = Description(id: "b")
    root.children = [a, b]
    for d in [a, b] {
      let key = d.id
      d.nativeRead = { ($0 as! State).values[key] ?? .undefined }
      d.nativeWrite = { object, value in
        if key == "b" { throw MagritteError("write failed") }
        (object as! State).values[key] = value
      }
    }
    let editor = try CachedMemento(model: NativeModel(state), description: root)
    try editor.write(.string("First"), using: a)
    try editor.write(.string("Second"), using: b)
    XCTAssertThrowsError(try editor.commit())
    XCTAssertEqual(state.values["a"], .string("First"))
    XCTAssertEqual(try editor.read(using: b), .string("Second"))
    let meta = try descriptionModelFor(a)
    XCTAssertThrowsError(
      try a.write(.string("Bogus"), using: XCTUnwrap(meta.descriptions[meta.root + ".type"])))
  }
  func fixture(_ name: String) throws -> Any {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
  }
  func data(_ any: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: any, options: .sortedKeys)
  }
  func array(_ any: Any?) throws -> [[String: Any]] { try XCTUnwrap(any as? [[String: Any]]) }
  func object(_ any: Any?) throws -> [String: Any] { try XCTUnwrap(any as? [String: Any]) }
  func string(_ any: Any?) throws -> String { try XCTUnwrap(any as? String) }
  func value(_ any: Any?) throws -> Value { try decodeValue(data(XCTUnwrap(any))) }
  func values(_ values: [String: Value]) throws -> [String: Any] {
    try values.mapValues { try JSONSerialization.jsonObject(with: encodeValue($0)) }
  }
  func errors(_ errors: [ValidationError]) -> [[String: String]] {
    errors.map { ["code": $0.code, "description": $0.descriptionID] }
  }
  func snapshot(_ m: Memento, _ g: Graph, _ errors: [[String: String]]) throws -> [String: Any] {
    var reads: [String: Any] = [:]
    var readErrors: [String] = []
    for d in try m.description.orderedChildren() {
      do {
        reads[d.id] = try JSONSerialization.jsonObject(with: encodeValue(m.read(using: d)))
      } catch { readErrors.append(d.id) }
    }
    var result: [String: Any] = [
      "errors": errors, "reads": reads, "readErrors": readErrors,
      "stored": try values(XCTUnwrap(g.objects["model"]).values),
      "peerStored": try values(XCTUnwrap(g.objects["peerModel"]).values),
    ]
    if let cached = m as? CachedMemento {
      result["cache"] = try values(cached.cache)
      result["hasChanges"] = try cached.hasChanges()
    }
    if let checked = m as? CheckedMemento {
      result["original"] = try values(checked.original)
      result["hasModelChangedElsewhere"] = try checked.hasModelChangedElsewhere()
      result["hasConflict"] = try checked.hasConflict()
    }
    return result
  }
  func testGTEditingScenarios() throws {
    let reference = try object(fixture("editing-reference"))
    let scenarios = try array(fixture("editing-scenarios"))
    let cases = try array(reference["cases"])
    XCTAssertEqual(cases.count, 48)
    XCTAssertEqual(try cases.reduce(0) { try $0 + array($1["snapshots"]).count }, 201)
    for c in cases {
      let g = try Graph.decode(data(XCTUnwrap(c["graph"])))
      let root = try XCTUnwrap(g.descriptions[g.root])
      let model = try XCTUnwrap(g.objects["model"])
      let m: Memento
      switch try string(c["memento"]) {
      case "MAStraightMemento": m = try StraightMemento(model: model, description: root, graph: g)
      case "MACachedMemento": m = try CachedMemento(model: model, description: root, graph: g)
      default: m = try CheckedMemento(model: model, description: root, graph: g)
      }
      let snapshots = try array(c["snapshots"])
      let name = try string(c["name"])
      XCTAssertEqual(
        try data(snapshot(m, g, [])), try data(snapshots[0]), "GT initial: \(name) \(type(of: m))")
      let scenario = try XCTUnwrap(scenarios.first { ($0["name"] as? String) == name })
      for (i, step) in try array(scenario["steps"]).enumerated() {
        var result: [[String: String]] = []
        do {
          let d = g.descriptions[step["field"] as? String ?? ""]
          switch try string(step["action"]) {
          case "write": try m.write(value(step["value"]), using: XCTUnwrap(d))
          case "external": try model.write(value(step["value"]), using: XCTUnwrap(d))
          case "externalObject":
            try XCTUnwrap(g.objects["peerModel"]).write(value(step["value"]), using: XCTUnwrap(d))
          case "property": try XCTUnwrap(d).properties[string(step["key"])] = value(step["value"])
          case "addField": root.children.append(try XCTUnwrap(g.descriptions["extra"]))
          case "removeField": root.children.removeAll { $0 === g.descriptions["name"] }
          case "reset": try m.reset()
          case "commit": try m.commit()
          case "validate": result = try errors(m.validate())
          default: XCTFail("Unknown scenario action")
          }
        } catch { result = [["code": "runtimeError", "description": "editor"]] }
        XCTAssertEqual(
          try data(snapshot(m, g, result)), try data(snapshots[i + 1]),
          "GT snapshot: \(name) \(type(of: m)) step \(i + 1)")
      }
      if name == "ordinary-edit", m is CheckedMemento {
        let score = try XCTUnwrap(g.descriptions["score"])
        let meta = try descriptionModelFor(score)
        let metadata = try CheckedMemento(
          model: score, description: XCTUnwrap(meta.descriptions[meta.root]), graph: meta)
        try metadata.write(.integer(7), using: XCTUnwrap(meta.descriptions[meta.root + ".min"]))
        XCTAssertTrue(try metadata.validate().isEmpty)
        try metadata.commit()
        XCTAssertEqual(try m.validate().first?.code, "MARangeError")
        try m.write(.integer(8), using: score)
        XCTAssertTrue(try m.validate().isEmpty)
        try m.commit()
        if let path = ProcessInfo.processInfo.environment["MAGRITTE_EDITING_EXPORT"] {
          try g.encode().write(to: URL(fileURLWithPath: path))
        }
      }
    }
  }
  func testPinnedWriteFiltering() throws {
    let reference = try object(fixture("editing-reference"))
    let cases = try array(reference["cases"])
    let g = try Graph.decode(data(XCTUnwrap(cases[0]["graph"])))
    let writes = try array(reference["writes"])
    XCTAssertEqual(writes.count, 486)
    XCTAssertEqual(writes.filter { ($0["live"] as? Bool) != ($0["result"] as? Bool) }.count, 8)
    for c in writes {
      let d = try XCTUnwrap(g.descriptions[string(c["description"])])
      XCTAssertEqual(
        try d.shouldWrite(value(c["candidate"]), over: value(c["previous"])), c["result"] as? Bool)
    }
  }
  func testGTSelfDescriptionAndMetadataEditing() throws {
    let cases = try array(fixture("self-description-reference"))
    XCTAssertEqual(cases.count, 14)
    for c in cases {
      let target = Description(
        id: "target", className: try string(c["class"]), key: try string(c["key"]))
      for (key, v) in try object(c["properties"]) { target.properties[key] = try value(v) }
      for (key, v) in try object(c["slots"]) { target.properties[key] = try value(v) }
      let meta = try descriptionModelFor(target)
      let root = try XCTUnwrap(meta.descriptions[meta.root])
      XCTAssertEqual(
        try data(
          withoutHistoricalLabelDefaults(object(JSONSerialization.jsonObject(with: meta.encode())))),
        try data(withoutHistoricalLabelDefaults(object(XCTUnwrap(c["graph"])))),
        "GT metadata graph: \(target.className)")
      for read in try array(c["reads"]) {
        XCTAssertEqual(
          try target.read(using: XCTUnwrap(meta.descriptions[string(read["field"])])),
          try value(read["value"]))
      }
      XCTAssertEqual(
        try data(errors(validate(target, using: root, graph: meta))),
        try data(XCTUnwrap(c["validation"])))
      let editor = try CheckedMemento(model: target, description: root, graph: meta)
      for edit in try array(c["edits"]) {
        try editor.write(
          value(edit["value"]), using: XCTUnwrap(meta.descriptions[string(edit["field"])]))
      }
      XCTAssertEqual(try target.property("label"), .string("Custom"))
      for read in try array(c["stagedReads"]) {
        XCTAssertEqual(
          try editor.read(using: XCTUnwrap(meta.descriptions[string(read["field"])])),
          try value(read["value"]))
      }
      XCTAssertEqual(try data(errors(editor.validate())), try data(XCTUnwrap(c["editValidation"])))
      try editor.commit()
      for read in try array(c["finalReads"]) {
        XCTAssertEqual(
          try target.read(using: XCTUnwrap(meta.descriptions[string(read["field"])])),
          try value(read["value"]))
      }
      if target.className == "MANumberDescription" {
        XCTAssertEqual(
          try Magritte.validateValue(.integer(5), using: target).map(\.code),
          c["sampleValidation"] as? [String])
      }
    }
  }
}
