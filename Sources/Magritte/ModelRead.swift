import Foundation

func undefinedIfNil(_ description: Description, _ value: Value) throws -> Value {
  try value.isNil ? description.property("undefinedValue") : value
}
extension Model {
  /// Object's default read hook; specialized models can override this protocol requirement.
  public func read(using description: Description) throws -> Value {
    let value = try description.effectiveAccessor.read(self)
    return try undefinedIfNil(description, value)
  }
}
