import Foundation

private final class CollectionNode {
  let kind: String
  var sequence: [Value] = []
  var text = ""
  var hashed: [String: (Value, Int)] = [:]
  init(_ kind: String) { self.kind = kind }
}
private final class CollectionStorage {
  var nodes: [String: CollectionNode] = [:]
  var serial = 0
}
public final class CollectionStore {
  private let state: CollectionStorage
  public init() { state = CollectionStorage() }
  private init(_ state: CollectionStorage) { self.state = state }
  public func contains(_ id: String) -> Bool { state.nodes[id] != nil }
  public func at(_ id: String) throws -> Value {
    try require(contains(id), "Unknown collection identity: " + id)
    return .mutableCollection(CollectionReference(state, id, true))
  }
  public func owns(_ value: Value) -> Bool {
    guard case .mutableCollection(let ref) = value, let storage = try? ref.storage() else {
      return false
    }
    return storage === state
  }
  public func create(
    kind: String, id: String = "", elements: [Value] = [], limits: Limits = Limits()
  )
    throws -> Value
  {
    var id = id
    if id.isEmpty {
      repeat {
        state.serial += 1
        id = "collection.\(state.serial)"
      } while contains(id)
    }
    _ = try identity(id)
    try require(id.utf8.count <= limits.bytes, "Collection identity byte limit")
    try require(
      ["array", "ordered", "set", "bag", "string"].contains(kind),
      "Unsupported mutable collection kind")
    try require(!contains(id), "Duplicate collection identity")
    try require(
      state.nodes.count < limits.nodes && elements.count <= limits.items, "Collection store limit")
    let node = CollectionNode(kind)
    if kind == "array" { node.sequence = Array(repeating: .undefined, count: elements.count) }
    if kind == "string" {
      for element in elements {
        guard case .character(let c) = element else {
          throw MagritteError("String requires Characters")
        }
        try checkLocalValue(element, limits: limits)
        node.text += c
        try require(node.text.utf8.count <= limits.bytes, "Mutable String byte limit")
      }
    }
    state.nodes[id] = node
    let result = try at(id)
    do { try result.mutableCollection().setElements(elements, limits: limits) } catch {
      state.nodes.removeValue(forKey: id)
      throw error
    }
    return result
  }
  public func string(id: String, text: String, limits: Limits = Limits()) throws -> Value {
    try create(kind: "string", id: id, elements: Value.string(text).elements(), limits: limits)
  }
  fileprivate static func copy(_ ref: CollectionReference, limits: Limits) throws -> Value {
    let storage = try ref.storage()
    var id: String
    repeat {
      storage.serial += 1
      id = "copy.collection.\(storage.serial)"
    } while storage.nodes[id] != nil
    return try CollectionStore(storage).create(
      kind: ref.kind(), id: id, elements: ref.snapshot().elements(), limits: limits)
  }
}
public final class CollectionReference {
  private weak var weakStorage: CollectionStorage?
  private let owner: CollectionStorage?
  public let id: String
  fileprivate init(_ state: CollectionStorage, _ id: String, _ retained: Bool) {
    weakStorage = state
    owner = retained ? state : nil
    self.id = id
  }
  fileprivate func storage() throws -> CollectionStorage {
    guard let state = weakStorage, state.nodes[id] != nil else {
      throw MagritteError("Native collection ownership expired")
    }
    return state
  }
  private func node() throws -> CollectionNode { try storage().nodes[id]! }
  public func identity() throws -> ObjectIdentifier { ObjectIdentifier(try node()) }
  public func kind() throws -> String { try node().kind }
  public func retained() throws -> Value {
    .mutableCollection(CollectionReference(try storage(), id, true))
  }
  fileprivate func borrowed() throws -> Value {
    .mutableCollection(CollectionReference(try storage(), id, false))
  }
  private func edge(_ value: Value, _ borrow: Bool) throws -> Value {
    switch value {
    case .mutableCollection(let ref):
      try require(
        ref.storage() === storage(), "Collection links require the same native ownership store")
      return try borrow ? ref.borrowed() : ref.retained()
    case .array(let a): return .array(try a.map { try edge($0, borrow) })
    case .collection(let kind, let a):
      return .collection(kind: kind, elements: try a.map { try edge($0, borrow) })
    default: return value
    }
  }
  public func snapshot() throws -> Value {
    let n = try node()
    if n.kind == "string" { return .string(n.text) }
    var values: [Value] = []
    if n.kind == "set" || n.kind == "bag" {
      for key in n.hashed.keys.sorted() {
        let e = n.hashed[key]!
        for _ in 0..<e.1 { values.append(try edge(e.0, false)) }
      }
    } else {
      values = try n.sequence.map { try edge($0, false) }
    }
    return n.kind == "array" ? .array(values) : .collection(kind: n.kind, elements: values)
  }
  public func shallowCopy(limits: Limits = Limits()) throws -> Value {
    try CollectionStore.copy(self, limits: limits)
  }
  public func setElements(_ next: [Value], limits: Limits = Limits()) throws {
    try require(
      next.count <= limits.items && next.count <= limits.visits,
      "Mutable collection item/work limit")
    let n = try node()
    var work = 0
    for value in next { try checkRuntimeValue(value, limits, &work) }
    if n.kind == "string" {
      try require(next.count == n.text.unicodeScalars.count, "String size is fixed")
      var text = ""
      for value in next {
        guard case .character(let c) = value, c.unicodeScalars.count == 1 else {
          throw MagritteError("String requires Characters")
        }
        text += c
        try require(text.utf8.count <= limits.bytes, "Mutable String byte limit")
      }
      n.text = text
    } else if n.kind == "array" || n.kind == "ordered" {
      try require(n.kind != "array" || next.count == n.sequence.count, "Array size is fixed")
      n.sequence = try next.map { try edge($0, true) }
    } else {
      var hashed: [String: (Value, Int)] = [:]
      func immutable(_ value: Value) throws {
        if case .mutableCollection = value {
          throw MagritteError(
            "Mutable collection members are outside the stable hashed-key profile")
        }
        switch value {
        case .array(let a), .collection(_, let a): for e in a { try immutable(e) }
        default: break
        }
      }
      for value in next {
        try immutable(value)
        let key = try valueKey(value) { d in
          work += 1
          try require(
            work <= limits.visits && d <= limits.depth, "Collection hashing work/depth limit")
        }
        hashed[key] = (value, n.kind == "set" ? 1 : (hashed[key]?.1 ?? 0) + 1)
      }
      n.hashed = hashed
    }
  }
  public func append(_ value: Value, limits: Limits = Limits()) throws {
    try require(!["array", "string"].contains(kind()), "Collection size is fixed")
    var values = try snapshot().elements()
    values.append(value)
    try setElements(values, limits: limits)
  }
  public func atPut(_ index: Int, _ value: Value, limits: Limits = Limits()) throws {
    try require(!["set", "bag"].contains(kind()), "Hashed collection has no indexed write")
    var values = try snapshot().elements()
    try require(values.indices.contains(index), "Collection index outside storage")
    values[index] = value
    try setElements(values, limits: limits)
  }
  public func remove(_ value: Value, limits: Limits = Limits()) throws {
    try require(!["array", "string"].contains(kind()), "Collection size is fixed")
    var values = try snapshot().elements()
    guard let index = try values.firstIndex(where: { try valuesEqual(value, $0, limits: limits) })
    else { throw MagritteError("Collection element not found") }
    values.remove(at: index)
    try setElements(values, limits: limits)
  }
  public func clear(limits: Limits = Limits()) throws {
    try require(!["array", "string"].contains(kind()), "Collection size is fixed")
    try setElements([], limits: limits)
  }
}
extension Value {
  public func mutableCollection() throws -> CollectionReference {
    guard case .mutableCollection(let ref) = self else {
      throw MagritteError("Value is not a mutable collection")
    }
    _ = try ref.identity()
    return ref
  }
  public func sameCollection(_ other: Value) throws -> Bool {
    guard case .mutableCollection(let a) = self, case .mutableCollection(let b) = other else {
      return false
    }
    return try a.identity() == b.identity()
  }
  public func shallowCopy(limits: Limits = Limits()) throws -> Value {
    if case .mutableCollection(let ref) = self { return try ref.shallowCopy(limits: limits) }
    return self
  }
}
func checkRuntimeValue(_ value: Value, _ limits: Limits, _ work: inout Int, _ depth: Int = 0) throws
{
  var seen = Set<ObjectIdentifier>()
  func walk(_ v: Value, _ d: Int) throws {
    try require(d <= limits.depth, "Runtime value work/depth limit")
    switch v {
    case .mutableCollection(let ref):
      work += 1
      try require(work <= limits.visits, "Runtime value work limit")
      if !seen.insert(try ref.identity()).inserted { return }
      try require(seen.count <= limits.nodes, "Collection node limit")
      try walk(ref.snapshot(), d)
    case .array(let a), .collection(_, let a):
      work += 1
      try require(work <= limits.visits, "Runtime value work limit")
      try require(a.count <= limits.items, "Collection item limit")
      for e in a { try walk(e, d + 1) }
    default:
      try checkLocalValue(v, limits: limits)
      _ = try valueKey(
        v,
        tick: { level in
          work += 1
          try require(
            work <= limits.visits && level <= limits.depth, "Runtime value work/depth limit")
        }, depth: d)
    }
  }
  try walk(value, depth)
}
func equalRuntimeValues(
  _ a: Value, _ b: Value, _ limits: Limits, _ work: inout Int, _ depth: Int = 0
) throws -> Bool {
  var active = Set<String>()
  func equal(_ x: Value, _ y: Value, _ d: Int) throws -> Bool {
    work += 1
    try require(work <= limits.visits && d <= limits.depth, "Collection equality work/depth limit")
    if try x.sameCollection(y) { return true }
    let left: Value
    let right: Value
    if case .mutableCollection(let r) = x { left = try r.snapshot() } else { left = x }
    if case .mutableCollection(let r) = y { right = try r.snapshot() } else { right = y }
    func sequence(_ v: Value) -> (String, [Value])? {
      switch v {
      case .array(let a): return ("array", a)
      case .collection(let k, let a): return (k, a)
      default: return nil
      }
    }
    if (sequence(left) == nil) != (sequence(right) == nil) { return false }
    if let l = sequence(left), let r = sequence(right) {
      if l.0 != r.0 { return false }
      if l.0 == "array" || l.0 == "ordered" {
        let one = try? x.mutableCollection().identity()
        let two = try? y.mutableCollection().identity()
        let key = "\(String(describing:one))|\(String(describing:two))"
        let track = one != nil || two != nil
        if track {
          try require(
            active.insert(key).inserted,
            "Recursive collection equality has no supported finite result")
        }
        defer { if track { active.remove(key) } }
        if l.1.count != r.1.count { return false }
        for (a, b) in zip(l.1, r.1) { if try !equal(a, b, d + 1) { return false } }
        return true
      }
    }
    func key(_ v: Value) throws -> String {
      try valueKey(
        v,
        tick: { level in
          work += 1
          try require(
            work <= limits.visits && level <= limits.depth, "Collection equality work/depth limit")
        }, depth: d)
    }
    return try key(left) == key(right)
  }
  return try equal(a, b, depth)
}
public func valuesEqual(_ a: Value, _ b: Value, limits: Limits = Limits()) throws -> Bool {
  var work = 0
  return try equalRuntimeValues(a, b, limits, &work)
}

// Swift Array provides native value storage; this box supplies the source collection identity.
public final class DescriptionChildren {
  public var values: [Description]
  public let kind: String
  public init(_ values: [Description] = [], kind: String = "ordered") {
    self.values = values
    self.kind = kind
  }
  public func shallowCopy() -> DescriptionChildren { DescriptionChildren(values, kind: kind) }
}
