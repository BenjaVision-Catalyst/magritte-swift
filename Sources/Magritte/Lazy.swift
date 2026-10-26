import Foundation

private func element(_ d: Description) throws {
  try require(
    ClassRegistry.shared.includesBehavior(d.className, "MAElementDescription"),
    "Lazy/initial answer protocol requires an element description")
}
private func declaredDefault(_ d: Description, _ limits: Limits) throws -> Value {
  try require(
    d.defaultFunction == nil,
    "Lazy initialization/initial answer does not evaluate callable defaults")
  let value = try d.property("default", limits: limits)
  try checkLocalValue(value, limits: limits)
  return value
}
extension Description {
  public func initialAnswer(limits: Limits = Limits()) throws -> Value {
    try element(self)
    return try propertyAt(
      "initialAnswer", ifAbsent: { try declaredDefault(self, limits) }, limits: limits)
  }
  @discardableResult public func setInitialAnswer(_ value: Value, limits: Limits = Limits()) throws
    -> Description
  {
    try element(self)
    try propertyPut("initialAnswer", value, limits: limits)
    return self
  }
  public func lazilyInitializeFrom(_ current: Value, for model: Model, limits: Limits = Limits())
    throws -> Value
  {
    try element(self)
    try checkLocalValue(current, limits: limits)
    if !current.isNil { return current }
    let value = try declaredDefault(self, limits)
    if try flag("shouldCacheDefault") { try model.write(value, using: self) }
    return value
  }
  public func maLazyPropertyUsing(_ description: Description, limits: Limits = Limits()) throws
    -> Value
  {
    let accessor =
      try description.accessorObject?.snapshot(limits: limits) ?? description.effectiveAccessor
    try require(
      accessor.className == "MASelectorAccessor" && !accessor.name.isEmpty,
      "maLazyPropertyUsing requires a nonempty selector read accessor")
    let current = try propertyAt(accessor.name, ifAbsent: { .undefined }, limits: limits)
    return try description.lazilyInitializeFrom(current, for: self, limits: limits)
  }
}
