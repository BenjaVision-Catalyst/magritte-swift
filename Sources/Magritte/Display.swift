import Foundation

public final class DisplayBlock {
  fileprivate let operation: (Value, Description) throws -> String
  public init(_ operation: @escaping (Value, Description) throws -> String) {
    self.operation = operation
  }
  public convenience init(_ operation: @escaping (Value) throws -> String) {
    self.init { v, _ in try operation(v) }
  }
  public convenience init(_ operation: @escaping () throws -> String) {
    self.init { _, _ in try operation() }
  }
}
extension Description {
  public func display(_ selector: String) {
    displayBlock = nil
    properties["displayBlockOrSymbol"] = .symbol(selector)
  }
  public func display(_ block: DisplayBlock) {
    displayBlock = block
    properties["displayBlockOrSymbol"] = .undefined
  }
  public func displayStringFor(_ value: Value, graph: Graph? = nil, limits: Limits = Limits())
    throws -> String
  {
    let budget = Budget(limits)
    // Validate local Value shape without charging JSON envelope bytes as display text.
    var validation = limits
    validation.bytes = Int.max
    try checkRuntimeValue(value,validation,&budget.work)
    let result: String
    if let block = displayBlock {
      result = try block.operation(value, self)
    } else {
      guard case .symbol(let selector) = try property("displayBlockOrSymbol"), !selector.isEmpty,
        selector.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 })
      else { throw MagritteError("Display selector must be nonempty ASCII Symbol") }
      var arity = selector.filter { $0 == ":" }.count
      if arity == 0 && selector.allSatisfy({ "!%&*+,/<=>?@\\~|-".contains($0) }) { arity = 1 }
      try require(arity <= 1, "Display selector takes more than one description argument")
      if case .reference = value {
        guard let graph else { throw MagritteError("Display receiver requires graph resolver") }
        let output = try graph.resolve(value).displayMessage(
          selector, argument: arity == 1 ? self : nil)
        guard case .string(let text) = output else {
          throw MagritteError("Display message must return String")
        }
        result = text
      } else if arity == 0 && ["greaseString", "asString"].contains(selector) {
        result = try displayString(value)
      } else if selector == "yourself",case .mutableCollection(let ref)=value,try ref.kind()=="string" {
        result=try displayString(ref.snapshot())
      } else if selector == "yourself", case .string(let text) = value {
        result = text
      } else if selector == "label", case .classValue(let name) = value,
        let info = ClassRegistry.shared.find(name)
      {
        result = info.label
      } else {
        throw MagritteError("Unbound scalar display selector: " + selector)
      }
    }
    try require(result.utf8.count <= limits.bytes, "Display output byte limit")
    _ = try valueKey(.string(result), tick: budget.tick)
    try checkLocalValue(.string(result), limits: validation)
    return result
  }
}
