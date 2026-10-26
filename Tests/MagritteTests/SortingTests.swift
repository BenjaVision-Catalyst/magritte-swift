import Foundation
import Magritte
import XCTest

final class SortingTests: XCTestCase {
  func fixture() throws -> [String: Any] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "sorting-scenarios", withExtension: "json", subdirectory: "Fixtures"))
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }
  func value(_ object: Any?) throws -> Value {
    try decodeValue(JSONSerialization.data(withJSONObject: XCTUnwrap(object)))
  }
  func testSharedComparisons() throws {
    let rows = try XCTUnwrap(fixture()["comparisons"] as? [[String: Any]])
    for row in rows {
      let block = try SortBlock(selector: XCTUnwrap(row["selector"] as? String))
      let a = try value(row["left"])
      let b = try value(row["right"])
      if row["result"] is NSNull {
        XCTAssertThrowsError(try block.value(a, b))
      } else {
        XCTAssertEqual(try block.value(a, b), try value(row["result"]))
      }
      XCTAssertTrue(block.fixTemps() === block)
    }
  }
  final class SortableOverride: Description { override var isSortable: Bool { true } }
  func testSortabilityQueriesAndInheritance() throws {
    let custom = SortableOverride(id: "custom", className: "MAContainer")
    XCTAssertTrue(custom.isSortable)
    XCTAssertEqual(
      try custom.readSlot(strategy: "MASelectorAccessor", name: "isSortable"), .boolean(true))
    for row in try XCTUnwrap(fixture()["sortability"] as? [[String: Any]]) {
      let d = Description(id: "query", className: try XCTUnwrap(row["className"] as? String))
      let expected = try XCTUnwrap(row["result"] as? Bool)
      XCTAssertEqual(d.isSortable, expected)
      XCTAssertTrue(d.respondsToSelector("isSortable"))
      XCTAssertEqual(
        try d.readSlot(strategy: "MASelectorAccessor", name: "isSortable"), .boolean(expected))
      XCTAssertThrowsError(
        try d.writeSlot(strategy: "MASelectorAccessor", name: "isSortable:", value: .boolean(true)))
    }
    try ClassRegistry.shared.registerClasses([
      ClassInfo(name: "MASortTestText", superclass: "MAStringDescription"),
      ClassInfo(name: "MASortTestPassword", superclass: "MAPasswordDescription"),
    ])
    XCTAssertTrue(Description(id: "text", className: "MASortTestText").isSortable)
    XCTAssertFalse(Description(id: "password", className: "MASortTestPassword").isSortable)
  }
  final class Trace { var events: [String] = [] }
  final class Track: Model {
    let trace: Trace, tag: String
    var mode = "", onRead: (() throws -> Void)?,
      values: [String: Value] = ["rank": .integer(3), "other": .integer(9)]
    init(_ trace: Trace, _ tag: String) {
      self.trace = trace
      self.tag = tag
    }
    func readSlot(strategy: String, name: String) throws -> Value {
      trace.events.append(tag + ":" + name)
      try onRead?()
      if mode == "throw" { throw MagritteError("read") }
      return values[name] ?? .undefined
    }
    func read(using d: Description) throws -> Value { try d.effectiveAccessor.read(self) }
    func write(_ value: Value, using d: Description) throws { values[d.key] = value }
  }
  func testReadOrderAndSharedAccessorCopy() throws {
    let trace = Trace()
    let left = Track(trace, "L")
    let right = Track(trace, "R")
    right.values["rank"] = .integer(7)
    let live = try AccessorObject.fromAccessor(id: "rank", Accessor(name: "rank"))
    let block = try SortBlock(accessor: live, selector: "<=")
    XCTAssertEqual(try block.value(left, right), .boolean(true))
    XCTAssertEqual(trace.events, ["L:rank", "R:rank"])
    let copy = block.copy()
    XCTAssertFalse(copy === block)
    XCTAssertTrue(copy.accessor === live)
    trace.events = []
    left.onRead = { live.value.name = "other" }
    XCTAssertEqual(try copy.value(left, right), .boolean(true))
    XCTAssertEqual(trace.events, ["L:rank", "R:other"])
    left.onRead = nil
    live.value.name = "rank"
    trace.events = []
    left.mode = "throw"
    XCTAssertThrowsError(try block.value(left, right))
    XCTAssertEqual(trace.events, ["L:rank"])
    left.mode = ""
    trace.events = []
    right.mode = "throw"
    XCTAssertThrowsError(try block.value(left, right))
    XCTAssertEqual(trace.events, ["L:rank", "R:rank"])
    right.mode = ""
    trace.events = []
    XCTAssertThrowsError(try SortBlock(accessor: live, selector: "yourself").value(left, right))
    XCTAssertEqual(trace.events, ["L:rank", "R:rank"])
  }
  final class Host: NSObject {}
  func testValueTargetsAndHostMessages() throws {
    let resolver = Graph(root: "")
    let model = DictionaryModel(["rank": .integer(3)])
    let object = Value.reference("model")
    resolver.nativeObjects["model"] = model
    let identity = Accessor(className: "MAIdentityAccessor")
    let chain = Accessor(className: "MAChainAccessor", steps: [Accessor(name: "rank"), identity])
    XCTAssertEqual(try chain.readValue(object, graph: resolver), .integer(3))
    let delegator = Accessor(className: "MADelegatorAccessor", steps: [identity])
    XCTAssertEqual(try delegator.readValue(.string("raw")), .string("raw"))
    XCTAssertThrowsError(try Accessor(name: "rank").readValue(.string("raw")))
    let read = Accessor.ReadBlock { _ in .integer(42) }
    XCTAssertEqual(
      try Accessor.pluggable(read: read).readValue(object, graph: resolver), .integer(42))
    let host = Host()
    let native = NativeModel(host)
    let adapter = NativeModel(host)
    let ref = Value.reference("host")
    let alias = Value.reference("alias")
    let adapterRef = Value.reference("adapter")
    resolver.nativeObjects["host"] = native
    resolver.nativeObjects["alias"] = native
    resolver.nativeObjects["adapter"] = adapter
    XCTAssertEqual(try SortBlock(selector: "=").value(ref, alias, graph: resolver), .boolean(true))
    XCTAssertEqual(
      try SortBlock(selector: "=").value(ref, adapterRef, graph: resolver), .boolean(true))
    XCTAssertEqual(
      try SortBlock(selector: "~=").value(ref, adapterRef, graph: resolver), .boolean(false))
    let trace = Trace()
    let left = Track(trace, "L")
    let right = Track(trace, "R")
    native.binaryReaders["combine:"] = { receiver, arg, graph in
      XCTAssertTrue(receiver === host)
      XCTAssertTrue(graph === resolver)
      XCTAssertEqual(arg, alias)
      trace.events.append("send")
      native.binaryReaders.removeValue(forKey: "combine:")
      return .string("combined")
    }
    let projection = Accessor.pluggable(
      read: Accessor.ReadBlock { m in
        trace.events.append(m === left ? "L" : "R")
        return m === left ? ref : alias
      })
    let block = try SortBlock(accessor: projection, selector: "combine:")
    XCTAssertEqual(try block.value(left, right, graph: resolver), .string("combined"))
    XCTAssertEqual(trace.events, ["L", "R", "send"])
    XCTAssertThrowsError(try block.value(left, right, graph: resolver))
    native.binaryReaders["="] = { _, _, _ in .boolean(false) }
    XCTAssertEqual(try SortBlock(selector: "~=").value(ref, alias, graph: resolver), .boolean(true))
    native.binaryReaders["="] = { _, _, _ in .string("not boolean") }
    XCTAssertThrowsError(try SortBlock(selector: "~=").value(ref, alias, graph: resolver))
    XCTAssertThrowsError(try SortBlock(selector: "<=").value(ref, alias))
    XCTAssertThrowsError(
      try SortBlock(selector: "<=").value(.reference("missing"), alias, graph: resolver))
  }
  func testBoundsAndWireSnapshots() throws {
    let cyclic = try AccessorObject.fromAccessor(
      id: "cycle", Accessor(className: "MAIdentityAccessor"))
    cyclic.value.className = "MADelegatorAccessor"
    cyclic.next = cyclic
    XCTAssertThrowsError(
      try SortBlock(accessor: cyclic, selector: "<=").value(.integer(1), .integer(2)))
    cyclic.next = nil
    var low = Limits()
    low.visits = 1
    XCTAssertThrowsError(try SortBlock(selector: "<=").value(.integer(1), .integer(2), limits: low))
    let a = Description(id: "a", key: "a")
    let b = Description(id: "b", key: "b")
    let root = Description(id: "root", className: "MAContainer")
    a.properties["priority"] = .integer(7)
    b.properties["priority"] = .integer(3)
    root.children = [a, b]
    let graph = Graph(root: root.id, descriptions: [a.id: a, b.id: b, root.id: root])
    graph.format = "magritte.graph/4"
    let wire = try graph.encode()
    let imported = try Graph.decode(wire)
    let block = try SortBlock(
      accessor: Accessor(className: "MAPropertyAccessor", name: "priority"), selector: "<=")
    XCTAssertEqual(
      try block.value(XCTUnwrap(imported.descriptions["a"]), XCTUnwrap(imported.descriptions["b"])),
      .boolean(false))
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_SORTING_EXPORT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
  }
}
