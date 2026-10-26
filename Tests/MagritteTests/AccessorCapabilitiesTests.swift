import Foundation
import Magritte
import XCTest

final class AccessorCapabilitiesTests: XCTestCase {
  final class Probe {
    var contents: Value = .undefined
    var reads = 0, writes = 0
    var fail = false
  }
  func bind(_ p: Probe) -> NativeModel {
    let m = NativeModel(p)
    m.readers["MASelectorAccessor:contents"] = { raw in
      let p = raw as! Probe
      p.reads += 1
      if p.fail { throw MagritteError("Probe read failure") }
      return p.contents
    }
    m.writers["MASelectorAccessor:contents:"] = { raw, value in
      let p = raw as! Probe
      p.writes += 1
      p.contents = value
    }
    m.readers["MAVariableAccessor:contents"] = { ($0 as! Probe).contents }
    m.writers["MAVariableAccessor:contents"] = { ($0 as! Probe).contents = $1 }
    m.readers["MAVariableAccessor:failRead"] = { .boolean(($0 as! Probe).fail) }
    return m
  }
  func selector(_ read: String = "contents", _ write: String = "contents:") -> Accessor {
    Accessor(className: "MASelectorAccessor", name: read, writeName: write)
  }
  func data(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
  }
  func testCapabilitiesAndInvocationTracesAgainstGT() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "accessor-capabilities-reference", withExtension: "json",
        subdirectory: "Fixtures"))
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    XCTAssertEqual(fixture["absentSelectorMetadataIsNil"] as? Bool, true)
    let rows = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
    var output: [[String: Any]] = []
    for row in rows {
      let probe = Probe()
      let other = Probe()
      probe.fail = try XCTUnwrap(row["failRead"] as? Bool)
      other.contents = .string("value")
      let p = bind(probe)
      let o = bind(other)
      let inner = DictionaryModel(["field": .string("hello"), "child": .reference("other")])
      probe.contents = try XCTUnwrap(row["nilContents"] as? Bool) ? .undefined : .reference("inner")
      let graph = Graph(root: "unused")
      graph.nativeObjects = ["probe": p, "other": o, "inner": inner]
      let models: [String: Model] = [
        "probe": p, "dictionary": inner, "plain": DictionaryModel(),
        "description": Description(id: "description"),
      ]
      let model = try XCTUnwrap(models[XCTUnwrap(row["model"] as? String)])
      let a = try decodeAccessor(data(XCTUnwrap(row["accessor"])))
      XCTAssertEqual(
        try data(JSONSerialization.jsonObject(with: encodeAccessor(a))),
        try data(XCTUnwrap(row["accessor"])))
      let object = try AccessorObject.fromAccessor(id: "accessor", a)
      XCTAssertEqual(try encodeAccessor(object.snapshot()), try encodeAccessor(a))
      for writing in [false, true] {
        probe.reads = 0
        other.reads = 0
        probe.writes = 0
        other.writes = 0
        let expected = try XCTUnwrap(row[writing ? "write" : "read"] as? [String: Any])
        var failed = false
        var result = false
        do {
          result = try writing ? a.canWrite(model, graph: graph) : a.canRead(model, graph: graph)
        } catch { failed = true }
        let context = "\(row["name"]!) \(writing ? "write" : "read")"
        XCTAssertEqual(failed, expected["error"] != nil, context)
        if !failed { XCTAssertEqual(result, try XCTUnwrap(expected["value"] as? Bool), context) }
        XCTAssertEqual(
          [probe.reads, other.reads], try XCTUnwrap(expected["reads"] as? [Int]), context)
        XCTAssertEqual(
          [probe.writes, other.writes], try XCTUnwrap(expected["writes"] as? [Int]), context)
      }
      var config = row
      config.removeValue(forKey: "read")
      config.removeValue(forKey: "write")
      config["accessor"] = try JSONSerialization.jsonObject(with: encodeAccessor(a))
      output.append(config)
    }
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_CAPABILITIES_EXPORT"] {
      try data(output).write(to: URL(fileURLWithPath: path))
    }
  }
  func testLiveBindingsMetadataAndBounds() throws {
    let raw = Probe()
    let native = bind(Probe())
    let a = selector()
    _ = raw
    XCTAssertTrue(try a.canRead(native))
    XCTAssertTrue(try a.canWrite(native))
    native.readers.removeValue(forKey: "MASelectorAccessor:contents")
    XCTAssertFalse(try a.canRead(native))
    XCTAssertTrue(try a.canWrite(native))
    native.writers["MASelectorAccessor:contents"] = { _, _ in }
    XCTAssertTrue(try a.canRead(native))  // respondsTo: ignores invocation arity.
    native.writers.removeValue(forKey: "MASelectorAccessor:contents")
    var called = false
    native.readers["MASelectorAccessor:"] = { _ in
      called = true
      return .undefined
    }
    let absent = selector("", "")
    XCTAssertFalse(try absent.canRead(native))
    XCTAssertFalse(try absent.canWrite(native))
    XCTAssertThrowsError(try absent.read(native))
    XCTAssertThrowsError(try absent.write(.undefined, to: native))
    XCTAssertFalse(called)
    let variable = Accessor(className: "MAVariableAccessor", name: "failRead")
    XCTAssertTrue(try variable.canRead(native))
    XCTAssertTrue(try variable.canWrite(native))
    let field = Description(id: "field", key: "field")
    let dictionary = DictionaryModel()
    field.properties["readOnly"] = .boolean(true)
    field.properties["visible"] = .boolean(false)
    XCTAssertTrue(try field.effectiveAccessor.canWrite(dictionary))
    try field.effectiveAccessor.write(.string("edited"), to: dictionary)
    XCTAssertEqual(dictionary.values["field"], .string("edited"))
    let metadata = Description(id: "metadata", key: "metadata")
    let session = RecursiveDescriptionModel()
    let binding = try session.bind(metadata)
    XCTAssertTrue(try selector("label", "label:").canWrite(binding))
    XCTAssertFalse(try selector("children", "setChildren:").canRead(binding))
    metadata.className = "MAContainer"
    XCTAssertTrue(try selector("children", "setChildren:").canRead(binding))
    let accessorObject = try AccessorObject.fromAccessor(
      id: "dictionary-accessor", field.effectiveAccessor)
    let accessorBinding = try session.bind(accessorObject)
    XCTAssertTrue(try selector("key", "key:").canRead(accessorBinding))
    XCTAssertTrue(try selector("key", "key:").canWrite(accessorBinding))
    var shortSession: RecursiveDescriptionModel? = RecursiveDescriptionModel()
    let expired = try shortSession!.bind(metadata)
    shortSession = nil
    XCTAssertThrowsError(try selector("label", "label:").canRead(expired))
    let missingObject = try AccessorObject.fromAccessor(id: "missing-selector", absent)
    let missingBinding = try session.bind(missingObject)
    XCTAssertTrue(try selector("selector", "selector:").read(missingBinding).isNil)
    let emptyNative = bind(Probe())
    let independent = Accessor(
      className: "MAChainAccessor", steps: [selector(), try field.effectiveAccessor])
    XCTAssertTrue(try independent.canRead(emptyNative))
    XCTAssertTrue(try independent.canWrite(emptyNative))
    var tiny = Limits()
    tiny.visits = 1
    XCTAssertThrowsError(try a.canRead(native, limits: tiny))
    let chain = Accessor(
      className: "MAChainAccessor", steps: [selector(), try field.effectiveAccessor])
    tiny = Limits()
    tiny.depth = 0
    XCTAssertThrowsError(try chain.canWrite(native, limits: tiny))
    XCTAssertThrowsError(try Accessor(className: "UnknownAccessor").canRead(dictionary))
    let graphField = Description(id: "setter")
    let root = Description(id: "root", className: "MAContainer")
    graphField.accessor = selector("", "contents:")
    root.children = [graphField]
    let graph = Graph(root: "root", descriptions: ["root": root, "setter": graphField])
    graph.format = "magritte.graph/4"
    let decoded = try Graph.decode(graph.encode())
    XCTAssertTrue(try XCTUnwrap(decoded.descriptions["setter"]).effectiveAccessor.canWrite(native))
  }
}
