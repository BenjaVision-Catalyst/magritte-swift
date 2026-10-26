import Foundation

// Structural ownership/codec inspection must not send the source-level reference getter.
func referenceTarget(_ owner: Description) throws -> Description {
  guard let target = owner.reference else {
    throw MagritteError("Reference description is unavailable; retain it in the graph")
  }
  return target
}
extension Description {
  public func referenceDescription() throws -> Description {
    let target = try referenceTarget(self)
    let block = displayBlock
    if block != nil {
      target.properties["displayBlockOrSymbol"] = .undefined
    } else if let setting = properties["displayBlockOrSymbol"] {
      target.properties["displayBlockOrSymbol"] = setting
    } else {
      target.properties.removeValue(forKey: "displayBlockOrSymbol")
    }
    target.displayBlock = block
    return target
  }
  @discardableResult public func setUndefined(_ value: Value, limits: Limits = Limits()) throws
    -> Description
  {
    if !value.isNil {
      guard case .string = value else {
        throw MagritteError("Undefined text must be String or nil")
      }
    }
    try checkLocalValue(value, limits: limits)
    var work = 0
    func apply(_ current: Description, _ depth: Int) throws {
      work += 1
      try require(
        work <= limits.visits && depth <= limits.depth, "Undefined propagation work/depth limit")
      current.properties["undefined"] = value
      if current.isOption {
        _ = try current.referenceDescription()
        try apply(current.referenceDescription(), depth + 1)
      }
    }
    try apply(self, 0)
    return self
  }
}
