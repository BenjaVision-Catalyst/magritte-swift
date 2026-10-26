import XCTest
import Foundation
@testable import Magritte

final class ConformanceTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
    func json(_ data: Data) throws -> Any { try JSONSerialization.jsonObject(with: data) }
    func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: .sortedKeys) }
    func value(_ any: Any) throws -> Value { try decodeValue(data(any)) }
    func graph() throws -> Graph { try Graph.decode(fixture("person-v1")) }
    func testGTScalarReference() throws {
        let g = try graph(), r = try XCTUnwrap(json(fixture("reference")) as? [String: Any])
        let cases = try XCTUnwrap(r["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 10)
        for c in cases {
            let d = try XCTUnwrap(g.descriptions[c["description"] as? String ?? ""])
            let errors = try Magritte.validateValue(value(XCTUnwrap(c["input"])), using: d)
            XCTAssertEqual(errors.first?.code ?? "valid", c["result"] as? String)
        }
        let ada = try XCTUnwrap(g.objects["ada"]), active = try XCTUnwrap(g.descriptions["active"])
        XCTAssertTrue(ada.description === g.descriptions[g.root])
        XCTAssertTrue(try validate(ada, using: ada.description).isEmpty)
        XCTAssertEqual(try ada.read(using: active), try value(XCTUnwrap(r["rawMissing"])))
        XCTAssertEqual(try active.defaultValue(), try value(XCTUnwrap(r["mementoDefault"])))
    }
    func testOrderingAndFlags() throws {
        let g = try graph(), root = try XCTUnwrap(g.descriptions[g.root]), name = try XCTUnwrap(g.descriptions["name"])
        let r = try XCTUnwrap(json(fixture("reference")) as? [String: Any])
        XCTAssertEqual(try root.orderedChildren().map(\.id), r["containerOrder"] as? [String])
        root.className = "MAPriorityContainer"
        try root.setChildren(root.children)
        XCTAssertEqual(try root.orderedChildren().map(\.id), r["priorityOrder"] as? [String])
        name.properties["readOnly"] = .boolean(true)
        XCTAssertTrue(try Magritte.validateValue(.undefined, using: name).isEmpty)
        let ada = try XCTUnwrap(g.objects["ada"])
        try ada.write(.string("Raw"), using: name)
        XCTAssertEqual(try ada.read(using: name), .string("Raw"))
        name.properties.removeValue(forKey: "readOnly"); name.properties["visible"] = .boolean(false)
        XCTAssertTrue(try Magritte.validateValue(.undefined, using: name).isEmpty)
        name.properties.removeValue(forKey: "visible"); name.properties["undefinedValue"] = .string("unset")
        XCTAssertTrue(try Magritte.validateValue(.string("unset"), using: name).isEmpty)
    }
    func testSelfDescription() throws {
        let g = try graph(), name = try XCTUnwrap(g.descriptions["name"]), meta = descriptionModel()
        let r = try XCTUnwrap(json(fixture("reference")) as? [String: Any])
        XCTAssertEqual(try name.read(using: meta.children[0]), .string(try XCTUnwrap(r["selfLabel"] as? String)))
        XCTAssertEqual(try name.read(using: meta.children[3]), .boolean(try XCTUnwrap(r["selfRequired"] as? Bool)))
        try name.write(.boolean(false), using: meta.children[3])
        XCTAssertTrue(try Magritte.validateValue(.undefined, using: name).isEmpty)
        try name.write(.boolean(true), using: meta.children[3])
        XCTAssertTrue(try validate(name, using: meta).isEmpty)
    }
    func testRuntimeEvolutionAndRoundTrip() throws {
        let g = try graph(), changed = try Graph.decode(fixture("person-v2"))
        let ada = try XCTUnwrap(g.objects["ada"]), root = try XCTUnwrap(changed.descriptions[changed.root])
        ada.description = root
        let errors = try validate(ada, using: root)
        XCTAssertEqual(errors.map(\.descriptionID), ["age", "email"])
        XCTAssertEqual(errors.map(\.code), ["MARangeError", "MARequiredError"])
        try ada.write(.integer(21), using: XCTUnwrap(changed.descriptions["age"]))
        try ada.write(.string("ada@example.org"), using: XCTUnwrap(changed.descriptions["email"]))
        XCTAssertTrue(try validate(ada, using: root).isEmpty)
        let fresh = AdaptiveModel(description: root)
        XCTAssertEqual(try validate(fresh, using: root).count, 2)
        changed.objects["ada"] = ada
        let encoded = try changed.encode()
        XCTAssertEqual(try Graph.decode(encoded).encode(), encoded)
        if let path = ProcessInfo.processInfo.environment["MAGRITTE_EXPORT"] { try encoded.write(to: URL(fileURLWithPath: path)) }
        XCTAssertThrowsError(try g.encode())
    }
    func testGraphAndMetadataRoundTrips() throws {
        let g = try graph()
        let second = Description(id: "second", className: "MAContainer")
        second.children = [try XCTUnwrap(g.descriptions["name"])]
        g.descriptions["second"] = second
        let aliased = try Graph.decode(g.encode())
        XCTAssertTrue(aliased.descriptions["second"]?.children[0] === aliased.descriptions["name"])
        g.descriptions.removeValue(forKey: "second")
        let ada = try XCTUnwrap(g.objects["ada"])
        try ada.write(.undefined, using: XCTUnwrap(g.descriptions["active"]))
        XCTAssertNotNil(try Graph.decode(g.encode()).objects["ada"]?.values["active"])
        ada.values.removeValue(forKey: "active")
        XCTAssertNotEqual(Value.string("é"), Value.string("e\u{301}"))
        let before = try g.encode()
        XCTAssertEqual(try Graph.decode(before).encode(), before)
        let name = try XCTUnwrap(g.descriptions["name"])
        let metadata = Value.array([.string("text"), .integer(3)])
        name.properties["metadata:hint"] = metadata
        let copy = try Graph.decode(g.encode())
        XCTAssertEqual(copy.descriptions["name"]?.properties["metadata:hint"], metadata)
    }
    func testSharedValueBoundaries() throws {
        let values = try XCTUnwrap(json(fixture("values")) as? [String: [Any]])
        for v in try XCTUnwrap(values["roundtrips"]) {
            let decoded = try value(v)
            XCTAssertEqual(try decodeValue(encodeValue(decoded)), decoded)
        }
        for v in try XCTUnwrap(values["rejected"]) { XCTAssertThrowsError(try value(v)) }
    }
    func testSharedInvalidGraphs() throws {
        let cases = try XCTUnwrap(json(fixture("invalid-graphs")) as? [[String: Any]])
        for c in cases { XCTAssertThrowsError(try Graph.decode(data(XCTUnwrap(c["graph"]))), c["name"] as? String ?? "case") }
    }
    func testStrictJSONAndLimits() throws {
        for s in ["{\"type\":\"nil\",\"type\":\"nil\"}", "{\"type\":\"nil\",\"ty\\u0070e\":\"nil\"}", "{\"type\":\"nil\"} trailing", "{\"type\":\"nil\",}"] {
            XCTAssertThrowsError(try decodeValue(Data(s.utf8)))
        }
        let input = try fixture("person-v1")
        var l = Limits(); l.bytes = 10
        XCTAssertThrowsError(try Graph.decode(input, limits: l))
        l = Limits(); l.nodes = 1
        XCTAssertThrowsError(try Graph.decode(input, limits: l))
        l = Limits(); l.depth = 1
        XCTAssertThrowsError(try Graph.decode(input, limits: l))
        l = Limits(); l.items = 5
        XCTAssertThrowsError(try Graph.decode(input, limits: l))
        let g = try graph(), root = try XCTUnwrap(g.descriptions[g.root]), ada = try XCTUnwrap(g.objects["ada"])
        l = Limits(); l.visits = 1
        XCTAssertThrowsError(try validate(ada, using: root, limits: l))
        let cyclic = descriptionModel(); cyclic.children.append(cyclic)
        XCTAssertThrowsError(try visit(cyclic) { _ in })
        cyclic.children.removeLast()
    }
    func testLocalExecutableBehavior() throws {
        let g = try graph(), name = try XCTUnwrap(g.descriptions["name"])
        name.conditions = [Condition(label: "Must start with A") { v in
            guard case .string(let s) = v else { return false }; return s.hasPrefix("A")
        }]
        XCTAssertEqual(try Magritte.validateValue(.string("Bob"), using: name).first?.code, "MAConditionError")
        XCTAssertThrowsError(try g.encode())
        name.conditions = []; name.defaultFunction = { .string("Generated") }
        XCTAssertEqual(try name.defaultValue(), .string("Generated"))
        XCTAssertThrowsError(try g.encode())
    }
    func testNativeAndDictionaryAccessors() throws {
        final class Person { var name = "Before" }
        let person = Person(), adapter = NativeModel(person)
        let g = try graph(), d = try XCTUnwrap(g.descriptions["name"])
        d.nativeRead = { object in
            guard let p = object as? Person else { throw MagritteError("Wrong native object") }; return .string(p.name)
        }
        d.nativeWrite = { object, v in
            guard let p = object as? Person, case .string(let s) = v else { throw MagritteError("Wrong native value") }; p.name = s
        }
        try adapter.write(.string("After"), using: d)
        XCTAssertEqual(try adapter.read(using: d), .string("After")); XCTAssertEqual(person.name, "After")
        XCTAssertThrowsError(try g.encode())
        let dictionary = DictionaryModel()
        try dictionary.write(.string("Mapped"), using: d)
        XCTAssertEqual(try dictionary.read(using: d), .string("Mapped"))
    }
}
