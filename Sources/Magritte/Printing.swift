import Foundation

/// A bounded native bridge for the WriteStream used by Magritte printing.
public final class PrintStream {
  public let limits: Limits
  public private(set) var contents = ""
  private var work = 0
  public init(limits: Limits = Limits()) { self.limits = limits }
  public func append(_ text: String) throws {
    let size = text.utf8.count
    let current = contents.utf8.count
    try require(
      current <= limits.bytes && size <= limits.bytes - current, "Print output byte limit")
    try require(work < limits.visits && size < limits.visits - work, "Print output work limit")
    var validation = limits
    validation.bytes = Int.max
    try checkLocalValue(.string(text), limits: validation)
    contents += text
    work += size + 1
  }
}
public final class PrintValueBlock {
  fileprivate let operation: (Value) throws -> String
  public init(_ operation: @escaping (Value) throws -> String) { self.operation = operation }
  public convenience init(_ operation: @escaping () throws -> String) {
    self.init { _ in try operation() }
  }
}
public final class PrintSeparatorBlock {
  fileprivate let operation: (PrintStream) throws -> Void
  public init(_ operation: @escaping (PrintStream) throws -> Void) { self.operation = operation }
  public convenience init(_ operation: @escaping () throws -> Void) {
    self.init { _ in try operation() }
  }
}
extension Description {
  @discardableResult public func setPrintString(
    _ block: PrintValueBlock?, limits: Limits = Limits()
  ) throws -> Description {
    try propertyPut("maPrintString", .undefined, limits: limits)
    printStringBlock = block
    if block == nil { properties.removeValue(forKey: "maPrintString") }
    return self
  }
  @discardableResult public func setPrintSeparator(
    _ block: PrintSeparatorBlock?, limits: Limits = Limits()
  ) throws -> Description {
    try require(isContainer, "Print separator requires a container")
    try propertyPut("maPrintStringSeparator", .undefined, limits: limits)
    printSeparatorBlock = block
    if block == nil { properties.removeValue(forKey: "maPrintStringSeparator") }
    return self
  }
  public func readToString(_ model: Model, graph: Graph? = nil, limits: Limits = Limits()) throws
    -> String
  {
    let value = try model.read(using: self)
    return try writeString(value, using: self, graph: graph, limits: limits)
  }
  public func printFor(_ model: Model, on stream: PrintStream, graph: Graph? = nil) throws {
    try require(
      ClassRegistry.shared.includesBehavior(className, "MAElementDescription"),
      "printFor requires an element description")
    let value = try model.read(using: self)
    if !value.isNil {
      try stream.append(writeString(value, using: self, graph: graph, limits: stream.limits))
    }
  }
  public func print(_ model: Model, on stream: PrintStream, graph: Graph? = nil) throws {
    try require(isContainer, "print requires a container")
    let separator = printSeparatorBlock
    let hasSeparator = hasProperty("maPrintStringSeparator")
    let fields = try enumerationChildren(self, limits: stream.limits)
    for (index, field) in fields.enumerated() {
      if index > 0 {
        if let separator {
          try separator.operation(stream)
        } else if hasSeparator {
          throw MagritteError("Print separator has no local callable representation")
        } else {
          try stream.append(" ")
        }
      }
      let value = try model.read(using: field)
      if value.isNil { continue }
      let budget = Budget(stream.limits)
      _ = try valueKey(value, tick: budget.tick)
      var validation = stream.limits
      validation.bytes = Int.max
      try checkLocalValue(value, limits: validation)
      if let block = field.printStringBlock {
        try stream.append(block.operation(value))
      } else if field.hasProperty("maPrintString") {
        throw MagritteError("Print formatter has no local callable representation")
      } else {
        try stream.append(writeString(value, using: field, graph: graph, limits: stream.limits))
      }
    }
  }
}
