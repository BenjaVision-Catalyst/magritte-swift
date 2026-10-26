import Foundation
import Magritte
import XCTest

final class BuildersTests: XCTestCase {
  func obj(_ v: Any?) throws -> [String: Any] { try XCTUnwrap(v as? [String: Any]) }
  func rows(_ v: Any?) throws -> [[String: Any]] { try XCTUnwrap(v as? [[String: Any]]) }
  func data(_ v: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .fragmentsAllowed])
  }
  func normal(_ v: Any) -> Any {
    if let j = v as? [String: Any] {
      if j["error"] != nil { return ["error": true] }
      return j.mapValues(normal)
    }
    if let a = v as? [Any] { return a.map(normal) }
    return v
  }
  func same(_ actual: Any, _ expected: Any, file: StaticString = #filePath, line: UInt = #line)
    throws
  { XCTAssertEqual(try data(actual), try data(normal(expected)), file: file, line: line) }
  func wire(_ v: Value) throws -> Any {
    if case .reference = v { return ["type": "model"] }
    return try JSONSerialization.jsonObject(with: encodeValue(v))
  }
  func attempt(_ read: () throws -> Value) -> [String: Any] {
    do { return ["value": try wire(read())] } catch { return ["error": true] }
  }
  func fixture() throws -> [String: Any] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "builders-reference", withExtension: "json", subdirectory: "Fixtures"))
    return try obj(JSONSerialization.jsonObject(with: Data(contentsOf: url)))
  }
  func field(_ name: String, _ priority: Int64) -> Description {
    let d = Description(id: name, key: name)
    d.properties = [
      "label": .string(name), "priority": .integer(priority), "canExpand": .boolean(false),
    ]
    return d
  }
  func container(_ id: String, _ children: [Description] = []) -> Description {
    let d = Description(id: id, className: "MAContainer")
    d.children = children
    return d
  }
  func snapshot(_ d: Description) throws -> [String: Any] {
    let name = try d.effectiveAccessor.accessorName()
    let text: String
    switch name {
    case .symbol(let s), .string(let s): text = s
    default: text = ""
    }
    return [
      "name": text, "label": try wire(d.property("label")), "group": try wire(d.property("group")),
      "priority": try wire(d.property("priority")), "container": d.isContainer,
    ]
  }
  final class DataObject {
    var values: [String: Value]
    let tag: String
    init(_ values: [String: Value], _ tag: String) {
      self.values = values
      self.tag = tag
    }
  }
  final class TrackingModel: Model {
    let data: DataObject
    weak var graph: Graph?
    let event: (String) -> Void
    init(_ data: DataObject, _ graph: Graph, _ event: @escaping (String) -> Void) {
      self.data = data
      self.graph = graph
      self.event = event
    }
    func readSlot(strategy: String, name: String) throws -> Value {
      guard strategy == "MADictionaryAccessor" else { throw MagritteError("Unbound strategy") }
      event(data.tag + ":" + name)
      return data.values[name] ?? .undefined
    }
    func writeSlot(strategy: String, name: String, value: Value) throws {
      data.values[name] = value
    }
    func read(using d: Description) throws -> Value {
      try d.effectiveAccessor.read(self, graph: graph)
    }
    func write(_ v: Value, using d: Description) throws {
      try d.effectiveAccessor.write(v, to: self, graph: graph)
    }
  }
  func testFlatteningAndCanExpandAgainstGT() throws {
    let f = try fixture()
    for row in try rows(f["canExpand"]) {
      let d = Description(id: "can")
      d.properties = [
        "visible": .boolean(try XCTUnwrap(row["visible"] as? Bool)),
        "readOnly": .boolean(try XCTUnwrap(row["readOnly"] as? Bool)),
        "group": (row["group"] as? String).map(Value.string) ?? .undefined,
      ]
      var env = BuilderEnvironment()
      env.tabDisplay = { _ in try XCTUnwrap(row["tab"] as? Bool) }
      XCTAssertEqual(try canExpand(d, environment: env), row["result"] as? Bool)
    }
    for row in try rows(f["flattening"]) {
      let graph = Graph(root: "")
      var trace: [String] = []
      let city = field("city", 30)
      let nestedSchema = container("nestedSchema", [city])
      let leaf = field("name", 10)
      let childSchema = container("childSchema", [leaf])
      if row["primitiveDrop"] as? Bool == true { leaf.properties["canExpand"] = .boolean(true) }
      if row["emptySchema"] as? Bool == true { childSchema.children = [] }
      let unused = field("unused", 0)
      let parent = field("child", 100)
      let reference = container("unusedSchema", [unused])
      parent.className = "MAToOneRelationDescription"
      parent.reference = reference
      parent.properties["label"] = .string("Child")
      parent.properties["visible"] = .boolean(try XCTUnwrap(row["visible"] as? Bool))
      parent.properties["readOnly"] = .boolean(try XCTUnwrap(row["readOnly"] as? Bool))
      parent.properties["group"] = (row["group"] as? String).map(Value.string) ?? .undefined
      parent.properties.removeValue(forKey: "canExpand")
      if let v = row["explicit"] as? Bool { parent.properties["canExpand"] = .boolean(v) }
      let nestedRelation = field("nested", 20)
      let nestedReference = container("nestedReference")
      nestedRelation.className = "MAToOneRelationDescription"
      nestedRelation.reference = nestedReference
      nestedRelation.properties["label"] = .string("Nested")
      nestedRelation.properties["canExpand"] = .boolean(true)
      if row["recursive"] as? Bool == true { childSchema.children.append(nestedRelation) }
      let prefix = field("prefix", 0)
      let suffix = field("suffix", 200)
      let source = container("source", [prefix, parent, suffix])
      let rootData = DataObject(
        [
          "prefix": .string("P"), "suffix": .string("S"),
          "child": row["nilValue"] as? Bool == true ? .undefined : .reference("childModel"),
        ], "root")
      let childData = DataObject(
        ["name": .string("Ada"), "nested": .reference("nestedModel")], "child")
      let nestedData = DataObject(["city": .string("Paris")], "nested")
      func native(_ data: DataObject) -> TrackingModel {
        TrackingModel(data, graph) { trace.append($0) }
      }
      let root = native(rootData)
      let child = native(childData)
      let nested = native(nestedData)
      graph.nativeObjects = ["rootModel": root, "childModel": child, "nestedModel": nested]
      let builder = DescriptionFlattener()
      builder.environment.graph = graph
      builder.environment.describe = { m in
        if m === root { return source }
        if m === child { return childSchema }
        if m === nested { return nestedSchema }
        return nil
      }
      if row["missingTab"] as? Bool != true {
        builder.environment.tabDisplay = { _ in try XCTUnwrap(row["tab"] as? Bool) }
      }
      if row["missingGroup"] as? Bool != true {
        builder.environment.groupExpandOnLabel = { _ in try XCTUnwrap(row["groupLabel"] as? Bool) }
      }
      if row["missingAdd"] as? Bool != true {
        builder.environment.addToAccessor = { d, head in
          d.accessor = Accessor(
            className: "MAChainAccessor", steps: [head, try d.effectiveAccessor])
          d.accessorObject = nil
        }
      }
      var outcome: [String: Any]
      do {
        if row["collectionTarget"] as? Bool == true {
          _ = try builder.buildFromValue(
            source, newIDPrefix: "flat",
            target: .array(row["emptyTarget"] as? Bool == true ? [] : [.reference("rootModel")]))
        } else {
          _ = try builder.buildFrom(source, newIDPrefix: "flat", target: root)
        }
        outcome = ["success": true]
      } catch { outcome = ["error": true] }
      let result = builder.builtDescription
      let readTrace = trace
      let fields = try result?.children.map(snapshot) ?? []
      let values = result?.children.map { d in attempt { try root.read(using: d) } } ?? []
      let actual: [String: Any] = [
        "outcome": outcome, "fields": fields, "values": values, "trace": readTrace,
        "sharedLeaf": result?.children.contains { $0 === leaf } ?? false,
        "leaf": try snapshot(leaf), "sourceParent": try snapshot(parent),
      ]
      for (key, value) in actual { try same(value, try XCTUnwrap(row[key])) }
      if row["id"] as? String == "flat",
        let path = ProcessInfo.processInfo.environment["MAGRITTE_BUILDERS_EXPORT"], let result
      {
        let out = Graph(root: result.id)
        out.format = "magritte.graph/4"
        out.descriptions[result.id] = result
        let person = AdaptiveModel(id: "sample", description: result)
        for d in result.children {
          out.descriptions[d.id] = d
          person.values[d.id] = try root.read(using: d)
        }
        out.objects[person.id] = person
        try out.encode().write(to: URL(fileURLWithPath: path))
      }
    }
  }
  func testCompositionAgainstGT() throws {
    for row in try rows(fixture()["composition"]) {
      let mode = try XCTUnwrap(row["mode"] as? String)
      let relation = mode.contains("relation")
      let source = mode == "scalar" ? field("source", 0) : container("source")
      source.properties["label"] = .string("Source")
      let reference = container("reference")
      reference.properties["label"] = .string("Reference")
      if relation {
        source.className =
          mode == "many-relation" ? "MAToManyRelationDescription" : "MAToOneRelationDescription"
        source.key = "child"
        source.reference = reference
      }
      let replacement = container("replacement")
      replacement.properties["label"] = .string("Replacement")
      let targetSchema = container("targetSchema")
      let graph = Graph(root: "")
      let root = DictionaryModel()
      let child = DictionaryModel()
      let marker = DictionaryModel()
      root.resolver = graph
      graph.nativeObjects["child"] = child
      root.values["child"] =
        mode == "nil-relation"
        ? .undefined : mode == "many-relation" ? .array([.reference("child")]) : .reference("child")
      var events: [[Any]] = []
      var steps: [BuilderStep] = []
      if mode == "class-step" {
        steps = [.named("MADescriptionBuilder")]
      } else if mode != "empty" {
        for tag in ["A", "B"] {
          steps.append(
            BuilderStep { d, _, context in
              guard let d, case .string(let label) = try d.property("label") else {
                throw MagritteError("Nil input")
              }
              let role =
                context.targetValue.map { $0.isCollection ? "collection" : "child" } ?? "root"
              events.append([tag, label, role, context.model === marker])
              if mode == "failure" && tag == "B" { throw MagritteError("step") }
              d.properties["label"] = .string(label + tag)
              return DescriptionCopy(
                root: mode == "replace" && tag == "A" ? replacement : d,
                retained: [source, reference, replacement])
            })
        }
      }
      let builder = ComposedDescriptionBuilder()
      builder.environment.graph = graph
      builder.environment.describe = { _ in targetSchema }
      builder.environment.descriptionBuilders = { _ in steps }
      builder.model = marker
      var success = true
      do { _ = try builder.buildFrom(source, newIDPrefix: "composed", target: root) } catch {
        success = false
      }
      let result = builder.builtDescription
      var actual: [String: Any] = [
        "mode": mode, "success": success,
        "resultLabel": try wire(result?.property("label") ?? .undefined), "sourceLabel": mode,
        "sameSource": result === source, "replacement": result === replacement, "events": events,
      ]
      if case .string(let text) = try source.property("label") { actual["sourceLabel"] = text }
      if relation {
        if case .string(let text) = try source.referenceDescription().property("label") {
          actual["referenceLabel"] = text
        }
        actual["sameReference"] = source.reference === reference
      }
      try same(actual, row)
    }
  }
  func testRuntimeFactoriesCyclesAndExactPriorities() throws {
    final class Named: DescriptionBuilder {
      override func visitStringDescription(_ d: Description) throws {
        d.properties["label"] = .string("Native")
        try super.visitStringDescription(d)
      }
    }
    try registerDescriptionBuilder("MABuildersTestNative") { Named(limits: $0) }
    let source = container("classes", [field("x", 0)])
    try setDescriptionBuilders(source, classes: ["MABuildersTestNative"])
    let builder = ComposedDescriptionBuilder()
    let output = try XCTUnwrap(builder.buildFrom(source, newIDPrefix: "registered"))
    XCTAssertFalse(output.root === source)
    XCTAssertEqual(try output.root.children[0].property("label"), .string("Native"))
    let cyclic = container("cycle")
    try setDescriptionBuilders(cyclic, classes: ["MAComposedDescriptionBuilder"])
    var low = Limits()
    low.depth = 3
    let bounded = ComposedDescriptionBuilder(limits: low)
    XCTAssertThrowsError(try bounded.buildFrom(cyclic, newIDPrefix: "cycle-copy"))
    var targetBound = Limits()
    targetBound.items = 1
    let targetLimited = DescriptionFlattener(limits: targetBound)
    XCTAssertThrowsError(
      try targetLimited.buildFromValue(
        source, newIDPrefix: "bounded-target", target: .array([.undefined, .undefined])))
    let explicitExpansion = Description(id: "explicit")
    explicitExpansion.properties = [
      "visible": .boolean(false), "readOnly": .boolean(true), "canExpand": .boolean(true),
    ]
    XCTAssertTrue(try canExpand(explicitExpansion))
    let plain = field("plain", 0)
    let undescribed = DictionaryModel()
    let noAnnotations = ComposedDescriptionBuilder()
    XCTAssertTrue(
      try noAnnotations.buildFrom(plain, newIDPrefix: "plain-built", target: undescribed)?.root
        === plain)
    let nilBinding = DescriptionFlattener()
    let nilSchema = container("nilSchema", [field("nilField", 0)])
    let nilRoot = container("nilRoot")
    try nilBinding.setBuiltDescription(nilRoot)
    nilBinding.environment.describe = { _ in nilSchema }
    XCTAssertThrowsError(try nilBinding.expandDescription(plain, for: .undefined))
    XCTAssertEqual(try Value.rational(1, 2), .float(0.5))
    XCTAssertEqual(try Value.rational(2, 2), .integer(1))
    let v = try Value.rational(-1, 1000)
    XCTAssertEqual(try decodeValue(encodeValue(v)), v)
  }
  func testExactFractionPrioritiesAgainstGT() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "builders-priorities-reference", withExtension: "json",
        subdirectory: "Fixtures"))
    let f = try obj(JSONSerialization.jsonObject(with: Data(contentsOf: url)))
    for row in try rows(f["comparisons"]) {
      let left = try decodeValue(data(XCTUnwrap(row["left"])))
      let right = try decodeValue(data(XCTUnwrap(row["right"])))
      XCTAssertEqual(left == right, row["equal"] as? Bool)
      for (selector, key) in [("<", "less"), (">", "greater")] {
        let p = Predicate(selector: selector, arguments: [right])
        XCTAssertEqual(try p.evaluate(left), row[key] as? Bool)
      }
    }
    for row in try rows(f["arithmetic"]) {
      let leaf = field("arithName", 0)
      leaf.key = "name"
      leaf.properties["priority"] = try decodeValue(data(XCTUnwrap(row["child"])))
      let childSchema = container("arithChild", [leaf])
      let reference = container("arithRef")
      let parent = field("arithParent", 0)
      parent.className = "MAToOneRelationDescription"
      parent.key = "child"
      parent.reference = reference
      parent.properties["priority"] = try decodeValue(data(XCTUnwrap(row["parent"])))
      parent.properties["canExpand"] = .boolean(true)
      let root = container("arithRoot", [parent])
      let graph = Graph(root: "")
      let model = DictionaryModel()
      let child = DictionaryModel()
      model.resolver = graph
      child.values["name"] = .string("value")
      graph.nativeObjects["arithValue"] = child
      model.values["child"] = .reference("arithValue")
      let builder = DescriptionFlattener()
      builder.environment.graph = graph
      builder.environment.describe = { m in m === child ? childSchema : nil }
      builder.environment.groupExpandOnLabel = { _ in false }
      builder.environment.addToAccessor = { d, head in
        d.accessor = Accessor(className: "MAChainAccessor", steps: [head, try d.effectiveAccessor])
      }
      let out = try XCTUnwrap(builder.buildFrom(root, newIDPrefix: "arithBuilt", target: model))
      XCTAssertEqual(
        try out.root.children[0].property("priority"),
        try decodeValue(data(XCTUnwrap(row["result"]))))
    }
    let priorities = container("prioritySort", [field("large", 0), field("small", 0)])
    priorities.className = "MAPriorityContainer"
    priorities.children[0].properties["priority"] = try .rational(10001, 100)
    priorities.children[1].properties["priority"] = .integer(100)
    try priorities.resort()
    XCTAssertEqual(try priorities.orderedChildren()[0].id, "small")
    XCTAssertThrowsError(try Value.rational(1, 0))
    XCTAssertThrowsError(try Value.rational(1, -1))
    let graph = Graph(root: priorities.id)
    graph.format = "magritte.graph/4"
    graph.descriptions[priorities.id] = priorities
    for d in priorities.children { graph.descriptions[d.id] = d }
    let modern = try graph.encode()
    var legacy = try obj(JSONSerialization.jsonObject(with: modern))
    legacy["format"] = "magritte.graph/3"
    XCTAssertThrowsError(try Graph.decode(data(legacy)))
  }

}
