import Foundation
import Magritte

func observe(_ body: () throws -> Any) -> [String: Any] {
  do { return ["result": try body()] } catch { return ["error": String(describing: error)] }
}
func value(_ v: Value) throws -> Any { try JSONSerialization.jsonObject(with: encodeValue(v)) }
final class VisitorProbe: Visitor {
  var count = 0
  override func visitStringDescription(_ d: Description) throws { count += 1 }
}
let classes = ClassRegistry.shared
try classes.registerClasses([
  ClassInfo(name: "GapAuditText", superclass: "MAStringDescription"),
  ClassInfo(name: "GapAuditNumber", superclass: "MANumberDescription"),
  ClassInfo(name: "GapAuditContainer", superclass: "MAContainer"),
  ClassInfo(name: "GapAuditMany", superclass: "MAToManyRelationDescription"),
])
let text = Description(id: "custom", className: "GapAuditText", key: "custom")
let number = Description(id: "number", className: "GapAuditNumber")
let container = Description(id: "container", className: "GapAuditContainer")
let many = Description(id: "many", className: "GapAuditMany")
let visitor = VisitorProbe()
try text.acceptMagritte(visitor)
var out: [String: Any] = [:]
var subclasses: [String: Any] = [
  "registered": classes.find("GapAuditText") != nil,
  "visitor_string_dispatch": visitor.count == 1,
  "numeric_kind": try value(number.property("kind")),
  "container_query": container.isContainer, "multiple_query": many.isMultiple,
  "validation": observe { try validateValue(.string("Ada"), using: text).count },
  "metadata": observe { try descriptionModelFor(text).root },
]
let root = Description(id: "root", className: "MAContainer")
root.children = [text]
let g = Graph(root: "root", descriptions: ["root": root, "custom": text])
g.format = "magritte.graph/4"
subclasses["graph"] = observe {
  _ = try g.encode()
  return true
}
out["registered_subclasses"] = subclasses
let choice = Description(id: "choice", className: "MASingleOptionDescription", key: "choice")
let boolean = Description(id: "boolean", className: "MABooleanDescription")
out["reference_defaults"] = [
  "single_option": observe { try choice.referenceDescription().className },
  "boolean": observe { try boolean.referenceDescription() === boolean },
]
let option = Description(id: "option", className: "MASingleOptionDescription", key: "option")
let ref = Description(id: "reference")
option.reference = ref
let session = RecursiveDescriptionModel()
let schema = try session.describeReflective(option)
let hasGroup = try schema.children.contains { try $0.effectiveAccessor.name == "groupBy" }
option.properties["groupBy"] = .symbol("grouping")
root.children = [option]
g.descriptions = ["root": root, "option": option, "reference": ref]
out["grouping"] = [
  "annotated_groupBy_present": hasGroup,
  "graph": observe {
    _ = try g.encode()
    return true
  },
]
let a = Description(id: "a", key: "a")
let b = Description(id: "b", key: "b")
a.properties["priority"] = .integer(1)
b.properties["priority"] = .integer(2)
let priority = Description(id: "priority", className: "MAPriorityContainer")
priority.children = [a, b]
let before = try priority.orderedChildren().map(\.id)
a.properties["priority"] = .integer(3)
out["priority_order"] = [
  "before": before,
  "after_child_priority_change_without_resort": try priority.orderedChildren().map(\.id),
]
let num = Description(id: "number", className: "MANumberDescription", key: "number")
let fraction = try Value.rational(1, 2)
let rendered = try writeString(fraction, using: num)
out["numbers"] = [
  "fraction_text": rendered,
  "read_own_fraction_text": observe { try value(readString(rendered, using: num)) },
]
let message = Description(id: "message")
try message.setKindErrorMessage(.undefined)
out["nil_error_message"] = observe { try validateValue(.integer(1), using: message).count }
let announced = Description(id: "announced")
out["property_announcer"] = observe {
  try announced.propertyPut("propertyAnnouncer", .undefined)
  return true
}
let conditions = Description(id: "conditions", className: "MAContainer")
conditions.conditions.append(Condition(label: "fails", test: { _ in false }))
out["container_conditions"] = observe { try validate(DictionaryModel(), using: conditions).count }
let json = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
FileHandle.standardOutput.write(json)
