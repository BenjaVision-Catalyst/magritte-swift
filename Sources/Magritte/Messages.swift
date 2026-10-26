import Foundation

private func messageText(_ value: Value) throws -> Value {
  if !value.isNil {
    guard case .string = value else { throw MagritteError("Error message must be String or nil") }
  }
  return value
}
private func message(_ d: Description, _ key: String, _ fallback: String, _ limits: Limits) throws
  -> Value
{
  try messageText(d.propertyAt(key, ifAbsent: { .string(fallback) }, limits: limits))
}
private func magnitude(_ d: Description) throws {
  try require(
    ClassRegistry.shared.includesBehavior(d.className, "MAMagnitudeDescription"),
    "Range message requires a magnitude description")
}
private func putMessage(_ d: Description, _ key: String, _ value: Value, _ limits: Limits) throws
  -> Description
{
  try d.propertyPut(key, messageText(value), limits: limits)
  return d
}
extension Description {
  public func requiredErrorMessage(limits: Limits = Limits()) throws -> Value {
    try message(self, "requiredErrorMessage", "Input is required but no input given", limits)
  }
  public func kindErrorMessage(limits: Limits = Limits()) throws -> Value {
    try message(self, "kindErrorMessage", "Invalid input given", limits)
  }
  public func conflictErrorMessage(limits: Limits = Limits()) throws -> Value {
    try message(
      self, "conflictErrorMessage", "Input is conflicting with concurrent modification", limits)
  }
  public func rangeErrorMessage(limits: Limits = Limits()) throws -> Value {
    try magnitude(self)
    return try messageText(
      propertyAt(
        "rangeErrorMessage",
        ifAbsent: {
          let minText = try writeString(self.property("min"), using: self, limits: limits)
          let maxText = try writeString(self.property("max"), using: self, limits: limits)
          let hasMin = try !self.property("min").isNil
          let hasMax = try !self.property("max").isNil
          if hasMin && hasMax {
            return .string("Input must be between " + minText + " and " + maxText)
          }
          if hasMin { return .string("Input must be above or equeal to " + minText) }
          if hasMax { return .string("Input must be below or equal to " + maxText) }
          return .undefined
        }, limits: limits))
  }
  @discardableResult public func setRequiredErrorMessage(_ v: Value, limits: Limits = Limits())
    throws -> Description
  { try putMessage(self, "requiredErrorMessage", v, limits) }
  @discardableResult public func setKindErrorMessage(_ v: Value, limits: Limits = Limits()) throws
    -> Description
  { try putMessage(self, "kindErrorMessage", v, limits) }
  @discardableResult public func setConflictErrorMessage(_ v: Value, limits: Limits = Limits())
    throws -> Description
  { try putMessage(self, "conflictErrorMessage", v, limits) }
  @discardableResult public func setRangeErrorMessage(_ v: Value, limits: Limits = Limits()) throws
    -> Description
  {
    try magnitude(self)
    return try putMessage(self, "rangeErrorMessage", v, limits)
  }
}
func validationMessage(_ d: Description, _ code: String, _ limits: Limits) throws -> String {
  let value: Value
  switch code {
  case "MARequiredError": value = try d.requiredErrorMessage(limits: limits)
  case "MAKindError": value = try d.kindErrorMessage(limits: limits)
  case "MAConflictError": value = try d.conflictErrorMessage(limits: limits)
  case "MARangeError": value = try d.rangeErrorMessage(limits: limits)
  default: throw MagritteError("Unsupported description error message")
  }
  guard case .string(let s) = value else {
    throw MagritteError("Nil error text has no String ValidationError representation")
  }
  return s
}
