import Foundation

private final class ModelWork {
  let budget: Budget
  init(_ limits: Limits) { budget = Budget(limits) }
  func value(_ value: Value) throws {
    _ = try valueKey(value, tick: budget.tick)
    try checkLocalValue(value, limits: budget.limits)
  }
  func equal(_ left: Value, _ right: Value, _ graph: Graph?) throws -> Bool {
    try budget.tick(0)
    if case .reference = left {
      guard let graph else {
        throw MagritteError("Model equality receiver requires a graph resolver")
      }
      let result = try graph.resolve(left).binaryMessage("=", argument: right, graph: graph)
      try value(result)
      guard case .boolean(let b) = result else {
        throw MagritteError("Model equality message must return Boolean")
      }
      return b
    }
    return try valueKey(left, tick: budget.tick) == valueKey(right, tick: budget.tick)
  }
}
private func declaredModelDefault(_ d: Description, _ work: ModelWork) throws -> Value {
  try require(
    d.defaultFunction == nil, "Model initialization/comparison does not evaluate callable defaults")
  let value = try d.property(
    d.isContainer ? "undefinedValue" : "default", limits: work.budget.limits)
  try work.value(value)
  return value
}
@discardableResult public func initializeMagritte(
  _ model: Model, using description: Description, limits: Limits = Limits()
) throws -> Model {
  let work = ModelWork(limits)
  for d in try enumerationChildren(description, limits: limits) {
    try work.budget.tick(0)
    if try !d.flag("readOnly") { try model.write(declaredModelDefault(d, work), using: d) }
  }
  return model
}
@discardableResult public func initializeMagritte(
  _ model: Model, using provider: () throws -> Description, limits: Limits = Limits()
) throws -> Model {
  let description = try provider()
  return try initializeMagritte(model, using: description, limits: limits)
}
public func isSameAs(
  _ model: Model, _ other: Model, using description: Description, graph: Graph? = nil,
  limits: Limits = Limits()
) throws -> Bool {
  let work = ModelWork(limits)
  for d in try enumerationChildren(description, limits: limits) {
    try work.budget.tick(0)
    let accessor = try d.accessorObject?.snapshot(limits: limits) ?? d.effectiveAccessor
    if try !accessor.canRead(other, graph: graph, limits: limits) { return false }
    let left = try model.read(using: d)
    let right = try other.read(using: d)
    let fallback = try declaredModelDefault(d, work)
    try work.value(left)
    try work.value(right)
    func matchesDefault(_ candidate: Value) throws -> Bool {
      try work.equal(.undefined, candidate, graph) || work.equal(fallback, candidate, graph)
    }
    if try matchesDefault(left) && matchesDefault(right) { continue }
    if try !work.equal(left, right, graph) { return false }
  }
  return true
}
public func isSameAs(
  _ model: Model, _ other: Model, using provider: () throws -> Description, graph: Graph? = nil,
  limits: Limits = Limits()
) throws -> Bool {
  let description = try provider()
  return try isSameAs(model, other, using: description, graph: graph, limits: limits)
}
