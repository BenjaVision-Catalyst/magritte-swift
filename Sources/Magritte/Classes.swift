import Foundation

public struct ClassInfo: Equatable, Sendable {
  public let name: String, superclass: String?, isAbstract: Bool, label: String
  public static func == (a: ClassInfo, b: ClassInfo) -> Bool {
    a.name == b.name && a.superclass == b.superclass && a.isAbstract == b.isAbstract
      && a.label.utf8.elementsEqual(b.label.utf8)
  }

  public init(
    name: String, superclass: String? = "Object", isAbstract: Bool = false, label: String? = nil
  ) {
    self.name = name
    self.superclass = superclass
    self.isAbstract = isAbstract
    self.label = label ?? name
  }
}
/// The process's registered class environment. Definitions are immutable once published.
public final class ClassRegistry: @unchecked Sendable {
  public static let shared = ClassRegistry()
  private let lock = NSLock()
  private var classes: [String: ClassInfo] = [:], types: [ObjectIdentifier: String] = [:],
    names: [String: ObjectIdentifier] = [:]
  private init() {
    try! registerClasses([
      ClassInfo(name: "Array", superclass: "ArrayedCollection", isAbstract: false, label: "Array"),
      ClassInfo(
        name: "ArrayedCollection", superclass: "SequenceableCollection", isAbstract: true,
        label: "Arrayed Collection"),
      ClassInfo(name: "Bag", superclass: "Collection", isAbstract: false, label: "Bag"),
      ClassInfo(name: "Behavior", superclass: "Object", isAbstract: false, label: "Behavior"),
      ClassInfo(name: "Boolean", superclass: "Object", isAbstract: false, label: "Boolean"),
      ClassInfo(name: "Character", superclass: "Magnitude", isAbstract: false, label: "Character"),
      ClassInfo(name: "Class", superclass: "ClassDescription", isAbstract: false, label: "Class"),
      ClassInfo(
        name: "ClassDescription", superclass: "Behavior", isAbstract: true,
        label: "Class Description"),
      ClassInfo(name: "Collection", superclass: "Object", isAbstract: true, label: "Collection"),
      ClassInfo(name: "Float", superclass: "Number", isAbstract: true, label: "Float"),
      ClassInfo(name: "GRObject", superclass: "Object", isAbstract: false, label: "Object"),
      ClassInfo(
        name: "HashedCollection", superclass: "Collection", isAbstract: true,
        label: "Hashed Collection"),
      ClassInfo(name: "Integer", superclass: "Number", isAbstract: true, label: "Integer"),
      ClassInfo(name: "MAAccessor", superclass: "MAObject", isAbstract: true, label: "Accessor"),
      ClassInfo(
        name: "MAAdaptiveModel", superclass: "MABasicObject", isAbstract: false,
        label: "Adaptive Model"),
      ClassInfo(
        name: "MABasicObject", superclass: "GRObject", isAbstract: false, label: "Basic Object"),
      ClassInfo(
        name: "MABooleanDescription", superclass: "MAElementDescription", isAbstract: false,
        label: "Boolean"),
      ClassInfo(
        name: "MACachedMemento", superclass: "MAMemento", isAbstract: false, label: "Cached Memento"
      ),
      ClassInfo(
        name: "MAChainAccessor", superclass: "MADelegatorAccessor", isAbstract: false,
        label: "Chain Accessor"),
      ClassInfo(
        name: "MACheckedMemento", superclass: "MACachedMemento", isAbstract: false,
        label: "Checked Memento"),
      ClassInfo(
        name: "MAClassDescription", superclass: "MAElementDescription", isAbstract: false,
        label: "Class"),
      ClassInfo(name: "MACondition", superclass: "MAObject", isAbstract: true, label: "Condition"),
      ClassInfo(
        name: "MAConjunctiveCondition", superclass: "MACondition", isAbstract: false,
        label: "Conjunctive Condition"),
      ClassInfo(
        name: "MAContainer", superclass: "MADescription", isAbstract: false, label: "Container"),
      ClassInfo(
        name: "MADelegatorAccessor", superclass: "MAAccessor", isAbstract: false,
        label: "Delegator Accessor"),
      ClassInfo(
        name: "MADescription", superclass: "MAObject", isAbstract: true, label: "Description"),
      ClassInfo(
        name: "MADictionaryAccessor", superclass: "MAAccessor", isAbstract: false,
        label: "Dictionary Accessor"),
      ClassInfo(
        name: "MAElementDescription", superclass: "MADescription", isAbstract: true,
        label: "Element Description"),
      ClassInfo(
        name: "MAIdentityAccessor", superclass: "MAAccessor", isAbstract: false,
        label: "Identity Accessor"),
      ClassInfo(
        name: "MAMagnitudeDescription", superclass: "MAElementDescription", isAbstract: true,
        label: "Magnitude Description"),
      ClassInfo(name: "MAMemento", superclass: "MAObject", isAbstract: true, label: "Memento"),
      ClassInfo(
        name: "MAMemoDescription", superclass: "MAStringDescription", isAbstract: false,
        label: "Memo"),
      ClassInfo(
        name: "MAMultipleOptionDescription", superclass: "MAOptionDescription", isAbstract: false,
        label: "Multiple-Option"),
      ClassInfo(
        name: "MANegationCondition", superclass: "MACondition", isAbstract: false,
        label: "Negation Condition"),
      ClassInfo(
        name: "MANullAccessor", superclass: "MAAccessor", isAbstract: false, label: "Null Accessor"),
      ClassInfo(
        name: "MANumberDescription", superclass: "MAMagnitudeDescription", isAbstract: false,
        label: "Number"),
      ClassInfo(name: "MAObject", superclass: "MABasicObject", isAbstract: true, label: "Object"),
      ClassInfo(
        name: "MAOptionDescription", superclass: "MAReferenceDescription", isAbstract: true,
        label: "Option Description"),
      ClassInfo(
        name: "MAPasswordDescription", superclass: "MAStringDescription", isAbstract: false,
        label: "Password"),
      ClassInfo(
        name: "MAPluggableCondition", superclass: "MACondition", isAbstract: false,
        label: "Pluggable Condition"),
      ClassInfo(
        name: "MAPriorityContainer", superclass: "MAContainer", isAbstract: false,
        label: "Priority Container"),
      ClassInfo(
        name: "MAPropertyAccessor", superclass: "MADictionaryAccessor", isAbstract: false,
        label: "Property Accessor"),
      ClassInfo(
        name: "MAReader", superclass: "MAStreamingVisitor", isAbstract: false, label: "Reader"),
      ClassInfo(
        name: "MAReferenceDescription", superclass: "MAElementDescription", isAbstract: true,
        label: "Reference Description"),
      ClassInfo(
        name: "MARelationDescription", superclass: "MAReferenceDescription", isAbstract: true,
        label: "Relation Description"),
      ClassInfo(
        name: "MASelectorAccessor", superclass: "MAAccessor", isAbstract: false,
        label: "Selector Accessor"),
      ClassInfo(
        name: "MASingleOptionDescription", superclass: "MAOptionDescription", isAbstract: false,
        label: "Single-Option"),
      ClassInfo(
        name: "MAStraightMemento", superclass: "MAMemento", isAbstract: false,
        label: "Straight Memento"),
      ClassInfo(
        name: "MAStreamingVisitor", superclass: "MAVisitor", isAbstract: false,
        label: "Streaming Visitor"),
      ClassInfo(
        name: "MAStringDescription", superclass: "MAElementDescription", isAbstract: false,
        label: "String"),
      ClassInfo(
        name: "MAStringReader", superclass: "MAReader", isAbstract: false, label: "String Reader"),
      ClassInfo(
        name: "MAStringWriter", superclass: "MAWriter", isAbstract: false, label: "String Writer"),
      ClassInfo(
        name: "MASymbolDescription", superclass: "MAStringDescription", isAbstract: false,
        label: "Symbol"),
      ClassInfo(
        name: "MAToManyRelationDescription", superclass: "MARelationDescription", isAbstract: false,
        label: "1:m Relation"),
      ClassInfo(
        name: "MAToManyScalarRelationDescription", superclass: "MAToManyRelationDescription",
        isAbstract: false, label: "1:m scalar Relation"),
      ClassInfo(
        name: "MAToOneRelationDescription", superclass: "MARelationDescription", isAbstract: false,
        label: "1:1 Relation"),
      ClassInfo(
        name: "MATokenDescription", superclass: "MAReferenceDescription", isAbstract: false,
        label: "Token"),
      ClassInfo(
        name: "MAValidatorVisitor", superclass: "MAVisitor", isAbstract: false,
        label: "Validator Visitor"),
      ClassInfo(
        name: "MAVariableAccessor", superclass: "MAAccessor", isAbstract: false,
        label: "Variable Accessor"),
      ClassInfo(
        name: "MAVisitor", superclass: "MABasicObject", isAbstract: false, label: "Visitor"),
      ClassInfo(
        name: "MAWriter", superclass: "MAStreamingVisitor", isAbstract: false, label: "Writer"),
      ClassInfo(name: "Magnitude", superclass: "Object", isAbstract: false, label: "Magnitude"),
      ClassInfo(name: "Number", superclass: "Magnitude", isAbstract: true, label: "Number"),
      ClassInfo(name: "Object", superclass: "ProtoObject", isAbstract: false, label: "Object"),
      ClassInfo(
        name: "OrderedCollection", superclass: "SequenceableCollection", isAbstract: false,
        label: "Ordered Collection"),
      ClassInfo(name: "ProtoObject", superclass: nil, isAbstract: false, label: "Proto Object"),
      ClassInfo(
        name: "SequenceableCollection", superclass: "Collection", isAbstract: true,
        label: "Sequenceable Collection"),
      ClassInfo(name: "Set", superclass: "HashedCollection", isAbstract: false, label: "Set"),
      ClassInfo(
        name: "String", superclass: "ArrayedCollection", isAbstract: false, label: "String"),
      ClassInfo(name: "Symbol", superclass: "String", isAbstract: false, label: "Symbol"),
      ClassInfo(
        name: "UndefinedObject", superclass: "Object", isAbstract: false, label: "Undefined Object"),
    ])
  }
  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
  private func installed(_ definitions: [ClassInfo]) throws -> [String: ClassInfo] {
    var next = classes
    func valid(_ name: String) -> Bool {
      !name.isEmpty && name.utf8.allSatisfy { $0 >= 33 && $0 <= 126 }
    }
    for info in definitions {
      try require(
        valid(info.name) && (info.superclass.map(valid) ?? true), "Invalid class identity")
      if let old = next[info.name] {
        try require(old == info, "Conflicting class registration: \(info.name)")
      }
      next[info.name] = info
    }
    var done = Set<String>()
    for name in next.keys {
      var path = Set<String>()
      var cursor: String? = name
      while let n = cursor, !done.contains(n) {
        try require(path.insert(n).inserted, "Cyclic class hierarchy")
        guard let info = next[n] else { throw MagritteError("Unknown superclass: \(n)") }
        cursor = info.superclass
      }
      done.formUnion(path)
    }
    return next
  }
  public func registerClass(_ info: ClassInfo) throws { try registerClasses([info]) }
  public func registerClasses(_ definitions: [ClassInfo]) throws {
    try locked { classes = try installed(definitions) }
  }
  public func registerNativeClass<T: AnyObject>(_ type: T.Type, info: ClassInfo) throws {
    try locked {
      let typeID = ObjectIdentifier(type)
      try require(
        (types[typeID] == nil || types[typeID] == info.name)
          && (names[info.name] == nil || names[info.name] == typeID),
        "Conflicting native class registration")
      let next = try installed([info])
      classes = next
      types[typeID] = info.name
      names[info.name] = typeID
    }
  }
  public func classForNativeType(_ type: Any.Type) -> String? {
    locked { types[ObjectIdentifier(type)] }
  }
  public func find(_ name: String) -> ClassInfo? { locked { classes[name] } }
  public func allClasses() -> [String] { locked { classes.keys.sorted() } }
  private func includes(_ name: String, _ ancestor: String) -> Bool {
    guard classes[ancestor] != nil else { return false }
    var cursor: String? = name
    while let n = cursor {
      guard let info = classes[n] else { return false }
      if n == ancestor { return true }
      cursor = info.superclass
    }
    return false
  }
  public func includesBehavior(_ name: String, _ ancestor: String) -> Bool {
    locked { includes(name, ancestor) }
  }
  public func inheritsFrom(_ name: String, _ ancestor: String) -> Bool {
    name != ancestor && includesBehavior(name, ancestor)
  }
  public func subclasses(_ name: String) throws -> [String] {
    try locked {
      try require(classes[name] != nil, "Unknown class: \(name)")
      return classes.values.filter { $0.superclass == name }.map(\.name).sorted()
    }
  }
  public func withAllSubclasses(_ name: String) throws -> [String] {
    try locked {
      try require(classes[name] != nil, "Unknown class: \(name)")
      return classes.keys.filter { includes($0, name) }.sorted()
    }
  }
  public func allSubclasses(_ name: String) throws -> [String] {
    try withAllSubclasses(name).filter { $0 != name }
  }
  public func withAllConcreteClasses(_ name: String) throws -> [String] {
    try locked {
      try require(classes[name] != nil, "Unknown class: \(name)")
      return classes.values.filter { !$0.isAbstract && includes($0.name, name) }.map(\.name)
        .sorted()
    }
  }
  public func commonSuperclass(_ names: [String]) throws -> String? {
    try locked {
      guard let first = names.first else { return nil }
      for n in names { try require(classes[n] != nil, "Unknown class: \(n)") }
      var cursor: String? = first
      while let n = cursor {
        if names.allSatisfy({ includes($0, n) }) { return n }
        cursor = classes[n]?.superclass
      }
      return nil
    }
  }
}
