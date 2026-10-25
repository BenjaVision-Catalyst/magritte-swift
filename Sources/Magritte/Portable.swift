import Foundation

public struct Predicate {
  public var className = "MAPluggableCondition", selector = ""
  public var receiver: Value = .undefined
  public var arguments: [Value] = []
  public var index = 0
  public var children: [Predicate] = []
  public init(
    selector: String = "", arguments: [Value] = [], receiver: Value = .undefined, index: Int = 0
  ) {
    self.selector = selector
    self.arguments = arguments
    self.receiver = receiver
    self.index = index
  }
  public func check(limits: Limits = Limits()) throws { try checkPredicate(self, Work(limits), 0) }
  public func evaluate(_ value: Value, limits: Limits = Limits()) throws -> Bool {
    var work = 0
    return try evaluatePredicate(self, value, limits: limits, work: &work)
  }
}
public struct PortableCondition {
  public var label: String, predicate: Predicate
  public init(label: String, predicate: Predicate) {
    self.label = label
    self.predicate = predicate
  }
}
public struct Accessor {
  public var className: String, name: String, writeName: String
  public var uuid: Value = .undefined
  public var steps: [Accessor]
  public init(
    className: String = "MADictionaryAccessor", name: String = "", writeName: String = "",
    steps: [Accessor] = []
  ) {
    self.className = className
    self.name = name
    self.writeName = writeName
    self.steps = steps
  }
  public func check(limits: Limits = Limits()) throws { try checkAccessor(self, Work(limits), 0) }
  public func read(_ model: Model, graph: Graph? = nil, limits: Limits = Limits()) throws -> Value {
    let w = Work(limits)
    try checkAccessor(self, w, 0)
    return try accessRead(self, model, graph, w, 0)
  }
  public func write(_ value: Value, to model: Model, graph: Graph? = nil, limits: Limits = Limits())
    throws
  {
    let w = Work(limits)
    try checkAccessor(self, w, 0)
    try accessWrite(self, model, value, graph, w, 0)
  }
}
private final class Work {
  let limits: Limits
  var count: Int
  init(_ limits: Limits, _ count: Int = 0) {
    self.limits = limits
    self.count = count
  }
  func tick(_ depth: Int, _ amount: Int = 1) throws {
    try require(
      amount >= 0 && depth <= limits.depth && count <= limits.visits
        && amount <= limits.visits - count, "Portable interpreter work/depth limit")
    count += amount
  }
  func key(_ value: Value) throws -> String { try valueKey(value, tick: { try self.tick($0) }) }
}
private func portableText(_ value: Value) throws -> String {
  switch value {
  case .string(let s), .symbol(let s): return s
  default: throw MagritteError("Expected text")
  }
}
private func arity(_ selector: String) throws -> Int {
  if ["isNil", "notNil", "isEmpty", "notEmpty", "isInteger", "positive", "negative", "even", "odd"]
    .contains(selector)
  {
    return 0
  }
  if ["=", "~=", "<", "<=", ">", ">=", "includes:", "beginsWith:", "endsWith:"].contains(selector) {
    return 1
  }
  if selector == "between:and:" { return 2 }
  throw MagritteError("Unsupported portable condition selector: \(selector)")
}
private func checkPredicate(_ p: Predicate, _ w: Work, _ depth: Int) throws {
  try w.tick(depth)
  if p.className == "MAPluggableCondition" {
    try require(
      p.arguments.count == arity(p.selector) && p.index >= 0 && p.index <= p.arguments.count
        && p.children.isEmpty, "Invalid pluggable condition shape")
    func constant(_ v: Value, _ depth: Int) throws {
      try w.tick(depth)
      switch v {
      case .reference: throw MagritteError("Condition object constants are unsupported")
      case .array(let a), .collection(_, let a): for e in a { try constant(e, depth + 1) }
      default: break
      }
    }
    for v in [p.receiver] + p.arguments {
      _ = try w.key(v)
      _ = try encodeValue(v, limits: w.limits)
      try constant(v, depth + 1)
    }
  } else {
    try require(
      p.selector.isEmpty && p.arguments.isEmpty && p.index == 0 && p.receiver.isNil,
      "Invalid compound condition shape")
    try require(
      p.className == "MAConjunctiveCondition"
        || (p.className == "MANegationCondition" && p.children.count == 1),
      "Unsupported compound condition")
    for c in p.children { try checkPredicate(c, w, depth + 1) }
  }
}
func checkPortableDescription(_ d: Description, limits: Limits, work: inout Int) throws {
  let w = Work(limits, work)
  try w.tick(0)
  if let accessor = d.accessor { try checkAccessor(accessor, w, 0) }
  for c in d.portableConditions { try checkPredicate(c.predicate, w, 0) }
  work = w.count
}
func evaluatePredicate(_ p: Predicate, _ input: Value, limits: Limits, work: inout Int) throws
  -> Bool
{
  let w = Work(limits, work)
  try checkPredicate(p, w, 0)
  _ = try w.key(input)
  let result = try predicate(p, input, w, 0)
  work = w.count
  return result
}
private func predicate(_ p: Predicate, _ input: Value, _ w: Work, _ depth: Int) throws -> Bool {
  try w.tick(depth)
  if p.className == "MANegationCondition" {
    return try !predicate(p.children[0], input, w, depth + 1)
  }
  if p.className == "MAConjunctiveCondition" {
    for c in p.children { if try !predicate(c, input, w, depth + 1) { return false } }
    return true
  }
  let r = p.index == 0 ? input : p.receiver
  var args = p.arguments
  if p.index > 0 { args[p.index - 1] = input }
  func equal(_ a: Value, _ b: Value) throws -> Bool { try w.key(a) == w.key(b) }
  let s = p.selector
  if s == "isNil" { return r.isNil }
  if s == "notNil" { return !r.isNil }
  if s == "=" { return try equal(r, args[0]) }
  if s == "~=" { return try !equal(r, args[0]) }
  if s == "isInteger" {
    if case .integer = r { return true }
    return false
  }
  if s == "isEmpty" || s == "notEmpty" {
    let empty = try r.collectionCount() == 0
    return s == "isEmpty" ? empty : !empty
  }
  if s == "includes:" {
    try require(r.collectionCount() <= w.limits.visits - w.count, "Condition collection work limit")
    for e in try r.elements() {
      try w.tick(depth)
      if try equal(e, args[0]) { return true }
    }
    return false
  }
  if s == "beginsWith:" || s == "endsWith:" {
    let a = Array(try portableText(r).utf8)
    let b = Array(try portableText(args[0]).utf8)
    try w.tick(depth, a.count + b.count)
    return s == "beginsWith:" ? a.starts(with: b) : a.reversed().starts(with: b.reversed())
  }
  if s == "even" || s == "odd" {
    let even: Bool
    switch r {
    case .integer(let n): even = n % 2 == 0
    case .float(let n):
      try require(n.isFinite, "Non-finite float")
      even = n.truncatingRemainder(dividingBy: 2) == 0
    default: throw MagritteError("Parity requires numeric receiver")
    }
    return s == "even" ? even : !even
  }
  if s == "positive" || s == "negative" {
    let c = try compareNumbers(r, .integer(0))
    return s == "positive" ? c >= 0 : c < 0
  }
  func cmp(_ a: Value, _ b: Value) throws -> Int {
    if isNumber(a) && isNumber(b) { return try compareNumbers(a, b) }
    let x = Array(try portableText(a).utf8)
    let y = Array(try portableText(b).utf8)
    try w.tick(depth, x.count + y.count)
    return x == y ? 0 : x.lexicographicallyPrecedes(y) ? -1 : 1
  }
  if s == "between:and:" { return try cmp(r, args[0]) >= 0 && cmp(r, args[1]) <= 0 }
  let c = try cmp(r, args[0])
  return s == "<" ? c < 0 : s == "<=" ? c <= 0 : s == ">" ? c > 0 : c >= 0
}
private func checkAccessor(_ a: Accessor, _ w: Work, _ depth: Int) throws {
  try w.tick(depth)
  try require(a.className == "MANullAccessor" || a.uuid.isNil, "Unexpected null accessor token")
  _ = try w.key(a.uuid)
  if !a.uuid.isNil {
    guard case .array(let bytes) = a.uuid, bytes.count == 16 else {
      throw MagritteError("Null UUID requires 16 bytes or nil")
    }
    for e in bytes {
      guard case .integer(let b) = e, b >= 0 && b <= 255 else {
        throw MagritteError("Invalid UUID byte")
      }
    }
  }
  if a.className == "MAChainAccessor" {
    try require(
      a.steps.count >= 2 && a.name.isEmpty && a.writeName.isEmpty, "Invalid chain accessor")
    for step in a.steps { try checkAccessor(step, w, depth + 1) }
    return
  }
  try require(a.steps.isEmpty, "Nonchain accessor has steps")
  if a.className == "MAIdentityAccessor" || a.className == "MANullAccessor" {
    try require(a.name.isEmpty && a.writeName.isEmpty, "Unexpected accessor name")
    return
  }
  try require(
    ["MADictionaryAccessor", "MAPropertyAccessor", "MASelectorAccessor", "MAVariableAccessor"]
      .contains(a.className), "Unsupported accessor")
  try require(!a.name.isEmpty, "Missing accessor name")
  try w.tick(depth, a.name.utf8.count + a.writeName.utf8.count)
  try require(
    a.className == "MASelectorAccessor" || a.writeName.isEmpty, "Unexpected write selector")
}
private func accessRead(_ a: Accessor, _ model: Model, _ graph: Graph?, _ w: Work, _ depth: Int)
  throws -> Value
{
  try w.tick(depth)
  if a.className == "MANullAccessor" { throw MagritteError("MAReadError: null accessor") }
  if a.className == "MAIdentityAccessor" {
    guard let graph else {
      throw MagritteError("Identity value access requires graph registration")
    }
    for (id, m) in graph.objects {
      try w.tick(depth)
      if m === model { return .reference(id) }
    }
    for (id, m) in graph.nativeObjects {
      try w.tick(depth)
      if m === model { return .reference(id) }
    }
    throw MagritteError("Identity target is unregistered")
  }
  if a.className != "MAChainAccessor" {
    return try model.readSlot(strategy: a.className, name: a.name)
  }
  var target = model
  var result = Value.undefined
  for (i, step) in a.steps.enumerated() {
    result = try accessRead(step, target, graph, w, depth + 1)
    if i + 1 < a.steps.count {
      guard let graph else { throw MagritteError("Chain requires graph resolver") }
      target = try graph.resolve(result)
    }
  }
  return result
}
private func accessWrite(
  _ a: Accessor, _ model: Model, _ value: Value, _ graph: Graph?, _ w: Work, _ depth: Int
) throws {
  try w.tick(depth)
  if a.className == "MANullAccessor" || a.className == "MAIdentityAccessor" {
    throw MagritteError("MAWriteError: read-only accessor")
  }
  if a.className != "MAChainAccessor" {
    try model.writeSlot(
      strategy: a.className, name: a.className == "MASelectorAccessor" ? a.writeName : a.name,
      value: value)
    return
  }
  var target = model
  for step in a.steps.dropLast() {
    let next = try accessRead(step, target, graph, w, depth + 1)
    guard let graph else { throw MagritteError("Chain requires graph resolver") }
    target = try graph.resolve(next)
  }
  try accessWrite(a.steps.last!, target, value, graph, w, depth + 1)
}
extension DictionaryModel {
  public func readSlot(strategy: String, name: String) throws -> Value {
    try require(strategy == "MADictionaryAccessor", "Dictionary slot requires dictionary accessor")
    return values[name] ?? .undefined
  }
  public func writeSlot(strategy: String, name: String, value: Value) throws {
    try require(strategy == "MADictionaryAccessor", "Dictionary slot requires dictionary accessor")
    values[name] = value
  }
}
extension Description {
  public func readSlot(strategy: String, name: String) throws -> Value {
    try require(strategy == "MAPropertyAccessor", "Description slot requires property accessor")
    return properties[name] ?? .undefined
  }
  public func writeSlot(strategy: String, name: String, value: Value) throws {
    try require(strategy == "MAPropertyAccessor", "Description slot requires property accessor")
    properties[name] = value
  }
}
extension NativeModel {
  public func readSlot(strategy: String, name: String) throws -> Value {
    try require(
      ["MASelectorAccessor", "MAVariableAccessor", "MAPropertyAccessor"].contains(strategy),
      "Unsupported native binding strategy")
    guard let f = readers[strategy + ":" + name] else {
      throw MagritteError("Unbound native accessor read")
    }
    return try f(object)
  }
  public func writeSlot(strategy: String, name: String, value: Value) throws {
    try require(
      ["MASelectorAccessor", "MAVariableAccessor", "MAPropertyAccessor"].contains(strategy),
      "Unsupported native binding strategy")
    guard let f = writers[strategy + ":" + name] else {
      throw MagritteError("Unbound native accessor write")
    }
    try f(object, value)
  }
}
func isNumber(_ v: Value) -> Bool {
  switch v {
  case .integer, .float: return true
  default: return false
  }
}
func compareNumbers(_ a: Value, _ b: Value) throws -> Int {
  switch (a, b) {
  case (.integer(let x), .integer(let y)): return x < y ? -1 : x > y ? 1 : 0
  case (.float, .integer): return try -compareNumbers(b, a)
  case (.integer(let x), .float(let y)):
    try require(y.isFinite, "Non-finite float")
    if y >= 9223372036854775808.0 { return -1 }
    if y < -9223372036854775808.0 { return 1 }
    let truncated = Int64(y)
    if x != truncated { return x < truncated ? -1 : 1 }
    return y > Double(truncated) ? -1 : y < Double(truncated) ? 1 : 0
  case (.float(let x), .float(let y)):
    try require(x.isFinite && y.isFinite, "Non-finite float")
    return x < y ? -1 : x > y ? 1 : 0
  default: throw MagritteError("Numeric comparison requires numbers")
  }
}
func floatBits(_ n: Double) throws -> String {
  try require(n.isFinite, "Non-finite float")
  return String(format: "%016llx", n.bitPattern)
}
func floatFromBits(_ s: String) throws -> Double {
  try require(
    s.utf8.count == 16 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) },
    "Expected canonical 16 hex float bits")
  guard let bits = UInt64(s, radix: 16) else { throw MagritteError("Invalid float bits") }
  let n = Double(bitPattern: bits)
  try require(n.isFinite, "Non-finite float")
  return n
}
func floatText(_ n: Double) throws -> String {
  try require(n.isFinite, "Non-finite float")
  let negative = n.sign == .minus
  var s = String(abs(n)).lowercased()
  var exponent = 0
  if let e = s.firstIndex(of: "e") {
    exponent = Int(s[s.index(after: e)...])!
    s = String(s[..<e])
  }
  let parts = s.split(separator: ".", omittingEmptySubsequences: false)
  let before = parts[0].count
  var digits = Array(s.filter { $0 != "." })
  var point = before + exponent
  while digits.count > 1 && digits.first == "0" {
    digits.removeFirst()
    point -= 1
  }
  while digits.count > 1 && digits.last == "0" { digits.removeLast() }
  if n == 0 { point = 1 }
  exponent = point - 1
  let raw = String(digits)
  let sign = negative ? "-" : ""
  if exponent >= 6 || exponent <= -5 {
    return sign + String(digits[0]) + "." + (digits.count == 1 ? "0" : String(digits.dropFirst()))
      + "e" + String(exponent)
  }
  if point <= 0 { return sign + "0." + String(repeating: "0", count: -point) + raw }
  if point >= digits.count {
    return sign + raw + String(repeating: "0", count: point - digits.count) + ".0"
  }
  return sign + String(digits.prefix(point)) + "." + String(digits.dropFirst(point))
}
private func propText(_ d: Description, _ name: String) throws -> String {
  let v = d.property(name)
  return v.isNil ? "" : try portableText(v)
}
private func read(_ d: Description, _ input: String, _ w: Work, _ depth: Int, _ initial: Bool)
  throws -> Value
{
  try w.tick(depth, input.utf8.count + 1)
  let undef = try propText(d, "undefined")
  if initial && (input.isEmpty || (!undef.isEmpty && input.utf8.starts(with: undef.utf8))) {
    return .undefined
  }
  switch d.className {
  case "MASymbolDescription": return .symbol(input)
  case "MAStringDescription", "MAMemoDescription", "MAPasswordDescription": return .string(input)
  case "MABooleanDescription":
    func lower(_ s: String) throws -> String {
      try require(s.utf8.allSatisfy { $0 < 128 }, "Non-ASCII Boolean alias comparison unsupported")
      return s.lowercased()
    }
    for (single, aliases, yes) in [
      ("trueString", "trueStrings", true), ("falseString", "falseStrings", false),
    ] {
      if try input.utf8.elementsEqual(propText(d, single).utf8) { return .boolean(yes) }
      for alias in try d.property(aliases).elements() {
        let s = try portableText(alias)
        try w.tick(depth, s.utf8.count)
        if try lower(s) == lower(input) { return .boolean(yes) }
      }
    }
    throw MagritteError("MAReadError: Boolean text")
  case "MANumberDescription":
    guard case .character(let sep) = d.property("thousandsSeparator"), sep.unicodeScalars.count == 1
    else { throw MagritteError("Expected thousands separator") }
    let s = input.components(separatedBy: sep).joined()
    let bytes = Array(s.utf8)
    var i = bytes.first == 45 ? 1 : 0
    func digits() -> Bool {
      let start = i
      while i < bytes.count && (48...57).contains(bytes[i]) { i += 1 }
      return i > start
    }
    try require(digits(), "MAReadError: numeric syntax")
    var fraction = false
    var exponent = ""
    if i < bytes.count && bytes[i] == 46 {
      fraction = true
      i += 1
      try require(digits(), "MAReadError: numeric fraction")
    }
    if i < bytes.count && bytes[i] == 101 {
      i += 1
      let start = i
      if i < bytes.count && bytes[i] == 45 { i += 1 }
      try require(digits(), "MAReadError: numeric exponent")
      exponent = String(decoding: bytes[start..<i], as: UTF8.self)
    }
    try require(i == bytes.count, "MAReadError: numeric syntax outside portable decimal grammar")
    if !fraction && (exponent.isEmpty || !exponent.hasPrefix("-")) {
      let zeros = exponent.isEmpty ? 0 : Int(exponent) ?? 20
      try require(zeros <= 19, "MAReadError: exponent outside Int64")
      let integer = s.split(separator: "e")[0] + String(repeating: "0", count: zeros)
      guard let n = Int64(integer) else {
        throw MagritteError("MAReadError: integer outside Int64")
      }
      return .integer(n)
    }
    guard let n = Double(s), n.isFinite else {
      throw MagritteError("MAReadError: float outside finite binary64")
    }
    if n == 0 {
      try require(
        !s.split(separator: "e")[0].utf8.contains { (49...57).contains($0) },
        "MAReadError: nonzero float underflow")
    }
    return .float(n)
  case "MASingleOptionDescription":
    var matched: Value?
    for label in d.labels {
      try w.tick(depth, label.label.utf8.count + 1)
      if !label.label.isEmpty && input.utf8.starts(with: label.label.utf8) {
        try require(matched == nil, "Ambiguous option label prefix")
        matched = label.value
      }
    }
    if let matched { return matched }
    return try read(d.referenceDescription(), input, w, depth + 1, false)
  case "MATokenDescription":
    let separators = Set(try propText(d, "separators").unicodeScalars)
    let ref = try d.referenceDescription()
    var result: [Value] = []
    var token = ""
    for c in input.unicodeScalars {
      try w.tick(depth)
      if !separators.contains(c) {
        token.unicodeScalars.append(c)
      } else if !token.isEmpty {
        result.append(try read(ref, token, w, depth + 1, true))
        token = ""
      }
    }
    if !token.isEmpty { result.append(try read(ref, token, w, depth + 1, true)) }
    return .array(result)
  case "MAMultipleOptionDescription":
    let chars = Array(input.unicodeScalars)
    let ref = try d.referenceDescription()
    var start = 0
    var result: [Value] = []
    while start < chars.count {
      var end = start
      while end < chars.count && chars[end] != "," { end += 1 }
      result.append(
        try read(ref, String(String.UnicodeScalarView(chars[start..<end])), w, depth + 1, true))
      start = end + 1
      if start < chars.count && chars[start] == " " { start += 1 }
    }
    return .array(result)
  default: throw MagritteError("MAReadError: unsupported string reader description")
  }
}
private func writeModel(_ d: Description, _ model: Model, _ graph: Graph?, _ w: Work, _ depth: Int)
  throws -> String
{
  try w.tick(depth)
  try require(d.isContainer, "Model writer requires container")
  var result = ""
  var first = true
  for child in try d.orderedChildren() {
    if !first { result += "-" }
    first = false
    if try !child.flag("visible") { continue }
    if child.isContainer && !(model is AdaptiveModel) && child.nativeRead == nil
      && (child.accessor == nil || child.accessor?.className == "MAIdentityAccessor")
    {
      result += try writeModel(child, model, graph, w, depth + 1)
    } else {
      result += try write(child, model.read(using: child), graph, w, depth + 1, true)
    }
    try require(result.utf8.count <= w.limits.bytes, "String output byte limit")
  }
  return result
}
private func write(
  _ d: Description, _ value: Value, _ graph: Graph?, _ w: Work, _ depth: Int, _ initial: Bool
) throws -> String {
  try w.tick(depth)
  var result = ""
  if initial && value.isNil {
    result = try propText(d, "undefined")
  } else if d.isContainer {
    guard let graph else { throw MagritteError("Container writer requires graph resolver") }
    result = try writeModel(d, graph.resolve(value), graph, w, depth + 1)
  } else if d.className == "MABooleanDescription" {
    guard case .boolean(let b) = value else {
      throw MagritteError("Boolean writer requires Boolean")
    }
    result = try propText(d, b ? "trueString" : "falseString")
  } else if d.className == "MASingleOptionDescription" {
    var found = false
    for label in d.labels {
      try w.tick(depth)
      try require(portableLabelKey(label.value), "Nonportable label key")
      if try sameLabelType(value, label.value) && w.key(value) == w.key(label.value) {
        result = label.label
        found = true
        break
      }
    }
    if !found { result = try displayString(value) }
  } else if d.className == "MATokenDescription" || d.isMultiple {
    try require(
      value.collectionCount() <= w.limits.visits - w.count, "Writer collection work limit")
    let ref = try d.referenceDescription()
    var sep = ", "
    if try d.className == "MATokenDescription" && value.collectionCount() > 1 {
      guard let c = try propText(d, "separators").unicodeScalars.first else {
        throw MagritteError("Token writer requires separator")
      }
      sep = String(c)
    }
    if try d.className == "MAMultipleOptionDescription" && value.collectionCount() == 0 {
      result = try propText(d, "undefined")
    } else {
      var first = true
      for e in try value.elements() {
        if !first { result += sep }
        first = false
        if d.isOption {
          var found = false
          for label in d.labels {
            try w.tick(depth)
            try require(portableLabelKey(label.value), "Nonportable label key")
            if try sameLabelType(e, label.value) && w.key(e) == w.key(label.value) {
              result += label.label
              found = true
              break
            }
          }
          if !found { result += try displayString(e) }
        } else {
          result += try write(ref, e, graph, w, depth + 1, d.className != "MATokenDescription")
        }
        try require(result.utf8.count <= w.limits.bytes, "String output byte limit")
      }
    }
  } else if d.isRelation {
    result = try write(d.referenceDescription(), value, graph, w, depth + 1, true)
  } else {
    switch value {
    case .undefined: result = "nil"
    case .string(let s), .symbol(let s), .character(let s): result = s
    case .integer(let i): result = String(i)
    case .float(let n): result = try floatText(n)
    case .boolean(let b): result = b ? "true" : "false"
    default: throw MagritteError("Unsupported display string")
    }
  }
  try w.tick(depth, result.utf8.count)
  try require(result.utf8.count <= w.limits.bytes, "String output byte limit")
  return result
}
/// MAStringReader; parsing does not validate, enforce UI flags or apply defaults.
public func readString(_ input: String, using d: Description, limits: Limits = Limits()) throws
  -> Value
{
  try require(input.utf8.count <= limits.bytes, "String input byte limit")
  var work = 0
  try visit(d, limits: limits) {
    try supported($0)
    try checkPortableDescription($0, limits: limits, work: &work)
  }
  return try read(d, input, Work(limits, work), 0, true)
}
public func writeString(
  _ value: Value, using d: Description, graph: Graph? = nil, limits: Limits = Limits()
) throws -> String {
  var work = 0
  try visit(d, limits: limits) {
    try supported($0)
    try checkPortableDescription($0, limits: limits, work: &work)
  }
  return try write(d, value, graph, Work(limits, work), 0, true)
}
public func writeString(
  _ model: Model, using d: Description, graph: Graph? = nil, limits: Limits = Limits()
) throws -> String {
  var work = 0
  try visit(d, limits: limits) {
    try supported($0)
    try checkPortableDescription($0, limits: limits, work: &work)
  }
  return try writeModel(d, model, graph, Work(limits, work), 0)
}

func predicateWire(_ p: Predicate, _ limits: Limits, _ depth: Int = 0) throws -> [String: Any] {
  try require(depth <= limits.depth, "Condition depth limit")
  if p.className == "MAPluggableCondition" {
    return [
      "class": p.className, "selector": p.selector, "receiver": try wire(p.receiver, limits),
      "arguments": try p.arguments.map { try wire($0, limits) }, "index": p.index,
    ]
  }
  return [
    "class": p.className,
    "conditions": try p.children.map { try predicateWire($0, limits, depth + 1) },
  ]
}
func predicateValue(_ any: Any, _ limits: Limits, _ depth: Int = 0) throws -> Predicate {
  try require(depth <= limits.depth, "Condition depth limit")
  let j = try dictionary(any)
  var p = Predicate()
  p.className = try text(j["class"])
  if p.className == "MAPluggableCondition" {
    try keys(j, ["class", "selector", "receiver", "arguments", "index"])
    p.selector = try text(j["selector"])
    guard let r = j["receiver"], let index = j["index"] as? NSNumber,
      CFGetTypeID(index) != CFBooleanGetTypeID(),
      index.doubleValue >= 0,
      index.doubleValue < Double(Int.max),
      index.doubleValue.rounded(.towardZero) == index.doubleValue
    else { throw MagritteError("Expected condition index") }
    p.index = index.intValue
    p.receiver = try value(r, limits)
    p.arguments = try list(j["arguments"]).map { try value($0, limits) }
  } else {
    try keys(j, ["class", "conditions"])
    p.children = try list(j["conditions"]).map { try predicateValue($0, limits, depth + 1) }
  }
  try p.check(limits: limits)
  return p
}
func accessorWire(_ a: Accessor, _ limits: Limits, _ depth: Int = 0) throws -> [String: Any] {
  try require(depth <= limits.depth, "Accessor depth limit")
  var j: [String: Any] = ["class": a.className]
  switch a.className {
  case "MANullAccessor": j["uuid"] = try wire(a.uuid, limits)
  case "MAChainAccessor": j["steps"] = try a.steps.map { try accessorWire($0, limits, depth + 1) }
  case "MASelectorAccessor":
    j["readSelector"] = a.name
    j["writeSelector"] = a.writeName
  case "MADictionaryAccessor", "MAPropertyAccessor": j["key"] = a.name
  case "MAVariableAccessor": j["name"] = a.name
  default: break
  }
  return j
}
func accessorValue(_ any: Any, _ limits: Limits, _ depth: Int = 0) throws -> Accessor {
  try require(depth <= limits.depth, "Accessor depth limit")
  let j = try dictionary(any)
  var a = Accessor(className: try text(j["class"]))
  switch a.className {
  case "MANullAccessor":
    try keys(j, ["class", "uuid"])
    guard let v = j["uuid"] else { throw MagritteError("Missing null token") }
    a.uuid = try value(v, limits)
  case "MAChainAccessor":
    try keys(j, ["class", "steps"])
    a.steps = try list(j["steps"]).map { try accessorValue($0, limits, depth + 1) }
  case "MASelectorAccessor":
    try keys(j, ["class", "readSelector", "writeSelector"])
    a.name = try identity(j["readSelector"])
    a.writeName = try text(j["writeSelector"])
    if !a.writeName.isEmpty { _ = try identity(j["writeSelector"]) }
  case "MADictionaryAccessor", "MAPropertyAccessor":
    try keys(j, ["class", "key"])
    a.name = try identity(j["key"])
  case "MAVariableAccessor":
    try keys(j, ["class", "name"])
    a.name = try identity(j["name"])
  default: try keys(j, ["class"])
  }
  try a.check(limits: limits)
  return a
}

public func decodePredicate(_ data: Data, limits: Limits = Limits()) throws -> Predicate {
  try predicateValue(parse(data, limits), limits)
}
public func encodePredicate(_ p: Predicate, limits: Limits = Limits()) throws -> Data {
  try p.check(limits: limits)
  let data = try JSONSerialization.data(
    withJSONObject: predicateWire(p, limits), options: .sortedKeys)
  _ = try decodePredicate(data, limits: limits)
  return data
}
public func decodeAccessor(_ data: Data, limits: Limits = Limits()) throws -> Accessor {
  try accessorValue(parse(data, limits), limits)
}
public func encodeAccessor(_ a: Accessor, limits: Limits = Limits()) throws -> Data {
  try a.check(limits: limits)
  let data = try JSONSerialization.data(
    withJSONObject: accessorWire(a, limits), options: .sortedKeys)
  _ = try decodeAccessor(data, limits: limits)
  return data
}

func displayString(_ value: Value) throws -> String {
  switch value {
  case .undefined: return "nil"
  case .string(let s), .symbol(let s), .character(let s): return s
  case .integer(let i): return String(i)
  case .float(let n): return try floatText(n)
  case .boolean(let b): return b ? "true" : "false"
  default: throw MagritteError("Unsupported display string")
  }
}

extension Description {
  public func obfuscated(_ value: Value, limits: Limits = Limits()) throws -> String {
    try require(className == "MAPasswordDescription", "Obfuscation requires password description")
    return String(
      repeating: "*",
      count: try writeString(value, using: self, limits: limits).unicodeScalars.count)
  }
  public func isObfuscated(_ value: Value) throws -> Bool {
    try require(className == "MAPasswordDescription", "Obfuscation requires password description")
    switch value {
    case .string(let s), .symbol(let s):
      return !s.isEmpty && s.unicodeScalars.allSatisfy { $0 == "*" }
    default: return false
    }
  }
}
