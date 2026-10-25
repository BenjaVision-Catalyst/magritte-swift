import Foundation
import CoreFoundation

public indirect enum Value: Equatable {
    case undefined, boolean(Bool), integer(Int64), string(String), array([Value])
    case reference(String), character(String), collection(kind: String, elements: [Value])
    public var isNil: Bool { if case .undefined = self { return true }; return false }
    public static func == (lhs: Value, rhs: Value) -> Bool {
        switch (lhs, rhs) {
        case (.undefined, .undefined): return true
        case (.boolean(let a), .boolean(let b)): return a == b
        case (.integer(let a), .integer(let b)): return a == b
        case (.string(let a), .string(let b)): return a.utf8.elementsEqual(b.utf8)
        case (.array(let a), .array(let b)): return a == b
        case (.reference(let a), .reference(let b)), (.character(let a), .character(let b)): return a.utf8.elementsEqual(b.utf8)
        case (.collection, .collection):
            // Equatable is a local operation; interpreters use the bounded key below.
            return (try! valueKey(lhs, tick: { _ in })) == (try! valueKey(rhs, tick: { _ in }))
        default: return false
        }
    }
    public var isCollection: Bool {
        switch self { case .string, .array, .collection: return true; default: return false }
    }
    public func collectionCount() throws -> Int {
        switch self {
        case .array(let a), .collection(_, let a): return a.count
        case .string(let s): return s.unicodeScalars.count
        default: throw MagritteError("Value is not a collection")
        }
    }
    public func elements() throws -> [Value] {
        switch self {
        case .array(let a), .collection(_, let a): return a
        case .string(let s): return s.unicodeScalars.map { .character(String($0)) }
        default: throw MagritteError("Value is not a collection")
        }
    }
}
public struct MagritteError: Error, CustomStringConvertible {
    public let description: String
    public init(_ message: String) { description = message }
}
public struct Limits {
    public var bytes = 1_048_576, depth = 64, nodes = 10_000, items = 100_000, visits = 100_000
    public init() {}
}
public struct ValidationError: Equatable {
    public let descriptionID: String, code: String, message: String
}
public protocol Model: AnyObject {
    func kindOf(_ name: String) -> Bool
    func read(using description: Description) throws -> Value
    // Raw Magritte model access: validation and UI flags belong to interpreters.
    func write(_ value: Value, using description: Description) throws
}
public extension Model { func kindOf(_ name: String) -> Bool { name == "Object" } }
public struct Condition {
    public var label: String
    public var test: (Value) throws -> Bool
    public init(label: String, test: @escaping (Value) throws -> Bool) {
        self.label = label; self.test = test
    }
}
public final class Description: Model {
    public var id: String
    public var className: String
    public var key: String
    public var properties: [String: Value] = [:]
    public var children: [Description] = []
    public weak var reference: Description?
    public var classes: [String] = []
    public var options: [Value] = []
    public var labels: [(value: Value, label: String)] = []
    public var conditions: [Condition] = []
    public var nativeRead: ((AnyObject) throws -> Value)?
    public var nativeWrite: ((AnyObject, Value) throws -> Void)?
    public var defaultFunction: (() throws -> Value)?
    public init(id: String, className: String = "MAStringDescription", key: String = "") {
        self.id = id; self.className = className; self.key = key
    }
    public var isContainer: Bool { className == "MAContainer" || className == "MAPriorityContainer" }
    public func property(_ name: String) -> Value {
        if let v = properties[name] { return v }
        switch name {
        case "visible": return .boolean(true)
        case "required", "readOnly", "ordered", "distinct", "definitive", "sorted", "extensible": return .boolean(false)
        case "shouldCacheDefault": return .boolean(isRelation && isMultiple)
        case "priority": return .integer(0)
        case "undefined": return .string("")
        case "label": return .string(key)
        default: return .undefined
        }
    }
    public func defaultValue() throws -> Value {
        if let f = defaultFunction { return try f() }
        return property("default")
    }
    public func flag(_ name: String) throws -> Bool {
        guard case .boolean(let b) = property(name) else { throw MagritteError("Expected Boolean flag") }
        return b
    }
    public func priority() throws -> Int64 {
        guard case .integer(let i) = property("priority") else { throw MagritteError("Expected integer priority") }
        return i
    }
    public func orderedChildren() throws -> [Description] {
        if className != "MAPriorityContainer" { return children }
        // Stable ties are a documented port policy, not a claim about upstream ties.
        let ranked = try children.enumerated().map { ($0.offset, $0.element, try $0.element.priority()) }
        return ranked.sorted { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 < $1.2 }.map { $0.1 }
    }
    public func read(using description: Description) throws -> Value { property(description.key) }
    public func write(_ value: Value, using description: Description) throws { properties[description.key] = value }
}
public final class AdaptiveModel: Model {
    public func kindOf(_ name: String) -> Bool { ["Object", "MABasicObject", "MAAdaptiveModel"].contains(name) }
    public var id: String
    public var description: Description
    public var values: [String: Value]
    public init(id: String = "", description: Description, values: [String: Value] = [:]) {
        self.id = id; self.description = description; self.values = values
    }
    public func read(using description: Description) throws -> Value { values[description.id] ?? .undefined }
    public func write(_ value: Value, using description: Description) throws { values[description.id] = value }
}
public final class DictionaryModel: Model {
    public var values: [String: Value]
    public init(_ values: [String: Value] = [:]) { self.values = values }
    public func read(using description: Description) throws -> Value { try require(!description.isContainer, "Identity container access requires the model validator"); return values[description.key] ?? .undefined }
    public func write(_ value: Value, using description: Description) throws { try require(!description.isContainer, "Identity container write is unsupported"); values[description.key] = value }
}
public final class NativeModel: Model {
    public let object: AnyObject
    public let ancestry: [String]
    public init(_ object: AnyObject, ancestry: [String] = []) { self.object = object; self.ancestry = ancestry }
    public func kindOf(_ name: String) -> Bool { name == "Object" || ancestry.contains(name) }
    public func read(using description: Description) throws -> Value {
        guard let f = description.nativeRead else { throw MagritteError("Native read accessor unavailable") }
        return try f(object)
    }
    public func write(_ value: Value, using description: Description) throws {
        guard let f = description.nativeWrite else { throw MagritteError("Native write accessor unavailable") }
        try f(object, value)
    }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw MagritteError(message) }
}
func supported(_ d: Description) throws {
    try require(["MAContainer", "MAPriorityContainer", "MAStringDescription", "MANumberDescription", "MABooleanDescription", "MAToOneRelationDescription", "MAToManyRelationDescription", "MAToManyScalarRelationDescription", "MASingleOptionDescription", "MAMultipleOptionDescription"].contains(d.className), "Unsupported description class: \(d.className)")
    for (k, v) in d.properties {
        switch k {
        case "required", "readOnly", "visible", "ordered", "distinct", "definitive", "sorted", "extensible", "shouldCacheDefault":
            guard case .boolean = v else { throw MagritteError("Expected Boolean property: \(k)") }
        case "priority":
            guard case .integer = v else { throw MagritteError("Expected integer priority") }
        case "min", "max":
            try require(d.className == "MANumberDescription", "Range requires number description")
            if !v.isNil, case .integer = v {} else if !v.isNil { throw MagritteError("Unsupported numeric bound") }
        case "label", "comment", "group", "undefined":
            if !v.isNil, case .string = v {} else if !v.isNil { throw MagritteError("Expected text property: \(k)") }
        case "default", "undefinedValue": break
        default: try require(k.hasPrefix("metadata:"), "Unsupported semantic property: \(k)")
        }
    }
    try require(d.isContainer || d.children.isEmpty, "Scalar cannot contain children")
    if d.isReference { _ = try d.referenceDescription() }
    else { try require(d.reference == nil, "Reference slot requires a reference description") }
    try require(d.isRelation || d.classes.isEmpty, "Classes require a relation")
    try require(d.isOption || (d.options.isEmpty && d.labels.isEmpty), "Options require an option description")
    for k in ["ordered", "distinct", "definitive", "sorted", "extensible"] where d.properties[k] != nil {
        try require((k == "extensible" && d.isOption) || (k == "distinct" && d.className == "MAMultipleOptionDescription") || (k == "ordered" && d.isMultiple) || (k == "definitive" && d.isRelation && d.isMultiple) || (k == "sorted" && (d.isOption || (d.isRelation && d.isMultiple))), "Property does not apply to this description")
    }
}
public func visit(_ root: Description, limits: Limits = Limits(), _ visitor: (Description) throws -> Void) throws {
    var active = Set<ObjectIdentifier>(), composed = Set<ObjectIdentifier>(), seen = Set<ObjectIdentifier>(), work = 0
    func composition(_ d: Description, _ depth: Int) throws {
        work += 1
        try require(work <= limits.visits && depth <= limits.depth, "Description traversal limit")
        let id = ObjectIdentifier(d)
        try require(!active.contains(id), "Cyclic composition is unsupported")
        if composed.contains(id) { return }
        active.insert(id)
        for c in try d.orderedChildren() { try composition(c, depth + 1) }
        active.remove(id); composed.insert(id)
    }
    func walk(_ d: Description, _ depth: Int) throws {
        work += 1
        try require(work <= limits.visits && depth <= limits.depth, "Description traversal limit")
        let id = ObjectIdentifier(d)
        if !seen.insert(id).inserted { return }
        try require(seen.count <= limits.nodes, "Description node limit")
        try composition(d, 0); try visitor(d)
        for c in try d.orderedChildren() { try walk(c, depth + 1) }
        if d.isReference { try walk(d.referenceDescription(), depth + 1) }
    }
    try walk(root, 0)
}
public func descriptionModel() -> Description {
    let container = Description(id: "MADescription.bootstrap", className: "MAContainer")
    for key in ["label", "comment", "group", "required", "readOnly", "visible", "priority"] {
        let kind = ["required", "readOnly", "visible"].contains(key) ? "MABooleanDescription" : (key == "priority" ? "MANumberDescription" : "MAStringDescription")
        let d = Description(id: "MADescription." + key, className: kind, key: key)
        d.properties["label"] = .string(key)
        container.children.append(d)
    }
    return container
}

// Preflight before Foundation constructs an untrusted JSON graph. In particular,
// Foundation alone silently accepts duplicate keys; semantic imports must not.
private struct JSONGuard {
    var bytes: [UInt8], index = 0, items = 0
    let limits: Limits
    mutating func tick() throws { items += 1; try require(items <= limits.items, "JSON item limit") }
    mutating func whitespace() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func quoted() throws -> String {
        let start = index
        try require(index < bytes.count && bytes[index] == 34, "Expected JSON string")
        index += 1
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 92 { try require(index < bytes.count, "Incomplete escape"); index += 1 }
            else if byte == 34 {
                let v = try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: .fragmentsAllowed)
                guard let s = v as? String else { throw MagritteError("Expected string") }
                return s
            }
        }
        throw MagritteError("Unterminated string")
    }
    mutating func value(_ depth: Int) throws {
        try require(depth <= limits.depth, "JSON depth limit")
        try tick(); whitespace()
        try require(index < bytes.count, "Missing JSON value")
        let b = bytes[index]
        if b == 34 { _ = try quoted(); return }
        if b == 123 || b == 91 {
            index += 1; whitespace()
            let close: UInt8 = b == 123 ? 125 : 93
            var keys = Set<String>()
            if index < bytes.count && bytes[index] == close { index += 1; try tick(); return }
            while true {
                if b == 123 {
                    whitespace(); try tick()
                    let k = try quoted()
                    try require(keys.insert(k).inserted, "Duplicate JSON key")
                    whitespace(); try require(index < bytes.count && bytes[index] == 58, "Expected colon"); index += 1
                }
                try value(depth + 1); whitespace()
                try require(index < bytes.count, "Unterminated container")
                if bytes[index] == close { index += 1; try tick(); return }
                try require(bytes[index] == 44, "Expected comma"); index += 1; whitespace()
            }
        }
        let start = index
        while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
        try require(index > start, "Invalid JSON token")
        // Foundation subsequently checks the primitive token's exact grammar.
    }
    mutating func check() throws {
        try value(0); whitespace(); try require(index == bytes.count, "Trailing JSON input")
    }
}
private func parse(_ data: Data, _ limits: Limits) throws -> Any {
    try require(data.count <= limits.bytes, "Input byte limit")
    try require(String(data: data, encoding: .utf8) != nil, "Expected UTF-8")
    var guardJSON = JSONGuard(bytes: Array(data), limits: limits)
    try guardJSON.check()
    return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
}
private func dictionary(_ any: Any) throws -> [String: Any] {
    guard let d = any as? [String: Any] else { throw MagritteError("Expected object") }; return d
}
private func keys(_ d: [String: Any], _ names: Set<String>) throws {
    try require(Set(d.keys) == names, "Missing or unsupported members")
}
private func text(_ any: Any?) throws -> String {
    guard let s = any as? String else { throw MagritteError("Expected string") }; return s
}
private func identity(_ any: Any?) throws -> String {
    let s = try text(any); try require(!s.isEmpty && s.utf8.allSatisfy { $0 >= 33 && $0 <= 126 }, "Expected nonempty ASCII identity"); return s
}
private func list(_ any: Any?) throws -> [Any] {
    guard let a = any as? [Any] else { throw MagritteError("Expected array") }; return a
}
private func value(_ any: Any, _ limits: Limits, _ depth: Int = 0) throws -> Value {
    try require(depth <= limits.depth, "Value depth limit")
    let d = try dictionary(any), type = try text(d["type"])
    if type == "nil" { try keys(d, ["type"]); return .undefined }
    try keys(d, ["type", "value"])
    guard let v = d["value"] else { throw MagritteError("Missing value") }
    switch type {
    case "string": return .string(try text(v))
    case "reference": return .reference(try identity(v))
    case "character":
        let s = try text(v); try require(s.unicodeScalars.count == 1, "Character requires one Unicode scalar"); return .character(s)
    case "boolean":
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw MagritteError("Expected Boolean") }
        return .boolean(n.boolValue)
    case "integer":
        let s = try text(v)
        guard let i = Int64(s), String(i) == s else { throw MagritteError("Unsupported or noncanonical integer") }
        return .integer(i)
    case "array", "ordered", "set", "bag":
        let a = try list(v); try require(a.count <= limits.items, "Value item limit")
        let elements = try a.map { try value($0, limits, depth + 1) }
        if type == "set" {
            var work = 0, keys = Set<String>()
            for e in elements {
                let key = try valueKey(e) { depth in
                    work += 1; try require(work <= limits.visits && depth <= limits.depth, "Set comparison work/depth limit")
                }
                try require(keys.insert(key).inserted, "Duplicate set element")
            }
        }
        return type == "array" ? .array(elements) : .collection(kind: type, elements: elements)
    default: throw MagritteError("Unsupported value type: \(type)")
    }
}
private func wire(_ v: Value, _ limits: Limits, _ depth: Int = 0) throws -> [String: Any] {
    try require(depth <= limits.depth, "Value depth limit")
    switch v {
    case .undefined: return ["type": "nil"]
    case .boolean(let b): return ["type": "boolean", "value": b]
    case .integer(let i): return ["type": "integer", "value": String(i)]
    case .string(let s): return ["type": "string", "value": s]
    case .reference(let id): return ["type": "reference", "value": try identity(id)]
    case .character(let s):
        try require(s.unicodeScalars.count == 1, "Character requires one Unicode scalar")
        return ["type": "character", "value": s]
    case .array(let a):
        try require(a.count <= limits.items, "Value item limit")
        return ["type": "array", "value": try a.map { try wire($0, limits, depth + 1) }]
    case .collection(let kind, let a):
        try require(["ordered", "set", "bag"].contains(kind), "Unsupported collection kind")
        try require(a.count <= limits.items, "Value item limit")
        return ["type": kind, "value": try a.map { try wire($0, limits, depth + 1) }]
    }
}
public func decodeValue(_ data: Data, limits: Limits = Limits()) throws -> Value { try value(parse(data, limits), limits) }
public func encodeValue(_ v: Value, limits: Limits = Limits()) throws -> Data {
    let data = try JSONSerialization.data(withJSONObject: wire(v, limits), options: [.sortedKeys, .fragmentsAllowed])
    _ = try decodeValue(data, limits: limits); return data
}
public final class Graph {
    public var format = "magritte.graph/2"
    public var nativeObjects: [String: Model] = [:]
    public var root: String
    public var descriptions: [String: Description]
    public var objects: [String: AdaptiveModel]
    public init(root: String, descriptions: [String: Description] = [:], objects: [String: AdaptiveModel] = [:]) {
        self.root = root; self.descriptions = descriptions; self.objects = objects
    }
    public static func decode(_ data: Data, limits: Limits = Limits()) throws -> Graph {
        let j = try dictionary(parse(data, limits))
        try keys(j, ["format", "root", "descriptions", "objects"])
        let format = try text(j["format"])
        try require(["magritte.graph/1", "magritte.graph/2"].contains(format), "Unsupported format")
        let g = Graph(root: try identity(j["root"])); g.format = format
        let nodes = try list(j["descriptions"])
        try require(nodes.count <= limits.nodes, "Description node limit")
        for node in nodes {
            let n = try dictionary(node)
            let d = Description(id: try identity(n["id"]), className: try text(n["class"]))
            var names: Set<String> = d.isContainer ? ["id", "class", "properties", "children"] : ["id", "class", "properties", "accessor"]
            if d.isRelation { names.formUnion(["reference", "classes"]) }
            if d.isOption { names.formUnion(["reference", "options", "labels"]) }
            try keys(n, names)
            try require(format == "magritte.graph/2" || !d.isReference, "Reference descriptions require graph/2")
            guard let props = n["properties"] else { throw MagritteError("Missing properties") }
            for (k, v) in try dictionary(props) { _ = try identity(k); d.properties[k] = try value(v, limits) }
            if !d.isContainer {
                guard let accessor = n["accessor"] else { throw MagritteError("Missing accessor") }
                let a = try dictionary(accessor); try keys(a, ["class", "key"])
                try require(text(a["class"]) == "MADictionaryAccessor", "Unsupported accessor strategy")
                d.key = try identity(a["key"])
            }
            try require(g.descriptions[d.id] == nil, "Duplicate description identity")
            g.descriptions[d.id] = d
        }
        // Check owning edges before assigning them so rejected imports cannot leak ARC cycles.
        var composition: [String: [String]] = [:]
        for node in nodes {
            let n = try dictionary(node), id = try text(n["id"])
            guard g.descriptions[id]?.isContainer == true else { continue }
            for child in try list(n["children"]) {
                let key = try identity(child)
                try require(g.descriptions[key] != nil, "Dangling description identity")
                composition[id, default: []].append(key)
            }
        }
        var activeComposition = Set<String>(), completeComposition = Set<String>(), compositionWork = 0
        func checkComposition(_ id: String, _ depth: Int) throws {
            compositionWork += 1
            try require(compositionWork <= limits.visits && depth <= limits.depth, "Composition work/depth limit")
            try require(!activeComposition.contains(id), "Cyclic composition is unsupported")
            if completeComposition.contains(id) { return }
            activeComposition.insert(id)
            for child in composition[id] ?? [] { try checkComposition(child, depth + 1) }
            activeComposition.remove(id); completeComposition.insert(id)
        }
        for id in g.descriptions.keys where !completeComposition.contains(id) { try checkComposition(id, 0) }
        for node in nodes {
            let n = try dictionary(node)
            guard let d = g.descriptions[try text(n["id"])] else { throw MagritteError("Missing description") }
            if d.isReference {
                guard let ref = g.descriptions[try identity(n["reference"])] else { throw MagritteError("Dangling reference description") }
                d.reference = ref
            }
            if d.isRelation {
                let kinds: Set<String> = ["Object", "MABasicObject", "MAAdaptiveModel", "UndefinedObject", "String", "Boolean", "Number", "Integer", "Character", "Collection", "SequenceableCollection", "Array", "OrderedCollection", "Set", "Bag"]
                var unique = Set<String>()
                for c in try list(n["classes"]) {
                    let cls = try identity(c)
                    try require(kinds.contains(cls) && unique.insert(cls).inserted, "Unsupported or duplicate class constraint")
                    d.classes.append(cls)
                }
            }
            if d.isOption {
                for option in try list(n["options"]) { d.options.append(try value(option, limits)) }
                var labelKeys = Set<String>(), labelWork = 0
                for label in try list(n["labels"]) {
                    let entry = try dictionary(label); try keys(entry, ["value", "label"])
                    guard let v = entry["value"] else { throw MagritteError("Missing label value") }
                    let keyValue = try value(v, limits)
                    try require(portableLabelKey(keyValue), "Identity-sensitive option label key is not portable")
                    let key = try valueKey(keyValue) { depth in
                        labelWork += 1; try require(labelWork <= limits.visits && depth <= limits.depth, "Label comparison work limit")
                    }
                    try require(labelKeys.insert(key).inserted, "Duplicate label key")
                    d.labels.append((keyValue, try text(entry["label"])))
                }
            }
            try supported(d)
            if format == "magritte.graph/1" {
                let old: Set<String> = ["required", "readOnly", "visible", "priority", "min", "max", "label", "comment", "group", "undefined", "default", "undefinedValue"]
                for k in d.properties.keys { try require(old.contains(k) || k.hasPrefix("metadata:"), "Property requires graph/2") }
            }
            if !d.isContainer { continue }
            var unique = Set<String>()
            for child in try list(n["children"]) {
                let id = try identity(child)
                try require(unique.insert(id).inserted, "Duplicate container child")
                guard let c = g.descriptions[id] else { throw MagritteError("Dangling description identity") }
                try require(format == "magritte.graph/2" || !c.isContainer, "Nested containers require graph/2")
                d.children.append(c)
            }
        }
        guard let root = g.descriptions[g.root], root.isContainer else { throw MagritteError("Root must identify a container") }
        var checked = Set<ObjectIdentifier>(), graphWork = 0
        for d in g.descriptions.values where !checked.contains(ObjectIdentifier(d)) {
            try visit(d, limits: limits) { node in
                graphWork += 1; try require(graphWork <= limits.visits, "Graph traversal work limit")
                checked.insert(ObjectIdentifier(node))
            }
        }
        let objects = try list(j["objects"])
        try require(objects.count <= limits.nodes, "Object node limit")
        for object in objects {
            let o = try dictionary(object); try keys(o, ["id", "description", "values"])
            let id = try identity(o["id"]), desc = try identity(o["description"])
            guard let d = g.descriptions[desc], d.isContainer else { throw MagritteError("Object description must identify a container") }
            let m = AdaptiveModel(id: id, description: d)
            guard let values = o["values"] else { throw MagritteError("Missing object values") }
            let fields = Set(d.children.map(\.id))
            for (k, v) in try dictionary(values) {
                try require(fields.contains(k), "Value is not described by the object container")
                m.values[k] = try value(v, limits)
            }
            try require(g.objects[id] == nil, "Duplicate object identity"); g.objects[id] = m
        }
        func references(_ v: Value, _ depth: Int) throws {
            graphWork += 1; try require(depth <= limits.depth && graphWork <= limits.visits, "Value reference traversal limit")
            switch v {
            case .reference:
                try require(format == "magritte.graph/2", "Object references require graph/2"); _ = try g.resolve(v)
            case .character: try require(format == "magritte.graph/2", "Characters require graph/2")
            case .collection(_, let a):
                try require(format == "magritte.graph/2", "Typed collections require graph/2")
                for e in a { try references(e, depth + 1) }
            case .array(let a): for e in a { try references(e, depth + 1) }
            default: break
            }
        }
        for d in g.descriptions.values {
            for v in d.properties.values { try references(v, 0) }
            for v in d.options { try references(v, 0) }
            for label in d.labels { try references(label.value, 0) }
        }
        for o in g.objects.values { for v in o.values.values { try references(v, 0) } }
        return g
    }
    public func encode(limits: Limits = Limits()) throws -> Data {
        try require(descriptions.count <= limits.nodes && objects.count <= limits.nodes, "Graph node limit")
        try require(nativeObjects.isEmpty, "Local native object bindings are not portable")
        var nodes: [[String: Any]] = [], models: [[String: Any]] = []
        for id in descriptions.keys.sorted() {
            guard let d = descriptions[id] else { throw MagritteError("Missing description") }
            try require(id == d.id, "Inconsistent description identity"); try supported(d)
            try require(d.conditions.isEmpty && d.nativeRead == nil && d.nativeWrite == nil && d.defaultFunction == nil, "Local executable behavior is not portable")
            var props: [String: Any] = [:]
            for (k, v) in d.properties { props[k] = try wire(v, limits) }
            var n: [String: Any] = ["id": d.id, "class": d.className, "properties": props]
            if d.isContainer {
                for c in d.children { try require(descriptions[c.id] === c, "Unregistered child identity") }
                n["children"] = d.children.map(\.id)
            } else { n["accessor"] = ["class": "MADictionaryAccessor", "key": d.key] }
            if d.isReference {
                let ref = try d.referenceDescription()
                try require(descriptions[ref.id] === ref, "Unregistered reference description")
                n["reference"] = ref.id
            }
            if d.isRelation { n["classes"] = d.classes }
            if d.isOption {
                n["options"] = try d.options.map { try wire($0, limits) }
                n["labels"] = try d.labels.map { ["value": try wire($0.value, limits), "label": $0.label] as [String: Any] }
            }
            nodes.append(n)
        }
        for id in objects.keys.sorted() {
            guard let m = objects[id] else { throw MagritteError("Missing object") }
            try require(id == m.id && descriptions[m.description.id] === m.description, "Unregistered object description")
            var values: [String: Any] = [:]
            for (k, v) in m.values { values[k] = try wire(v, limits) }
            models.append(["id": id, "description": m.description.id, "values": values])
        }
        let data = try JSONSerialization.data(withJSONObject: ["format": format, "root": root, "descriptions": nodes, "objects": models], options: [.sortedKeys, .prettyPrinted])
        _ = try Graph.decode(data, limits: limits)
        return data
    }
}
