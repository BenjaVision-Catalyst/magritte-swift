import Foundation
import CoreFoundation

public indirect enum Value: Equatable {
    case undefined, boolean(Bool), integer(Int64), string(String), array([Value])
  case fraction(numerator: Int64, denominator: Int64)
  case conflict(CompositeConflict)
  case reference(String), character(String), collection(kind: String, elements: [Value]), symbol(
    String), float(Double), classValue(String)
  public var isNil: Bool { if case .undefined = self { return true }; return false }
  public static func == (lhs: Value, rhs: Value) -> Bool {
        do { return try valueKey(lhs, tick: { _ in }) == valueKey(rhs, tick: { _ in }) }
        catch { return false }
    }
    public var isCollection: Bool {
        switch self { case .string, .symbol, .array, .collection: return true; default: return false }
    }
    public func collectionCount() throws -> Int {
        switch self {
        case .array(let a), .collection(_, let a): return a.count
        case .string(let s), .symbol(let s): return s.unicodeScalars.count
        default: throw MagritteError("Value is not a collection")
        }
    }
    public func elements() throws -> [Value] {
        switch self {
        case .array(let a), .collection(_, let a): return a
        case .string(let s), .symbol(let s): return s.unicodeScalars.map { .character(String($0)) }
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
  func binaryMessage(_ selector: String, argument: Value, graph: Graph?) throws -> Value
  func displayMessage(_ selector: String, argument: Description?) throws -> Value
  var usesStoredContainerValues: Bool { get }
  func kindOf(_ name: String) -> Bool
  func respondsToSelector(_ selector: String) throws -> Bool
  func hasVariable(_ name: String) throws -> Bool
  func readSlot(strategy: String, name: String) throws -> Value
    func writeSlot(strategy: String, name: String, value: Value) throws
    func read(using description: Description) throws -> Value
    // Raw Magritte model access: validation and UI flags belong to interpreters.
    func write(_ value: Value, using description: Description) throws
}
public extension Model {
  func binaryMessage(_ selector: String, argument: Value, graph: Graph? = nil) throws -> Value {
    if selector == "~=" {
      let result = try binaryMessage("=", argument: argument, graph: graph);
      guard case .boolean(let equal) = result else {
        throw MagritteError("Equality result does not understand not")
      }; return .boolean(!equal)
    }
    if selector == "=" {
      var equal = false;
      if case .reference = argument {
        guard let graph else { throw MagritteError("Binary argument requires graph resolver") };
        equal = try graph.resolve(argument) === self
      }; return .boolean(equal)
    }
    throw MagritteError("Unbound binary message: " + selector)
  }
  func displayMessage(_ selector: String, argument: Description? = nil) throws -> Value {
    try require(argument == nil, "Unbound display message with description argument");
    return try readSlot(strategy: "MASelectorAccessor", name: selector)
  }
  var usesStoredContainerValues: Bool { false }
  func kindOf(_ name: String) -> Bool { ClassRegistry.shared.includesBehavior("Object", name) }
  func respondsToSelector(_ selector: String) throws -> Bool { false }
  func hasVariable(_ name: String) throws -> Bool { false }
  func readSlot(strategy: String, name: String) throws -> Value { throw MagritteError("Unbound accessor read") }
    func writeSlot(strategy: String, name: String, value: Value) throws { throw MagritteError("Unbound accessor write") }
}
public struct Condition {
    public var label: String
    public var test: (Value) throws -> Bool
    public init(label: String, test: @escaping (Value) throws -> Bool) {
        self.label = label; self.test = test
    }
}
open class Description: Model {
    open func acceptMagritte(_ visitor: Visitor) throws { try dispatchMagritte(self, visitor) }
    public var id: String
    public var className: String
    public var key: String
  public var definingContext: DescriptionContext?
  public var displayBlock: DisplayBlock?
  open var isSortable: Bool {
    let registry = ClassRegistry.shared
    if registry.includesBehavior(className, "MAPasswordDescription") { return false }
    return registry.includesBehavior(className, "MAStringDescription")
      || registry.includesBehavior(className, "MAMagnitudeDescription")
  }
  public var properties: [String: Value] = [:]
  public var children: [Description] = []
    public weak var reference: Description?
    public var classes: [String] = []
    public var options: Options = []
    public var labels: [(value: Value, label: String)] = []
    public var conditions: [Condition] = []
    public var portableConditions: [PortableCondition] = []
    public var accessor: Accessor?
    public var accessorObject: AccessorObject?
  var defaultNullAccessor: Accessor?
  public var effectiveAccessor: Accessor {
    get throws {
      if let accessorObject { return try accessorObject.snapshot() };
      if let accessor { return accessor }
      if !isContainer && key.isEmpty {
        if defaultNullAccessor == nil {
          var a = Accessor(className: "MANullAccessor"), random = SystemRandomNumberGenerator()
          a.uuid = .array(
            (0..<16).map { _ in .integer(Int64(UInt8.random(in: 0...255, using: &random))) })
          defaultNullAccessor = a
        }
        return defaultNullAccessor!
      }
      return Accessor(
        className: isContainer ? "MAIdentityAccessor" : "MADictionaryAccessor",
        name: isContainer ? "" : key)
    }
  }
  public func materializeAccessor(limits: Limits = Limits()) throws { if let object = accessorObject { let value = try object.snapshot(limits: limits); accessor = isContainer && value.className == "MAIdentityAccessor" ? nil : value; accessorObject = nil } }
    public var nativeRead: ((AnyObject) throws -> Value)?
    public var nativeWrite: ((AnyObject, Value) throws -> Void)?
    public var defaultFunction: (() throws -> Value)?
    public init(id: String, className: String = "MAStringDescription", key: String = "") {
        self.id = id; self.className = className; self.key = key
    }
    public var isContainer: Bool { className == "MAContainer" || className == "MAPriorityContainer" }
  public func property(_ name: String, limits: Limits = Limits()) throws -> Value {
    if name == "displayBlockOrSymbol", displayBlock != nil {
      throw MagritteError(
        "Display block is local; inspect displayBlock rather than a Value snapshot")
    }
    if let v = properties[name] {
      if name == "label" || name == "name" { _ = try encodeValue(v, limits: limits) }; return v
    }
    switch name {
    case "kind":
      var kind = "Object"
      if className == "MAClassDescription" {
        kind = "Class"
      } else if className == "MASymbolDescription" {
        kind = "Symbol"
      } else if className == "MANumberDescription" {
        kind = "Number"
      } else if className == "MABooleanDescription" {
        kind = "Boolean"
      } else if className == "MATokenDescription" {
        kind = "Array"
      } else if isMultiple {
        kind = "Collection"
      } else if ClassRegistry.shared.includesBehavior(className, "MAStringDescription") {
        kind = "String"
      }
      return .classValue(kind)
    case "displayBlockOrSymbol": return .symbol("greaseString")
    case "stringReader": return .classValue("MAStringReader")
    case "stringWriter": return .classValue("MAStringWriter")
        case "validator": return .classValue("MAValidatorVisitor")
        case "separators": return .string(" ,;\r\n\t")
        case "thousandsSeparator": return .character(",")
        case "lineCount": return .integer(3)
        case "trueString": return .string("true")
        case "falseString": return .string("false")
        case "trueStrings": return .array(["true","t","yes","y","1","on"].map(Value.string))
        case "falseStrings": return .array(["false","f","no","n","0","off"].map(Value.string))
        case "visible": return .boolean(true)
        case "required", "readOnly", "ordered", "distinct", "definitive", "sorted", "extensible": return .boolean(false)
        case "shouldCacheDefault": return .boolean(isRelation && isMultiple)
    case "descriptionBuilders": return .array([])
    case "priority": return .integer(0)
    case "undefined": return .string("")
    case "label":
      let result = Value.string(try defaultLabel(limits: limits));
      try checkLocalValue(result, limits: limits); return result
    case "name": return try boundedAccessor(limits).accessorName(limits: limits)
    default: return .undefined
        }
    }
  private func boundedAccessor(_ limits: Limits) throws -> Accessor {
    if let accessorObject { return try accessorObject.snapshot(limits: limits) }
    return try effectiveAccessor
  }
  public func defaultLabel(limits: Limits = Limits()) throws -> String {
    try boundedAccessor(limits).defaultLabel(for: self, limits: limits)
  }
  public func hasLabel(limits: Limits = Limits()) throws -> Bool {
    let label = try property("label", limits: limits)
    if label.isNil { return false }
    guard case .string(let text) = label else { throw MagritteError("Expected label text") }
    return !text.isEmpty
  }
  public func defaultValue() throws -> Value {
        if let f = defaultFunction { return try f() }
    return try property(isContainer ? "undefinedValue" : "default")
  }
    public func flag(_ name: String) throws -> Bool {
    guard case .boolean(let b) = try property(name) else {
      throw MagritteError("Expected Boolean flag")
    }
    return b
    }
    public func priority() throws -> Int64 {
    guard case .integer(let i) = try property("priority") else {
      throw MagritteError("Expected integer priority")
    }
    return i
    }
    public func orderedChildren() throws -> [Description] {
        if className != "MAPriorityContainer" { return children }
        // Stable ties are a documented port policy, not a claim about upstream ties.
    let ranked = try children.enumerated().map {
      ($0.offset, $0.element, try $0.element.priorityValue())
    }
    return try ranked.sorted {
      let c = try compareNumbers($0.2, $1.2); return c == 0 ? $0.0 < $1.0 : c < 0
    }.map { $0.1 }
  }
  public func read(using description: Description) throws -> Value {
    if description.accessor != nil || description.accessorObject != nil {
      return try description.effectiveAccessor.read(self)
    }; return try property(description.key)
  }
  public func write(_ value: Value, using description: Description) throws { if description.accessor != nil || description.accessorObject != nil { try description.effectiveAccessor.write(value, to: self) } else { properties[description.key] = value } }
}
public final class AdaptiveModel: Model {
    public var usesStoredContainerValues: Bool { true }
    public func kindOf(_ name: String) -> Bool { ClassRegistry.shared.includesBehavior("MAAdaptiveModel", name) }
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
    public weak var resolver: Graph?
    public var values: [String: Value]
    public init(_ values: [String: Value] = [:]) { self.values = values }
    public func read(using description: Description) throws -> Value { try description.effectiveAccessor.read(self, graph: resolver) }
    public func write(_ value: Value, using description: Description) throws { try description.effectiveAccessor.write(value, to: self, graph: resolver) }
}
public final class NativeModel: Model {
  public var binaryReaders: [String: (AnyObject, Value, Graph?) throws -> Value] = [:]
  public func binaryMessage(_ selector: String, argument: Value, graph: Graph? = nil) throws
    -> Value
  {
    if let callback = binaryReaders[selector] { return try callback(object, argument, graph) }
    if selector == "~=" {
      let result = try binaryMessage("=", argument: argument, graph: graph);
      guard case .boolean(let equal) = result else {
        throw MagritteError("Equality result does not understand not")
      }; return .boolean(!equal)
    }
    if selector == "=" {
      var equal = false;
      if case .reference = argument {
        guard let graph else { throw MagritteError("Binary argument requires graph resolver") };
        equal = (try graph.resolve(argument) as? NativeModel)?.object === object
      }; return .boolean(equal)
    }
    throw MagritteError("Unbound binary message: " + selector)
  }
  public var displayReaders: [String: (AnyObject, Description?) throws -> Value] = [:]
  public func displayMessage(_ selector: String, argument: Description? = nil) throws -> Value {
    if let f = displayReaders[selector] { return try f(object, argument) }
    try require(argument == nil, "Unbound display message with description argument")
    return try readSlot(strategy: "MASelectorAccessor", name: selector)
  }
  public weak var resolver: Graph?
  // Explicit host bindings, keyed by strategy + ":" + selector/variable/property name.
  public var readers: [String: (AnyObject) throws -> Value] = [:]
  public var writers: [String: (AnyObject, Value) throws -> Void] = [:]
  public let object: AnyObject
    public let ancestry: [String]
    public init(_ object: AnyObject, ancestry: [String] = []) { self.object = object; self.ancestry = ancestry }
    public convenience init(registered object: AnyObject) throws {
        guard let name=ClassRegistry.shared.classForNativeType(type(of: object)) else {throw MagritteError("Native type is not registered")}
        self.init(object,ancestry:[name])
    }
    public func kindOf(_ name: String) -> Bool {
        let registry=ClassRegistry.shared,registered=ancestry.contains{registry.find($0) != nil}
        return (!registered && registry.includesBehavior("Object",name)) || ancestry.contains{ $0 == name || registry.includesBehavior($0,name) }
    }
    public func read(using description: Description) throws -> Value {
        if let f = description.nativeRead { return try f(object) }
        return try description.effectiveAccessor.read(self, graph: resolver)
    }
    public func write(_ value: Value, using description: Description) throws {
        if let f = description.nativeWrite { try f(object, value) }
        else { try description.effectiveAccessor.write(value, to: self, graph: resolver) }
    }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw MagritteError(message) }
}
func supported(_ d: Description) throws {
    try require(["MAContainer", "MAPriorityContainer", "MAStringDescription", "MASymbolDescription", "MAMemoDescription", "MAPasswordDescription", "MATokenDescription", "MANumberDescription", "MABooleanDescription", "MAToOneRelationDescription", "MAToManyRelationDescription", "MAToManyScalarRelationDescription", "MASingleOptionDescription", "MAMultipleOptionDescription", "MAClassDescription"].contains(d.className), "Unsupported description class: \(d.className)")
    for (k, v) in d.properties {
        switch k {
    case "canExpand", "required", "readOnly", "visible", "ordered", "distinct", "definitive",
      "sorted", "extensible", "shouldCacheDefault":
      guard case .boolean = v else { throw MagritteError("Expected Boolean property: \(k)") }
    case "separators", "trueString", "falseString":
      try require(
        (k == "separators" && d.className == "MATokenDescription")
          || (k != "separators" && d.className == "MABooleanDescription"),
        "Text setting does not apply")
      guard case .string = v else { throw MagritteError("Expected text setting") }
        case "thousandsSeparator":
            try require(d.className == "MANumberDescription", "Separator requires number")
            guard case .character(let c) = v, c.unicodeScalars.count == 1 else { throw MagritteError("Expected separator character") }
        case "lineCount":
            try require(d.className == "MAMemoDescription", "Line count requires memo")
            guard case .integer = v else { throw MagritteError("Expected memo line count") }
    case "displayBlockOrSymbol":
      switch v {
      case .undefined, .symbol: break;
      default:
        throw MagritteError("Display must be Symbol or nil; use displayBlock for local callbacks")
      }
    case "priority":
      try require(isNumber(v), "Expected numeric priority")
    case "min", "max":
      try require(d.className == "MANumberDescription", "Range requires number description")
      try require(v.isNil || isNumber(v), "Unsupported numeric bound")
      if case .float(let n) = v { try require(n.isFinite, "Non-finite numeric bound") }
        case "label", "comment", "group", "undefined":
            if !v.isNil, case .string = v {} else if !v.isNil { throw MagritteError("Expected text property: \(k)") }
        case "stringReader", "stringWriter", "validator":
            let expected = k == "stringReader" ? "MAStringReader" : k == "stringWriter" ? "MAStringWriter" : "MAValidatorVisitor"
            try require(v == .classValue(expected), "Unsupported interpreter class override")
    case "descriptionBuilder":
      if !v.isNil {
        guard case .classValue = v else { throw MagritteError("Builder must be Class or nil") }
      }
    case "descriptionBuilders":
      guard d.isContainer, case .array(let entries) = v else {
        throw MagritteError("Builders require container Array")
      };
      for e in entries {
        guard case .classValue = e else { throw MagritteError("Builder entry must be Class") }
      }
    case "kind":
      if !v.isNil {
        guard case .classValue(let name) = v, knownClass(name) else {
          throw MagritteError("Description kind must be Class or nil")
        }
      }
    case "name":
      switch v { case .undefined, .string, .symbol: break; default: throw MagritteError("Expected description name") }
        case "default", "undefinedValue": break
        default: try require(k.hasPrefix("metadata:"), "Unsupported semantic property: \(k)")
        }
    }
    try require(!d.isContainer || d.portableConditions.isEmpty, "Portable container conditions require a model message protocol")
    try require(d.isContainer || d.children.isEmpty, "Scalar cannot contain children")
  if d.isReference {
    _ = try referenceTarget(d)
  } else {
    try require(d.reference == nil, "Reference slot requires a reference description")
  }
  try require(d.isRelation || d.classes.isEmpty, "Classes require a relation")
    if !d.isOption {
        guard case .collection(let options) = d.options, options.isEmpty, d.labels.isEmpty else {
            throw MagritteError("Options require an option description")
        }
    }
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
    if d.isReference { try walk(referenceTarget(d), depth + 1) }
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
func parse(_ data: Data, _ limits: Limits) throws -> Any {
    try require(data.count <= limits.bytes, "Input byte limit")
    try require(String(data: data, encoding: .utf8) != nil, "Expected UTF-8")
    var guardJSON = JSONGuard(bytes: Array(data), limits: limits)
    try guardJSON.check()
    return try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
}
func dictionary(_ any: Any) throws -> [String: Any] {
    guard let d = any as? [String: Any] else { throw MagritteError("Expected object") }; return d
}
func keys(_ d: [String: Any], _ names: Set<String>) throws {
    try require(Set(d.keys) == names, "Missing or unsupported members")
}
func text(_ any: Any?) throws -> String {
    guard let s = any as? String else { throw MagritteError("Expected string") }; return s
}
func identity(_ any: Any?) throws -> String {
    let s = try text(any); try require(!s.isEmpty && s.utf8.allSatisfy { $0 >= 33 && $0 <= 126 }, "Expected nonempty ASCII identity"); return s
}
func list(_ any: Any?) throws -> [Any] {
    guard let a = any as? [Any] else { throw MagritteError("Expected array") }; return a
}
func value(_ any: Any, _ limits: Limits, _ depth: Int = 0) throws -> Value {
    try require(depth <= limits.depth, "Value depth limit")
    let d = try dictionary(any), type = try text(d["type"])
    if type == "nil" { try keys(d, ["type"]); return .undefined }
    try keys(d, ["type", "value"])
    guard let v = d["value"] else { throw MagritteError("Missing value") }
    switch type {
  case "fraction":
    let f = try dictionary(v); try keys(f, ["numerator", "denominator"]);
    guard let n = Int64(try text(f["numerator"])), let d = Int64(try text(f["denominator"])),
      String(n) == (f["numerator"] as? String), String(d) == (f["denominator"] as? String)
    else { throw MagritteError("Noncanonical fraction") }; return try Value.rational(n, d)
  case "string": return .string(try text(v))
  case "class":
    let name = try identity(v); try require(knownClass(name), "Unknown portable class");
    return .classValue(name)
  case "symbol": return .symbol(try text(v))
    case "float": return .float(try floatFromBits(text(v)))
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
func wire(_ v: Value, _ limits: Limits, _ depth: Int = 0) throws -> [String: Any] {
    try require(depth <= limits.depth, "Value depth limit")
    switch v {
    case .undefined: return ["type": "nil"]
    case .boolean(let b): return ["type": "boolean", "value": b]
    case .integer(let i): return ["type": "integer", "value": String(i)]
    case .string(let s): return ["type": "string", "value": s]
    case .symbol(let s): return ["type": "symbol", "value": s]
  case .fraction:
    let f = try fractionOf(v);
    return ["type": "fraction", "value": ["numerator": String(f.0), "denominator": String(f.1)]]
  case .conflict:
    throw MagritteError("Composite conflicts are local objects and cannot be exported")
  case .classValue(let name):
    try require(knownClass(name), "Unknown portable class");
    return ["type": "class", "value": name]
  case .float(let n): return ["type": "float", "value": try floatBits(n)]
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
    public var format = "magritte.graph/3"
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
        try require(["magritte.graph/1", "magritte.graph/2", "magritte.graph/3", "magritte.graph/4"].contains(format), "Unsupported format")
        if format != "magritte.graph/4" {
            func legacy(_ node: Any) throws {
                if let object = node as? [String: Any] {
          try require(
            !["class", "fraction"].contains((object["type"] as? String) ?? "")
              && !["MADelegatorAccessor", "MACompositeAccessor"].contains(
                (object["class"] as? String) ?? ""),
            "Class values and delegators require graph/4")
          for value in object.values { try legacy(value) }
        } else if let array = node as? [Any] {
          for value in array { try legacy(value) }
        }
      }; try legacy(j)
        }
        let g = Graph(root: try identity(j["root"])); g.format = format
        let nodes = try list(j["descriptions"])
        try require(nodes.count <= limits.nodes, "Description node limit")
        for node in nodes {
            let n = try dictionary(node)
            let d = Description(id: try identity(n["id"]), className: try text(n["class"]))
            var names: Set<String> = d.isContainer ? ["id", "class", "properties", "children"] : ["id", "class", "properties", "accessor"]
            if d.isRelation { names.formUnion(["reference", "classes"]) }
            if d.isOption { names.formUnion(["reference", "options", "labels"]) }
            if d.className == "MATokenDescription" { names.insert("reference") }
            if format >= "magritte.graph/3" { names.insert("conditions") }
      if let raw = n["definingContext"] {
        try require(format == "magritte.graph/4", "Defining context requires graph/4");
        names.insert("definingContext"); let c = try dictionary(raw);
        try keys(c, ["modelClass", "methodSelector"]);
        let cls = try value(c["modelClass"] as Any, limits),
          selector = try value(c["methodSelector"] as Any, limits)
        ; let context = DescriptionContext();
        if !cls.isNil {
          guard case .classValue(let name) = cls else {
            throw MagritteError("Context modelClass must be Class or nil")
          }; context.modelClass = name
        };
        if !selector.isNil {
          guard case .symbol(let name) = selector else {
            throw MagritteError("Context selector must be Symbol or nil")
          }; context.methodSelector = name
        }; d.definingContext = context
      }
      try keys(n, names)
      try require(format == "magritte.graph/4" || d.className != "MAClassDescription", "Class descriptions require graph/4")
            try require(format != "magritte.graph/1" || !d.isReference, "Reference descriptions require graph/2")
            guard let props = n["properties"] else { throw MagritteError("Missing properties") }
            for (k, v) in try dictionary(props) { _ = try identity(k); d.properties[k] = try value(v, limits) }
            if !d.isContainer {
                guard let accessor = n["accessor"] else { throw MagritteError("Missing accessor") }
                let a = try accessorValue(accessor, limits)
                try require(format >= "magritte.graph/3" || a.className == "MADictionaryAccessor", "Accessor requires graph/3")
                if a.className == "MADictionaryAccessor" { d.key = a.name } else { d.accessor = a }
            }
            if format >= "magritte.graph/3" {
                for c in try list(n["conditions"]) {
                    let entry = try dictionary(c); try keys(entry, ["label", "predicate"])
                    guard let p = entry["predicate"] else { throw MagritteError("Missing predicate") }
                    d.portableConditions.append(PortableCondition(label: try text(entry["label"]), predicate: try predicateValue(p, limits)))
                }
            } else {
                try require(!["MATokenDescription", "MASymbolDescription", "MAMemoDescription", "MAPasswordDescription"].contains(d.className), "Description requires graph/3")
        for k in d.properties.keys {
          try require(
            ![
              "separators", "thousandsSeparator", "lineCount", "trueString", "falseString",
              "trueStrings", "falseStrings", "displayBlockOrSymbol",
            ].contains(k), "Property requires graph/3")
        }
      }
      try require(g.descriptions[d.id] == nil, "Duplicate description identity")
      g.descriptions[d.id] = d
    }
    // Check owning edges before assigning them so rejected imports cannot leak ARC cycles.
        var composition: [String: [String]] = [:]
        var portableWork = 0
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

                var unique = Set<String>()
                for c in try list(n["classes"]) {
                    let cls = try identity(c)
                    try require((format >= "magritte.graph/3" || (cls != "Symbol" && cls != "Float" && (!cls.hasPrefix("MA") || cls == "MABasicObject" || cls == "MAAdaptiveModel"))) && knownClass(cls) && unique.insert(cls).inserted, "Unsupported or duplicate class constraint")
                    d.classes.append(cls)
                }
            }
            if d.isOption {
                d.options = Options(try list(n["options"]).map { try value($0, limits) })
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
            try supported(d); try checkPortableDescription(d, limits: limits, work: &portableWork)
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
                try require(format != "magritte.graph/1" || !c.isContainer, "Nested containers require graph/2")
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
                try require(format != "magritte.graph/1", "Object references require graph/2"); _ = try g.resolve(v)
            case .classValue: try require(format == "magritte.graph/4", "Class values require graph/4")
            case .symbol, .float: try require(format >= "magritte.graph/3", "Symbol/Float requires graph/3")
            case .character: try require(format != "magritte.graph/1", "Characters require graph/2")
            case .collection(_, let a):
                try require(format != "magritte.graph/1", "Typed collections require graph/2")
                for e in a { try references(e, depth + 1) }
            case .array(let a): for e in a { try references(e, depth + 1) }
            default: break
            }
        }
        for d in g.descriptions.values {
            for v in d.properties.values { try references(v, 0) }
            for v in try d.options.values(limits: limits) { try references(v, 0) }
            for label in d.labels { try references(label.value, 0) }
        }
        for o in g.objects.values { for v in o.values.values { try references(v, 0) } }
        return g
    }
    public func encode(limits: Limits = Limits()) throws -> Data {
        try require(descriptions.count <= limits.nodes && objects.count <= limits.nodes, "Graph node limit")
        try require(nativeObjects.isEmpty, "Local native object bindings are not portable")
        var nodes: [[String: Any]] = [], models: [[String: Any]] = []
        var portableWork = 0
        for id in descriptions.keys.sorted() {
            guard let d = descriptions[id] else { throw MagritteError("Missing description") }
            try require(id == d.id, "Inconsistent description identity"); try supported(d); try checkPortableDescription(d, limits: limits, work: &portableWork)
            try require(!d.options.isDynamic, "Local dynamic option providers are not portable; replace with explicit static options before export")
            try require(d.accessorObject == nil, "Live accessor identity is local; materialize an explicit snapshot before export")
      try require(
        d.conditions.isEmpty && d.nativeRead == nil && d.nativeWrite == nil
          && d.defaultFunction == nil && d.displayBlock == nil,
        "Local executable behavior is not portable")
      var props: [String: Any] = [:]
      for (k, v) in d.properties { props[k] = try wire(v, limits) }
      var n: [String: Any] = ["id": d.id, "class": d.className, "properties": props]
      if let c = d.definingContext {
        try require(format == "magritte.graph/4", "Defining context requires graph/4");
        n["definingContext"] = [
          "modelClass": try wire(c.modelClass.map(Value.classValue) ?? .undefined, limits),
          "methodSelector": try wire(c.methodSelector.map(Value.symbol) ?? .undefined, limits),
        ]
      }
      if format >= "magritte.graph/3" {
        n["conditions"] = try d.portableConditions.map { ["label": $0.label, "predicate": try predicateWire($0.predicate, limits)] as [String: Any] }
            } else { try require(d.portableConditions.isEmpty, "Conditions require graph/3") }
            if d.isContainer {
                try require(d.accessor == nil, "Container accessors are implicit identity")
                for c in d.children { try require(descriptions[c.id] === c, "Unregistered child identity") }
                n["children"] = d.children.map(\.id)
            } else { n["accessor"] = try accessorWire(d.effectiveAccessor, limits) }
            if d.isReference {
        let ref = try referenceTarget(d)
        try require(descriptions[ref.id] === ref, "Unregistered reference description")
        n["reference"] = ref.id
            }
            if d.isRelation { n["classes"] = d.classes }
            if d.isOption {
                n["options"] = try d.options.values(limits: limits).map { try wire($0, limits) }
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
