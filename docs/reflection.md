# Class values and reflective metadata (0.6)

This phase adds MAClassDescription, finite class-valued metadata, actual accessor-object editing and faithful condition self-description to both independent ports. The baseline is upstream [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e), rechecked against remote HEAD and live GT. This remains a selected headless profile, not complete Magritte reflection.

## Class values

C++ `Value(Value::Class{"String"})` and Swift `Value.classValue("String")` represent the same interned class identity. `portableClasses()` publishes the sorted 61-name registry in conformance/class-registry.json. It includes the supported description/accessor/condition hierarchy, adaptive model, scalar/collection ancestry and implemented interpreter classes. Registry membership does not make every class instantiable: only supported concrete descriptions can be constructed through graph interchange. Names cannot request host reflection, arbitrary messages or executable behavior. Unknown names fail validation/encoding; Strings and Symbols never implicitly become classes. Class identity is distinct from both, including option membership and Set uniqueness. Classes can be identity-safe option label keys.

MAClassDescription has kind Class, type label Class and class-name rendering. Nil follows the usual required/undefined rules. Its text reader returns nil for empty text and rejects every nonempty input, matching upstream's unimplemented class reader. Its writer renders supported Class values and rejects ordinary String/Symbol/integer inputs. JSON class decoding is separate from text reading.

The real `stringReader`, `stringWriter` and `validator` properties default to Class values MAStringReader, MAStringWriter and MAValidatorVisitor. Their metadata uses single-option descriptions referencing MAClassDescription. Each option list deliberately contains only its implemented interpreter class; unsupported overrides fail before mutation or import. Relation `classes` metadata is a multiple-option description of Class values, with an empty Set default and the portable registry as options. Committing a classes edit changes the actual relation constraints. Plain class-name text is rejected by that setter.

## Reflective sessions

`RecursiveDescriptionModel.describeReflective(description)` extends the selected recursive profile with accessor, stringReader, stringWriter and validator, plus classes for relation descriptions. It includes MAClassDescription in supported child/reference constraints. The older `describe(description)` and non-Class `descriptionModelFor` profiles remain available for existing graph/3 consumers. A session can reflect its newly generated metadata descriptions again, without a permanent class schema cache.

`describe(accessorObject)` and `describe(conditionObject)` use ordinary descriptions and Model adapters, with the same validators and mementos as application fields. These are actual local objects, rather than adaptive objects claiming another class. The returned schemas are graph/4 data. `schemas()` exports the accumulated schemas without native bindings; the resolver retains those bindings and cannot itself be exported. Bindings weakly reference the owning session; keep it alive while using models/mementos. ID collisions across descriptions, accessors and conditions fail explicitly. Do not mutate bound IDs or remove resolver bindings.

Accessor fields follow the real upstream annotations:

| Concrete accessor | Annotated fields |
| --- | --- |
| MADictionaryAccessor, MAPropertyAccessor | required Symbol key |
| MASelectorAccessor | Symbol selector |
| MADelegatorAccessor | next relation, priority 100 |
| MAChainAccessor | next relation, priority 100; accessor relation, priority 200 |
| MAVariableAccessor, MANullAccessor, MAIdentityAccessor | none |

Delegator and chain relation constraints project MAAccessor subclasses to the eight implemented classes. Their reference description is MAStringDescription, exactly as upstream; relation validation checks the target class without cascading through that reference. Assigning selector resets both readSelector and writeSelector, deriving the writer by appending a colon, even if a custom writer was present before.

The supported MAPluggableCondition, MAConjunctiveCondition and MANegationCondition classes have **no annotated fields** in upstream or GT. Their self-description is therefore an empty container labelled with the concrete class name. `ConditionObject` still owns and evaluates the portable Predicate; no invented receiver/selector/arguments editor is published. Host callback conditions remain local and outside this reflective profile. Arbitrary condition mutation, memento self-description and full hierarchy bootstrap remain future work.

## Live accessor identity and snapshots

`AccessorObject` holds leaf Accessor state and actual binary `accessor`/`next` links. `fromAccessor(id, value)` constructs a tree from an existing portable accessor; `snapshot()` converts it back, flattening chain tails to the existing ordered steps representation. MADelegatorAccessor is operational: reads and writes forward through next. Snapshotting and binding preflight IDs, slots, cycles and configured depth/node/work bounds. Shared acyclic children are supported. A failed link write restores the previous slot; a failed bind publishes no partial object tree. Local directly-created owning cycles must be broken by their creator.

Reading a description's accessor metadata lazily binds its effective accessor as an AccessorObject. Setting that metadata attaches the referenced actual object. Descriptions sharing it observe later key/selector/link edits through ordinary dictionary/native model access. Local callback accessors cannot be converted into reflective objects. Effective access, nested-container interpreters, validation preflight, equality and copying consult live accessor state. While a live binding exists it takes precedence over the inline accessor field; replace it through metadata or clear accessorObject explicitly. Selected description copying clones the live accessor tree, consistent with the existing accessor copy profile; it is not a cycle-preserving arbitrary graph clone.

A C++ key edit uses the usual memento protocol:

```cpp
RecursiveDescriptionModel session;
auto schema = session.describe(accessorObject);
auto adapter = session.bind(accessorObject);
CheckedMemento editor(*adapter, schema, &session.resolver());
editor.writeUsing(*session.resolver().descriptions.at(schema->id + ".key"),
                  Value(Value::Symbol{"final"}));
if (editor.validate().empty()) editor.commit();
```

The Swift equivalent is:

```swift
let session = RecursiveDescriptionModel()
let schema = try session.describe(accessorObject)
let adapter = try session.bind(accessorObject)
let editor = try CheckedMemento(model: adapter, description: schema, graph: session.resolver)
try editor.write(.symbol("final"), using: session.resolver.descriptions[schema.id + ".key"]!)
if try editor.validate().isEmpty { try editor.commit() }
```

The inline accessor wire format has value semantics, with no accessor identity table. Graph encoding refuses descriptions carrying live AccessorObject bindings. Call `description.materializeAccessor()` explicitly (throwing in Swift) to replace each live binding with a checked snapshot before export. Alias identity is then deliberately lost; equivalent independent accessor records remain. Container identity snapshots return to the implicit identity form; custom container accessors still have no wire representation. Class values and generated schemas survive interchange. Editing caches and local condition/accessor bindings are never serialized. Swift's `Description.effectiveAccessor` is now a throwing getter, so callers use `try` to handle invalid live trees.

## Evidence and boundaries

reflection-reference.json records 15 full supported description schemas and getter/validation results, eight accessor schemas and checked edits, three condition schemas and evaluations, eight class-validation cases, four class text reads and six writes. It verifies all 61 registry names as actual GT Classes and discovers/asserts the absence of condition annotations. The replay also checks concrete delegator read/write forwarding. Twenty-six inspected live method fingerprints match pinned upstream ignoring whitespace; reflection-live-methods.json records their hashes. Source and tests were independently authored, not copied from upstream.

The live shared-accessor scenario describes a Number description, then its dictionary accessor, then an alias description. Checked mementos attach the same accessor to both descriptions and change its key to final; ordinary reads through both change from their original keys to the shared value 9. Native tests compare each schema and getter against GT, including the accumulated 50-description metadata graph. Each port exports a 54-description graph with one adaptive object holding a Class value. GT reconstructs real descriptions and Classes, validates the application and three metadata schemas, and reexports semantically equivalent data. Inline dictionary keys are reconstructed as Symbols for the declared symbolic fallback-name profile; String/Symbol dictionary-key identity is not a new wire guarantee.

The full reference/replay and native round-trip report/replay live in conformance/. reflection-invalid.json contains independently authored protocol rejection cases, not GT behavior claims. Native tests additionally cover class-constraint edits, unsupported interpreters, shared links, selector writer reset, explicit snapshot export, class/predicate legacy rejection, aggregate limits and mutation rollback. Existing as-is default label, supported class-list and SortedCollection snapshot projections remain explicit profile policies.

C++ has five CTest targets; Swift has 34 tests. Debug C++, ASan/UBSan, Swift, fixture hashes and an installed CMake consumer are checked on macOS arm64. LeakSanitizer is unavailable on this platform. Reference operations use CCNativeMcpLease and a completion marker checked outside GT after release. They allocate no native Runtime resources and change no persistent Smalltalk source. No Linux/Windows validation or complete core equivalence is claimed.
