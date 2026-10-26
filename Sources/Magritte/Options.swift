import Foundation

/// MADynamicOptions preserves separate live completion, membership and conversion callbacks.
public final class DynamicOptions {
  public var block: ((String) throws -> Value)?
  public var includesBlock: ((Value) throws -> Bool)?
  public var reader: ((Value) throws -> Value)?
  public init(block: ((String) throws -> Value)? = nil) { self.block = block }
  public func allOptionsFor(_ description: Description) -> DynamicOptions { self }
  public func selectMatching(_ query: String, limits: Limits = Limits()) throws -> Value {
    _ = try encodeValue(.string(query), limits: limits)
    guard let block else { throw MagritteError("Dynamic options completion block is missing") }
    let result = try block(query)
    try checkLocalValue(result, limits: limits)
    return result
  }
  public func includes(_ value: Value, limits: Limits = Limits()) throws -> Bool {
    try checkLocalValue(value, limits: limits)
    guard let includesBlock else {
      throw MagritteError("Dynamic options includes block is missing")
    }
    return try includesBlock(value)
  }
  public func detect(_ value: Value, limits: Limits = Limits()) throws -> Value {
    try checkLocalValue(value, limits: limits)
    let result = try reader?(value) ?? value
    try checkLocalValue(result, limits: limits)
    return result
  }
  public func copy() -> DynamicOptions {
    let result = DynamicOptions(block: block)
    result.includesBlock = includesBlock
    result.reader = reader
    return result
  }
}
public enum OptionItem: Equatable {
  case value(Value)
  case provider(DynamicOptions)
  public static func == (lhs: OptionItem, rhs: OptionItem) -> Bool {
    switch (lhs, rhs) {
    case (.value(let a), .value(let b)): return a == b
    case (.provider(let a), .provider(let b)): return a === b
    default: return false
    }
  }
}
/// Magritte options can be a collection or a live provider; neither is implicitly enumerated.
public enum Options: Equatable, ExpressibleByArrayLiteral {
  case collection([OptionItem])
  case dynamic(DynamicOptions)
  public init(_ values: [Value]) { self = .collection(values.map(OptionItem.value)) }
  public init(arrayLiteral elements: Value...) { self.init(elements) }
  public var isDynamic: Bool {
    if case .dynamic = self { return true }
    return false
  }
  public func provider() throws -> DynamicOptions {
    guard case .dynamic(let source) = self else {
      throw MagritteError("Options are a collection, not a provider")
    }
    return source
  }
  public func entries() throws -> [OptionItem] {
    guard case .collection(let items) = self else {
      throw MagritteError("Dynamic options are not an enumerable collection")
    }
    return items
  }
  public func values(limits: Limits = Limits()) throws -> [Value] {
    let items = try entries()
    try require(items.count <= limits.items, "Options item limit")
    return try items.map {
      guard case .value(let value) = $0 else {
        throw MagritteError("Local dynamic provider entry is not a portable Value")
      }
      return value
    }
  }
  public var count: Int { get throws { try entries().count } }
  public mutating func append(_ value: Value) throws {
    var items = try entries()
    items.append(.value(value))
    self = .collection(items)
  }
  public mutating func removeLast() throws {
    var items = try entries()
    try require(!items.isEmpty, "Empty options collection")
    items.removeLast()
    self = .collection(items)
  }
  public func copy() -> Options {
    if case .dynamic(let source) = self { return .dynamic(source.copy()) }
    return self
  }
  public func selectMatching(_ query: String, limits: Limits = Limits()) throws -> Value {
    if case .dynamic(let source) = self { return try source.selectMatching(query, limits: limits) }
    _ = try encodeValue(.string(query), limits: limits)
    var work = 0
    let result = try values(limits: limits).filter { value in
      _ = try valueKey(value) { depth in
        work += 1
        try require(
          work <= limits.visits && depth <= limits.depth, "Options matching work/depth limit")
      }
      return try displayString(value).utf8.starts(with: query.utf8)
    }
    let value = Value.array(result)
    try checkLocalValue(value, limits: limits)
    return value
  }
  public static func == (lhs: Options, rhs: Options) -> Bool {
    switch (lhs, rhs) {
    case (.collection(let a), .collection(let b)): return a == b
    case (.dynamic(let a), .dynamic(let b)): return a === b
    default: return false
    }
  }
}
