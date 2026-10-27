import Foundation
import Magritte
import XCTest

final class ContainerMutationTests: XCTestCase {
  func field(_ id: String, _ priority: Int64 = 0) -> Description {
    let d = Description(id: id, key: id)
    d.properties["priority"] = .integer(priority)
    return d
  }
  func ids(_ d: Description) throws -> [String] { try d.orderedChildren().map(\.id) }
  func register() throws {
    try ClassRegistry.shared.registerClasses([
      ClassInfo(name: "MutatingContainer", superclass: "MAContainer"),
      ClassInfo(name: "MutatingPriorityContainer", superclass: "MAPriorityContainer"),
    ])
  }
  func testSharedMutationTraces() throws {
    try register()
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "container-mutation-scenarios", withExtension: "json", subdirectory: "Fixtures"
      ))
    let data = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    for row in try XCTUnwrap(data["cases"] as? [[String: Any]]) {
      let container = Description(
        id: "container", className: try XCTUnwrap(row["class"] as? String))
      var nodes: [String: Description] = [:]
      for (id, raw) in try XCTUnwrap(data["nodes"] as? [String: [String: Any]]) {
        let d = field(id, try XCTUnwrap(raw["priority"] as? Int64))
        d.key = try XCTUnwrap(raw["key"] as? String)
        nodes[id] = d
      }
      for step in try XCTUnwrap(row["steps"] as? [[String: Any]]) {
        func operation() throws -> Description {
          let action = try XCTUnwrap(step["action"] as? String)
          let child = (step["child"] as? String).flatMap { nodes[$0] }
          let children = (step["children"] as? [String] ?? []).map { nodes[$0]! }
          switch action {
          case "set": return try container.setChildren(children)
          case "add": return try container.add(XCTUnwrap(child))
          case "addAll": return try container.addAll(children)
          case "remove": return try container.remove(XCTUnwrap(child))
          case "moveUp": return try container.moveUp(XCTUnwrap(child))
          case "moveDown": return try container.moveDown(XCTUnwrap(child))
          case "resort": return try container.resort()
          case "clear": return try container.removeAll()
          default:
            try XCTUnwrap(child).properties["priority"] = .integer(
              try XCTUnwrap(step["value"] as? Int64))
            return container
          }
        }
        if step["error"] as? Bool == true {
          XCTAssertThrowsError(try operation())
        } else {
          XCTAssertTrue(try operation() === container)
        }
        let expected = try XCTUnwrap(step["expected"] as? [String])
        XCTAssertEqual(try ids(container), expected, "\(container.className) \(step["action"]!)")
        XCTAssertEqual(try ids(container), expected)
      }
    }
  }
  func testPersistentStateConsumersAndInterchange() throws {
    try register()
    let a = field("a", 10)
    let b = field("b", 20)
    let c = field("c", 30)
    let root = field("root")
    root.className = "MutatingPriorityContainer"
    try root.setChildren([c, a, b])
    a.properties["priority"] = .integer(40)
    XCTAssertEqual(try ids(root), ["a", "b", "c"])
    let values = DictionaryModel(["a": .string("A"), "b": .string("B"), "c": .string("C")])
    XCTAssertEqual(try writeString(values, using: root), "A-B-C")
    XCTAssertTrue(try validate(values, using: root).isEmpty)
    let copied = try copyDescription(root, newID: "copy")
    XCTAssertEqual(try ids(copied.root), ["b", "c", "a"])
    XCTAssertEqual(try ids(root), ["a", "b", "c"])
    let selected = try selectDescriptions(root, newID: "selected") { _ in true }
    XCTAssertEqual(try ids(selected.root), ["b", "c", "a"])
    var trace: [String] = []
    let collected = try collectDescriptions(root, newID: "collected") { d in
      trace.append(d.id)
      return d
    }
    XCTAssertEqual(trace, ["a", "b", "c"])
    XCTAssertEqual(try ids(collected.root), ["b", "c", "a"])
    let range = try copyRange(root, range: 0..<2, newID: "range")
    XCTAssertEqual(try ids(range.root), ["b", "a"])
    let session = RecursiveDescriptionModel()
    let schema = try session.describe(root)
    let binding = try session.bind(root)
    let children = try XCTUnwrap(session.resolver.descriptions[schema.id + ".children"])
    try binding.write(.array([.reference("c"), .reference("a"), .reference("b")]), using: children)
    XCTAssertEqual(try ids(root), ["b", "c", "a"])
    b.properties["priority"] = .integer(50)
    let previous = try ids(root)
    let previousStorage=root.childCollection
    XCTAssertThrowsError(try binding.write(.array([.reference("root")]), using: children))
    XCTAssertEqual(try ids(root), previous)
    XCTAssertTrue(root.childCollection === previousStorage)
    try root.setChildren([a, b, c])
    b.properties["priority"] = .integer(5)
    try root.add(c)
    XCTAssertEqual(try ids(root), ["c", "c", "a", "b"])
    let graph = Graph(root: "root", descriptions: ["root": root, "a": a, "b": b, "c": c])
    graph.format = "magritte.graph/4"
    let wire = try graph.encode()
    let decoded = try Graph.decode(wire)
    XCTAssertEqual(try ids(XCTUnwrap(decoded.descriptions["root"])), try ids(root))
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
    legacy["descriptions"] = try XCTUnwrap(legacy["descriptions"] as? [[String: Any]]).map { row in
      var d = row
      d.removeValue(forKey: "childrenOrder")
      return d
    }
    let normalized = try Graph.decode(JSONSerialization.data(withJSONObject: legacy))
    XCTAssertEqual(try ids(XCTUnwrap(normalized.descriptions["root"])), ["b", "c", "c", "a"])
    let canonical = field("canonical")
    canonical.className = "MAPriorityContainer"
    canonical.children = root.children
    let old = Graph(
      root: "canonical", descriptions: ["canonical": canonical, "a": a, "b": b, "c": c])
    old.format = "magritte.graph/3"
    XCTAssertThrowsError(try old.encode())
    var malformed = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
    malformed["descriptions"] = try XCTUnwrap(malformed["descriptions"] as? [[String: Any]]).map {
      row in
      var d = row
      if d["id"] as? String == "a" { d["childrenOrder"] = "stored" }
      return d
    }
    XCTAssertThrowsError(try Graph.decode(JSONSerialization.data(withJSONObject: malformed)))
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_MUTATION_OUTPUT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_MUTATION_INPUT"] {
      let peer = try Graph.decode(Data(contentsOf: URL(fileURLWithPath: path)))
      XCTAssertEqual(
        try JSONSerialization.jsonObject(with: peer.encode()) as? NSDictionary,
        try JSONSerialization.jsonObject(with: wire) as? NSDictionary)
    }
  }
  func testMutationFailuresAndBounds() throws {
    let a = field("a", 40)
    let b = field("b", 5)
    let c = field("c", 30)
    let bad = field("bad")
    bad.properties["priority"] = .string("bad")
    let p = Description(id: "p", className: "MAPriorityContainer")
    try p.setChildren([a, c])
    let before = try ids(p)
    XCTAssertThrowsError(try p.setChildren([a, bad]))
    XCTAssertEqual(try ids(p), before)
    XCTAssertThrowsError(try p.add(bad))
    XCTAssertEqual(try ids(p), before)
    XCTAssertThrowsError(try p.addAll([b, bad]))
    XCTAssertEqual(p.children.count, 4)
    XCTAssertTrue(p.children.last === bad)
    XCTAssertThrowsError(try p.resort())
    XCTAssertEqual(p.children.count, 4)
    let plain = Description(id: "plain", className: "MAContainer")
    XCTAssertThrowsError(try plain.resort())
    XCTAssertThrowsError(try field("scalar").add(a))
    var low = Limits()
    low.items = 0
    XCTAssertThrowsError(try plain.add(a, limits: low))
    XCTAssertTrue(plain.children.isEmpty)
    try plain.setChildren([a, b])
    try plain.addAll(plain.children)
    XCTAssertEqual(plain.children.count, 4)
  }
}
