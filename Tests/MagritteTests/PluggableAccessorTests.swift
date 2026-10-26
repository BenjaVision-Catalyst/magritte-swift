import Foundation
import Magritte
import XCTest

final class PluggableAccessorTests: XCTestCase {
  func data(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
  }
  func value(_ j: Any?) throws -> Value { try decodeValue(data(XCTUnwrap(j))) }
  func wire(_ v: Value) throws -> Any { try JSONSerialization.jsonObject(with: encodeValue(v)) }
  func object(_ j: Any?) throws -> [String: Any] { try XCTUnwrap(j as? [String: Any]) }
  func rows(_ j: Any?) throws -> [[String: Any]] { try XCTUnwrap(j as? [[String: Any]]) }
  func bool(_ j: Any?) throws -> Bool { try XCTUnwrap(j as? Bool) }
  func testLocalAccessorsAgainstGT() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "pluggable-accessors-reference", withExtension: "json",
        subdirectory: "Fixtures"))
    let f = try object(JSONSerialization.jsonObject(with: Data(contentsOf: url)))
    let model = DictionaryModel()
    let plain = DictionaryModel()
    var calls: [Any] = []
    let r = Accessor.ReadBlock { target in
      calls.append(["read", target === model])
      return try target.readSlot(strategy: "MADictionaryAccessor", name: "slot")
    }
    let w = Accessor.WriteBlock { target, value in
      calls.append(["write", target === model, try self.wire(value)])
      try target.writeSlot(strategy: "MADictionaryAccessor", name: "slot", value: value)
    }
    for row in try rows(f["capabilities"]) {
      let a = Accessor.pluggable(
        read: try bool(row["read"]) ? r : nil, write: try bool(row["write"]) ? w : nil)
      let target: Model = (row["model"] as? String) == "dictionary" ? model : plain
      calls = []
      XCTAssertEqual(try a.canRead(target), try bool(row["canRead"]))
      XCTAssertEqual(try a.canWrite(target), try bool(row["canWrite"]))
      XCTAssertEqual(try data(calls), try data(XCTUnwrap(row["calls"])))
    }
    var a = Accessor.pluggable(read: r, write: w)
    for row in try rows(f["readWrites"]) {
      calls = []
      try a.write(value(row["input"]), to: model)
      XCTAssertEqual(try a.read(model), try value(row["value"]))
      XCTAssertEqual(try data(calls), try data(XCTUnwrap(row["calls"])))
    }
    var b = Accessor.pluggable(read: r, write: w)
    let c = Accessor.pluggable(
      read: .init { try $0.readSlot(strategy: "MADictionaryAccessor", name: "slot") }, write: w)
    let selector = Accessor(className: "MASelectorAccessor", name: "slot", writeName: "slot:")
    let equalities = try [
      accessorEqual(a, a), accessorEqual(a, b), accessorEqual(a, c),
      accessorEqual(a, .pluggable(read: r)), accessorEqual(a, selector),
      accessorEqual(.pluggable(), .pluggable()), accessorEqual(a, a),
    ]
    XCTAssertEqual(equalities, f["equality"] as? [Bool])
    var counter = 0
    a = .pluggable(
      read: .init { _ in
        counter += 1
        return .integer(Int64(counter))
      }, write: w)
    b = a
    var outputs = [try a.read(model), try b.read(model)]
    let copyInfo = try object(f["copy"])
    XCTAssertEqual(a.readBlock === b.readBlock, try bool(copyInfo["sameReadBlock"]))
    XCTAssertEqual(a.writeBlock === b.writeBlock, try bool(copyInfo["sameWriteBlock"]))
    b.readBlock = .init { _ in .integer(99) }
    outputs += [try a.read(model), try b.read(model)]
    XCTAssertEqual(
      outputs, try XCTUnwrap(copyInfo["outputs"] as? [Int]).map { .integer(Int64($0)) })
    XCTAssertEqual(counter, copyInfo["counter"] as? Int)
    XCTAssertEqual(try accessorEqual(a, b), try bool(copyInfo["equalAfterReplacement"]))
    let d = Description(id: "field")
    d.properties = ["label": .string("Value"), "required": .boolean(true)]
    d.accessor = a
    var copied = try copyDescription(d, newID: "copy")
    XCTAssertEqual(try descriptionEqual(d, copied.root), try bool(copyInfo["descriptionEqual"]))
    XCTAssertEqual(
      try copied.root.effectiveAccessor.readBlock === a.readBlock,
      try bool(copyInfo["descriptionReadShared"]))
    d.accessor = nil
    d.accessorObject = try AccessorObject.fromAccessor(id: "live-accessor", a)
    copied = try copyDescription(d, newID: "copy-live")
    XCTAssertEqual(
      d.accessorObject !== copied.root.accessorObject,
      try bool(copyInfo["descriptionAccessorDistinct"]))
    XCTAssertTrue(try accessorEqual(d.effectiveAccessor, copied.root.effectiveAccessor))
    let inner = DictionaryModel(["slot": .string("start")])
    let resolver = Graph(root: "unused")
    resolver.nativeObjects["inner"] = inner
    let head = Accessor.pluggable(
      read: .init { _ in
        calls.append("head")
        return .reference("inner")
      })
    let tail = Accessor.pluggable(
      read: .init { target in
        calls.append("tailRead")
        return try target.readSlot(strategy: "MADictionaryAccessor", name: "slot")
      },
      write: .init { target, value in
        calls.append("tailWrite")
        try target.writeSlot(strategy: "MADictionaryAccessor", name: "slot", value: value)
      })
    let chain = Accessor(className: "MAChainAccessor", steps: [head, tail])
    for row in try rows(f["chains"]) {
      calls = []
      var result = Value.undefined
      switch row["operation"] as? String {
      case "canRead": result = .boolean(try chain.canRead(model, graph: resolver))
      case "canWrite": result = .boolean(try chain.canWrite(model, graph: resolver))
      case "read": result = try chain.read(model, graph: resolver)
      case "write": try chain.write(.string("changed"), to: model, graph: resolver)
      default: XCTFail("Unknown reference operation")
      }
      XCTAssertEqual(result, try value(row["value"]))
      XCTAssertEqual(inner.values["slot"], try value(row["inner"]))
      XCTAssertEqual(try data(calls), try data(XCTUnwrap(row["calls"])))
    }
    XCTAssertTrue(try chain.canRead(model))
    XCTAssertTrue(try chain.canWrite(model))
    let delegator = Accessor(className: "MADelegatorAccessor", steps: [tail])
    XCTAssertTrue(try delegator.canRead(inner))
    XCTAssertTrue(try delegator.canWrite(inner))
    XCTAssertEqual(try delegator.read(inner), .string("changed"))
    a = .pluggable(read: r, write: w)
    d.accessorObject = nil
    d.accessor = a
    model.values["slot"] = .string("base")
    let root = Description(id: "root", className: "MAContainer")
    root.children = [d]
    let editor = try CachedMemento(model: model, description: root)
    var snapshots: [[String: Any]] = []
    func snapshot() throws {
      snapshots.append([
        "model": try wire(XCTUnwrap(model.values["slot"])),
        "editor": try wire(editor.read(using: d)), "changed": try editor.hasChanges(),
      ])
    }
    try snapshot()
    try editor.write(.string("edited"), using: d)
    XCTAssertTrue(try editor.validate().isEmpty)
    try snapshot()
    try editor.commit()
    try snapshot()
    XCTAssertEqual(try data(snapshots), try data(XCTUnwrap(f["memento"])))
    XCTAssertThrowsError(try Accessor.pluggable().read(model))
    XCTAssertThrowsError(try Accessor.pluggable().write(.undefined, to: model))
    XCTAssertThrowsError(
      try Accessor.pluggable(read: .init { _ in throw MagritteError("Read failure") }).read(model))
    XCTAssertThrowsError(
      try Accessor.pluggable(write: .init { _, _ in throw MagritteError("Write failure") }).write(
        .undefined, to: model))
    let info = try XCTUnwrap(ClassRegistry.shared.find("MAPluggableAccessor"))
    let classInfo = try object(f["class"])
    XCTAssertEqual(info.superclass, classInfo["superclass"] as? String)
    XCTAssertEqual(info.label, classInfo["label"] as? String)
    XCTAssertFalse(info.isAbstract)
    let object = try AccessorObject.fromAccessor(id: "pluggable", a)
    let session = RecursiveDescriptionModel()
    XCTAssertTrue(try session.describe(object).children.isEmpty)
    XCTAssertEqual((f["metadataFields"] as? [String])?.count, 0)
    let metadata = try session.bind(d)
    XCTAssertTrue(
      try Accessor(className: "MASelectorAccessor", name: "name", writeName: "name:").read(metadata)
        .isNil)
    let live = try AccessorObject.fromAccessor(id: "live", a)
    d.accessorObject = live
    d.accessor = nil
    live.value.readBlock = .init { _ in .string("replacement") }
    XCTAssertEqual(try model.read(using: d), .string("replacement"))
    XCTAssertThrowsError(try encodeAccessor(a))
    XCTAssertThrowsError(try encodeAccessor(.pluggable()))
    XCTAssertThrowsError(try encodeAccessor(chain))
    XCTAssertThrowsError(try decodeAccessor(data(["class": "MAPluggableAccessor"])))
    let graph = Graph(root: "root", descriptions: ["root": root, "field": d])
    graph.format = "magritte.graph/4"
    d.properties["visible"] = .boolean(false)
    XCTAssertThrowsError(try graph.encode())
    try d.materializeAccessor()
    XCTAssertThrowsError(try graph.encode())
    d.properties["visible"] = .boolean(true)
    var malformed = a
    malformed.name = "unexpected"
    XCTAssertThrowsError(try malformed.check())
    malformed = selector
    malformed.readBlock = r
    XCTAssertThrowsError(try malformed.check())
    var replacing = Accessor.pluggable()
    replacing.readBlock = .init { _ in
      replacing.readBlock = nil
      return .string("read-once")
    }
    XCTAssertEqual(try replacing.read(model), .string("read-once"))
    XCTAssertFalse(try replacing.canRead(model))
    replacing.writeBlock = .init { _, _ in replacing.writeBlock = nil }
    try replacing.write(.undefined, to: model)
    XCTAssertFalse(try replacing.canWrite(model))
    var tiny = Limits()
    tiny.visits = 0
    XCTAssertThrowsError(try a.canRead(model, limits: tiny))
    tiny = Limits()
    tiny.bytes = 8
    var called = false
    let bounded = Accessor.pluggable(
      read: .init { _ in .string("long result") }, write: .init { _, _ in called = true })
    XCTAssertThrowsError(try bounded.read(model, limits: tiny))
    XCTAssertThrowsError(try bounded.write(.string("long input"), to: model, limits: tiny))
    XCTAssertFalse(called)
    d.accessor = Accessor(name: "slot")
    graph.objects["sample"] = AdaptiveModel(
      id: "sample", description: root, values: ["field": try XCTUnwrap(model.values["slot"])])
    let encoded = try graph.encode()
    let decoded = try Graph.decode(encoded)
    XCTAssertEqual(
      try decoded.descriptions["field"]?.effectiveAccessor.className, "MADictionaryAccessor")
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_PLUGGABLE_EXPORT"] {
      try encoded.write(to: URL(fileURLWithPath: path))
    }
  }
}
