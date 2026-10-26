import Foundation

func descriptionType(_ d: Description) throws -> String {
  let names = [
    "MAClassDescription": "Class", "MAContainer": "Container", "MAPriorityContainer": "Priority Container",
    "MAStringDescription": "String", "MASymbolDescription": "Symbol",
    "MAMemoDescription": "Memo", "MAPasswordDescription": "Password",
    "MANumberDescription": "Number", "MABooleanDescription": "Boolean",
    "MATokenDescription": "Token", "MAToOneRelationDescription": "1:1 Relation",
    "MAToManyRelationDescription": "1:m Relation",
    "MAToManyScalarRelationDescription": "1:m scalar Relation",
    "MASingleOptionDescription": "Single-Option", "MAMultipleOptionDescription": "Multiple-Option",
  ]
  guard let name = names[d.className] else {
    throw MagritteError("Unsupported self-description class")
  }
  return name
}
func metadataSelector(_ d: Description, _ name: String, writing: Bool) -> Bool {
  if [
    "label", "comment", "group", "required", "readOnly", "visible", "priority", "undefined",
    "undefinedValue", "shouldCacheDefault", "stringReader", "stringWriter", "validator",
  ].contains(name) {
    return true
  }
  if name == "name" { return true }
  if ["defaultLabel", "hasLabel", "isSortable"].contains(name) { return !writing }
  if name == "type" { return !writing }
  if name == "default" { return !writing || !d.isContainer }
  if ["min", "max", "thousandsSeparator"].contains(name) && d.className == "MANumberDescription" {
    return true
  }
  if ["trueString", "falseString"].contains(name) && d.className == "MABooleanDescription" {
    return true
  }
  if name == "lineCount" && d.className == "MAMemoDescription" { return true }
  if name == "separators" && d.className == "MATokenDescription" { return true }
  if ["sorted", "extensible"].contains(name) && d.isOption { return true }
  if name == "distinct" && d.className == "MAMultipleOptionDescription" { return true }
  if ["ordered", "definitive", "sorted"].contains(name) && d.isRelation && d.isMultiple {
    return true
  }
  return name == "ordered" && d.className == "MAMultipleOptionDescription"
}
/// Expanded class-specific metadata descriptions with actual MASelectorAccessor records.
/// Retain the returned graph to own the auxiliary reference descriptions.
public func descriptionModelFor(_ target: Description, limits: Limits = Limits()) throws -> Graph {
  _ = try descriptionType(target)
  let graph = Graph(root: "meta." + target.className)
  if target.className == "MAClassDescription" { graph.format = "magritte.graph/4" }
  let root = Description(id: "meta." + target.className, className: "MAContainer")
  root.properties["label"] = .string(target.className)
  graph.descriptions[root.id] = root
  @discardableResult func add(
    _ key: String, _ cls: String, _ label: String, _ priority: Int64, _ defaultValue: Value? = nil
  ) throws -> Description {
    let d = Description(id: graph.root + "." + key, className: cls)
    d.accessor = Accessor(className: "MASelectorAccessor", name: key, writeName: key + ":")
    if !label.isEmpty { d.properties["label"] = .string(label) }
    d.properties["priority"] = .integer(priority)
    if let defaultValue { d.properties["default"] = defaultValue }
    if d.isReference {
      let ref = Description(id: d.id + ".reference")
      ref.accessor = Accessor(className: "MANullAccessor")
      d.reference = ref
      graph.descriptions[ref.id] = ref
      if d.className == "MATokenDescription" {
        d.properties["separators"] = try d.property("separators")
      }
    }
    root.children.append(d)
    graph.descriptions[d.id] = d
    return d
  }
  try add("type", "MAStringDescription", "Kind", 0).properties["readOnly"] = .boolean(true)
  let labelDefault = Value.string(try target.defaultLabel(limits: limits))
  try add("label", "MAStringDescription", "Label", 100, labelDefault)
  try add("comment", "MAMemoDescription", "Comment", 110, .undefined)
  try add("group", "MAStringDescription", "Group", 105, .undefined)
  try add("priority", "MANumberDescription", "Priority", 130, .integer(0)).properties["required"] =
    .boolean(true)
  try add("readOnly", "MABooleanDescription", "Read-only", 200, .boolean(false))
  if target.className != "MABooleanDescription" {
    try add("required", "MABooleanDescription", "Required", 220, .boolean(false))
  }
  try add("visible", "MABooleanDescription", "Visible", 210, .boolean(true))
  try add("undefined", "MAStringDescription", "Undefined String", 140, .string(""))
  try add("undefinedValue", "MAToOneRelationDescription", "", 150, .undefined)
  if !target.isContainer && !target.isOption {
    try add("default", target.className, "Default", 130, .undefined)
  }
  if target.className == "MANumberDescription" {
    try add("min", target.className, "Min", 400)
    try add("max", target.className, "Maximum", 410)
  }
  if target.className == "MABooleanDescription" {
    try add("trueString", "MAStringDescription", "True String", 400, .string("true"))
    try add("falseString", "MAStringDescription", "False String", 410, .string("false"))
  }
  if target.className == "MAMemoDescription" {
    let lines = try add("lineCount", "MANumberDescription", "Number of Lines", 400, .integer(3))
    lines.properties["min"] = .integer(1)
    lines.portableConditions = [
      PortableCondition(
        label: "No integer was entered", predicate: Predicate(selector: "isInteger"))
    ]
  }
  if target.className == "MATokenDescription" {
    try add("separators", "MAStringDescription", "Separators", 250)
  }
  if target.isOption {
    try add("sorted", "MABooleanDescription", "Sorted", 240, .boolean(false))
    try add("extensible", "MABooleanDescription", "Extensible", 250, .boolean(false))
  }
  if target.isRelation && target.isMultiple {
    try add("ordered", "MABooleanDescription", "Ordered", 260, .boolean(false))
    try add("definitive", "MABooleanDescription", "Definitive", 265, .boolean(false))
    try add("sorted", "MABooleanDescription", "Sorted", 240, .boolean(false))
  }
  if target.className == "MAMultipleOptionDescription" {
    try add("distinct", "MABooleanDescription", "Distinct", 250, .boolean(false))
    try add("ordered", "MABooleanDescription", "Ordered", 260, .boolean(false))
  }
  _ = try graph.encode(limits: limits)
  return graph
}
