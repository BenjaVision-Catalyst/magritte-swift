#include <iostream>
#include <magritte/magritte.hpp>
#include <nlohmann/json.hpp>
using namespace magritte;
using J = nlohmann::json;
template <class F> J observe(F f) {
  try {
    return J{{"result", f()}};
  } catch (const Error &e) {
    return J{{"error", e.what()}};
  }
}
J value(const Value &v) { return J::parse(encodeValue(v)); }
struct VisitorProbe : Visitor {
  int count = 0;
  void visitStringDescription(Description &) override { ++count; }
};
int main() {
  J out;
  auto &classes = ClassRegistry::global();
  classes.registerClasses({{"GapAuditText", "MAStringDescription"},
                           {"GapAuditNumber", "MANumberDescription"},
                           {"GapAuditContainer", "MAContainer"},
                           {"GapAuditMany", "MAToManyRelationDescription"}});
  auto text = std::make_shared<Description>();
  text->id = text->key = "custom";
  text->className = "GapAuditText";
  Description number;
  number.className = "GapAuditNumber";
  Description container;
  container.className = "GapAuditContainer";
  Description many;
  many.className = "GapAuditMany";
  VisitorProbe visitor;
  text->acceptMagritte(visitor);
  out["registered_subclasses"] = {
      {"registered", bool(classes.find("GapAuditText"))},
      {"visitor_string_dispatch", visitor.count == 1},
      {"numeric_kind", value(number.property("kind"))},
      {"container_query", container.isContainer()},
      {"multiple_query", many.isMultiple()},
      {"validation",
       observe([&] { return J(validateValue(*text, Value("Ada")).size()); })},
      {"metadata",
       observe([&] { return J(descriptionModelFor(*text).root); })}};
  auto root = std::make_shared<Description>();
  root->id = "root";
  root->className = "MAContainer";
  root->children = {text};
  Graph g;
  g.format = "magritte.graph/4";
  g.root = root->id;
  g.descriptions = {{root->id, root}, {text->id, text}};
  out["registered_subclasses"]["graph"] = observe([&] {
    g.encode();
    return J(true);
  });
  Description choice;
  choice.id = choice.key = "choice";
  choice.className = "MASingleOptionDescription";
  out["reference_defaults"]["single_option"] =
      observe([&] { return J(choice.referenceDescription()->className); });
  Description boolean;
  boolean.className = "MABooleanDescription";
  out["reference_defaults"]["boolean"] = observe(
      [&] { return J(boolean.referenceDescription().get() == &boolean); });
  auto option = std::make_shared<Description>(),
       ref = std::make_shared<Description>();
  option->id = option->key = "option";
  option->className = "MASingleOptionDescription";
  ref->id = "reference";
  option->reference = ref;
  RecursiveDescriptionModel session;
  auto schema = session.describeReflective(option);
  bool hasGroup = false;
  for (const auto &d : schema->children) {
    auto a = d->effectiveAccessor();
    if (a.name == "groupBy")
      hasGroup = true;
  }
  out["grouping"]["annotated_groupBy_present"] = hasGroup;
  option->properties["groupBy"] = Value(Value::Symbol{"grouping"});
  root->children = {option};
  g.descriptions = {{root->id, root}, {option->id, option}, {ref->id, ref}};
  out["grouping"]["graph"] = observe([&] {
    g.encode();
    return J(true);
  });
  auto a = std::make_shared<Description>(), b = std::make_shared<Description>();
  a->id = a->key = "a";
  b->id = b->key = "b";
  a->properties["priority"] = Value(std::int64_t(1));
  b->properties["priority"] = Value(std::int64_t(2));
  Description priority;
  priority.className = "MAPriorityContainer";
  priority.children = {a, b};
  auto ids = [&] {
    J r = J::array();
    for (auto &d : priority.orderedChildren())
      r.push_back(d->id);
    return r;
  };
  out["priority_order"]["before"] = ids();
  a->properties["priority"] = Value(std::int64_t(3));
  out["priority_order"]["after_child_priority_change_without_resort"] = ids();
  Description num;
  num.id = num.key = "number";
  num.className = "MANumberDescription";
  auto fraction = Value(Value::Fraction{1, 2});
  auto rendered = writeString(num, fraction);
  out["numbers"] = {{"fraction_text", rendered},
                    {"read_own_fraction_text", observe([&] {
                       return value(readString(num, rendered));
                     })}};
  Description message;
  message.id = "message";
  message.setKindErrorMessage(Value());
  out["nil_error_message"] = observe(
      [&] { return J(validateValue(message, Value(std::int64_t(1))).size()); });
  Description announced;
  out["property_announcer"] = observe([&] {
    announced.propertyPut("propertyAnnouncer", Value());
    return J(true);
  });
  Description conditions;
  conditions.id = "conditions";
  conditions.className = "MAContainer";
  conditions.conditions.push_back(
      {"fails", [](const Value &) { return false; }});
  DictionaryModel model;
  out["container_conditions"] =
      observe([&] { return J(validate(conditions, model).size()); });
  std::cout << out.dump(2) << '\n';
}
