import Foundation

private final class EditingWork {
  let limits: Limits
  var count: Int
  init(_ limits: Limits, _ count: Int = 0) {
    self.limits = limits
    self.count = count
  }
  func tick() throws {
    count += 1
    try require(count <= limits.visits, "Editing work limit")
  }
  func key(_ v: Value) throws -> String {
    try valueKey(v) { depth in
      try self.tick()
      try require(depth <= self.limits.depth, "Editing depth limit")
    }
  }
  func equal(_ a: Value, _ b: Value) throws -> Bool { try key(a) == key(b) }
}
private func ignorable(_ value: Value, using d: Description, work: EditingWork) throws -> Bool {
  try work.tick()
  let undefined = try d.property("undefinedValue")
  var ignoreDefault = false
  if try !d.flag("shouldCacheDefault") && work.equal(value, d.defaultValue()) {
    ignoreDefault = try work.equal(value, d.defaultValue())
  }
  return try value.isNil || work.equal(value, undefined) || ignoreDefault
}
func shouldWrite(
  _ candidate: Value, over previous: Value, using d: Description, limits: Limits, work: inout Int
) throws -> Bool {
  try supported(d)
  try checkPortableDescription(d, limits: limits, work: &work)
  try require(!d.isContainer, "Container fields do not implement MAElementDescription editing")
  let budget = EditingWork(limits, work)
  try budget.tick()
  var result = false
  if try d.flag("visible") && !d.flag("readOnly") {
    result =
      try
      !(ignorable(candidate, using: d, work: budget) && ignorable(previous, using: d, work: budget))
      && !budget.equal(candidate, previous)
  }
  work = budget.count
  return result
}
extension Description {
  public func isIgnorableValue(_ value: Value, limits: Limits = Limits()) throws -> Bool {
    try supported(self)
    var work = 0
    try checkPortableDescription(self, limits: limits, work: &work)
    try require(!isContainer, "Container is not an editable element")
    return try ignorable(value, using: self, work: EditingWork(limits, work))
  }
  public func shouldWrite(_ candidate: Value, over previous: Value, limits: Limits = Limits())
    throws -> Bool
  {
    var work = 0
    return try Magritte.shouldWrite(
      candidate, over: previous, using: self, limits: limits, work: &work)
  }
}
/// Abstract editing adapter. Swift retains its model; graph context is weak.
public class Memento: Model {
  public let model: Model, description: Description, limits: Limits
  public weak var graph: Graph?
  public var className: String { "MAMemento" }
  public func kindOf(_ name: String) -> Bool {
    ClassRegistry.shared.includesBehavior(className,name)
  }
  public var usesStoredContainerValues: Bool { true }
  init(wrapping model: Model, description: Description, graph: Graph?, limits: Limits) throws {
    self.model = model
    self.description = description
    self.graph = graph
    self.limits = limits
    _ = try fields()
  }
  func fields() throws -> [Description] {
    try require(description.isContainer, "Memento description must be a container")
    var work = 0
    try visit(description, limits: limits) {
      try supported($0)
      try checkPortableDescription($0, limits: limits, work: &work)
    }
    let result = try description.orderedChildren()
    var ids = Set<String>()
    try require(result.count <= limits.items, "Editing field item limit")
    for d in result {
      try require(
        !d.isContainer,
        "Mementos edit direct element fields; use relationship references for nested objects")
      try require(
        !d.id.isEmpty && ids.insert(d.id).inserted,
        "Editing fields require unique nonempty identities")
    }
    return result
  }
  public func read(using description: Description) throws -> Value {
    throw MagritteError("Abstract memento read")
  }
  public func write(_ value: Value, using description: Description) throws {
    throw MagritteError("Abstract memento write")
  }
  public func reset() throws { throw MagritteError("Abstract memento reset") }
  /// Commit does not validate and does not provide a transaction.
  public func commit() throws { throw MagritteError("Abstract memento commit") }
  public func validate() throws -> [ValidationError] {
    try Magritte.validate(self, using: description, limits: limits, graph: graph)
  }
}
public final class StraightMemento: Memento {
  public override var className: String { "MAStraightMemento" }
  public init(
    model: Model, description: Description, graph: Graph? = nil, limits: Limits = Limits()
  ) throws {
    try super.init(wrapping: model, description: description, graph: graph, limits: limits)
  }
  public override func read(using d: Description) throws -> Value {
    let raw = try model.read(using: d)
    let value = try raw.isNil ? d.defaultValue() : raw
    _ = try EditingWork(limits).key(value)
    return value
  }
  public override func write(_ value: Value, using d: Description) throws {
    if try d.shouldWrite(value, over: model.read(using: d), limits: limits) {
      try model.write(value, using: d)
    }
  }
  public override func reset() throws {}
  public override func commit() throws {}
}
public class CachedMemento: Memento {
  public override var className: String { "MACachedMemento" }
  struct Entry {
    let description: Description
    var value: Value
  }
  var entries: [String: Entry] = [:], order: [String] = []
  public var cache: [String: Value] { entries.mapValues(\.value) }
  init(model: Model, description: Description, graph: Graph?, limits: Limits, initialize: Bool)
    throws
  {
    try super.init(wrapping: model, description: description, graph: graph, limits: limits)
    if initialize { try reset() }
  }
  public convenience init(
    model: Model, description: Description, graph: Graph? = nil, limits: Limits = Limits()
  ) throws {
    try self.init(
      model: model, description: description, graph: graph, limits: limits, initialize: true)
  }
  func pullRaw() throws -> [String: Value] {
    var result: [String: Value] = [:]
    let work = EditingWork(limits)
    for d in try fields() {
      try work.tick()
      let value = try model.read(using: d)
      _ = try work.key(value)
      result[d.id] = value
    }
    return result
  }
  func checkIdentities() throws {
    for d in try fields() {
      if let entry = entries[d.id] {
        try require(
          entry.description === d, "Description identity replaced; reset the memento before reuse")
      }
    }
  }
  func changed(_ first: [String: Value], from second: [String: Value]) throws -> Bool {
    var work = 0
    for d in try fields() {
      if try Magritte.shouldWrite(
        first[d.id] ?? .undefined, over: second[d.id] ?? .undefined, using: d, limits: limits,
        work: &work)
      {
        return true
      }
    }
    return false
  }
  public func hasChanges() throws -> Bool {
    try checkIdentities()
    return try changed(cache, from: pullRaw())
  }
  public override func read(using d: Description) throws -> Value {
    guard let entry = entries[d.id] else {
      throw MagritteError("Description is not cached; reset or write the described field first")
    }
    try require(entry.description === d, "Cached description identity mismatch")
    return entry.value
  }
  public override func write(_ value: Value, using d: Description) throws {
    try checkIdentities()
    try checkLocalValue(value, limits: limits)
    let work = EditingWork(limits)
    for (id, entry) in entries where id != d.id { _ = try work.key(entry.value) }
    _ = try work.key(value)
    if var entry = entries[d.id] {
      try require(entry.description === d, "Cached description identity mismatch")
      entry.value = value
      entries[d.id] = entry
      return
    }
    guard let field = try fields().first(where: { $0 === d }) else {
      throw MagritteError("Cannot cache a foreign description; add it to the container first")
    }
    entries[d.id] = Entry(description: field, value: value)
    order.append(d.id)
  }
  public override func reset() throws {
    var next: [String: Entry] = [:]
    var nextOrder: [String] = []
    let work = EditingWork(limits)
    for d in try fields() {
      try work.tick()
      var value = try model.read(using: d)
      if try work.equal(value, d.property("undefinedValue")) { value = try d.defaultValue() }
      _ = try work.key(value)
      next[d.id] = Entry(description: d, value: value)
      nextOrder.append(d.id)
    }
    entries = next
    order = nextOrder
  }
  func shouldPush(_ entry: Entry, current: Value, work: inout Int) throws -> Bool {
    try Magritte.shouldWrite(
      entry.value, over: current, using: entry.description, limits: limits, work: &work)
  }
  public override func commit() throws {
    try checkIdentities()
    let pending = entries
    let pendingOrder = order
    var work = 0
    for id in pendingOrder {
      work += 1
      try require(work <= limits.visits, "Editing commit work limit")
      guard let entry = pending[id] else { throw MagritteError("Missing cached entry") }
      let current = try model.read(using: entry.description)
      if try shouldPush(entry, current: current, work: &work) {
        try model.write(entry.value, using: entry.description)
      }
    }
    try reset()
  }
}
public final class CheckedMemento: CachedMemento {
  public override var className: String { "MACheckedMemento" }
  public private(set) var original: [String: Value] = [:]
  public init(
    model: Model, description: Description, graph: Graph? = nil, limits: Limits = Limits()
  ) throws {
    try super.init(
      model: model, description: description, graph: graph, limits: limits, initialize: false)
    try reset()
  }
  public override func reset() throws {
    try super.reset()
    original = try pullRaw()
  }
  public func hasModelChangedElsewhere() throws -> Bool {
    try checkIdentities()
    return try changed(original, from: pullRaw())
  }
  public func hasConflict() throws -> Bool { try hasChanges() && hasModelChangedElsewhere() }
  override func shouldPush(_ entry: Entry, current: Value, work: inout Int) throws -> Bool {
    guard let previous = original[entry.description.id] else {
      throw MagritteError("New field has no original value; reset checked memento first")
    }
    guard let actual = entries[entry.description.id] else {
      throw MagritteError("Missing checked cache value")
    }
    return try Magritte.shouldWrite(
      actual.value, over: previous, using: entry.description, limits: limits, work: &work)
      && super.shouldPush(entry, current: current, work: &work)
  }
  public override func validate() throws -> [ValidationError] {
    if try !hasConflict() { return try super.validate() }
    try reset()
    return [
      ValidationError(
        descriptionID: description.id, code: "MAConflictError",
        message: "Model changed while editing; memento reset")
    ]
  }
}
