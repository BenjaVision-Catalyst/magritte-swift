import Foundation

public final class SortBlock {
  public let accessor: AccessorObject, selector: String
  public convenience init(selector: String) throws {
    try self.init(accessor: Accessor(className: "MAIdentityAccessor"), selector: selector)
  }
  public convenience init(accessor: Accessor, selector: String) throws {
    try self.init(
      accessor: AccessorObject.fromAccessor(id: "sort.accessor." + UUID().uuidString, accessor),
      selector: selector)
  }
  public init(accessor: AccessorObject, selector: String) throws {
    try require(
      !selector.isEmpty && selector.utf8.allSatisfy { $0 >= 33 && $0 <= 126 },
      "Invalid sort block initialization")
    self.accessor = accessor
    self.selector = selector
  }
  private init(copy: SortBlock) {
    accessor = copy.accessor
    selector = copy.selector
  }
  public func copy() -> SortBlock { SortBlock(copy: self) }
  @discardableResult public func fixTemps() -> SortBlock { self }
  public func value(_ first: Value, _ second: Value, graph: Graph? = nil, limits: Limits = Limits())
    throws -> Value
  {
    let left = try accessor.snapshot(limits: limits).readValue(first, graph: graph, limits: limits)
    let right = try accessor.snapshot(limits: limits).readValue(
      second, graph: graph, limits: limits)
    return try send(left, right, graph, limits)
  }
  public func value(_ first: Model, _ second: Model, graph: Graph? = nil, limits: Limits = Limits())
    throws -> Value
  {
    let left = try accessor.snapshot(limits: limits).read(first, graph: graph, limits: limits)
    let right = try accessor.snapshot(limits: limits).read(second, graph: graph, limits: limits)
    return try send(left, right, graph, limits)
  }
  private func send(_ left: Value, _ right: Value, _ graph: Graph?, _ limits: Limits) throws
    -> Value
  {
    var count = selector.filter { $0 == ":" }.count
    if count == 0 && selector.allSatisfy({ "!%&*+,/<=>?@\\~|-".contains($0) }) { count = 1 }
    try require(count == 1, "Sort message requires one argument")
    try checkLocalValue(left, limits: limits)
    try checkLocalValue(right, limits: limits)
    if case .reference = left {
      guard let graph else { throw MagritteError("Binary receiver requires graph resolver") }
      let result = try graph.resolve(left).binaryMessage(selector, argument: right, graph: graph)
      try checkLocalValue(result, limits: limits)
      return result
    }
    let budget = Budget(limits)
    let aKey = try valueKey(left, tick: budget.tick)
    let bKey = try valueKey(right, tick: budget.tick)
    if selector == "=" || selector == "~=" {
      return .boolean(selector == "=" ? aKey == bKey : aKey != bKey)
    }
    try require(
      ["<", "<=", ">", ">="].contains(selector), "Unbound scalar binary selector: " + selector)
    let comparison: Int
    if isNumber(left) && isNumber(right) {
      comparison = try compareNumbers(left, right)
    } else {
      func text(_ value: Value) -> String? {
        switch value {
        case .string(let s), .symbol(let s): return s
        default: return nil
        }
      }
      let a: String
      let b: String
      if let x = text(left), let y = text(right) {
        a = x
        b = y
      } else if case .character(let x) = left, case .character(let y) = right {
        a = x
        b = y
      } else {
        throw MagritteError("Unsupported ordered receiver/argument")
      }
      comparison =
        a.utf8.elementsEqual(b.utf8) ? 0 : a.utf8.lexicographicallyPrecedes(b.utf8) ? -1 : 1
    }
    return .boolean(
      selector == "<"
        ? comparison < 0
        : selector == "<=" ? comparison <= 0 : selector == ">" ? comparison > 0 : comparison >= 0)
  }
}
