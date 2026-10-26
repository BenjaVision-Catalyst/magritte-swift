import Foundation

private func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 {
  var x = a
  var y = b
  while y != 0 {
    let r = x % y
    x = y
    y = r
  }
  return x
}
func fractionOf(_ v: Value) throws -> (Int64, Int64) {
  switch v {
  case .integer(let n): return (n, 1)
  case .fraction(let n, let d):
    try require(d > 0, "Fraction denominator must be positive")
    let g = gcd(n.magnitude, UInt64(d))
    return (n / Int64(g), d / Int64(g))
  case .float(let n):
    if let f = try floatFraction(n) { return f }
    fallthrough
  default: throw MagritteError("Priority cannot be represented as bounded exact fraction")
  }
}
func floatFraction(_ n: Double) throws -> (Int64, Int64)? {
  try require(n.isFinite, "Non-finite float")
  if n == 0 { return (0, 1) }
  let bits = n.bitPattern
  let raw = Int((bits >> 52) & 2047)
  var mantissa = bits & 0x000f_ffff_ffff_ffff
  var exp = raw == 0 ? -1074 : raw - 1023 - 52
  if raw != 0 { mantissa |= 1 << 52 }
  while mantissa & 1 == 0 {
    mantissa >>= 1
    exp += 1
  }
  if exp < 0 {
    if -exp > 62 || mantissa > UInt64(Int64.max) { return nil }
    return (n < 0 ? -Int64(mantissa) : Int64(mantissa), Int64(1) << (-exp))
  }
  if exp > 62 || mantissa > (UInt64(Int64.max) >> exp) { return nil }
  return (n < 0 ? -Int64(mantissa << exp) : Int64(mantissa << exp), 1)
}
extension Value {
  public static func rational(_ numerator: Int64, _ denominator: Int64) throws -> Value {
    let f = try fractionOf(.fraction(numerator: numerator, denominator: denominator))
    return f.1 == 1 ? .integer(f.0) : .fraction(numerator: f.0, denominator: f.1)
  }
}
private func positiveCompare(_ a: UInt64, _ b: UInt64, _ c: UInt64, _ d: UInt64) -> Int {
  var a = a
  var b = b
  var c = c
  var d = d
  var direction = 1
  while true {
    let x = a / b
    let y = c / d
    if x != y { return (x < y ? -1 : 1) * direction }
    let r = a % b
    let s = c % d
    if r == 0 || s == 0 { return (r == s ? 0 : r == 0 ? -1 : 1) * direction }
    a = b
    b = r
    c = d
    d = s
    direction = -direction
  }
}
private func fractionFloat(_ x: (Int64, Int64), _ y: Double) throws -> Int {
  try require(y.isFinite, "Non-finite float")
  if x.0 < 0 && y >= 0 { return -1 }
  if x.0 >= 0 && y < 0 { return 1 }
  let negative = x.0 < 0
  let n = x.0.magnitude
  let d = UInt64(x.1)
  var f = abs(y)
  if f >= 18446744073709551616.0 { return negative ? 1 : -1 }
  let integer = UInt64(f)
  let q = n / d
  var result = 0
  if q != integer {
    result = q < integer ? -1 : 1
  } else {
    var r = n % d
    f -= Double(integer)
    while r != 0 || f != 0 {
      r *= 2
      f *= 2
      let bit = r >= d
      let other = f >= 1
      if bit != other {
        result = bit ? 1 : -1
        break
      }
      if bit { r -= d }
      if other { f -= 1 }
    }
  }
  return negative ? -result : result
}
func compareFractions(_ a: Value, _ b: Value) throws -> Int {
  if case .float(let n) = a { return try -fractionFloat(fractionOf(b), n) }
  if case .float(let n) = b { return try fractionFloat(fractionOf(a), n) }
  let x = try fractionOf(a)
  let y = try fractionOf(b)
  if x.0 < 0 && y.0 >= 0 { return -1 }
  if x.0 >= 0 && y.0 < 0 { return 1 }
  let r = positiveCompare(x.0.magnitude, UInt64(x.1), y.0.magnitude, UInt64(y.1))
  return x.0 < 0 ? -r : r
}
func flattenedPriority(_ parent: Value, _ child: Value) throws -> Value {
  let a = try fractionOf(parent)
  var b = try fractionOf(child)
  func mul(_ x: Int64, _ y: Int64) throws -> Int64 {
    let r = x.multipliedReportingOverflow(by: y)
    try require(!r.overflow, "Fraction priority overflow")
    return r.partialValue
  }
  let g = Int64(gcd(b.0.magnitude, 1000))
  b.0 /= g
  b.1 = try mul(b.1, 1000 / g)
  let common = Int64(gcd(UInt64(a.1), UInt64(b.1)))
  let left = try mul(a.0, b.1 / common)
  let right = try mul(b.0, a.1 / common)
  let sum = left.addingReportingOverflow(right)
  try require(!sum.overflow, "Fraction priority overflow")
  return try .rational(sum.partialValue, mul(a.1, b.1 / common))
}
extension Description {
  public func priorityValue() throws -> Value {
    let p = try property("priority")
    try require(isNumber(p), "Expected numeric priority")
    return p
  }
}
