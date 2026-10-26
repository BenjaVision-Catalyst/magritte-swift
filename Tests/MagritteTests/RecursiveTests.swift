import Foundation
import XCTest

@testable import Magritte

final class RecursiveTests: XCTestCase {
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
  func prototype(_ cls: String) throws -> Description {
    let d = Description(id: "target", className: cls, key: "Value")
    d.accessor = Accessor(name: "Value")
    let record = try XCTUnwrap(
      array(fixture("self-description-reference")).first { ($0["class"] as? String) == cls })
    for (key, v) in try object(record["properties"]) { d.properties[key] = try value(v) }
    for (key, v) in try object(record["slots"]) { d.properties[key] = try value(v) }
    return d
  }
  func referenceFor(_ d: Description) -> Description {
    let ref = Description(id: "target.reference")
    ref.accessor = Accessor(className: "MANullAccessor")
    if d.isReference { d.reference = ref }
    return ref
  }
  func compare(
    _ context: RecursiveDescriptionModel, _ target: Description, _ schema: Description,
    _ record: [String: Any]
  ) throws {
    let level = Graph(root: schema.id)
    let expected = try object(record["graph"])
    for node in try array(expected["descriptions"]) {
      let id = try string(node["id"])
      level.descriptions[id] = try XCTUnwrap(context.resolver.descriptions[id])
    }
    XCTAssertEqual(
      try canonical(JSONSerialization.jsonObject(with: level.encode())), try canonical(expected),
      "GT recursive schema \(target.className)")
    let binding = try context.bind(target)
    for read in try array(record["reads"]) {
      let field = try XCTUnwrap(context.resolver.descriptions[string(read["field"])])
      XCTAssertEqual(
        try binding.read(using: field), try value(read["value"]),
        "GT getter \(target.className) \(field.id)")
    }
  }
  func testGTCompositionAndEquality() throws {
    let reference = try object(fixture("composition-reference"))
    let graph = try Graph.decode(data(XCTUnwrap(reference["graph"])))
    for row in try array(reference["equalities"]) {
      XCTAssertEqual(
        try descriptionEqual(
          XCTUnwrap(graph.descriptions[string(row["lhs"])]),
          XCTUnwrap(graph.descriptions[string(row["rhs"])])), row["equal"] as? Bool)
    }
    for (i, row) in try array(reference["operations"]).enumerated() {
      let a = try XCTUnwrap(graph.descriptions[string(row["lhs"])])
      let rhs = try string(row["rhs"])
      let b = rhs.isEmpty ? a : try XCTUnwrap(graph.descriptions[rhs])
      let id = "composed.\(i)"
      let op = try string(row["operation"])
      let result: DescriptionCopy
      switch op {
      case "concat": result = try concatenate(a, b, newID: id)
      case "union": result = try unionDescriptions(a, b, newID: id)
      case "intersection": result = try intersectDescriptions(a, b, newID: id)
      case "copy": result = try copyDescription(a, newID: id)
      case "empty": result = try copyEmpty(a, newID: id)
      case "range": result = try copyRange(a, range: 1..<3, newID: id)
      case "select", "reject":
        result = try selectDescriptions(a, newID: id) {
          try descriptionEqual($0, XCTUnwrap(graph.descriptions["a"])) == (op == "select")
        }
      default:
        result = try collectDescriptions(a, newID: id) {
          try descriptionEqual($0, XCTUnwrap(graph.descriptions["b"]))
            ? XCTUnwrap(graph.descriptions["num"]) : $0
        }
      }
      XCTAssertEqual(result.root.className, row["class"] as? String)
      XCTAssertEqual(result.root.property("label"), .string(try string(row["label"])))
      let children = try result.root.orderedChildren()
      let expected = try XCTUnwrap(row["children"] as? [String])
      XCTAssertEqual(children.count, expected.count)
      if op == "intersection" {
        XCTAssertTrue(
          try descriptionEqual(
            XCTUnwrap(children.first), XCTUnwrap(graph.descriptions[XCTUnwrap(expected.first)])))
        XCTAssertTrue(children.first === graph.descriptions["a"])
      } else if result.root.className == "MAPriorityContainer" {
        XCTAssertEqual(children.map(\.id).sorted(), expected.sorted())
      } else {
        XCTAssertEqual(children.map(\.id), expected)
      }
    }
  }
  func testGTRecursiveClassSchemas() throws {
    let reference = try object(fixture("recursive-reference"))
    for record in try array(reference["classes"]) {
      let target = try prototype(string(record["class"]))
      let ref = referenceFor(target)
      let context = RecursiveDescriptionModel()
      try withExtendedLifetime(ref) {
        let schema = try context.describe(target)
        try compare(context, target, schema, record)
      }
    }
  }
  func testGTRecursiveEditingAndSchemaExport() throws {
    let reference = try object(fixture("recursive-reference"))
    let levels = try array(reference["levels"])
    let target = try prototype("MANumberDescription")
    let context = RecursiveDescriptionModel()
    let first = try context.describe(target)
    try compare(context, target, first, levels[0])
    let second = try context.describe(first)
    try compare(context, first, second, levels[1])
    let min = try XCTUnwrap(context.resolver.descriptions[first.id + ".min"])
    let third = try context.describe(min)
    try compare(context, min, third, levels[2])
    let metadata = try CheckedMemento(
      model: context.bind(min), description: third, graph: context.resolver)
    try metadata.write(
      .integer(7), using: XCTUnwrap(context.resolver.descriptions[third.id + ".min"]))
    XCTAssertTrue(try metadata.validate().isEmpty)
    try metadata.commit()
    let editor = try CheckedMemento(
      model: context.bind(target), description: first, graph: context.resolver)
    XCTAssertEqual(try editor.validate().map(\.code), reference["before"] as? [String])
    try editor.write(.integer(8), using: min)
    XCTAssertTrue(try editor.validate().isEmpty)
    try editor.commit()
    let structure = try CheckedMemento(
      model: context.bind(first), description: second, graph: context.resolver)
    let remaining = first.children.filter {
      !["comment", "max"].contains($0.effectiveAccessor.name)
    }
    try structure.write(
      .collection(kind: "ordered", elements: remaining.map { .reference($0.id) }),
      using: XCTUnwrap(context.resolver.descriptions[second.id + ".children"]))
    XCTAssertTrue(try structure.validate().isEmpty)
    try structure.commit()
    XCTAssertEqual(target.property("min"), try value(reference["targetMin"]))
    XCTAssertEqual(
      try canonical(JSONSerialization.jsonObject(with: context.schemas().encode())),
      try canonical(XCTUnwrap(reference["finalSchemas"])))
    XCTAssertThrowsError(try context.resolver.encode())
    let schemas = context.schemas()
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_RECURSIVE_EXPORT"] {
      try schemas.encode().write(to: URL(fileURLWithPath: path))
    }
    let imported = try Graph.decode(schemas.encode())
    let importedRoot = try XCTUnwrap(imported.descriptions[first.id])
    let receiver = RecursiveDescriptionModel()
    let importedEditor = try CheckedMemento(
      model: receiver.bind(importedRoot), description: XCTUnwrap(imported.descriptions[second.id]),
      graph: receiver.resolver)
    let importedChildren = importedRoot.children.dropLast().map { Value.reference($0.id) }
    try importedEditor.write(
      .collection(kind: "ordered", elements: importedChildren),
      using: XCTUnwrap(imported.descriptions[second.id + ".children"]))
    XCTAssertTrue(try importedEditor.validate().isEmpty)
    try importedEditor.commit()
    XCTAssertEqual(importedRoot.children.count, importedChildren.count)
    let children = try XCTUnwrap(context.resolver.descriptions[second.id + ".children"])
    XCTAssertThrowsError(
      try context.bind(first).write(
        .collection(kind: "ordered", elements: [.reference(first.id)]), using: children))
    XCTAssertEqual(first.children.count, remaining.count)
  }
  func testNativeCopyOwnershipAndLimits() throws {
    var graph: Graph? = try Graph.decode(
      data(XCTUnwrap(try object(fixture("composition-reference"))["graph"])))
    let option = try XCTUnwrap(graph?.descriptions["option"])
    let num = try XCTUnwrap(graph?.descriptions["num"])
    let left = try XCTUnwrap(graph?.descriptions["left"])
    option.accessor = option.effectiveAccessor
    let copy = try copyDescription(option, newID: "copy")
    XCTAssertFalse(copy.root === option)
    XCTAssertFalse(try copy.root.referenceDescription() === num)
    try copy.root.referenceDescription().properties["min"] = .integer(9)
    XCTAssertEqual(num.property("min"), .integer(1))
    XCTAssertNotNil(copy.root.accessor)
    copy.root.accessor?.name = "changed"
    XCTAssertEqual(option.effectiveAccessor.name, "option")
    copy.root.options.append(.integer(3))
    XCTAssertEqual(option.options.count, 2)
    let container = try copyDescription(left, newID: "container.copy")
    container.root.properties["label"] = .string("Copied")
    XCTAssertEqual(left.property("label"), .string("Left"))
    left.children[0].properties["label"] = .string("Shared")
    XCTAssertEqual(container.root.children[0].property("label"), .string("Shared"))
    XCTAssertEqual(
      try copyWithout(left, excluding: XCTUnwrap(graph?.descriptions["a"]), newID: "without").root
        .children.map(\.id), ["b"])
    XCTAssertEqual(
      try copyWithoutAll(
        left, excluding: [XCTUnwrap(graph?.descriptions["a"]), num], newID: "withoutAll"
      ).root.children.map(\.id), ["b"])
    XCTAssertTrue(try asContainer(left, newID: "ignored").root === left)
    XCTAssertThrowsError(try copyDescription(left, newID: "left"))
    XCTAssertThrowsError(try copyRange(left, range: 2..<10, newID: "bad"))
    var tiny = Limits()
    tiny.visits = 1
    XCTAssertThrowsError(try unionDescriptions(left, left, newID: "bounded", limits: tiny))
    let recursive = Description(id: "recursive", className: "MATokenDescription")
    recursive.reference = recursive
    XCTAssertThrowsError(try copyDescription(recursive, newID: "cycle.copy"))
    let independent = try copyDescription(option, newID: "independent")
    graph = nil
    XCTAssertEqual(try independent.root.referenceDescription().property("min"), .integer(1))
    var bound = Limits()
    bound.nodes = 1
    let context = RecursiveDescriptionModel(limits: bound)
    XCTAssertThrowsError(try context.describe(prototype("MANumberDescription")))
    XCTAssertEqual(context.resolver.nativeObjects.count, 1)
    var orphan: Model?
    do {
      let owner = RecursiveDescriptionModel()
      orphan = try owner.bind(prototype("MANumberDescription"))
    }
    let raw = Description(id: "raw", key: "min")
    raw.accessor = Accessor(className: "MASelectorAccessor", name: "min", writeName: "min:")
    XCTAssertThrowsError(try orphan?.read(using: raw))
  }
  func testNativeStructuralReferenceReplacementAndTextOptions() throws {
    let token = try prototype("MATokenDescription")
    let original = referenceFor(token)
    let context = RecursiveDescriptionModel()
    try withExtendedLifetime(original) {
      let schema = try context.describe(token)
      let replacement = Description(id: "replacement", className: "MANumberDescription")
      _ = try context.bind(replacement)
      let editor = try CheckedMemento(
        model: context.bind(token), description: schema, graph: context.resolver)
      try editor.write(
        .reference(replacement.id),
        using: XCTUnwrap(context.resolver.descriptions[schema.id + ".reference"]))
      XCTAssertTrue(try editor.validate().isEmpty)
      try editor.commit()
      XCTAssertTrue(token.reference === replacement)
    }
    let option = Description(id: "option", className: "MASingleOptionDescription")
    let number = Description(id: "number", className: "MANumberDescription")
    option.reference = number
    let schema = try context.describe(option)
    let field = try XCTUnwrap(context.resolver.descriptions[schema.id + ".optionsTextual"])
    let binding = try context.bind(option)
    let structural = try object(fixture("recursive-structural-reference"))
    for row in try array(structural["options"]) {
      let previous = option.options
      var failed = false
      do { try binding.write(.string(string(row["text"])), using: field) } catch { failed = true }
      XCTAssertEqual(failed, row["error"] as? Bool)
      let expected = try XCTUnwrap(row["options"] as? [Any]).map { try value($0) }
      XCTAssertEqual(option.options, expected)
      XCTAssertEqual(try binding.read(using: field), .string(try string(row["rendered"])))
      if failed { XCTAssertEqual(option.options, previous) }
    }
  }
}
