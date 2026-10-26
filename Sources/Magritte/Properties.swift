import Foundation

private func propertyKey(_ name: String, _ limits: Limits) throws {
  try require(
    !name.isEmpty && name.utf8.count <= limits.bytes && name.utf8.count < limits.visits
      && name.utf8.allSatisfy { $0 >= 33 && $0 <= 126 }, "Invalid or over-budget property key")
}
private func writable(_ owner: Description, _ name: String) throws {
  try require(
    name != "propertyAnnouncer" && owner.properties["propertyAnnouncer"] == nil,
    "Property announcements are outside the stored-Value profile")
}
private func checkedProperty(_ value: Value, _ limits: Limits) throws -> Value {
  try checkLocalValue(value, limits: limits)
  return value
}
extension Description {
  public func hasProperty(_ name: String) -> Bool {
    properties[name] != nil || (name == "displayBlockOrSymbol" && displayBlock != nil)
  }
  public func propertyAt(_ name: String, limits: Limits = Limits()) throws -> Value {
    try propertyKey(name, limits)
    if name == "displayBlockOrSymbol", displayBlock != nil {
      throw MagritteError("Display block has no stored Value representation")
    }
    guard let value = properties[name] else {
      throw MagritteError("MAPropertyError: property not found: " + name)
    }
    return try checkedProperty(value, limits)
  }
  public func propertyAt(_ name: String, ifAbsent: () throws -> Value, limits: Limits = Limits())
    throws -> Value
  {
    try propertyKey(name, limits)
    return try hasProperty(name)
      ? propertyAt(name, limits: limits) : checkedProperty(ifAbsent(), limits)
  }
  public func propertyAtIfAbsentPut(
    _ name: String, _ absent: () throws -> Value, limits: Limits = Limits()
  ) throws -> Value {
    try propertyKey(name, limits)
    if hasProperty(name) { return try propertyAt(name, limits: limits) }
    return try propertyPut(name, absent(), limits: limits)
  }
  public func propertyAtIfPresent(
    _ name: String, _ present: (Value) throws -> Value, limits: Limits = Limits()
  ) throws -> Value {
    try propertyKey(name, limits)
    if !hasProperty(name) { return .undefined }
    let value = try propertyAt(name, limits: limits)
    return try checkedProperty(present(value), limits)
  }
  public func propertyAtIfPresentOrElse(
    _ name: String, present: (Value) throws -> Value, absent: () throws -> Value,
    limits: Limits = Limits()
  ) throws -> Value {
    try propertyKey(name, limits)
    if !hasProperty(name) { return try checkedProperty(absent(), limits) }
    let value = try propertyAt(name, limits: limits)
    return try checkedProperty(present(value), limits)
  }
  public func propertyAtIfPresentOrPut(
    _ name: String, present: (Value) throws -> Value, absent: () throws -> Value,
    limits: Limits = Limits()
  ) throws -> Value {
    try propertyKey(name, limits)
    if !hasProperty(name) { return try propertyPut(name, absent(), limits: limits) }
    let value = try propertyAt(name, limits: limits)
    return try checkedProperty(present(value), limits)
  }
  @discardableResult public func propertyPut(
    _ name: String, _ value: Value, limits: Limits = Limits()
  ) throws -> Value {
    try propertyKey(name, limits)
    try writable(self, name)
    try checkLocalValue(value, limits: limits)
    properties[name] = value
    if name == "displayBlockOrSymbol" { displayBlock = nil }
    return value
  }
  @discardableResult public func propertyPutRemovingNil(
    _ name: String, _ value: Value, limits: Limits = Limits()
  ) throws -> Value {
    if !value.isNil { return try propertyPut(name, value, limits: limits) }
    try propertyKey(name, limits)
    try writable(self, name)
    if !hasProperty(name) { return .undefined }
    let old = try propertyAt(name, limits: limits)
    properties.removeValue(forKey: name)
    return old
  }
}
