import Foundation
import XCTest

@testable import Magritte

final class ReflectionTests: XCTestCase {
  func fixture(_ name: String) throws -> Any {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
  }
  func object(_ any: Any?) throws -> [String: Any] { try XCTUnwrap(any as? [String: Any]) }
  func array(_ any: Any?) throws -> [[String: Any]] { try XCTUnwrap(any as? [[String: Any]]) }
  func string(_ any: Any?) throws -> String { try XCTUnwrap(any as? String) }
  func data(_ any: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: any, options: .sortedKeys)
  }
  func value(_ any: Any?) throws -> Value { try decodeValue(data(XCTUnwrap(any))) }
  func canonical(_ any: Any) throws -> Data {
    var j = try object(any)
    var nodes = try array(j["descriptions"])
    for i in nodes.indices {
      if let classes = nodes[i]["classes"] as? [String] { nodes[i]["classes"] = classes.sorted() }
    }
    j["descriptions"] = nodes.sorted { ($0["id"] as! String) < ($1["id"] as! String) }
    return try data(j)
  }
  func prototype(_ row: [String: Any], id: String = "target") throws -> Description {
    let d = Description(id: id, className: try string(row["class"]), key: "Value")
    d.accessor = Accessor(name: "Value")
    for (key, v) in try object(row["properties"]) { d.properties[key] = try value(v) }
    if let separators = row["separators"] as? String {
      d.properties["separators"] = .string(separators)
    }
    return d
  }
  func referenceFor(_ d: Description) -> Description {
    let ref = Description(
      id: d.id + ".reference", className: d.isRelation ? "MAContainer" : "MAStringDescription")
    if !d.isRelation { ref.accessor = Accessor(className: "MANullAccessor") }
    if d.isReference { d.reference = ref }
    return ref
  }
  func compare(
    _ ctx: RecursiveDescriptionModel, _ model: Model, _ schema: Description, _ row: [String: Any]
  ) throws {
    let graph = Graph(root: schema.id)
    graph.format = "magritte.graph/4"
    let expected = try object(row["graph"])
    for node in try array(expected["descriptions"]) {
      let id = try string(node["id"])
      graph.descriptions[id] = try XCTUnwrap(ctx.resolver.descriptions[id])
    }
    XCTAssertEqual(
      try canonical(JSONSerialization.jsonObject(with: graph.encode())), try canonical(expected),
      "GT reflection schema")
    for read in try array(row["reads"]) {
      let field = try XCTUnwrap(ctx.resolver.descriptions[string(read["field"])])
      XCTAssertEqual(
        try model.read(using: field), try value(read["value"]), "GT reflective getter \(field.id)")
    }
    XCTAssertEqual(
      try validate(model, using: schema, graph: ctx.resolver).map(\.code),
      row["validation"] as? [String])
  }
  func testGTClassValuesAndTextConversion() throws {
    let report = try object(fixture("reflection-reference"))
    XCTAssertEqual(portableClasses(), report["registry"] as? [String])
    let d = Description(id: "class", className: "MAClassDescription")
    for row in try array(report["classValidation"]) {
      XCTAssertEqual(
        try Magritte.validateValue(value(row["input"]), using: d).map(\.code),
        row["errors"] as? [String])
    }
    for row in try array(report["classReads"]) {
      if row["error"] != nil {
        XCTAssertThrowsError(try readString(string(row["text"]), using: d))
      } else {
        XCTAssertEqual(try readString(string(row["text"]), using: d), try value(row["value"]))
      }
    }
    for row in try array(report["classWrites"]) {
      if row["error"] != nil {
        XCTAssertThrowsError(try writeString(value(row["input"]), using: d))
      } else {
        XCTAssertEqual(try writeString(value(row["input"]), using: d), row["text"] as? String)
      }
    }
  }
  func testGTDescriptionAccessorAndConditionSchemas() throws {
    let report = try object(fixture("reflection-reference"))
    for row in try array(report["descriptions"]) {
      let target = try prototype(row)
      let ref = referenceFor(target)
      let ctx = RecursiveDescriptionModel()
      try withExtendedLifetime(ref) {
        let schema = try ctx.describeReflective(target)
        try compare(ctx, ctx.bind(target), schema, row)
      }
    }
    for row in try array(report["accessors"]) {
      let a = try AccessorObject.fromAccessor(
        id: "accessor", decodeAccessor(data(XCTUnwrap(row["input"]))))
      let ctx = RecursiveDescriptionModel()
      let schema = try ctx.describe(a)
      try compare(ctx, ctx.bind(a), schema, row)
      let shared = try AccessorObject.fromAccessor(id: "replacement", Accessor(name: "shared"))
      _ = try ctx.bind(shared)
      let editor = try CheckedMemento(model: ctx.bind(a), description: schema, graph: ctx.resolver)
      for edit in try array(row["edits"]) {
        try editor.write(
          value(edit["value"]), using: XCTUnwrap(ctx.resolver.descriptions[string(edit["field"])]))
      }
      XCTAssertTrue(try editor.validate().isEmpty)
      try editor.commit()
      XCTAssertEqual(
        try data(JSONSerialization.jsonObject(with: encodeAccessor(a.snapshot()))),
        try data(XCTUnwrap(row["after"])))
      XCTAssertEqual(a.accessor != nil && a.accessor === a.next, row["sharedSlots"] as? Bool)
    }
    for row in try array(report["conditions"]) {
      let condition = try ConditionObject(
        id: "condition", predicate: decodePredicate(data(XCTUnwrap(row["predicate"]))))
      let ctx = RecursiveDescriptionModel()
      let schema = try ctx.describe(condition)
      try compare(ctx, ctx.bind(condition), schema, row)
      XCTAssertTrue(schema.children.isEmpty)
      for test in try array(row["values"]) {
        XCTAssertEqual(try condition.evaluate(value(test["value"])), test["result"] as? Bool)
      }
    }
  }
  func testGTLiveAccessorEditingAndClassGraphExport() throws {
    let report = try object(fixture("reflection-reference"))
    let descriptions = try array(report["descriptions"])
    let levels = try array(report["levels"])
    let d = try prototype(descriptions[7])
    let ctx = RecursiveDescriptionModel()
    let schema = try ctx.describeReflective(d)
    try compare(ctx, ctx.bind(d), schema, levels[0])
    let accessor = try XCTUnwrap(d.accessorObject)
    let keySchema = try ctx.describe(accessor)
    try compare(ctx, ctx.bind(accessor), keySchema, levels[1])
    let alias = try prototype(descriptions[7], id: "alias")
    alias.properties["label"] = .string("Alias")
    alias.accessor?.name = "original"
    let aliasSchema = try ctx.describeReflective(alias)
    try compare(ctx, ctx.bind(alias), aliasSchema, levels[2])
    let model = DictionaryModel([
      "Value": .integer(3), "final": .integer(9), "original": .integer(4),
    ])
    let reads = try object(report["finalReads"])
    XCTAssertEqual(try model.read(using: d), try value(reads["before"]))
    let aliasEditor = try CheckedMemento(
      model: ctx.bind(alias), description: aliasSchema, graph: ctx.resolver)
    try aliasEditor.write(
      .reference(accessor.id),
      using: XCTUnwrap(ctx.resolver.descriptions[aliasSchema.id + ".accessor"]))
    XCTAssertTrue(try aliasEditor.validate().isEmpty)
    try aliasEditor.commit()
    let editor = try CheckedMemento(
      model: ctx.bind(accessor), description: keySchema, graph: ctx.resolver)
    try editor.write(
      .symbol("final"), using: XCTUnwrap(ctx.resolver.descriptions[keySchema.id + ".key"]))
    XCTAssertTrue(try editor.validate().isEmpty)
    try editor.commit()
    XCTAssertTrue(d.accessorObject === alias.accessorObject)
    XCTAssertEqual(try model.read(using: d), try value(reads["after"]))
    XCTAssertEqual(try model.read(using: alias), try value(reads["alias"]))
    let graph = ctx.schemas()
    XCTAssertEqual(
      try canonical(JSONSerialization.jsonObject(with: graph.encode())),
      try canonical(XCTUnwrap(report["finalSchemas"])))
    let root = Description(id: "app", className: "MAContainer")
    let classField = Description(id: "klass", className: "MAClassDescription", key: "klass")
    root.children = [d, classField]
    graph.root = root.id
    graph.descriptions[root.id] = root
    graph.descriptions[d.id] = d
    graph.descriptions[alias.id] = alias
    graph.descriptions[classField.id] = classField
    graph.objects["sample"] = AdaptiveModel(
      id: "sample", description: root,
      values: [d.id: .integer(9), classField.id: .classValue("String")])
    XCTAssertThrowsError(try graph.encode())
    try d.materializeAccessor()
    try alias.materializeAccessor()
    let wire = try graph.encode()
    let imported = try Graph.decode(wire)
    XCTAssertEqual(try imported.encode(), wire)
    XCTAssertTrue(
      try validate(
        XCTUnwrap(imported.objects["sample"]), using: XCTUnwrap(imported.descriptions["app"]),
        graph: imported
      ).isEmpty)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_REFLECTION_EXPORT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
  }
  func testReflectionLimitsAndExplicitFailures() throws {
    let outer = Description(id: "outer", className: "MAContainer")
    let nested = Description(id: "nested", className: "MAContainer")
    let score = Description(id: "score", className: "MANumberDescription", key: "score")
    score.properties["required"] = .boolean(true)
    outer.children = [nested]
    nested.children = [score]
    nested.accessorObject = try AccessorObject.fromAccessor(
      id: "nested.accessor", Accessor(name: "child"))
    let child = DictionaryModel(["score": .integer(7)])
    let parent = DictionaryModel(["child": .reference("child")])
    let resolver = Graph(root: "")
    resolver.nativeObjects["child"] = child
    XCTAssertTrue(try validate(parent, using: outer, graph: resolver).isEmpty)
    XCTAssertEqual(try writeString(parent, using: outer, graph: resolver), "7")
    let portableRoot = Description(id: "root", className: "MAContainer")
    let containerGraph = Graph(root: "root")
    portableRoot.accessorObject = try AccessorObject.fromAccessor(
      id: "root.accessor", Accessor(className: "MAIdentityAccessor"))
    containerGraph.descriptions["root"] = portableRoot
    XCTAssertThrowsError(try containerGraph.encode())
    try portableRoot.materializeAccessor()
    XCTAssertFalse(try containerGraph.encode().isEmpty)

    for row in try array(fixture("reflection-invalid")) {
      if row["kind"] as? String == "value" {
        XCTAssertThrowsError(try decodeValue(data(XCTUnwrap(row["input"]))))
      } else {
        XCTAssertThrowsError(try decodeAccessor(data(XCTUnwrap(row["input"]))))
      }
    }

    let delegated = Accessor(className: "MADelegatorAccessor", steps: [Accessor(name: "alpha")])
    let dict = DictionaryModel(["alpha": .integer(2)])
    XCTAssertEqual(try delegated.read(dict), .integer(2))
    try delegated.write(.integer(7), to: dict)
    XCTAssertEqual(dict.values["alpha"], .integer(7))
    XCTAssertEqual(
      try encodeAccessor(decodeAccessor(encodeAccessor(delegated))), try encodeAccessor(delegated))

    XCTAssertThrowsError(try decodeValue(data(["type": "class", "value": "UnknownClass"])))
    XCTAssertNotEqual(Value.classValue("String"), .symbol("String"))
    let source = Description(
      id: "relation", className: "MAToOneRelationDescription", key: "relation")
    let ref = referenceFor(source)
    let ctx = RecursiveDescriptionModel()
    try withExtendedLifetime(ref) {
      let schema = try ctx.describeReflective(source)
      let model = try ctx.bind(source)
      let classes = try XCTUnwrap(ctx.resolver.descriptions[schema.id + ".classes"])
      let editor = try CheckedMemento(model: model, description: schema, graph: ctx.resolver)
      try editor.write(.collection(kind: "set", elements: [.classValue("String")]), using: classes)
      XCTAssertTrue(try editor.validate().isEmpty)
      try editor.commit()
      XCTAssertEqual(source.classes, ["String"])
      XCTAssertTrue(
        try Magritte.validateValue(.string("yes"), using: source, graph: ctx.resolver).isEmpty)
      XCTAssertFalse(
        try Magritte.validateValue(.integer(1), using: source, graph: ctx.resolver).isEmpty)
      XCTAssertThrowsError(try model.write(.array([.string("String")]), using: classes))
      XCTAssertThrowsError(
        try model.write(
          .classValue("MAReader"),
          using: XCTUnwrap(ctx.resolver.descriptions[schema.id + ".stringReader"])))
      let copied = try copyDescription(source, newID: "copy")
      XCTAssertFalse(copied.root.accessorObject === source.accessorObject)
    }
    let chain = try AccessorObject.fromAccessor(
      id: "chain",
      Accessor(
        className: "MAChainAccessor", steps: [Accessor(name: "child"), Accessor(name: "leaf")]))
    let schema = try ctx.describe(chain)
    let previous = chain.next
    XCTAssertThrowsError(
      try ctx.bind(chain).write(
        .reference(chain.id), using: XCTUnwrap(ctx.resolver.descriptions[schema.id + ".next"])))
    XCTAssertTrue(chain.next === previous)
    var tiny = Limits()
    tiny.nodes = 1
    let bounded = RecursiveDescriptionModel(limits: tiny)
    XCTAssertThrowsError(try bounded.bind(chain))
    XCTAssertTrue(bounded.resolver.nativeObjects.isEmpty)
    let alien = try AccessorObject.fromAccessor(id: "relation", Accessor(name: "key"))
    XCTAssertThrowsError(try ctx.bind(alien))
    let root = Description(id: "root", className: "MAContainer")
    let field = Description(id: "type", key: "type")
    let graph = Graph(root: "root")
    root.children = [field]
    graph.descriptions = [root.id: root, field.id: field]
    graph.objects["model"] = AdaptiveModel(
      id: "model", description: root, values: [field.id: .string("ordinary")])
    XCTAssertFalse(try graph.encode().isEmpty)
    field.properties["metadata:class"] = .classValue("String")
    XCTAssertThrowsError(try graph.encode())
    field.properties.removeValue(forKey: "metadata:class")
    graph.format = "magritte.graph/4"
    field.className = "MAStringDescription"
    field.portableConditions = [
      PortableCondition(
        label: "class", predicate: Predicate(selector: "=", arguments: [.classValue("String")]))
    ]
    graph.objects["model"]?.values[field.id] = .classValue("String")
    var legacy = try object(JSONSerialization.jsonObject(with: graph.encode()))
    legacy["format"] = "magritte.graph/3"
    XCTAssertThrowsError(try Graph.decode(data(legacy)))
    field.portableConditions = []
    field.accessor = delegated
    graph.objects = [:]
    let delegation = try graph.encode()
    XCTAssertEqual(try Graph.decode(delegation).encode(), delegation)
    legacy = try object(JSONSerialization.jsonObject(with: delegation))
    legacy["format"] = "magritte.graph/3"
    XCTAssertThrowsError(try Graph.decode(data(legacy)))
  }
}
