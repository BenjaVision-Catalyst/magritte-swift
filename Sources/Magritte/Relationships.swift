import Foundation

public extension Description {
    var isRelation: Bool { ["MAToOneRelationDescription", "MAToManyRelationDescription", "MAToManyScalarRelationDescription"].contains(className) }
    var isOption: Bool { ["MASingleOptionDescription", "MAMultipleOptionDescription"].contains(className) }
    var isReference: Bool { isRelation || isOption }
    var isMultiple: Bool { ["MAToManyRelationDescription", "MAToManyScalarRelationDescription", "MAMultipleOptionDescription"].contains(className) }
    func referenceDescription() throws -> Description {
        guard let r = reference else { throw MagritteError("Reference description is unavailable; retain it in the graph") }; return r
    }
    func labelForOption(_ value: Value, limits: Limits = Limits()) throws -> String {
        let budget = Budget(limits)
        let key = try valueKey(value, tick: budget.tick)
        try require(isOption, "Option operation requires option description")
        for label in labels {
            try require(portableLabelKey(label.value), "Identity-sensitive option label key is not portable")
            if try valueKey(label.value, tick: budget.tick) == key { return label.label }
        }
        return try renderOption(value, referenceDescription(), budget)
    }
    func allOptions(limits: Limits = Limits()) throws -> [Value] { try allOptionsWith(.undefined, limits: limits) }
    func allOptionsWith(_ current: Value, limits: Limits = Limits()) throws -> [Value] {
        let budget = Budget(limits)
        var contains = false
        let key = try valueKey(current, tick: budget.tick)
        for option in options { if try valueKey(option, tick: budget.tick) == key { contains = true } }
        try require(isOption, "Option operation requires option description")
        var result = options
        if try flag("extensible") && !current.isNil && !contains { result.append(current) }
        if try flag("sorted") {
            let ref = try referenceDescription()
            let ranked = try result.enumerated().map { i, v -> (Int, Value, String) in
                let text = try renderOption(v, ref, budget)
                try require(text.utf8.allSatisfy { $0 < 128 }, "Non-ASCII case-insensitive option sorting is not implemented")
                return (i, v, text.lowercased())
            }
            result = ranked.sorted { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 < $1.2 }.map { $0.1 }
        }
        if try !isMultiple && !flag("required") { result.insert(property("undefinedValue"), at: 0) }
        return result
    }
}
private func renderOption(_ value: Value, _ reference: Description, _ budget: Budget) throws -> String {
    if try valueKey(value, tick: budget.tick) == valueKey(reference.property("undefinedValue"), tick: budget.tick) {
        if case .string(let s) = reference.property("undefined") { return s }; return ""
    }
    switch value {
    case .string(let s), .character(let s): return s
    case .integer(let i): return String(i)
    case .boolean(let b): return b ? "true" : "false"
    default: throw MagritteError("Unlabelled complex option rendering is not portable")
    }
}
public extension Graph {
    func resolve(_ value: Value) throws -> Model {
        guard case .reference(let id) = value else { throw MagritteError("Expected object reference") }
        try require(objects[id] == nil || nativeObjects[id] == nil, "Duplicate portable/native object identity")
        if let m = objects[id] { return m }
        if let m = nativeObjects[id] { return m }
        throw MagritteError("Dangling object reference: \(id)")
    }
}
private func kindOf(_ v: Value, _ kind: String, _ graph: Graph?) throws -> Bool {
    if case .reference = v {
        guard let graph else { throw MagritteError("Object reference validation requires a graph resolver") }
        return try graph.resolve(v).kindOf(kind)
    }
    if kind == "Object" { return true }
    switch (kind, v) {
    case ("UndefinedObject", .undefined), ("String", .string), ("Character", .character), ("Boolean", .boolean), ("Number", .integer), ("Integer", .integer): return true
    case ("Collection", _): return v.isCollection
    case ("SequenceableCollection", .string), ("SequenceableCollection", .array), ("SequenceableCollection", .collection("ordered", _)), ("Array", .array): return true
    case ("Set", .collection("set", _)), ("Bag", .collection("bag", _)), ("OrderedCollection", .collection("ordered", _)): return true
    default: return false
    }
}
private final class Budget {
    var work = 0
    let limits: Limits
    init(_ limits: Limits) { self.limits = limits }
    func tick(_ depth: Int) throws {
        work += 1; try require(work <= limits.visits && depth <= limits.depth, "Validation work/depth limit")
    }
}
private func validateModel(_ d: Description, _ model: Model, _ graph: Graph?, _ budget: Budget, _ depth: Int) throws -> [ValidationError] {
    try budget.tick(depth); try supported(d)
    if try !d.flag("visible") || d.flag("readOnly") { return [] }
    if !d.isContainer { return try validateField(d, model.read(using: d), graph, budget, depth + 1) }
    try require(d.conditions.isEmpty, "Container local conditions are not implemented")
    var errors: [ValidationError] = []
    for c in try d.orderedChildren() {
        if c.isContainer && (model is AdaptiveModel || c.nativeRead != nil) {
            errors += try validateField(c, model.read(using: c), graph, budget, depth + 1)
        } else { errors += try validateModel(c, model, graph, budget, depth + 1) }
    }
    return errors
}
private func checkReferences(_ v: Value, _ graph: Graph?, _ budget: Budget, _ depth: Int) throws {
    try budget.tick(depth)
    switch v {
    case .reference:
        guard let graph else { throw MagritteError("Object references require a graph resolver") }; _ = try graph.resolve(v)
    case .array(let a), .collection(_, let a):
        try require(a.count <= budget.limits.visits - budget.work, "Collection work limit")
        for e in a { try checkReferences(e, graph, budget, depth + 1) }
    default: break
    }
}
private func validateField(_ d: Description, _ v: Value, _ graph: Graph?, _ budget: Budget, _ depth: Int) throws -> [ValidationError] {
    try budget.tick(depth); try supported(d)
    if try !d.flag("visible") || d.flag("readOnly") { return [] }
    try checkReferences(v, graph, budget, depth)
    var errors: [ValidationError] = []
    func error(_ code: String) { errors.append(ValidationError(descriptionID: d.id, code: code, message: "Value does not satisfy description")) }
    if try d.flag("required") && (v.isNil || (d.isMultiple && v.isCollection && v.collectionCount() == 0)) { error("MARequiredError") }
    if try valueKey(v, tick: budget.tick) == valueKey(d.property("undefinedValue"), tick: budget.tick) { return errors }
    if d.isContainer {
        guard let graph else { throw MagritteError("Container value validation requires a graph resolver") }
        let nested = try validateModel(d, graph.resolve(v), graph, budget, depth + 1)
        return errors + nested
    }
    var kind = true
    if d.isRelation {
        func check(_ e: Value) throws {
            try budget.tick(depth)
            var accepted = false
            for cls in d.classes { try budget.tick(depth); if try kindOf(e, cls, graph) { accepted = true } }
            if !accepted { error("MAKindError"); kind = false }
        }
        if d.isMultiple {
            if !v.isCollection { error("MAKindError"); kind = false }
            else {
                try require(v.collectionCount() <= budget.limits.visits - budget.work, "Collection work limit")
                for e in try v.elements() { try check(e) }
            }
        } else { try check(v) }
    } else if d.isOption {
        func check(_ e: Value) throws {
            var member = false
            for option in d.options { try budget.tick(depth); if try valueKey(e, tick: budget.tick) == valueKey(option, tick: budget.tick) { member = true; break } }
            if member { return }
            if try !d.flag("extensible") { error("MAKindError"); kind = false; return }
            let nested = try validateField(d.referenceDescription(), e, graph, budget, depth + 1)
            if !nested.isEmpty { kind = false }; errors += nested
        }
        if d.isMultiple {
            if !v.isCollection { error("MAKindError"); kind = false }
            else {
                try require(v.collectionCount() <= budget.limits.visits - budget.work, "Collection work limit")
                for e in try v.elements() { try check(e) }
            }
        } else { try check(v) }
    } else {
        kind = try kindOf(v, d.className == "MAStringDescription" ? "String" : d.className == "MANumberDescription" ? "Number" : "Boolean", graph)
        if !kind { error("MAKindError") }
    }
    if !kind { return errors }
    if d.className == "MANumberDescription", case .integer(let n) = v {
        var range = false
        if case .integer(let min) = d.property("min"), n < min { range = true }
        if case .integer(let max) = d.property("max"), n > max { range = true }
        if range { error("MARangeError") }
    }
    for c in d.conditions {
        try budget.tick(depth)
        if try !c.test(v) { errors.append(ValidationError(descriptionID: d.id, code: "MAConditionError", message: c.label)) }
    }
    return errors
}
public func validateValue(_ value: Value, using d: Description, graph: Graph? = nil, limits: Limits = Limits()) throws -> [ValidationError] {
    try validateField(d, value, graph, Budget(limits), 0)
}
public func validate(_ model: Model, using root: Description, limits: Limits = Limits(), graph: Graph? = nil) throws -> [ValidationError] {
    try visit(root, limits: limits, supported)
    return try validateModel(root, model, graph, Budget(limits), 0)
}

// Length-delimited semantic keys avoid quadratic unordered-collection matching.
// Reference identity and collection kind remain part of the key.
func valueKey(_ value: Value, tick: (Int) throws -> Void, depth: Int = 0) throws -> String {
    try tick(depth)
    func wrap(_ s: String) -> String { String(s.utf8.count) + ":" + s }
    func hex(_ s: String) throws -> String {
        for _ in s.utf8 { try tick(depth) }
        return s.utf8.map { String(format: "%02x", $0) }.joined()
    }
    switch value {
    case .undefined: return "0:"
    case .boolean(let b): return b ? "1:1" : "1:0"
    case .integer(let i): return "2:" + String(i)
    case .string(let s): return "3:" + wrap(try hex(s))
    case .reference(let id): return "5:" + wrap(try hex(id))
    case .character(let c): return "6:" + wrap(try hex(c))
    case .array(let a):
        return "4:" + (try a.map { wrap(try valueKey($0, tick: tick, depth: depth + 1)) }).joined()
    case .collection(let kind, let a):
        var keys = try a.map { try valueKey($0, tick: tick, depth: depth + 1) }
        if kind != "ordered" { keys.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) } }
        return "7:" + wrap(kind) + keys.map(wrap).joined()
    }
}

func portableLabelKey(_ value: Value) -> Bool {
    switch value {
    case .undefined, .boolean, .reference, .character: return true
    case .integer(let i): return i >= -1073741824 && i <= 1073741823
    default: return false
    }
}
