import Foundation
import Magritte
import XCTest

private final class PrintingTrace: Model {
  var values: [String: Value] = [:], trace: [String] = []
  var beforeRead: ((Description) throws -> Void)?
  func read(using d: Description) throws -> Value {
    trace.append("read:" + d.id)
    try beforeRead?(d)
    return values[d.id] ?? .undefined
  }
  func write(_ value: Value, using d: Description) throws {
    throw MagritteError("Printing must not write")
  }
}
final class PrintingTests: XCTestCase {
  func field(_ id: String) -> Description {
    let d = Description(id: id, key: id)
    d.properties = [
      "required": .boolean(true), "readOnly": .boolean(true), "visible": .boolean(false),
      "default": .string("unused"), "undefined": .string("(nil)"),
    ]
    return d
  }
  func value(_ object: Any?) throws -> Value {
    try decodeValue(JSONSerialization.data(withJSONObject: XCTUnwrap(object)))
  }
  func testSharedPrintingAndReadToString() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "printing-scenarios", withExtension: "json", subdirectory: "Fixtures"))
    let fixture = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    for row in try XCTUnwrap(fixture["containers"] as? [[String: Any]]) {
      let root = Description(id: "root", className: "MAContainer")
      let model = PrintingTrace()
      root.properties["visible"] = .boolean(false)
      let values = try XCTUnwrap(row["values"] as? [Any])
      for (i, id) in ["a", "b", "c"].enumerated() {
        let d = field(id)
        model.values[id] = try value(values[i])
        root.children.append(d)
        if row["formatter"] as? Bool == true {
          try d.setPrintString(
            PrintValueBlock { [weak root] v in
              model.trace.append("format:" + id)
              return "[" + (try writeString(v, using: XCTUnwrap(root?.children.first))) + "]"
            })
        }
      }
      if let sep = row["separator"] as? String {
        try root.setPrintSeparator(
          PrintSeparatorBlock { s in
            model.trace.append("separator")
            try s.append(sep)
          })
      }
      let stream = PrintStream()
      try root.print(model, on: stream)
      XCTAssertEqual(stream.contents, row["output"] as? String)
      XCTAssertEqual(model.trace, row["trace"] as? [String])
    }
    for row in try XCTUnwrap(fixture["elements"] as? [[String: Any]]) {
      let d = field("a")
      let model = PrintingTrace()
      model.values[d.id] = try value(row["value"])
      try d.setPrintString(
        PrintValueBlock { throw MagritteError("printFor must ignore maPrintString") })
      XCTAssertEqual(try d.readToString(model), row["readToString"] as? String)
      let stream = PrintStream()
      try d.printFor(model, on: stream)
      XCTAssertEqual(stream.contents, row["printFor"] as? String)
      XCTAssertEqual(model.trace, ["read:a", "read:a"])
    }
  }
  func testCallbackTimingAndPartialFailures() throws {
    let root = Description(id: "root", className: "MAContainer")
    let a = field("a")
    let b = field("b")
    let c = field("c")
    let model = PrintingTrace()
    root.children = [a, b, c]
    model.values = ["a": .string("A"), "b": .string("B"), "c": .string("C")]
    let second = PrintSeparatorBlock { s in try s.append("!") }
    var separators = 0
    let first = PrintSeparatorBlock { [weak root] s in
      separators += 1
      try root?.setPrintSeparator(second)
      try s.append("|")
    }
    try root.setPrintSeparator(first)
    let formatter = PrintValueBlock { [weak a] _ in
      try a?.setPrintString(nil)
      return "first"
    }
    try a.setPrintString(formatter)
    let stream = PrintStream()
    try root.print(model, on: stream)
    XCTAssertEqual(stream.contents, "first|B|C")
    XCTAssertEqual(separators, 2)
    XCTAssertTrue(root.printSeparatorBlock === second)
    XCTAssertNil(a.printStringBlock)
    model.beforeRead = { d in
      if d.id == "b" { try b.setPrintString(PrintValueBlock { "after-read" }) }
    }
    let again = PrintStream()
    try root.print(model, on: again)
    XCTAssertEqual(again.contents, "A!after-read!C")
    model.beforeRead = nil
    try b.setPrintString(nil)
    try root.setPrintSeparator(nil)
    let partial = PrintStream()
    try partial.append("prefix:")
    model.trace.removeAll()
    model.beforeRead = { d in if d.id == "b" { throw MagritteError("read") } }
    XCTAssertThrowsError(try root.print(model, on: partial))
    XCTAssertEqual(partial.contents, "prefix:A ")
    XCTAssertEqual(model.trace, ["read:a", "read:b"])
    model.beforeRead = nil
    try root.setPrintSeparator(
      PrintSeparatorBlock { s in
        try s.append("|")
        throw MagritteError("separator")
      })
    let sepFailure = PrintStream()
    model.trace.removeAll()
    XCTAssertThrowsError(try root.print(model, on: sepFailure))
    XCTAssertEqual(sepFailure.contents, "A|")
    XCTAssertEqual(model.trace, ["read:a"])
    try root.setPrintSeparator(nil)
    try b.setPrintString(PrintValueBlock { throw MagritteError("formatter") })
    let formatFailure = PrintStream()
    XCTAssertThrowsError(try root.print(model, on: formatFailure))
    XCTAssertEqual(formatFailure.contents, "A ")
    try b.setPrintString(nil)
    try a.propertyPut("maPrintString", .undefined)
    model.values["a"] = .undefined
    let nilField = PrintStream()
    try root.print(model, on: nilField)
    XCTAssertEqual(nilField.contents, " B C")
    model.values["a"] = .string("A")
    XCTAssertThrowsError(try root.print(model, on: PrintStream()))
    try a.propertyPutRemovingNil("maPrintString", .undefined)
    try root.propertyPut("maPrintStringSeparator", .undefined)
    root.children = [a]
    let singleton = PrintStream()
    try root.print(model, on: singleton)
    XCTAssertEqual(singleton.contents, "A")
    root.children = [a, b]
    let nilSeparator = PrintStream()
    XCTAssertThrowsError(try root.print(model, on: nilSeparator))
    XCTAssertEqual(nilSeparator.contents, "A")
    try root.setPrintSeparator(nil)
  }
  func testLocalPropertiesCopiesAndWire() throws {
    let root = Description(id: "root", className: "MAContainer")
    let a = field("a")
    let b = field("b")
    let c = field("c")
    root.children = [a, b, c]
    let formatter = PrintValueBlock { "custom" }
    try a.setPrintString(formatter)
    XCTAssertTrue(a.hasProperty("maPrintString"))
    XCTAssertThrowsError(try a.propertyAt("maPrintString"))
    XCTAssertThrowsError(try a.property("maPrintString"))
    XCTAssertThrowsError(try a.propertyPutRemovingNil("maPrintString", .undefined))
    let copy = try copyDescription(a, newID: "copy")
    XCTAssertTrue(copy.root.printStringBlock === formatter)
    try copy.root.setPrintString(nil)
    XCTAssertTrue(a.printStringBlock === formatter)
    try a.propertyPut("maPrintString", .undefined)
    XCTAssertNil(a.printStringBlock)
    XCTAssertEqual(try a.propertyAt("maPrintString"), .undefined)
    try a.setPrintString(nil)
    let separator = PrintSeparatorBlock { s in try s.append("|") }
    XCTAssertThrowsError(try a.setPrintSeparator(separator))
    let model = AdaptiveModel(
      id: "object", description: root,
      values: ["a": .string("A"), "b": .string("B"), "c": .string("C")])
    XCTAssertThrowsError(try a.print(model, on: PrintStream()))
    XCTAssertThrowsError(try root.printFor(model, on: PrintStream()))
    let g = Graph(root: root.id, descriptions: [root.id: root, "a": a, "b": b, "c": c])
    g.format = "magritte.graph/4"
    g.objects[model.id] = model
    try root.setPrintString(
      PrintValueBlock { throw MagritteError("Container printer ignores its own field formatter") })
    let own = PrintStream()
    try root.print(model, on: own)
    XCTAssertEqual(own.contents, "A B C")
    XCTAssertThrowsError(try g.encode())
    try root.setPrintString(nil)
    try a.setPrintString(formatter)
    XCTAssertThrowsError(try g.encode())
    try a.setPrintString(nil)
    try root.setPrintSeparator(separator)
    let rootCopy = try copyDescription(root, newID: "rootCopy")
    XCTAssertTrue(rootCopy.root.printSeparatorBlock === separator)
    XCTAssertThrowsError(try g.encode())
    try root.setPrintSeparator(nil)
    let wire = try g.encode()
    let imported = try Graph.decode(wire)
    let out = PrintStream()
    try XCTUnwrap(imported.descriptions[imported.root]).print(
      XCTUnwrap(imported.objects["object"]), on: out, graph: imported)
    XCTAssertEqual(out.contents, "A B C")
    XCTAssertEqual(try imported.encode(), wire)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_PRINTING_EXPORT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
    var bad = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])
    var nodes = try XCTUnwrap(bad["descriptions"] as? [[String: Any]])
    var props = try XCTUnwrap(nodes[0]["properties"] as? [String: Any])
    props["maPrintString"] = ["type": "nil"]
    nodes[0]["properties"] = props
    bad["descriptions"] = nodes
    XCTAssertThrowsError(try Graph.decode(JSONSerialization.data(withJSONObject: bad)))
    try root.propertyPut("maPrintStringSeparator", .undefined)
    XCTAssertThrowsError(try g.encode())
  }
  func testBoundsAndZeroArgumentSeparator() throws {
    let root = Description(id: "root", className: "MAContainer")
    let a = field("a")
    let b = field("b")
    let model = PrintingTrace()
    root.children = [a, b]
    model.values = ["a": .string("A"), "b": .string("B")]
    var count = 0
    try root.setPrintSeparator(PrintSeparatorBlock { count += 1 })
    let none = PrintStream()
    try root.print(model, on: none)
    XCTAssertEqual(none.contents, "AB")
    XCTAssertEqual(count, 1)
    try root.setPrintSeparator(nil)
    let alias = PrintStream()
    try alias.append("A")
    try alias.append(alias.contents)
    XCTAssertEqual(alias.contents, "AA")
    root.children = [a, a]
    let duplicate = PrintStream()
    try root.print(model, on: duplicate)
    XCTAssertEqual(duplicate.contents, "A A")
    let c = field("c")
    model.values["c"] = .string("C")
    root.children = [a, b, c]
    root.className = "MAPriorityContainer"
    a.properties["priority"] = .integer(3)
    b.properties["priority"] = .integer(1)
    c.properties["priority"] = .integer(2)
    let sorted = PrintStream()
    try root.print(model, on: sorted)
    XCTAssertEqual(sorted.contents, "B C A")
    root.className = "MAContainer"
    root.children = [a, b]
    a.properties.removeValue(forKey: "priority")
    b.properties.removeValue(forKey: "priority")
    var small = Limits()
    small.bytes = 4
    let bounded = PrintStream(limits: small)
    try bounded.append("pre")
    model.trace.removeAll()
    XCTAssertThrowsError(try root.print(model, on: bounded))
    XCTAssertEqual(bounded.contents, "preA")
    XCTAssertEqual(model.trace, ["read:a"])
    var utf8 = Limits()
    utf8.bytes = 3
    let unicode = PrintStream(limits: utf8)
    XCTAssertThrowsError(try unicode.append("🙂"))
    XCTAssertTrue(unicode.contents.isEmpty)
    var low = Limits()
    low.visits = 1
    let work = PrintStream(limits: low)
    try work.append("")
    XCTAssertThrowsError(try work.append(""))
    var items = Limits()
    items.items = 1
    model.trace.removeAll()
    XCTAssertThrowsError(try root.print(model, on: PrintStream(limits: items)))
    XCTAssertTrue(model.trace.isEmpty)
  }
}
