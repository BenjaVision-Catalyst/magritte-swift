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
private let accessorClasses = [
  "MADictionaryAccessor", "MAPropertyAccessor", "MASelectorAccessor", "MAVariableAccessor",
  "MANullAccessor", "MAIdentityAccessor", "MADelegatorAccessor", "MAChainAccessor",
]
@discardableResult private func addMetadata(
  _ graph: Graph, _ key: String, _ cls: String, _ priority: Int64? = nil
) -> Description {
  let d = Description(id: graph.root + "." + key, className: cls)
  d.accessor = Accessor(className: "MASelectorAccessor", name: key, writeName: key + ":")
  if let priority { d.properties["priority"] = .integer(priority) }
  graph.descriptions[graph.root]!.children.append(d)
  graph.descriptions[d.id] = d
  if d.isReference {
    let ref = Description(id: d.id + ".reference")
    ref.accessor = Accessor(className: "MANullAccessor")
    d.reference = ref
    graph.descriptions[ref.id] = ref
  }
  return d
}
private func objectMetadata(_ cls: String) -> Graph {
  let graph = Graph(root: "meta." + cls)
  graph.format = "magritte.graph/4"
  let root = Description(id: graph.root, className: "MAContainer")
  root.properties["label"] = .string(cls)
  graph.descriptions[root.id] = root
  return graph
}
private func reflectedMetadata(
  _ target: Description, _ limits: Limits, completeRegistry: Bool = false
) throws -> Graph {
  let graph = try expandedMetadata(target, limits)
  graph.format = "magritte.graph/4"
  for d in graph.descriptions.values where d.isRelation && d.classes.contains("MAStringDescription")
  { d.classes.append("MAClassDescription") }
  addMetadata(graph, "accessor", "MAToOneRelationDescription", 10).classes = accessorClasses
  for key in ["stringReader", "stringWriter", "validator"] {
    let cls =
      key == "stringReader"
      ? "MAStringReader" : key == "stringWriter" ? "MAStringWriter" : "MAValidatorVisitor"
    let d = addMetadata(
      graph, key, "MASingleOptionDescription",
      key == "stringReader" ? 300 : key == "stringWriter" ? 310 : 250)
    d.properties["label"] = .string(
      key == "stringReader"
        ? "String Reader" : key == "stringWriter" ? "String Writer" : "Validator")
    d.properties["default"] = .classValue(cls)
    d.options = [.classValue(cls)]
    try d.referenceDescription().className = "MAClassDescription"
  }
  if target.isRelation {
    let d = addMetadata(graph, "classes", "MAMultipleOptionDescription", 400)
    d.properties["label"] = .string("Classes")
    d.properties["default"] = .collection(kind: "set", elements: [])
    try d.referenceDescription().className = "MAClassDescription"
    d.options = portableClasses().filter {
      completeRegistry
        || !["MAMemento", "MAStraightMemento", "MACachedMemento", "MACheckedMemento"].contains($0)
    }.map(Value.classValue)
  }
  return graph
}
private func accessorMetadata(_ target: AccessorObject) -> Graph {
  let cls = target.value.className
  let graph = objectMetadata(cls)
  if ["MADictionaryAccessor", "MAPropertyAccessor"].contains(cls) {
    addMetadata(graph, "key", "MASymbolDescription").properties["required"] = .boolean(true)
  }
  if cls == "MASelectorAccessor" { addMetadata(graph, "selector", "MASymbolDescription") }
  if ["MAChainAccessor", "MADelegatorAccessor"].contains(cls) {
    addMetadata(graph, "next", "MAToOneRelationDescription", 100).classes = accessorClasses
    if cls == "MAChainAccessor" {
      addMetadata(graph, "accessor", "MAToOneRelationDescription", 200).classes = accessorClasses
    }
  }
  return graph
}
private final class RecursiveState {
  let graph = Graph(root: ""), limits: Limits
  var generation = 0, metaIDs = Set<String>(), modelSchemaIDs = Set<String>()
  var mementos: [String: Memento] = [:]
  var accessors: [String: AccessorObject] = [:], conditions: [String: ConditionObject] = [:]
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
      try require(
        (graph.nativeObjects[d.id] == nil || graph.descriptions[d.id] != nil)
          && accessors[d.id] == nil && conditions[d.id] == nil, "Reflection identity collision")
      pending[d.id] = d
      for c in d.children { try walk(c) }
      if d.isReference { try walk(d.referenceDescription()) }
    }
    try walk(target)
    let added = pending.keys.filter { graph.descriptions[$0] == nil }.count
    try require(
      graph.descriptions.count + accessors.count + conditions.count + mementos.count + added
        <= limits.nodes,
      "Recursive metadata node limit")
    for (id, d) in pending {
      graph.descriptions[id] = d
      if graph.nativeObjects[id] == nil { graph.nativeObjects[id] = DescriptionBinding(self, d) }
    }
    return graph.nativeObjects[target.id]!
  }
  func bind(_ target: AccessorObject) throws -> Model {
    _ = try target.snapshot(limits: limits)
    var pending: [String: AccessorObject] = [:]
    var seen = Set<ObjectIdentifier>()
    func walk(_ a: AccessorObject) throws {
      if !seen.insert(ObjectIdentifier(a)).inserted { return }
      try checkReflectionID(a.id, limits)
      if let old = pending[a.id] { try require(old === a, "Reflection identity collision") }
      if let old = accessors[a.id] { try require(old === a, "Reflection identity collision") }
      try require(
        graph.descriptions[a.id] == nil && conditions[a.id] == nil
          && (graph.nativeObjects[a.id] == nil || accessors[a.id] != nil),
        "Reflection identity collision")
      pending[a.id] = a
      if let first = a.accessor { try walk(first) }
      if let next = a.next { try walk(next) }
    }
    try walk(target)
    let added = pending.keys.filter { accessors[$0] == nil }.count
    try require(
      graph.descriptions.count + accessors.count + conditions.count + mementos.count + added
        <= limits.nodes,
      "Reflection node limit")
    for (id, object) in pending {
      accessors[id] = object
      if graph.nativeObjects[id] == nil { graph.nativeObjects[id] = AccessorBinding(self, object) }
    }
    return graph.nativeObjects[target.id]!
  }
  func bind(_ target: ConditionObject) throws -> Model {
    try target.predicate.check(limits: limits)
    try checkReflectionID(target.id, limits)
    try require(
      graph.descriptions[target.id] == nil && accessors[target.id] == nil
        && (graph.nativeObjects[target.id] == nil || conditions[target.id] != nil),
      "Reflection identity collision")
    if let old = conditions[target.id] {
      try require(old === target, "Reflection identity collision")
    }
    if conditions[target.id] == nil {
      try require(
        graph.descriptions.count + accessors.count + conditions.count + mementos.count
          < limits.nodes,
        "Reflection node limit")
    }
    conditions[target.id] = target
    if graph.nativeObjects[target.id] == nil {
      graph.nativeObjects[target.id] = ConditionBinding(self, target)
    }
    return graph.nativeObjects[target.id]!
  }
  func bind(_ id: String, _ target: Memento) throws -> Model {
    try checkReflectionID(id, limits)
    if graph.nativeObjects[id] != nil {
      if mementos[id] === target { return target }
      throw MagritteError("Reflection identity collision")
    }
    try require(
      !mementos.values.contains { $0 === target }, "Memento already has a session identity")
    var added = Set<String>()
    try visit(target.description, limits: limits) { d in
      try require(d.id != id, "Memento identity collides with its description")
      if graph.descriptions[d.id] == nil { added.insert(d.id) }
    }
    try require(
      graph.descriptions.count + accessors.count + conditions.count + mementos.count + added.count
        + 1 <= limits.nodes, "Memento node limit")
    _ = try bind(target.description)
    mementos[id] = target
    graph.nativeObjects[id] = target
    return target
  }
  func bootstrap(_ target: Description) throws -> Graph {
    _ = try bind(target)
    var targets: [Description] = []
    try visit(target, limits: limits) { targets.append(graph.descriptions[$0.id]!) }
    let batch = Graph(root: "")
    batch.format = "magritte.graph/4"
    var nextGeneration = generation
    var roots: [Description] = []
    for d in targets {
      let next = try reflectedMetadata(d, limits, completeRegistry: true)
      let old = next.root
      nextGeneration += 1
      let prefix = "bootstrap.\(nextGeneration).\(d.id)"
      let root = next.descriptions[old]!
      roots.append(root)
      if batch.root.isEmpty { batch.root = prefix }
      for (id, node) in next.descriptions {
        node.id = prefix + id.dropFirst(old.count)
        try checkReflectionID(node.id, limits)
        try require(
          graph.nativeObjects[node.id] == nil && batch.descriptions[node.id] == nil,
          "Bootstrap identity collision")
        batch.descriptions[node.id] = node
      }
      try require(
        graph.descriptions.count + accessors.count + conditions.count + mementos.count
          + batch.descriptions.count <= limits.nodes, "Bootstrap node limit")
    }
    _ = try batch.encode(limits: limits)
    for root in roots { _ = try bind(root) }
    metaIDs.formUnion(batch.descriptions.keys)
    generation = nextGeneration
    graph.root = batch.root
    graph.format = batch.format
    return batch
  }
  func publish(_ next: Graph, targetID: String, family: String) throws -> Description {
    let old = next.root
    let root = next.descriptions[next.root]!
    let prefix = "\(family).\(generation + 1).\(targetID)"
    var renamed: [String: Description] = [:]
    for (id, d) in next.descriptions {
      d.id = prefix + id.dropFirst(old.count)
      renamed[d.id] = d
    }
    try require(
      graph.descriptions.count + accessors.count + conditions.count + mementos.count + renamed.count
        <= limits.nodes,
      "Recursive metadata node limit")
    for id in renamed.keys {
      try require(graph.nativeObjects[id] == nil, "Generated metadata identity collision")
    }
    _ = try bind(root)
    metaIDs.formUnion(renamed.keys)
    generation += 1
    graph.root = root.id
    if next.format == "magritte.graph/4" { graph.format = next.format }
    return root
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
    if name == "accessor" {
      try require(
        target.nativeRead == nil && target.nativeWrite == nil,
        "Local callbacks are not reflective accessor objects")
      if target.accessorObject == nil {
        var id = target.id + ".accessor"
        var serial = 1
        while s.graph.nativeObjects[id] != nil {
          serial += 1
          id = target.id + ".accessor.\(serial)"
        }
        let candidate = try AccessorObject.fromAccessor(
          id: id, target.effectiveAccessor, limits: s.limits)
        _ = try s.bind(candidate)
        target.accessorObject = candidate
      }
      let object = target.accessorObject!
      _ = try s.bind(object)
      return .reference(object.id)
    }
    if name == "classes", target.isRelation {
      return .collection(kind: "set", elements: target.classes.map(Value.classValue))
    }
    if name == "children", target.isContainer {
      return .collection(kind: "ordered", elements: try target.orderedChildren().map(ref))
    }
    if name == "reference", target.isReference { return try ref(target.referenceDescription()) }
    if name == "name" {
      if let value = target.properties["name"] { return value }
      let a = try target.effectiveAccessor
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
    if name == "accessor:" {
      guard case .reference(let id) = value, let object = s.accessors[id] else {
        throw MagritteError("Accessor requires a bound accessor object")
      }
      target.accessorObject = object
      target.accessor = nil
      return
    }
    if name == "classes:", target.isRelation {
      try require(
        value.isCollection && value.collectionCount() <= s.limits.items,
        "Classes require a bounded collection")
      var names: [String] = []
      var unique = Set<String>()
      for item in try value.elements() {
        guard case .classValue(let name) = item, knownClass(name), unique.insert(name).inserted
        else { throw MagritteError("Classes require unique supported class values") }
        names.append(name)
      }
      target.classes = names
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
private final class AccessorBinding: Model {
  weak var owner: RecursiveState?
  let target: AccessorObject
  init(_ owner: RecursiveState, _ target: AccessorObject) {
    self.owner = owner
    self.target = target
  }
  func state() throws -> RecursiveState {
    guard let owner else { throw MagritteError("Recursive metadata session expired") }
    return owner
  }
  func kindOf(_ cls: String) -> Bool {
    ["Object", "MABasicObject", "MAObject", "MAAccessor", target.value.className].contains(cls)
      || (cls == "MADictionaryAccessor" && target.value.className == "MAPropertyAccessor")
      || (cls == "MADelegatorAccessor" && target.value.className == "MAChainAccessor")
  }
  func readSlot(strategy: String, name: String) throws -> Value {
    let s = try state()
    try require(strategy == "MASelectorAccessor", "Accessor metadata requires selector access")
    let cls = target.value.className
    if (name == "key" && ["MADictionaryAccessor", "MAPropertyAccessor"].contains(cls))
      || (name == "selector" && cls == "MASelectorAccessor")
    {
      return .symbol(target.value.name)
    }
    guard let node = name == "next" ? target.next : name == "accessor" ? target.accessor : nil
    else { throw MagritteError("Unsupported accessor metadata getter") }
    _ = try s.bind(node)
    return .reference(node.id)
  }
  func writeSlot(strategy: String, name: String, value: Value) throws {
    let s = try state()
    try require(strategy == "MASelectorAccessor", "Accessor metadata requires selector access")
    let cls = target.value.className
    if (name == "key:" && ["MADictionaryAccessor", "MAPropertyAccessor"].contains(cls))
      || (name == "selector:" && cls == "MASelectorAccessor")
    {
      let text: String
      switch value {
      case .string(let s), .symbol(let s): text = s
      default: throw MagritteError("Accessor name requires Symbol or String")
      }
      var candidate = target.value
      candidate.name = text
      if name == "selector:" { candidate.writeName = text + ":" }
      try candidate.check(limits: s.limits)
      target.value = candidate
      return
    }
    guard case .reference(let id) = value, let node = s.accessors[id] else {
      throw MagritteError("Accessor slot requires a bound accessor")
    }
    if (name == "next:" && ["MAChainAccessor", "MADelegatorAccessor"].contains(cls))
      || (name == "accessor:" && cls == "MAChainAccessor")
    {
      let previous = name == "next:" ? target.next : target.accessor
      if name == "next:" { target.next = node } else { target.accessor = node }
      do { _ = try target.snapshot(limits: s.limits) } catch {
        if name == "next:" { target.next = previous } else { target.accessor = previous }
        throw error
      }
      return
    }
    throw MagritteError("Unsupported accessor metadata setter")
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
private final class ConditionBinding: Model {
  weak var owner: RecursiveState?
  let target: ConditionObject
  init(_ owner: RecursiveState, _ target: ConditionObject) {
    self.owner = owner
    self.target = target
  }
  func kindOf(_ cls: String) -> Bool {
    ["Object", "MABasicObject", "MAObject", "MACondition", target.predicate.className].contains(cls)
  }
  func read(using description: Description) throws -> Value {
    try require(owner != nil, "Recursive metadata session expired")
    throw MagritteError("Upstream condition objects have no annotated fields")
  }
  func write(_ value: Value, using description: Description) throws {
    try require(owner != nil, "Recursive metadata session expired")
    throw MagritteError("Upstream condition objects have no annotated fields")
  }
}
/// Explicit session for descriptions, live accessors and portable condition objects.
public final class RecursiveDescriptionModel {
  private let state: RecursiveState
  public init(limits: Limits = Limits()) { state = RecursiveState(limits) }
  public var resolver: Graph { state.graph }
  public func bind(_ target: Description) throws -> Model { try state.bind(target) }
  public func bind(_ target: AccessorObject) throws -> Model { try state.bind(target) }
  public func bind(_ target: ConditionObject) throws -> Model { try state.bind(target) }
  public func describe(_ target: Description) throws -> Description {
    _ = try state.bind(target)
    return try state.publish(
      expandedMetadata(target, state.limits), targetID: target.id, family: "recursive")
  }
  public func describeReflective(_ target: Description) throws -> Description {
    _ = try state.bind(target)
    return try state.publish(
      reflectedMetadata(target, state.limits), targetID: target.id, family: "reflective")
  }
  public func describe(_ target: AccessorObject) throws -> Description {
    _ = try state.bind(target)
    return try state.publish(accessorMetadata(target), targetID: target.id, family: "reflective")
  }
  public func describe(_ target: ConditionObject) throws -> Description {
    _ = try state.bind(target)
    return try state.publish(
      objectMetadata(target.predicate.className), targetID: target.id, family: "reflective")
  }
  public func schemas() throws -> Graph {
    let result = Graph(root: state.graph.root)
    result.format = state.graph.format
    var seen = Set<ObjectIdentifier>()
    var active = Set<ObjectIdentifier>()
    var composed = Set<ObjectIdentifier>()
    var work = 0
    func tick(_ depth: Int) throws {
      work += 1
      try require(
        work <= state.limits.visits && depth <= state.limits.depth, "Schema traversal limit")
    }
    func composition(_ d: Description, _ depth: Int) throws {
      try tick(depth)
      let id = ObjectIdentifier(d)
      try require(!active.contains(id), "Cyclic schema composition")
      if composed.contains(id) { return }
      active.insert(id)
      for c in try d.orderedChildren() { try composition(c, depth + 1) }
      active.remove(id)
      composed.insert(id)
    }
    func include(_ d: Description, _ depth: Int) throws {
      try tick(depth)
      if !seen.insert(ObjectIdentifier(d)).inserted { return }
      try composition(d, 0)
      try checkReflectionID(d.id, state.limits)
      if let old = result.descriptions[d.id] { try require(old === d, "Schema identity collision") }
      result.descriptions[d.id] = d
      try require(result.descriptions.count <= state.limits.nodes, "Schema node limit")
      for c in try d.orderedChildren() { try include(c, depth + 1) }
      if d.isReference { try include(d.referenceDescription(), depth + 1) }
    }
    for id in state.metaIDs.sorted() { try include(state.graph.descriptions[id]!, 0) }
    for id in state.modelSchemaIDs.sorted() { try include(state.graph.descriptions[id]!, 0) }
    return result
  }
  public func bind(_ id: String, _ target: Memento) throws -> Model { try state.bind(id, target) }
  public func describe(_ id: String, _ target: Memento) throws -> Description {
    _ = try state.bind(id, target)
    let d = target.description
    state.modelSchemaIDs.insert(d.id)
    state.graph.root = d.id
    state.graph.format = "magritte.graph/4"
    return d
  }
  public func bootstrap(_ target: Description) throws -> Graph { try state.bootstrap(target) }
  public func bootstrap(_ id: String, _ target: Memento) throws -> Graph {
    _ = try state.bind(id, target)
    return try state.bootstrap(target.description)
  }
}
