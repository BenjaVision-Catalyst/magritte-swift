import Foundation
import XCTest

@testable import Magritte

final class BootstrapTests: XCTestCase {
  func fixture() throws -> [String: Any] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "bootstrap-reference", withExtension: "json", subdirectory: "Fixtures"))
    return try object(JSONSerialization.jsonObject(with: Data(contentsOf: url)))
  }
  func object(_ value: Any?) throws -> [String: Any] { try XCTUnwrap(value as? [String: Any]) }
  func rows(_ value: Any?) throws -> [[String: Any]] { try XCTUnwrap(value as? [[String: Any]]) }
  func text(_ value: Any?) throws -> String { try XCTUnwrap(value as? String) }
  func data(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
  }
  func value(_ json: Any?) throws -> Value { try decodeValue(data(XCTUnwrap(json))) }
  func canonical(_ json: Any) throws -> Data {
    // These GT fixtures describe a selected class environment; other tests may register additional classes.
    let coreURL = try XCTUnwrap(
      Bundle.module.url(
        forResource: "registration-core-classes", withExtension: "json", subdirectory: "Fixtures"))
    let core = try JSONSerialization.jsonObject(with: Data(contentsOf: coreURL)) as! [[String: Any]]
    let available = Set(core.map { $0["name"] as! String })

    var j = withoutHistoricalLabelDefaults(try object(json))
    var descriptions = try rows(j["descriptions"])
    for i in descriptions.indices {
      if let classes = descriptions[i]["classes"] as? [String] {
        descriptions[i]["classes"] = classes.filter { available.contains($0) }.sorted()
      }
    }
    for i in descriptions.indices {
      if let options = descriptions[i]["options"] as? [[String: Any]] {
        descriptions[i]["options"] = options.filter {
          $0["type"] as? String != "class" || available.contains($0["value"] as? String ?? "")
        }
      }
    }
    j["descriptions"] = descriptions.sorted { ($0["id"] as! String) < ($1["id"] as! String) }
    return try data(j)
  }
  final class Example {
    let app = Description(id: "app", className: "MAContainer"),
      score = Description(id: "score", className: "MANumberDescription", key: "score"),
      link = Description(id: "link", className: "MAToOneRelationDescription", key: "link")
    init() {
      app.properties["label"] = .string("App")
      score.properties = [
        "label": .string("score"), "min": .integer(0), "max": .integer(10),
        "required": .boolean(true), "default": .integer(2),
      ]
      link.reference = app
      link.classes = ["MAMemento"]
      link.properties["label"] = .string("link")
      app.children = [score, link]
    }
    func model() -> AdaptiveModel {
      AdaptiveModel(id: "sample", description: app, values: ["score": .integer(3)])
    }
  }
  func editor(_ cls: String, _ model: Model, _ description: Description) throws -> Memento {
    if cls == "MAStraightMemento" {
      return try StraightMemento(model: model, description: description)
    }
    if cls == "MACachedMemento" { return try CachedMemento(model: model, description: description) }
    return try CheckedMemento(model: model, description: description)
  }
  func snapshot(_ editor: Memento, _ model: Model, _ example: Example, _ phase: String) throws
    -> [String: Any]
  {
    var j: [String: Any] = [
      "phase": phase,
      "value": try JSONSerialization.jsonObject(
        with: encodeValue(editor.read(using: example.score))),
      "model": try JSONSerialization.jsonObject(
        with: encodeValue(model.read(using: example.score))),
      "sameDescription": editor.description === example.app, "sameModel": editor.model === model,
    ]
    if let cached = editor as? CachedMemento { j["changes"] = try cached.hasChanges() }
    if let checked = editor as? CheckedMemento {
      j["conflict"] = try checked.hasConflict()
      j["elsewhere"] = try checked.hasModelChangedElsewhere()
    }
    return j
  }
  func testGTMementoSelfDescriptionAndNestedEditing() throws {
    let f = try fixture()
    for name in try XCTUnwrap(f["registry"] as? [String]) {
      XCTAssertNotNil(ClassRegistry.shared.find(name))
    }
    for row in try rows(f["mementos"]) {
      let e = Example()
      let model = e.model()
      let m = try editor(text(row["class"]), model, e.app)
      let session = RecursiveDescriptionModel()
      XCTAssertTrue(try session.bind("editor", m) === m)
      XCTAssertTrue(try session.describe("editor", m) === e.app)
      for kind in try rows(row["kinds"]) {
        XCTAssertEqual(m.kindOf(try text(kind["class"])), kind["result"] as? Bool)
      }
      let expected = try rows(row["snapshots"])
      func verify(_ index: Int, _ phase: String) throws {
        XCTAssertEqual(try data(snapshot(m, model, e, phase)), try data(expected[index]))
      }
      try verify(0, "initial")
      try m.write(.integer(5), using: e.score)
      try verify(1, "inner-write")
      let outer = try CheckedMemento(
        model: session.bind("editor", m), description: session.describe("editor", m),
        graph: session.resolver)
      try outer.write(.integer(8), using: e.score)
      XCTAssertTrue(try outer.validate().isEmpty)
      try outer.commit()
      try verify(2, "outer-commit")
      XCTAssertTrue(try m.validate().isEmpty)
      try m.commit()
      try verify(3, "inner-commit")
      try model.write(.integer(6), using: e.score)
      try verify(4, "external-write")
      XCTAssertEqual(try m.validate().map(\.code), row["validation"] as? [String])
      try verify(5, "validate")
      try m.reset()
      try verify(6, "reset")
      XCTAssertTrue(
        try Magritte.validateValue(.reference("editor"), using: e.link, graph: session.resolver)
          .isEmpty)
      XCTAssertThrowsError(try session.resolver.encode())
    }
  }
  func testGTRecursiveBootstrapAndMetadataMementos() throws {
    let f = try fixture()
    let e = Example()
    let session = RecursiveDescriptionModel()
    let batch = try session.bootstrap(e.app)
    XCTAssertEqual(
      try canonical(JSONSerialization.jsonObject(with: batch.encode())),
      try canonical(XCTUnwrap(f["bootstrap"])))
    XCTAssertEqual(batch.descriptions.count, 74)
    for row in try rows(f["schemas"]) {
      let id = try text(object(row["graph"])["root"])
      let schema = try XCTUnwrap(session.resolver.descriptions[id])
      let target = id == "bootstrap.1.app" ? e.app : id == "bootstrap.2.score" ? e.score : e.link
      let binding = try session.bind(target)
      for read in try rows(row["reads"]) {
        XCTAssertEqual(
          try binding.read(using: XCTUnwrap(session.resolver.descriptions[text(read["field"])])),
          try value(read["value"]))
      }
      XCTAssertTrue(try validate(binding, using: schema, graph: session.resolver).isEmpty)
    }
    let scoreSchema = try XCTUnwrap(batch.descriptions["bootstrap.2.score"])
    let target = try session.bind(e.score)
    let constraints = try CheckedMemento(
      model: target, description: scoreSchema, graph: session.resolver)
    XCTAssertTrue(try session.describe("constraints", constraints) === scoreSchema)
    let outer = try CheckedMemento(
      model: session.bind("constraints", constraints), description: scoreSchema,
      graph: session.resolver)
    let minimum = try XCTUnwrap(batch.descriptions["bootstrap.2.score.min"])
    try outer.write(.integer(7), using: minimum)
    XCTAssertTrue(try outer.validate().isEmpty)
    try outer.commit()
    XCTAssertEqual(try e.score.property("min"), .integer(0))
    let edit = try object(f["metadataEdit"])
    XCTAssertEqual(try constraints.read(using: minimum), try value(edit["stagedMin"]))
    XCTAssertTrue(try constraints.validate().isEmpty)
    try constraints.commit()
    XCTAssertEqual(try e.score.property("min"), try value(edit["committedMin"]))
    let model = e.model()
    model.values["score"] = .integer(9)
    let appEditor = try CheckedMemento(model: model, description: e.app, graph: session.resolver)
    XCTAssertTrue(try session.describe("app-editor", appEditor) === e.app)
    let notes = Description(id: "notes", key: "notes")
    e.app.children.append(notes)
    try appEditor.reset()
    let graph = try session.schemas()
    XCTAssertTrue(graph.descriptions["notes"] === notes)
    graph.root = "app"
    graph.objects[model.id] = model
    XCTAssertThrowsError(try graph.encode())
    for d in [e.app, e.score, e.link] { try d.materializeAccessor() }
    let wire = try graph.encode()
    let imported = try Graph.decode(wire)
    XCTAssertEqual(try imported.encode(), wire)
    XCTAssertTrue(
      try validate(
        XCTUnwrap(imported.objects["sample"]), using: XCTUnwrap(imported.descriptions["app"]),
        graph: imported
      ).isEmpty)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_BOOTSTRAP_EXPORT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
    for cls in try XCTUnwrap(f["classValues"] as? [Any]) {
      XCTAssertEqual(
        try data(JSONSerialization.jsonObject(with: encodeValue(value(cls)))), try data(cls))
    }
  }
  func testBootstrapBoundsAndBindingIdentity() throws {
    let e = Example()
    let model = e.model()
    let editor = try CheckedMemento(model: model, description: e.app)
    let session = RecursiveDescriptionModel()
    XCTAssertThrowsError(try session.bind("app", editor))
    XCTAssertTrue(session.resolver.nativeObjects.isEmpty)
    _ = try session.bind("editor", editor)
    XCTAssertThrowsError(try session.bind("other", editor))
    XCTAssertThrowsError(
      try session.bind("editor", CheckedMemento(model: model, description: e.app)))
    var tiny = Limits()
    tiny.nodes = 60
    let bounded = RecursiveDescriptionModel(limits: tiny)
    _ = try bounded.bind(e.app)
    XCTAssertThrowsError(try bounded.bootstrap(e.app))
    XCTAssertTrue(try bounded.schemas().descriptions.isEmpty)
    let collision = RecursiveDescriptionModel()
    _ = try collision.bind(Description(id: "bootstrap.1.app"))
    XCTAssertThrowsError(try collision.bootstrap(e.app))
    XCTAssertTrue(try collision.schemas().descriptions.isEmpty)
    var editorLimit = Limits()
    editorLimit.nodes = 3
    let boundedEditor = RecursiveDescriptionModel(limits: editorLimit)
    XCTAssertThrowsError(try boundedEditor.bind("editor", editor))
    XCTAssertTrue(boundedEditor.resolver.nativeObjects.isEmpty)
    var bytes = Limits()
    bytes.bytes = 20000
    let boundedBytes = RecursiveDescriptionModel(limits: bytes)
    XCTAssertThrowsError(try boundedBytes.bootstrap(e.app))
    XCTAssertTrue(try boundedBytes.schemas().descriptions.isEmpty)
    XCTAssertEqual(try boundedBytes.describeReflective(e.score).id, "reflective.1.score")
    _ = try session.describe("editor", editor)
    e.app.children.append(e.app)
    XCTAssertThrowsError(try session.schemas())
    e.app.children.removeLast()
    e.app.children.append(Description(id: "score"))
    XCTAssertThrowsError(try session.schemas())
    e.app.children.removeLast()
    let first = try session.bootstrap("editor", editor)
    let second = try session.bootstrap(e.app)
    XCTAssertNotEqual(first.root, second.root)
    XCTAssertEqual(first.descriptions.count, second.descriptions.count)
    XCTAssertTrue(
      try session.describeReflective(XCTUnwrap(first.descriptions[first.root])).isContainer)
  }
}
