import Foundation
import XCTest

@testable import Magritte

final class RegistrationTests: XCTestCase {
  class Holder { var contents: Int64 = 3 }
  final class DescriptionHolder: Holder {}
  class Person {}
  final class Employee: Person {}
  final class Alias {}
  func fixture() throws -> [String: Any] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "registration-reference", withExtension: "json", subdirectory: "Fixtures"))
    return try object(JSONSerialization.jsonObject(with: Data(contentsOf: url)))
  }
  func object(_ j: Any?) throws -> [String: Any] { try XCTUnwrap(j as? [String: Any]) }
  func rows(_ j: Any?) throws -> [[String: Any]] { try XCTUnwrap(j as? [[String: Any]]) }
  func text(_ j: Any?) throws -> String { try XCTUnwrap(j as? String) }
  func data(_ j: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: j, options: .sortedKeys)
  }
  func value(_ j: Any?) throws -> Value { try decodeValue(data(XCTUnwrap(j))) }
  func info(_ j: [String: Any]) throws -> ClassInfo {
    ClassInfo(
      name: try text(j["name"]), superclass: j["superclass"] as? String,
      isAbstract: try XCTUnwrap(j["abstract"] as? Bool), label: try text(j["label"]))
  }
  func canonical(_ j: Any) throws -> Data {
    var graph = try object(j)
    var nodes = try rows(graph["descriptions"])
    for i in nodes.indices {
      if let names = nodes[i]["classes"] as? [String] { nodes[i]["classes"] = names.sorted() }
    }
    graph["descriptions"] = nodes.sorted { ($0["id"] as! String) < ($1["id"] as! String) }
    return try data(graph)
  }
  func testRuntimeRegistrationDiscoveryAndNativeInterop() throws {
    let f = try fixture()
    let registry = ClassRegistry.shared
    for row in try rows(f["core"]) {
      XCTAssertEqual(registry.find(try text(row["name"])), try info(row))
    }
    _ = try decodeValue(data(["type": "class", "value": "String"]))
    XCTAssertThrowsError(try decodeValue(data(["type": "class", "value": "MAValueHolder"])))
    let relation = Description(
      id: "relation", className: "MAToOneRelationDescription", key: "relation")
    let reference = Description(id: "relation.reference", className: "MAContainer")
    relation.properties["label"] = .string("Relation")
    relation.reference = reference
    let before = RecursiveDescriptionModel()
    let old = try before.describeReflective(relation)
    let previous = try XCTUnwrap(before.resolver.descriptions[old.id + ".classes"]).options
    let definitions = try rows(f["additional"]).map(info)
    try registry.registerClasses(definitions)
    XCTAssertEqual(registry.allClasses(), f["classes"] as? [String])
    XCTAssertEqual(previous.count + definitions.count, registry.allClasses().count)
    XCTAssertEqual(before.resolver.descriptions[old.id + ".classes"]?.options, previous)
    for q in try rows(f["queries"]) {
      let name = try text(q["class"])
      XCTAssertEqual(try registry.subclasses(name), q["subclasses"] as? [String])
      XCTAssertEqual(try registry.allSubclasses(name), q["allSubclasses"] as? [String])
      XCTAssertEqual(try registry.withAllSubclasses(name), q["withAllSubclasses"] as? [String])
      XCTAssertEqual(
        try registry.withAllConcreteClasses(name), q["withAllConcreteClasses"] as? [String])
    }
    for q in try rows(f["includes"]) {
      let name = try text(q["class"])
      let ancestor = try text(q["ancestor"])
      XCTAssertEqual(registry.includesBehavior(name, ancestor), q["includes"] as? Bool)
      XCTAssertEqual(registry.inheritsFrom(name, ancestor), q["inherits"] as? Bool)
    }
    XCTAssertEqual(
      try registry.commonSuperclass(["MAValueHolder", "MADescriptionHolder"]),
      f["commonClass"] as? String)
    try registry.registerNativeClass(Holder.self, info: XCTUnwrap(registry.find("MAValueHolder")))
    try registry.registerNativeClass(
      DescriptionHolder.self, info: XCTUnwrap(registry.find("MADescriptionHolder")))
    let base = Holder()
    let derived: Holder = DescriptionHolder()
    let native = try NativeModel(registered: base)
    let child = try NativeModel(registered: derived)
    XCTAssertTrue(child.kindOf("MAValueHolder"))
    XCTAssertTrue(child.kindOf("MADescriptionHolder"))
    native.readers["MASelectorAccessor:contents"] = { .integer(($0 as! Holder).contents) }
    native.writers["MASelectorAccessor:contents:"] = { object, v in
      guard case .integer(let n) = v else { throw MagritteError("Expected integer") }
      (object as! Holder).contents = n
    }
    let contents = Description(id: "contents", className: "MANumberDescription")
    contents.accessor = Accessor(
      className: "MASelectorAccessor", name: "contents", writeName: "contents:")
    let reads = try XCTUnwrap(f["reads"] as? [Any])
    XCTAssertEqual(try native.read(using: contents), try value(reads[0]))
    try native.write(.integer(9), using: contents)
    XCTAssertEqual(try native.read(using: contents), try value(reads[1]))
    let local = Graph(root: "")
    local.nativeObjects = ["base": native, "derived": child, "object": NativeModel(Holder())]
    relation.classes = ["MAValueHolder"]
    let candidates: [Value] = [
      .reference("base"), .reference("derived"), .reference("object"), .integer(3),
      .string("hello"),
    ]
    let expected = try rows(f["validation"])
    for i in candidates.indices {
      XCTAssertEqual(
        try Magritte.validateValue(candidates[i], using: relation, graph: local).map(\.code),
        expected[i]["errors"] as? [String])
    }
    for row in try rows(f["scalars"]) {
      relation.classes = [try text(row["class"])]
      XCTAssertEqual(
        try Magritte.validateValue(value(row["input"]), using: relation).map(\.code),
        row["errors"] as? [String])
    }
    relation.classes = ["MAValueHolder"]
    let context = RecursiveDescriptionModel()
    let schema = try context.describeReflective(relation)
    let binding = try context.bind(relation)
    let row = try object(f["schema"])
    var graph = try context.schemas()
    XCTAssertEqual(
      try canonical(JSONSerialization.jsonObject(with: graph.encode())),
      try canonical(XCTUnwrap(row["graph"])))
    for read in try rows(row["reads"]) {
      XCTAssertEqual(
        try binding.read(using: XCTUnwrap(context.resolver.descriptions[text(read["field"])])),
        try value(read["value"]))
    }
    let choices = try XCTUnwrap(context.resolver.descriptions[schema.id + ".classes"])
    let edit = try CheckedMemento(model: binding, description: schema, graph: context.resolver)
    try edit.write(
      .collection(kind: "set", elements: [.classValue("MADescriptionHolder")]), using: choices)
    XCTAssertTrue(try edit.validate().isEmpty)
    try edit.commit()
    XCTAssertFalse(
      try Magritte.validateValue(.reference("base"), using: relation, graph: local).isEmpty)
    XCTAssertTrue(
      try Magritte.validateValue(.reference("derived"), using: relation, graph: local).isEmpty)
    relation.classes = ["MAValueHolder"]
    let app = Description(id: "app", className: "MAContainer")
    let kind = Description(id: "kind", className: "MAClassDescription", key: "kind")
    let option = Description(id: "choice", className: "MASingleOptionDescription", key: "choice")
    let classRef = Description(id: "choice.reference", className: "MAClassDescription")
    classRef.accessor = Accessor(className: "MANullAccessor")
    option.reference = classRef
    option.options = [.classValue("MAValueHolder"), .classValue("MADescriptionHolder")]
    app.children = [kind, option, relation]
    graph = try context.schemas()
    graph.root = "app"
    for d in [app, kind, option, classRef, relation, reference] { graph.descriptions[d.id] = d }
    try relation.materializeAccessor()
    graph.objects["sample"] = AdaptiveModel(
      id: "sample", description: app,
      values: [
        "kind": .classValue("MADescriptionHolder"), "choice": .classValue("MADescriptionHolder"),
      ])
    let wire = try graph.encode()
    let imported = try Graph.decode(wire)
    XCTAssertEqual(try imported.encode(), wire)
    XCTAssertTrue(
      try validate(
        XCTUnwrap(imported.objects["sample"]), using: XCTUnwrap(imported.descriptions["app"]),
        graph: imported
      ).isEmpty)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_REGISTRATION_EXPORT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
    try boundaries()
  }
  func boundaries() throws {
    let r = ClassRegistry.shared
    let before = r.allClasses()
    XCTAssertThrowsError(
      try r.registerClasses([
        ClassInfo(name: "ExampleA", superclass: "ExampleB"),
        ClassInfo(name: "ExampleB", superclass: "ExampleA"),
      ]))
    XCTAssertEqual(r.allClasses(), before)
    XCTAssertThrowsError(
      try r.registerClasses([
        ClassInfo(name: "ExampleValid"),
        ClassInfo(name: "ExampleBad", superclass: "MissingSuperclass"),
      ]))
    XCTAssertEqual(r.allClasses(), before)
    XCTAssertThrowsError(try r.registerClass(ClassInfo(name: "Bad Name")))
    try r.registerClasses([
      ClassInfo(name: "ExampleEmployee", superclass: "ExamplePerson"),
      ClassInfo(name: "ExamplePerson"),
    ])
    try r.registerNativeClass(Person.self, info: XCTUnwrap(r.find("ExamplePerson")))
    try r.registerNativeClass(Employee.self, info: XCTUnwrap(r.find("ExampleEmployee")))
    try r.registerNativeClass(Person.self, info: XCTUnwrap(r.find("ExamplePerson")))
    let employee: Person = Employee()
    let model = try NativeModel(registered: employee)
    XCTAssertTrue(model.kindOf("ExamplePerson"))
    XCTAssertTrue(model.kindOf("ExampleEmployee"))
    XCTAssertTrue(model.kindOf("Object"))
    XCTAssertEqual(
      try decodeValue(encodeValue(.classValue("ExampleEmployee"))), .classValue("ExampleEmployee"))
    XCTAssertThrowsError(try r.registerClass(ClassInfo(name: "ExamplePerson", isAbstract: true)))
    XCTAssertThrowsError(
      try r.registerNativeClass(Alias.self, info: XCTUnwrap(r.find("ExamplePerson"))))
    XCTAssertThrowsError(
      try r.registerNativeClass(Person.self, info: ClassInfo(name: "LeakedClass")))
    XCTAssertNil(r.find("LeakedClass"))
    XCTAssertThrowsError(try NativeModel(registered: Alias()))
    let names = r.allClasses()
    XCTAssertThrowsError(try decodeValue(data(["type": "class", "value": "WireInventedClass"])))
    XCTAssertEqual(r.allClasses(), names)
    try r.registerClass(ClassInfo(name: "ExampleEmptyLabel", label: ""))
    XCTAssertEqual(r.find("ExampleEmptyLabel")?.label, "")
    try r.registerClass(ClassInfo(name: "ExampleUnicodeLabel", label: "\u{e9}"))
    XCTAssertThrowsError(
      try r.registerClass(ClassInfo(name: "ExampleUnicodeLabel", label: "e\u{301}")))
    DispatchQueue.concurrentPerform(iterations: 64) { i in
      try? r.registerClass(ClassInfo(name: "ConcurrentClass\(i)"))
      try? r.registerClass(ClassInfo(name: "ConcurrentShared"))
      _ = try? r.allSubclasses("Object")
    }
    for i in 0..<64 { XCTAssertNotNil(r.find("ConcurrentClass\(i)")) }
  }
}
