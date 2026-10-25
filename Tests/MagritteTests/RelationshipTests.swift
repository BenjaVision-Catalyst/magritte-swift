import Foundation
import XCTest
@testable import Magritte

final class RelationshipTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }
    func data(_ any: Any) throws -> Data { try JSONSerialization.data(withJSONObject: any, options: .sortedKeys) }
    func value(_ any: Any) throws -> Value { try decodeValue(data(any)) }
    func graph() throws -> Graph { try Graph.decode(fixture("relations-v2")) }
    func testGTValidationAndOptions() throws {
        let g = try graph()
        let reference = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("relations-reference")) as? [String: Any])
        let cases = try XCTUnwrap(reference["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 109)
        for c in cases {
            let id = try XCTUnwrap(c["description"] as? String)
            let d = try XCTUnwrap(g.descriptions[id]), input = try value(XCTUnwrap(c["input"]))
            let expected = try XCTUnwrap(c["errors"] as? [[String: String]])
            if expected.first?["code"] == "runtimeError" {
                XCTAssertThrowsError(try Magritte.validateValue(input, using: d, graph: g)); continue
            }
            let errors = try Magritte.validateValue(input, using: d, graph: g)
            XCTAssertEqual(errors.map { ["code": $0.code, "description": $0.descriptionID] }, expected, "GT disagreement: \(id) \(input)")
        }
        for c in try XCTUnwrap(reference["optionCases"] as? [[String: Any]]) {
            let d = try XCTUnwrap(g.descriptions[c["description"] as? String ?? ""])
            XCTAssertEqual(try Value.array(d.allOptions()), try value(XCTUnwrap(c["allOptions"])))
            XCTAssertEqual(try Value.array(d.allOptionsWith(value(XCTUnwrap(c["current"])))), try value(XCTUnwrap(c["withCurrent"])))
        }
        for c in try XCTUnwrap(reference["labels"] as? [[String: Any]]) {
            let d = try XCTUnwrap(g.descriptions[c["description"] as? String ?? ""])
            XCTAssertEqual(try d.labelForOption(value(XCTUnwrap(c["input"]))), c["label"] as? String)
        }
    }
    func testIdentityCyclesNestedContainersAndEdits() throws {
        let g = try graph(), ada = try XCTUnwrap(g.objects["ada"]), bob = try XCTUnwrap(g.objects["bob"])
        let spouse = try XCTUnwrap(g.descriptions["spouse"])
        XCTAssertTrue(try g.resolve(ada.read(using: spouse)) === bob)
        XCTAssertTrue(try g.resolve(bob.read(using: spouse)) === ada)
        XCTAssertTrue(spouse.reference === ada.description)
        XCTAssertTrue(try validate(ada, using: ada.description, graph: g).isEmpty)
        XCTAssertFalse(try validate(bob, using: bob.description, graph: g).isEmpty)
        var count = 0; try visit(ada.description) { _ in count += 1 }
        XCTAssertEqual(count, 9)
        let wire = try g.encode(); XCTAssertEqual(try Graph.decode(wire).encode(), wire)
        let nested = try XCTUnwrap(g.descriptions["nested"])
        let dictionary = DictionaryModel()
        XCTAssertEqual(try validate(dictionary, using: nested, graph: g).count, 1)
        dictionary.values["name"] = .string("Dictionary")
        XCTAssertTrue(try validate(dictionary, using: nested, graph: g).isEmpty)
        let nestedObject = AdaptiveModel(id: "nestedObject", description: nested, values: ["group": .reference("bob")])
        g.objects[nestedObject.id] = nestedObject
        XCTAssertEqual(try validate(nestedObject, using: nested, graph: g).count, 1)
        XCTAssertNotNil(try Graph.decode(g.encode()).objects["nestedObject"]?.values["group"])
        try bob.write(.string("Bob"), using: XCTUnwrap(g.descriptions["name"]))
        try bob.write(.array([.string("a")]), using: XCTUnwrap(g.descriptions["tags"]))
        XCTAssertTrue(try validate(bob, using: bob.description, graph: g).isEmpty)
        if let path = ProcessInfo.processInfo.environment["MAGRITTE_RELATIONS_EXPORT"] {
            try g.encode().write(to: URL(fileURLWithPath: path))
        }
    }
    func testUnorderedValuesAndBounds() throws {
        XCTAssertEqual(Value.collection(kind: "set", elements: [.integer(1), .integer(2)]), .collection(kind: "set", elements: [.integer(2), .integer(1)]))
        XCTAssertNotEqual(Value.collection(kind: "bag", elements: [.integer(1), .integer(1)]), .collection(kind: "bag", elements: [.integer(1), .integer(2)]))
        XCTAssertNotEqual(Value.array([.integer(1)]), .collection(kind: "ordered", elements: [.integer(1)]))
        XCTAssertThrowsError(try decodeValue(Data("{\"type\":\"character\",\"value\":\"\\uD800\"}".utf8)))
        let labelGraph = try graph(), labelled = try XCTUnwrap(labelGraph.descriptions["limitedNumber"])
        labelled.labels.append((.undefined, "void"))
        XCTAssertEqual(try labelled.labelForOption(.undefined), "void")
        let unicode = Value.collection(kind: "set", elements: [.string("e\u{301}\u{327}"), .string("e\u{327}\u{301}")])
        XCTAssertEqual(try decodeValue(encodeValue(unicode)), unicode)
        let g = try graph(), ada = try XCTUnwrap(g.objects["ada"]), friends = try XCTUnwrap(g.descriptions["friends"])
        var l = Limits(); l.visits = 3
        XCTAssertThrowsError(try Magritte.validateValue(ada.read(using: friends), using: friends, graph: g, limits: l))
        XCTAssertThrowsError(try XCTUnwrap(g.descriptions["collectionOptions"]).allOptions(limits: l))
        var textLimit = Limits(); textLimit.visits = 20
        XCTAssertThrowsError(try Magritte.validateValue(.string(String(repeating: "x", count: 100)), using: XCTUnwrap(g.descriptions["status"]), graph: g, limits: textLimit))
        let ext = try XCTUnwrap(g.descriptions["extensibleNumber"]), saved = ext.reference
        ext.reference = ext
        XCTAssertThrowsError(try Magritte.validateValue(.integer(2), using: ext, graph: g))
        ext.reference = saved
        let old = try Graph.decode(fixture("person-v1"))
        old.descriptions["name"]?.properties["default"] = .reference("ada")
        XCTAssertThrowsError(try old.encode())
    }
    func testSharedInvalidGraphsAndNativeBindingLifetime() throws {
        let cases = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("relations-invalid")) as? [[String: Any]])
        for c in cases { XCTAssertThrowsError(try Graph.decode(data(XCTUnwrap(c["graph"]))), c["name"] as? String ?? "case") }
        let g = try graph()
        final class Person { var name = "Native" }
        let native = NativeModel(Person(), ancestry: ["Person"])
        g.nativeObjects["local"] = native
        let d = Description(id: "nativeRelation", className: "MAToOneRelationDescription")
        d.reference = g.descriptions[g.root]; d.classes = ["Person"]
        XCTAssertTrue(try Magritte.validateValue(.reference("local"), using: d, graph: g).isEmpty)
        XCTAssertThrowsError(try g.encode())
        weak var releasedRoot: Description?
        var retained: Description?
        do {
            let owned = try graph()
            releasedRoot = owned.descriptions[owned.root]; retained = owned.descriptions["spouse"]
        }
        XCTAssertNil(releasedRoot)
        XCTAssertThrowsError(try XCTUnwrap(retained).referenceDescription())
    }
}
