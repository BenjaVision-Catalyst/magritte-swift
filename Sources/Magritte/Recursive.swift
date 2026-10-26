import Foundation

private let concreteDescriptions = [
  "MAContainer", "MAPriorityContainer", "MAStringDescription", "MASymbolDescription",
  "MAMemoDescription", "MAPasswordDescription", "MATokenDescription", "MANumberDescription",
  "MABooleanDescription", "MAToOneRelationDescription", "MAToManyRelationDescription",
  "MAToManyScalarRelationDescription", "MASingleOptionDescription", "MAMultipleOptionDescription",
]
private func expandedMetadata(_ target: Description, _ limits: Limits) throws -> Graph {
  let graph = try descriptionModelFor(target, limits: limits)
  let root = graph.descriptions[graph.root]!
  @discardableResult func add(_ key: String, _ cls: String, _ priority: Int64) -> Description {
    let d = Description(id: graph.root + "." + key, className: cls)
    d.accessor = Accessor(
      className: "MASelectorAccessor", name: key,
      writeName: key == "children" ? "setChildren:" : key + ":")
    d.properties["priority"] = .integer(priority)
    root.children.append(d)
    graph.descriptions[d.id] = d
    if d.isReference {
      let ref = Description(id: d.id + ".reference")
      ref.accessor = Accessor(className: "MANullAccessor")
      d.reference = ref
      graph.descriptions[ref.id] = ref
    }
    return d
  }
  add("name", "MASymbolDescription", 1)
  if target.isContainer {
    let d = add("children", "MAToManyRelationDescription", 400)
    d.properties["label"] = .string("Elements")
    d.properties["ordered"] = .boolean(true)
    d.properties["default"] = .collection(kind: "ordered", elements: [])
    d.classes = concreteDescriptions.filter { $0 != "MAContainer" && $0 != "MAPriorityContainer" }
  }
  if target.isReference {
    let d = add("reference", "MAToOneRelationDescription", 400)
    d.properties["label"] = .string("Description")
    if target.isRelation {
      d.classes = ["MAContainer", "MAPriorityContainer"]
      d.properties["required"] = .boolean(false)
    } else {
      d.classes = concreteDescriptions
      d.properties["required"] = .boolean(true)
    }
  }
  if target.isOption {
    let d = add("optionsTextual", "MAMemoDescription", 410)
    d.properties["label"] = .string("Options")
    d.properties["default"] = .collection(kind: "ordered", elements: [])
  }
  return graph
}
private final class RecursiveState {
  let graph = Graph(root: ""), limits: Limits
  var generation = 0, metaIDs = Set<String>()
  init(_ limits: Limits) { self.limits = limits }
  func bind(_ target: Description) throws -> Model {
    try visit(target, limits: limits) { try supported($0) }
    var pending: [String: Description] = [:]
    var seen = Set<ObjectIdentifier>()
    func walk(_ d: Description) throws {
      if !seen.insert(ObjectIdentifier(d)).inserted { return }
      try require(
        !d.id.isEmpty && d.id.utf8.allSatisfy { $0 >= 33 && $0 <= 126 },
        "Invalid metadata target identity")
      if let old = pending[d.id] {
        try require(old === d, "Metadata target identity already bound")
      }
      if let old = graph.descriptions[d.id] {
        try require(old === d, "Metadata target identity already bound")
      }
      pending[d.id] = d
      for c in d.children { try walk(c) }
      if d.isReference { try walk(d.referenceDescription()) }
    }
    try walk(target)
    let added = pending.keys.filter { graph.descriptions[$0] == nil }.count
    try require(graph.descriptions.count + added <= limits.nodes, "Recursive metadata node limit")
    for (id, d) in pending {
      graph.descriptions[id] = d
      if graph.nativeObjects[id] == nil { graph.nativeObjects[id] = DescriptionBinding(self, d) }
    }
    return graph.nativeObjects[target.id]!
  }
}
private final class DescriptionBinding: Model {
  weak var owner: RecursiveState?
  let target: Description
  init(_ owner: RecursiveState, _ target: Description) {
    self.owner = owner
    self.target = target
  }
  func state() throws -> RecursiveState {
    guard let owner else { throw MagritteError("Recursive metadata session expired") }
    return owner
  }
  func kindOf(_ name: String) -> Bool { target.kindOf(name) }
  func ref(_ d: Description) throws -> Value {
    let s = try state()
    if s.graph.nativeObjects[d.id] == nil || s.graph.descriptions[d.id] !== d { _ = try s.bind(d) }
    return .reference(d.id)
  }
  func description(_ value: Value) throws -> Description {
    let model = try state().graph.resolve(value)
    guard let binding = model as? DescriptionBinding else {
      throw MagritteError("Metadata reference must identify a description")
    }
    return binding.target
  }
  func readSlot(strategy: String, name: String) throws -> Value {
    let s = try state()
    if strategy != "MASelectorAccessor" {
      return try target.readSlot(strategy: strategy, name: name)
    }
    if name == "children", target.isContainer {
      return .collection(kind: "ordered", elements: try target.orderedChildren().map(ref))
    }
    if name == "reference", target.isReference { return try ref(target.referenceDescription()) }
    if name == "name" {
      if let value = target.properties["name"] { return value }
      let a = target.effectiveAccessor
      if ["MAIdentityAccessor", "MANullAccessor"].contains(a.className) { return .undefined }
      return a.className != "MAVariableAccessor" ? .symbol(a.name) : .string(a.name)
    }
    if name == "optionsTextual", target.isOption {
      var work = 0
      _ = try valueKey(.array(target.options)) { depth in
        work += 1
        try require(
          work <= s.limits.visits && depth <= s.limits.depth, "Options rendering work/depth limit")
      }
      return .string(
        try target.options.map {
          try writeString(
            $0, using: target.referenceDescription(), graph: s.graph, limits: s.limits)
        }.joined(separator: "\r"))
    }
    return try target.readSlot(strategy: strategy, name: name)
  }
  func writeSlot(strategy: String, name: String, value: Value) throws {
    let s = try state()
    if strategy != "MASelectorAccessor" {
      try target.writeSlot(strategy: strategy, name: name, value: value)
      return
    }
    if name == "setChildren:", target.isContainer {
      try require(
        value.isCollection && value.collectionCount() <= s.limits.items,
        "Children require a bounded collection")
      let next = try value.elements().map(description)
      let previous = target.children
      target.children = next
      do { try visit(target, limits: s.limits) { _ in } } catch {
        target.children = previous
        throw error
      }
      return
    }
    if name == "reference:", target.isReference {
      target.reference = try description(value)
      return
    }
    if name == "name:" {
      switch value {
      case .undefined, .string, .symbol: target.properties["name"] = value
      default: throw MagritteError("Name requires text or Symbol")
      }
      return
    }
    if name == "optionsTextual:", target.isOption {
      let text: String
      switch value {
      case .undefined: text = ""
      case .string(let v): text = v
      default: throw MagritteError("Options text requires String")
      }
      let scalars = Array(text.unicodeScalars)
      var start = 0
      var values: [Value] = []
      while start < scalars.count {
        var end = start
        while end < scalars.count && scalars[end] != "\r" && scalars[end] != "\n" { end += 1 }
        let line = String(String.UnicodeScalarView(scalars[start..<end]))
        values.append(try readString(line, using: target.referenceDescription(), limits: s.limits))
        try require(values.count <= s.limits.items, "Options item limit")
        start = end + 1
        if end < scalars.count && scalars[end] == "\r" && start < scalars.count
          && scalars[start] == "\n"
        {
          start += 1
        }
      }
      target.options = values
      return
    }
    try target.writeSlot(strategy: strategy, name: name, value: value)
  }
  func read(using description: Description) throws -> Value {
    let s = try state()
    let value = try description.effectiveAccessor.read(self, graph: s.graph, limits: s.limits)
    _ = try encodeValue(value, limits: s.limits)
    return value
  }
  func write(_ value: Value, using description: Description) throws {
    let s = try state()
    _ = try encodeValue(value, limits: s.limits)
    try description.effectiveAccessor.write(value, to: self, graph: s.graph, limits: s.limits)
  }
}
/// Explicit session that retains description targets and lazily describes metadata itself.
/// Retain this session while using its adapters; each describe builds a fresh schema.
public final class RecursiveDescriptionModel {
  private let state: RecursiveState
  public init(limits: Limits = Limits()) { state = RecursiveState(limits) }
  public var resolver: Graph { state.graph }
  public func bind(_ target: Description) throws -> Model { try state.bind(target) }
  public func describe(_ target: Description) throws -> Description {
    _ = try state.bind(target)
    let next = try expandedMetadata(target, state.limits)
    let old = next.root
    let root = next.descriptions[old]!
    let prefix = "recursive.\(state.generation + 1).\(target.id)"
    var renamed: [String: Description] = [:]
    for (id, d) in next.descriptions {
      d.id = prefix + id.dropFirst(old.count)
      renamed[d.id] = d
    }
    try require(
      state.graph.descriptions.count + renamed.count <= state.limits.nodes,
      "Recursive metadata node limit")
    for id in renamed.keys {
      try require(state.graph.descriptions[id] == nil, "Generated metadata identity collision")
    }
    _ = try state.bind(root)
    state.metaIDs.formUnion(renamed.keys)
    state.generation += 1
    state.graph.root = root.id
    return root
  }
  /// Exports schema descriptions only; local target bindings are never serialized.
  public func schemas() -> Graph {
    let graph = Graph(root: state.graph.root)
    for id in state.metaIDs { graph.descriptions[id] = state.graph.descriptions[id] }
    return graph
  }
}
