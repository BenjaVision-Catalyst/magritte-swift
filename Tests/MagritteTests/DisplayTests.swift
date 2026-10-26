import Foundation
import Magritte
import XCTest

final class DisplayTests: XCTestCase {
  func plain(_ value: Value) throws -> String {
    try Description(id: "plain").displayStringFor(value)
  }
  func scalar(_ id: String, _ cls: String = "MAStringDescription") -> Description {
    Description(id: id, className: cls, key: id)
  }
  func configure(_ d: Description, _ mode: String) {
    switch mode {
    case "default": break
    case "block0": d.display(DisplayBlock { "fixed" })
    case "block1": d.display(DisplayBlock { [self] v in "[" + (try plain(v)) + "]" })
    case "block2":
      d.display(
        DisplayBlock { [self] v, d in
          guard case .string(let label) = try d.property("label") else {
            throw MagritteError("label")
          }
          return label + ":" + (try plain(v))
        })
    case "throw": d.display(DisplayBlock { () throws -> String in throw MagritteError("display") })
    case "nil": d.properties["displayBlockOrSymbol"] = .undefined
    default: d.display(mode == "too-many" ? "one:two:" : mode)
    }
  }
  func testSharedUpstreamScenarios() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "display-scenarios", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    for row in try XCTUnwrap(fixture["cases"] as? [[String: Any]]) {
      let cls = try XCTUnwrap(row["description"] as? String)
      let mode = try XCTUnwrap(row["mode"] as? String)
      let d = scalar("display", cls)
      let input = try decodeValue(JSONSerialization.data(withJSONObject: XCTUnwrap(row["input"])))
      d.properties = ["label": .string("Display"), "undefined": .string("(none)")]
      configure(d, mode)
      func run(_ key: String, _ operation: () throws -> String) throws {
        if row[key] is NSNull {
          XCTAssertThrowsError(try operation(), "\(cls) \(mode) \(key)")
        } else {
          XCTAssertEqual(try operation(), row[key] as? String, "\(cls) \(mode) \(key)")
        }
      }
      try run("direct") { try d.displayStringFor(input) }
      try run("writer") { try writeString(input, using: d) }
    }
  }
  final class Person: NSObject { let name = "Ada" }
  func testNativeMessagesAndCopy() throws {
    let d = scalar("name")
    var calls = 0
    let block = DisplayBlock { [self] v, _ in
      calls += 1
      return try plain(v) + "!"
    }
    d.display(block)
    XCTAssertEqual(try readString("Ada", using: d), .string("Ada"))
    XCTAssertEqual(calls, 0)
    XCTAssertEqual(try writeString(.string("Ada"), using: d), "Ada!")
    XCTAssertEqual(calls, 1)
    let copy = try copyDescription(d, newID: "copy")
    XCTAssertTrue(copy.root.displayBlock === block)
    d.display("asString")
    XCTAssertNil(d.displayBlock)
    XCTAssertTrue(copy.root.displayBlock === block)
    XCTAssertEqual(try writeString(.string("Bob"), using: copy.root), "Bob!")
    let native = Graph(root: "")
    let person = Person()
    let model = NativeModel(person)
    let ref = Value.reference("person")
    native.nativeObjects["person"] = model
    model.readers["MASelectorAccessor:shortName"] = { object in .string((object as! Person).name) }
    d.display("shortName")
    XCTAssertEqual(try d.displayStringFor(ref, graph: native), "Ada")
    XCTAssertEqual(try writeString(ref, using: d, graph: native), "Ada")
    d.properties["label"] = .string("Caption")
    model.displayReaders["caption:"] = { object, arg in
      XCTAssertTrue(arg === d)
      guard case .string(let label) = try XCTUnwrap(arg).property("label") else {
        throw MagritteError("label")
      }
      return .string((object as! Person).name + "/" + label)
    }
    d.display("caption:")
    XCTAssertEqual(try writeString(ref, using: d, graph: native), "Ada/Caption")
    XCTAssertThrowsError(try writeString(ref, using: d))
    model.displayReaders["bad"] = { _, _ in .integer(1) }
    d.display("bad")
    XCTAssertThrowsError(try writeString(ref, using: d, graph: native))
    d.display("unknown")
    XCTAssertThrowsError(try d.displayStringFor(ref, graph: native))
    model.displayReaders["+"] = { _, arg in
      XCTAssertTrue(arg === d)
      return .string("binary")
    }
    d.display("+")
    XCTAssertEqual(try d.displayStringFor(ref, graph: native), "binary")
    d.display(
      DisplayBlock {
        d.display("asString")
        return "once"
      })
    XCTAssertEqual(try writeString(.string("Ada"), using: d), "once")
    XCTAssertEqual(try writeString(.string("Ada"), using: d), "Ada")
    model.displayReaders["once"] = { _, _ in
      model.displayReaders.removeValue(forKey: "once")
      return .string("once")
    }
    d.display("once")
    XCTAssertEqual(try d.displayStringFor(ref, graph: native), "once")
    XCTAssertThrowsError(try d.displayStringFor(ref, graph: native))
    let option = scalar("nativeOption", "MASingleOptionDescription")
    let reference = scalar("nativeReference")
    let bob = NativeModel(Person())
    bob.readers["MASelectorAccessor:shortName"] = { _ in .string("Bob") }
    native.nativeObjects["bob"] = bob
    option.reference = reference
    reference.display("shortName")
    option.properties = ["required": .boolean(true), "sorted": .boolean(true)]
    option.display("shortName")
    option.options = Options([.reference("bob"), ref])
    XCTAssertEqual(try option.labelForOption(ref, graph: native), "Ada")
    XCTAssertEqual(try option.allOptions(graph: native).values().first, ref)
    let relation = scalar("relation", "MAToOneRelationDescription")
    relation.reference = d
    relation.display(
      DisplayBlock { () throws -> String in throw MagritteError("unused relation display") })
    d.display("shortName")
    XCTAssertThrowsError(try writeString(ref, using: relation, graph: native))
    let container = scalar("container", "MAContainer")
    container.children = [d]
    container.displayBlock = relation.displayBlock
    let dictionary = DictionaryModel(["name": .string("Ada")])
    d.display("asString")
    XCTAssertEqual(try writeString(dictionary, using: container), "Ada")
  }
  func testOptionRenderingSortingAndTokens() throws {
    let option = scalar("option", "MASingleOptionDescription")
    let reference = scalar("reference")
    option.reference = reference
    option.properties = ["required": .boolean(true), "sorted": .boolean(true)]
    option.options = Options([.string("Ada"), .string("Bob")])
    option.display(DisplayBlock { [self] v in "Option" + (try plain(v)) })
    var sortCalls = 0
    reference.display(
      DisplayBlock { [self] v in
        sortCalls += 1
        return try plain(v) == "Ada" ? "z" : "a"
      })
    XCTAssertEqual(try option.labelForOption(.string("Ada")), "OptionAda")
    XCTAssertEqual(try writeString(.string("Ada"), using: option), "OptionAda")
    XCTAssertEqual(try option.allOptions().values(), [.string("Ada"), .string("Bob")])
    XCTAssertEqual(sortCalls, 0)
    sortCalls = 0
    option.options = Options([.string("Ada")])
    XCTAssertEqual(try option.allOptions().count, 1)
    XCTAssertEqual(sortCalls, 0)
    option.options = Options([])
    XCTAssertEqual(try option.allOptions().count, 0)
    XCTAssertEqual(sortCalls, 0)
    option.labels = [(.symbol("Ada"), "Pinned")]
    XCTAssertEqual(try writeString(.symbol("Ada"), using: option), "Pinned")
    XCTAssertEqual(try writeString(.string("Ada"), using: option), "OptionAda")
    option.className = "MAMultipleOptionDescription"
    option.properties.removeValue(forKey: "sorted")
    XCTAssertEqual(
      try writeString(.array([.undefined, .string("Ada")]), using: option), "Optionnil, OptionAda")
    XCTAssertEqual(try writeString(.array([]), using: option), "")
    let token = scalar("token", "MATokenDescription")
    token.reference = reference
    reference.display(DisplayBlock { [self] v in "[" + (try plain(v)) + "]" })
    XCTAssertEqual(
      try writeString(.array([.undefined, .string("Ada")]), using: token), "nil Ada")
  }
  func testWireSnapshotsAndBounds() throws {
    let d = scalar("name")
    let root = scalar("container", "MAContainer")
    root.children = [d]
    let g = Graph(root: root.id, descriptions: [root.id: root, d.id: d])
    g.format = "magritte.graph/4"
    d.display("asString")
    let sample = AdaptiveModel(id: "sample", description: root, values: [d.id: .string("Ada")])
    g.objects[sample.id] = sample
    XCTAssertTrue(try validate(sample, using: root).isEmpty)
    XCTAssertEqual(try writeString(sample, using: root), "Ada")
    let encoded = try g.encode()
    XCTAssertEqual(try Graph.decode(encoded).encode(), encoded)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_DISPLAY_EXPORT"] {
      try encoded.write(to: URL(fileURLWithPath: path))
    }
    var badWire = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var nodes = try XCTUnwrap(badWire["descriptions"] as? [[String: Any]])
    for i in nodes.indices where nodes[i]["id"] as? String == d.id {
      var properties = try XCTUnwrap(nodes[i]["properties"] as? [String: Any])
      properties["displayBlockOrSymbol"] = ["type": "string", "value": "asString"]
      nodes[i]["properties"] = properties
    }
    badWire["descriptions"] = nodes
    XCTAssertThrowsError(try Graph.decode(JSONSerialization.data(withJSONObject: badWire)))
    d.properties["displayBlockOrSymbol"] = .undefined
    XCTAssertEqual(
      try Graph.decode(g.encode()).descriptions[d.id]?.property("displayBlockOrSymbol"), .undefined)
    g.format = "magritte.graph/2"
    XCTAssertThrowsError(try g.encode())
    g.format = "magritte.graph/4"
    for bad: Value in [.string("asString"), .integer(1), .array([])] {
      d.properties["displayBlockOrSymbol"] = bad
      XCTAssertThrowsError(try g.encode())
    }
    d.display(DisplayBlock { "fixed" })
    XCTAssertThrowsError(try g.encode())
    let container = scalar("container", "MAContainer")
    container.children = [d]
    d.properties["visible"] = .boolean(false)
    g.descriptions[container.id] = container
    g.root = container.id
    XCTAssertThrowsError(try g.encode())
    d.properties.removeValue(forKey: "visible")
    d.display("asString")
    var low = Limits()
    low.bytes = 3
    XCTAssertThrowsError(try d.displayStringFor(.string("long"), limits: low))
    d.display(DisplayBlock { "long" })
    XCTAssertThrowsError(try d.displayStringFor(.string("x"), limits: low))
    d.display("asString")
    XCTAssertEqual(try d.displayStringFor(.string("xy"), limits: low), "xy")
    d.display(DisplayBlock { "x" })
    XCTAssertEqual(try d.displayStringFor(.string("long input"), limits: low), "x")
  }
}
