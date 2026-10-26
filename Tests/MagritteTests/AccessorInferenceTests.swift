import Foundation
import Magritte
import XCTest

final class AccessorInferenceTests: XCTestCase {
  func data(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
  }
  func value(_ j: Any?) throws -> Value { try decodeValue(data(XCTUnwrap(j))) }
  func object(_ j: Any?) throws -> [String: Any] { try XCTUnwrap(j as? [String: Any]) }
  func rows(_ j: Any?) throws -> [[String: Any]] { try XCTUnwrap(j as? [[String: Any]]) }
  func wire(_ v: Value) throws -> Any { try JSONSerialization.jsonObject(with: encodeValue(v)) }
  func accessor(_ j: [String: Any]) throws -> Accessor {
    var a = Accessor(className: try XCTUnwrap(j["class"] as? String))
    a.name = (j["key"] as? String) ?? (j["name"] as? String) ?? (j["readSelector"] as? String) ?? ""
    a.writeName = (j["writeSelector"] as? String) ?? ""
    if let uuid = j["uuid"] { a.uuid = try value(uuid) }
    if let steps = j["steps"] { a.steps = try rows(steps).map(accessor) }
    if let next = j["next"] { a.steps = [try accessor(object(next))] }
    return a
  }
  func reference(_ expected: Any?, _ read: () throws -> Value) throws {
    let expected = try object(expected)
    if expected["error"] != nil {
      XCTAssertThrowsError(try read())
    } else {
      XCTAssertEqual(try read(), try value(expected["value"]))
    }
  }
  func testNamesLabelsAndMetadataAgainstGT() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "accessor-inference-reference", withExtension: "json", subdirectory: "Fixtures"
      ))
    let f = try object(JSONSerialization.jsonObject(with: Data(contentsOf: url)))
    for row in try rows(f["cases"]) {
      let a = try accessor(object(row["accessor"]))
      let d = Description(id: "target")
      d.accessor = a
      try reference(row["name"]) { try a.accessorName() }
      try reference(row["descriptionName"]) { try d.property("name") }
      let live = try AccessorObject.fromAccessor(id: "accessor", a)
      d.accessor = nil
      d.accessorObject = live
      try reference(row["name"]) { try d.property("name") }
      if !(try XCTUnwrap(row["ascii"] as? Bool)) {
        XCTAssertThrowsError(try a.defaultLabel(for: d))
        XCTAssertThrowsError(try d.property("label"))
        d.properties["label"] = .string("Étiquette")
        XCTAssertEqual(try d.property("label"), .string("Étiquette"))
        XCTAssertTrue(try d.hasLabel())
        continue
      }
      try reference(row["label"]) { .string(try a.defaultLabel(for: d)) }
      try reference(row["descriptionLabel"]) { try d.property("label") }
      XCTAssertEqual(try d.hasLabel(), try XCTUnwrap(row["hasLabel"] as? Bool))
      XCTAssertEqual(
        try d.readSlot(strategy: "MASelectorAccessor", name: "defaultLabel"),
        try value(object(row["label"])["value"]))
      XCTAssertEqual(
        try d.readSlot(strategy: "MASelectorAccessor", name: "hasLabel"),
        .boolean(try XCTUnwrap(row["hasLabel"] as? Bool)))
      let schema = try descriptionModelFor(d)
      XCTAssertEqual(
        try XCTUnwrap(schema.descriptions[schema.root + ".label"]).property("default"),
        try value(object(row["label"])["value"]))
    }
    for row in try rows(f["labelOverrides"]) {
      let d = Description(id: "target", key: "firstName")
      d.properties["label"] = try value(row["input"])
      XCTAssertEqual(try d.property("label"), try value(row["label"]))
      XCTAssertEqual(try d.hasLabel(), try XCTUnwrap(row["hasLabel"] as? Bool))
      XCTAssertEqual(.string(try d.defaultLabel()), try value(row["defaultLabel"]))
      let schema = try descriptionModelFor(d)
      XCTAssertEqual(
        try XCTUnwrap(schema.descriptions[schema.root + ".label"]).property("default"),
        try value(row["metadataDefault"]))
    }
    for row in try rows(f["nameOverrides"]) {
      let d = Description(id: "target", key: "firstName")
      d.properties["name"] = try value(row["input"])
      XCTAssertEqual(try d.property("name"), try value(row["name"]))
      XCTAssertEqual(try d.property("label"), try value(row["label"]))
    }
    for row in try rows(f["classes"]) {
      let d = Description(id: "target", className: try XCTUnwrap(row["class"] as? String))
      if !d.isContainer { d.key = "firstName" }
      XCTAssertEqual(try d.property("label"), try value(row["label"]))
      XCTAssertEqual(.string(try d.defaultLabel()), try value(row["defaultLabel"]))
      let schema = try descriptionModelFor(d)
      let label = try XCTUnwrap(schema.descriptions[schema.root + ".label"])
      XCTAssertEqual(try label.property("default"), try value(row["metadataDefault"]))
      let second = try descriptionModelFor(label)
      XCTAssertEqual(
        try XCTUnwrap(second.descriptions[second.root + ".label"]).property("default"),
        .string("Label"))
    }
    let d = Description(id: "field", key: "firstName")
    d.accessorObject = try AccessorObject.fromAccessor(id: "live", d.effectiveAccessor)
    var live: [[String: Any]] = []
    func snapshot() throws {
      live.append([
        "name": try wire(d.property("name")), "label": try wire(d.property("label")),
        "hasLabel": try d.hasLabel(), "defaultLabel": try wire(.string(d.defaultLabel())),
      ])
    }
    try snapshot()
    d.accessorObject!.value.name = "lastName"
    try snapshot()
    d.properties["label"] = .string("")
    d.accessorObject!.value.name = "postalCode"
    try snapshot()
    d.properties.removeValue(forKey: "label")
    try snapshot()
    let chain = Accessor(
      className: "MAChainAccessor",
      steps: [
        Accessor(name: "accountDetails"),
        Accessor(className: "MASelectorAccessor", name: "postalCode", writeName: "postalCode:"),
      ])
    d.accessorObject = try AccessorObject.fromAccessor(id: "chain", chain)
    try snapshot()
    XCTAssertEqual(try data(live), try data(XCTUnwrap(f["live"])))
    d.accessorObject = nil
    d.accessor = nil
    d.key = "firstName"
    let schema = try descriptionModelFor(d)
    let label = try XCTUnwrap(schema.descriptions[schema.root + ".label"])
    let editorRoot = Description(id: "editor", className: "MAContainer")
    editorRoot.children = [label]
    let editor = try CachedMemento(model: d, description: editorRoot)
    var editing: [[String: Any]] = []
    func editSnapshot() throws {
      editing.append([
        "label": try wire(d.property("label")), "editor": try wire(editor.read(using: label)),
        "hasLabel": try d.hasLabel(), "changed": try editor.hasChanges(),
      ])
    }
    try editSnapshot()
    try editor.write(.string(""), using: label)
    try editSnapshot()
    try editor.commit()
    try editSnapshot()
    XCTAssertEqual(try data(editing), try data(XCTUnwrap(f["editing"])))
    let session = RecursiveDescriptionModel()
    let binding = try session.bind(d)
    XCTAssertEqual(
      try Accessor(className: "MASelectorAccessor", name: "name", writeName: "name:").read(binding),
      try d.property("name"))
    let copy = try copyDescription(d, newID: "copy")
    copy.root.key = "lastName"
    copy.root.properties.removeValue(forKey: "label")
    XCTAssertEqual(try copy.root.property("label"), .string("Last Name"))
    XCTAssertEqual(try d.property("label"), .string(""))
    var calls = 0
    let local = Accessor.pluggable(
      read: .init { _ in
        calls += 1
        return .undefined
      })
    let localDescription = Description(id: "local")
    localDescription.accessor = local
    XCTAssertEqual(try localDescription.property("label"), .string(""))
    XCTAssertTrue(try localDescription.property("name").isNil)
    XCTAssertEqual(calls, 0)
    let unconfigured = Description(id: "unconfigured")
    XCTAssertEqual(try unconfigured.effectiveAccessor.className, "MANullAccessor")
    XCTAssertTrue(try unconfigured.property("name").isNil)
    XCTAssertFalse(try unconfigured.hasLabel())
    let fresh = Description(id: "fresh")
    let beforeCopy = try copyDescription(fresh, newID: "before")
    let unconfiguredInfo = try object(f["unconfigured"])
    XCTAssertEqual(
      try descriptionEqual(fresh, beforeCopy.root),
      unconfiguredInfo["copyBeforeAccessEqual"] as? Bool)
    let cached = try fresh.effectiveAccessor
    let other = Description(id: "other")
    XCTAssertEqual(
      try accessorEqual(cached, fresh.effectiveAccessor), unconfiguredInfo["stable"] as? Bool)
    XCTAssertEqual(
      try !accessorEqual(cached, other.effectiveAccessor), unconfiguredInfo["distinct"] as? Bool)
    let afterCopy = try copyDescription(fresh, newID: "after")
    XCTAssertEqual(
      try descriptionEqual(fresh, afterCopy.root), unconfiguredInfo["copyAfterAccessEqual"] as? Bool
    )
    var tiny = Limits()
    tiny.bytes = 1
    XCTAssertThrowsError(try chain.defaultLabel(for: d, limits: tiny))
    tiny = Limits()
    tiny.visits = 1
    XCTAssertThrowsError(try chain.accessorName(limits: tiny))
    tiny = Limits()
    tiny.depth = 0
    XCTAssertThrowsError(try chain.defaultLabel(for: d, limits: tiny))
    let cyclic = try AccessorObject.fromAccessor(id: "cyclic", chain)
    cyclic.next = cyclic
    d.accessorObject = cyclic
    d.properties["label"] = .string("Explicit")
    XCTAssertEqual(try d.property("label"), .string("Explicit"))
    XCTAssertThrowsError(try d.defaultLabel())
    cyclic.next = nil
    d.accessorObject = nil
    d.properties = [:]
    d.key = "firstName"
    d.properties["required"] = .boolean(true)
    let app = Description(id: "app", className: "MAContainer")
    app.children = [d]
    let graph = Graph(
      root: "app", descriptions: ["app": app, "field": d],
      objects: [
        "sample": AdaptiveModel(id: "sample", description: app, values: ["field": .string("Ada")])
      ])
    graph.format = "magritte.graph/4"
    let encoded = try graph.encode()
    let decoded = try Graph.decode(encoded)
    XCTAssertEqual(
      try XCTUnwrap(decoded.descriptions["field"]).property("label"), .string("First Name"))
    XCTAssertNil(decoded.descriptions["field"]?.properties["label"])
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_INFERENCE_EXPORT"] {
      try encoded.write(to: URL(fileURLWithPath: path))
    }
  }
}
