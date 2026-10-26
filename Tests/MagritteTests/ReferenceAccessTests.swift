import Foundation
import Magritte
import XCTest

final class ReferenceAccessTests: XCTestCase {
  func node(_ id: String, _ cls: String = "MAStringDescription") -> Description {
    Description(id: id, className: cls, key: id)
  }
  func renderer() -> DisplayBlock {
    DisplayBlock { value, d in
      guard case .string(let label) = try d.property("label"), case .string(let text) = value else {
        throw MagritteError("text")
      }
      return label + ":" + text
    }
  }
  func fixture() throws -> [String: Any] {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "reference-access-scenarios", withExtension: "json", subdirectory: "Fixtures"))
    return try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }
  func graph(_ owner: Description, _ reference: Description) -> Graph {
    let root = node("root", "MAContainer")
    root.children = [owner]
    let g = Graph(
      root: root.id, descriptions: [root.id: root, owner.id: owner, reference.id: reference])
    g.format = "magritte.graph/4"
    return g
  }
  func testSharedGetterCases() throws {
    for row in try XCTUnwrap(fixture()["display"] as? [[String: Any]]) {
      let owner = node("owner", try XCTUnwrap(row["className"] as? String))
      let reference = node("reference")
      let old = DisplayBlock { "old" }
      owner.reference = reference
      owner.properties["label"] = .string("Owner")
      reference.properties["label"] = .string("Reference")
      reference.display(old)
      let style = try XCTUnwrap(row["ownerDisplay"] as? String)
      switch style {
      case "asString": owner.display("asString")
      case "nil": owner.properties["displayBlockOrSymbol"] = .undefined
      case "block": owner.display(renderer())
      default: break
      }
      try visit(owner) { _ in }
      XCTAssertTrue(reference.displayBlock === old)
      let copy = try copyDescription(owner, newID: "copy")
      XCTAssertTrue(reference.displayBlock === old)
      XCTAssertTrue(copy.root.reference?.displayBlock === old)
      XCTAssertTrue(try owner.referenceDescription() === reference)
      if style == "block" {
        XCTAssertTrue(reference.displayBlock === owner.displayBlock)
      } else {
        XCTAssertNil(reference.displayBlock)
      }
      if row["result"] is NSNull {
        XCTAssertThrowsError(try writeString(.string("Ada"), using: reference))
      } else {
        XCTAssertEqual(try writeString(.string("Ada"), using: reference), row["result"] as? String)
      }
      XCTAssertTrue(try owner.referenceDescription() === reference)
      if style == "absent" { XCTAssertNil(reference.properties["displayBlockOrSymbol"]) }
    }
  }
  func testSharedUndefinedSetterCases() throws {
    for row in try XCTUnwrap(fixture()["undefined"] as? [[String: Any]]) {
      let owner = node("owner", try XCTUnwrap(row["className"] as? String))
      let reference = node("reference")
      owner.reference = reference
      reference.properties["undefined"] = .string("reference-before")
      owner.display("asString")
      reference.display("yourself")
      let value: Value =
        (row["value"] is NSNull) ? .undefined : .string(try XCTUnwrap(row["value"] as? String))
      if row["route"] as? String == "direct" {
        XCTAssertTrue(try owner.setUndefined(value) === owner)
      } else {
        try owner.writeSlot(strategy: "MASelectorAccessor", name: "undefined:", value: value)
      }
      XCTAssertEqual(try owner.property("undefined"), value)
      let expected: Value =
        (row["targetValue"] is NSNull)
        ? .undefined : .string(try XCTUnwrap(row["targetValue"] as? String))
      XCTAssertEqual(try reference.property("undefined"), expected)
      XCTAssertEqual(
        try reference.property("displayBlockOrSymbol"),
        .symbol(owner.isOption ? "asString" : "yourself"))
    }
  }
  func testSnapshotCopyAndSharedReferenceState() throws {
    let owner = node("owner", "MASingleOptionDescription")
    let reference = node("reference")
    owner.reference = reference
    owner.display("asString")
    reference.display("yourself")
    let g = graph(owner, reference)
    let wire = try g.encode()
    XCTAssertEqual(try reference.property("displayBlockOrSymbol"), .symbol("yourself"))
    let imported = try Graph.decode(wire)
    XCTAssertEqual(
      try imported.descriptions["reference"]?.property("displayBlockOrSymbol"), .symbol("yourself"))
    XCTAssertEqual(try imported.encode(), wire)
    if let path = ProcessInfo.processInfo.environment["MAGRITTE_REFERENCE_ACCESS_EXPORT"] {
      try wire.write(to: URL(fileURLWithPath: path))
    }
    let other = node("other", "MATokenDescription")
    other.reference = reference
    other.display(renderer())
    reference.properties["label"] = .string("Shared")
    _ = try other.referenceDescription()
    XCTAssertEqual(try writeString(.string("Ada"), using: reference), "Shared:Ada")
    _ = try owner.referenceDescription()
    XCTAssertNil(reference.displayBlock)
    XCTAssertNotNil(other.displayBlock)
    let old = renderer()
    reference.display(old)
    XCTAssertThrowsError(try g.encode())
    XCTAssertTrue(reference.displayBlock === old)
    owner.options = Options([.string("Ada")])
    XCTAssertTrue(try Magritte.validateValue(.string("Ada"), using: owner).isEmpty)
    XCTAssertTrue(reference.displayBlock === old)
    owner.properties["extensible"] = .boolean(true)
    XCTAssertTrue(try Magritte.validateValue(.string("Bob"), using: owner).isEmpty)
    XCTAssertNil(reference.displayBlock)
  }
  func testInterpreterTimingAndCascadeBounds() throws {
    for cls in [
      "MATokenDescription", "MAToManyRelationDescription", "MAToManyScalarRelationDescription",
    ] {
      let parent = node("parent", cls)
      let target = node("target")
      let second = DisplayBlock { "second" }
      parent.reference = target
      parent.display(
        DisplayBlock {
          parent.display(second)
          return "first"
        })
      XCTAssertEqual(
        try writeString(.array([.string("a"), .string("b")]), using: parent),
        cls == "MATokenDescription" ? "first second" : "first, second")
      target.display("yourself")
      XCTAssertEqual(try writeString(.array([]), using: parent), "")
      XCTAssertEqual(try target.property("displayBlockOrSymbol"), .symbol("yourself"))
    }
    let owner = node("owner", "MASingleOptionDescription")
    let reference = node("reference")
    owner.reference = reference
    owner.display("asString")
    owner.properties = ["sorted": .boolean(true), "required": .boolean(true)]
    owner.options = Options([.string("Ada")])
    reference.display("yourself")
    _ = try owner.allOptions()
    XCTAssertEqual(try reference.property("displayBlockOrSymbol"), .symbol("yourself"))
    let nested = node("nested", "MAMultipleOptionDescription")
    let leaf = node("leaf")
    owner.reference = nested
    nested.reference = leaf
    try owner.setUndefined(.string("missing"))
    XCTAssertEqual(try nested.property("undefined"), .string("missing"))
    XCTAssertEqual(try leaf.property("undefined"), .string("missing"))
    owner.reference = owner
    var low = Limits()
    low.depth = 2
    XCTAssertThrowsError(try owner.setUndefined(.string("partial"), limits: low))
    XCTAssertEqual(try owner.property("undefined"), .string("partial"))
    owner.reference = reference
    XCTAssertThrowsError(try owner.setUndefined(.boolean(true)))
    owner.reference = nil
    XCTAssertThrowsError(try owner.referenceDescription())
    XCTAssertThrowsError(try owner.setUndefined(.string("saved")))
    XCTAssertEqual(try owner.property("undefined"), .string("saved"))
  }
}
