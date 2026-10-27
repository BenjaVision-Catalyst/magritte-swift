import Foundation

public extension Description {
    var isRelation: Bool { descriptionIs(self, "MARelationDescription") }
    var isOption: Bool { descriptionIs(self, "MAOptionDescription") }
    var isReference: Bool { descriptionIs(self, "MAReferenceDescription") }
    var isMultiple: Bool {
      descriptionIs(self, "MAToManyRelationDescription") || descriptionIs(self, "MAMultipleOptionDescription")
    }
  func labelForOption(_ value: Value, limits: Limits = Limits(), graph: Graph? = nil) throws
    -> String
  {
    let budget = Budget(limits)
    try checkRuntimeValue(value,limits,&budget.work)
    func bounded(_ text: String) throws -> String {
      try require(
        text.utf8.count <= limits.bytes && text.utf8.count <= limits.visits - budget.work,
        "Option label output limit")
      budget.work += text.utf8.count; return text
        }
        if descriptionIs(self, "MABooleanDescription") {
      if case .boolean(let b) = value {
        guard case .string(let s) = try property(b ? "trueString" : "falseString") else {
          throw MagritteError("Expected Boolean label")
        }; return try bounded(s)
      }
      guard case .string(let s) = try property("undefined") else {
        throw MagritteError("Expected undefined text")
      }; return try bounded(s)
    }
        try require(isOption, "Option operation requires option description")
        for label in labels {
            try require(portableLabelKey(label.value), "Identity-sensitive option label key is not portable")
            if try sameLabelType(label.value, value) && equalRuntimeValues(label.value,value,limits,&budget.work) { return try bounded(label.label) }
        }
    return try bounded(displayStringFor(value, graph: graph, limits: limits))
  }
  func allOptions(limits: Limits = Limits(), graph: Graph? = nil) throws -> Options {
    if isOption, case .dynamic = options { return options }
    return try allOptionsWith(.undefined, limits: limits, graph: graph)
  }
  func allOptionsWith(_ current: Value, limits: Limits = Limits(), graph: Graph? = nil) throws
    -> Options
  {
    if descriptionIs(self, "MABooleanDescription") {
      try require(limits.visits >= 2 && limits.items >= 2, "Boolean option item/work limit");
      return [.boolean(false), .boolean(true)]
    }
    try require(isOption, "Option operation requires option description")
    if case .dynamic(let source) = options {
      if try flag("extensible") && !current.isNil && !source.includes(current, limits: limits) {
        throw MagritteError("Dynamic options do not implement copyWith:")
            }
            var items: [OptionItem] = []
      if try !isMultiple && !flag("required") {
        items.append(.value(try property("undefinedValue")))
      }
      // Inherited Object>>asArray wraps a copied provider. A singleton is not compared by sorting.
            items.append(.provider(source.copy()))
            _ = try flag("sorted")
            try require(items.count <= limits.items && limits.visits >= 1, "Options item/work limit")
            return .collection(items)
        }
        let budget = Budget(limits)
        var contains = false
        try checkRuntimeValue(current,limits,&budget.work)
        for option in try options.values(limits: limits) { if try equalRuntimeValues(option,current,limits,&budget.work) { contains = true } }
        var result = try options.values(limits: limits)
        if try flag("extensible") && !current.isNil && !contains { result.append(current) }
        if try flag("sorted") {
      func sortKey(_ value: Value) throws -> String {
        let text = try writeString(
          value, using: referenceDescription(), graph: graph, limits: limits)
        try require(
          text.utf8.allSatisfy { $0 < 128 },
          "Non-ASCII case-insensitive option sorting is not implemented")
        return text.lowercased()
      }
      result = try result.sorted { a, b in
        let left = try sortKey(a), right = try sortKey(b)
        try budget.tick(0);
        try require(left.utf8.count <= limits.visits - budget.work, "Option sorting work limit");
        budget.work += left.utf8.count
        try require(right.utf8.count <= limits.visits - budget.work, "Option sorting work limit");
        budget.work += right.utf8.count
        return left < right
      }
    }
    if try !isMultiple && !flag("required") { result.insert(try property("undefinedValue"), at: 0) }
    return Options(result)
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
func validationKindOf(_ v: Value, _ kind: String, _ graph: Graph?) throws -> Bool {
  if case .conflict(let c) = v { return c.kindOf(kind) }
  if case .reference = v {
    guard let graph else {
      throw MagritteError("Object reference validation requires a graph resolver")
    }
    return try graph.resolve(v).kindOf(kind)
    }
    let cls:String
    switch v {
  case .mutableCollection(let ref):
    let k = try ref.kind();
    cls =
      k == "array"
      ? "Array"
      : k == "ordered" ? "OrderedCollection" : k == "set" ? "Set" : k == "bag" ? "Bag" : "String"
  case .undefined: cls="UndefinedObject"
    case .boolean: cls="Boolean"
    case .integer: cls="Integer"
    case .float: cls="Float"
    case .string: cls="String"
    case .symbol: cls="Symbol"
    case .character: cls="Character"
    case .array: cls="Array"
    case .collection(let kind,_): cls=kind=="ordered" ? "OrderedCollection" : kind=="set" ? "Set" : "Bag"
  case .fraction: cls = "Fraction"
  case .classValue: cls = "Class"
  case .conflict: return false
  case .reference: return false
  }
  return ClassRegistry.shared.includesBehavior(cls,kind)

}
final class Budget {
    var work = 0
  var collections = Set<ObjectIdentifier>()
  let limits: Limits
    init(_ limits: Limits) { self.limits = limits }
    func tick(_ depth: Int) throws {
        work += 1; try require(work <= limits.visits && depth <= limits.depth, "Validation work/depth limit")
    }
}
public func validateValue(_ value:Value,using d:Description,graph:Graph?=nil,limits:Limits=Limits())throws->[ValidationError]{try validateValueDetailed(value,using:d,graph:graph,limits:limits).flatErrors(limits:limits)}
public func validate(_ model:Model,using d:Description,limits:Limits=Limits(),graph:Graph?=nil)throws->[ValidationError]{try validateDetailed(model,using:d,limits:limits,graph:graph).flatErrors(limits:limits)}

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
  case .mutableCollection(let ref):
    return try valueKey(ref.snapshot(), tick: tick, depth: depth + 1)
  case .fraction:
    let f = try fractionOf(value);
    return f.1 == 1 ? "2:" + String(f.0) : "12:" + String(f.0) + "/" + String(f.1)
  case .conflict: return "11:MACompositeConflict"
  case .undefined: return "0:"
  case .boolean(let b): return b ? "1:1" : "1:0"
  case .integer(let i): return "2:" + String(i)
    case .classValue(let name): try require(knownClass(name), "Unknown portable class"); return "10:" + wrap(try hex(name))
    case .symbol(let s): return "3:" + wrap(try hex(s))
    case .float(let n):
        try require(n.isFinite, "Non-finite float")
        if let i = Int64(exactly: n) { return "2:" + String(i) }
    if let f = try floatFraction(n) { return "12:" + String(f.0) + "/" + String(f.1) }
    return "9:" + (try floatBits(n))
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
    case .undefined, .boolean, .reference, .character, .symbol, .classValue: return true
    case .integer(let i): return i >= -1073741824 && i <= 1073741823
    default: return false
    }
}

func sameLabelType(_ a: Value, _ b: Value) -> Bool {
    switch (a,b) {
    case (.undefined,.undefined),(.boolean,.boolean),(.integer,.integer),(.reference,.reference),(.character,.character),(.symbol,.symbol),(.classValue,.classValue): return true
    default: return false
    }
}
