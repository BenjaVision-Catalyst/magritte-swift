# Runtime class registration and discovery (0.8)

The class-name allowlist has been replaced by a runtime class environment in both independent ports. Applications register class identities and inheritance, optionally associate them with native types, and discover the available classes through that environment. Class values, relation constraints, native subtype checks and recursive metadata use those registrations. Adding an application class requires no library edits.

## Register native classes

C++:

```cpp
struct Person { virtual ~Person() = default; };
struct Employee : Person {};

auto& classes = magritte::ClassRegistry::global();
classes.registerNativeClass<Person>({"Person", "Object"});
classes.registerNativeClass<Employee>({"Employee", "Person"});

Employee employee;
Person* person = &employee;
auto model = magritte::NativeModel::registered(person);
assert(model.kindOf("Employee"));
assert(model.kindOf("Person"));
auto classValue = magritte::Value(magritte::Value::Class{"Employee"});
```

Swift:

```swift
class Person {}
final class Employee: Person {}

let classes = ClassRegistry.shared
try classes.registerNativeClass(Person.self, info: ClassInfo(name: "Person"))
try classes.registerNativeClass(Employee.self,
    info: ClassInfo(name: "Employee", superclass: "Person"))

let person: Person = Employee()
let model = try NativeModel(registered: person)
assert(model.kindOf("Employee"))
assert(model.kindOf("Person"))
let classValue = Value.classValue("Employee")
```

C++ RTTI selects the dynamic type for polymorphic pointers; for other C++ objects pass the most-derived static type. Swift uses the object's dynamic metatype. C++ continues to borrow the object, which must outlive the adapter. Swift retains it. Existing native selector/variable/property accessor bindings continue to operate on the actual object. No field schema or instance constructor is invented by class registration.

Portable C++ and Swift do not provide Smalltalk's global enumeration of every application class and its superclass metadata. Registration supplies that platform bridge. Each process has one class environment, corresponding to the available class environment of an image. Built-in class declarations seed it through the same registration machinery; they are not a ceiling on available classes. Required ancestors are included and checked against GT. Applications can register further native classes at startup or later.

`ClassInfo` records a canonical name, superclass, abstract flag and class label. C++ uses an empty superclass string for a root; Swift uses nil. Names follow the existing nonempty printable ASCII identity contract. Labels retain exact UTF-8 content, including an explicitly empty label. The default label is the name. A symbolic class declaration can be installed with registerClass/registerClasses without a native type association. That supports class identities supplied by native modules even when no instance adapter is needed.

## Discovery and identity

| API | Meaning |
| --- | --- |
| allClasses | Currently registered class names |
| find | Lookup a class declaration; absent names return no result |
| subclasses | Direct subclasses |
| allSubclasses | Transitive subclasses, excluding the receiver |
| withAllSubclasses | Receiver plus transitive subclasses |
| withAllConcreteClasses | Receiver and descendants whose abstract flag is false |
| includesBehavior(class, ancestor) | Ancestry membership, including self |
| inheritsFrom(class, ancestor) | Strict ancestry, excluding self |
| commonSuperclass | Nearest shared superclass for a nonempty class list; no result for an empty list or disconnected roots |
| classForNativeType | Canonical identity associated with a native type |

Discovery returns sorted snapshots for deterministic native behavior. GT enumeration order is not claimed. Magritte's withAllConcreteClasses protocol is defined on MAObject's class hierarchy; the environment exposes its filtering operation as a general hierarchy query. The commonSuperclass helper supplies the nonempty-list hierarchy operation used by MARelationDescription; automatic relation template/reference construction remains outside this increment.

Definitions are immutable after publication so existing Class values keep their meaning. Repeating an identical declaration/type binding is idempotent. Conflicting definitions, unknown superclasses, cycles and ambiguous native type bindings fail. registerClasses accepts forward superclass references within an atomic batch. One native type has one canonical class identity, and a class identity has at most one native type binding. There is no implicit class removal, reparenting or arbitrary native object construction. Registration and queries are synchronized with a mutex/NSLock; returned declarations and lists do not expose mutable registry state.

The older NativeModel constructors with explicit ancestry remain available as caller-supplied native assertions. The registered constructors remove the need to supply those ancestor lists and support actual runtime type lookup. Class registration itself declares identity and ancestry; native methods/accessors remain implemented by native objects and existing adapters. A class name does not provide an implementation of an unimplemented description, accessor or interpreter protocol. Those wire records continue to fail explicitly rather than being executed as a different built-in type.

## Metadata, validation and interchange

Both recursive entry points and bootstrap now use discovery for description child/reference constraints, accessor subclasses, interpreter subclass options and relation class options. The former frozen 0.6/0.7 class-option exclusions are removed. A newly requested metadata schema sees new registrations; an already constructed metadata schema retains its existing option collection, matching the upstream annotation's construction-time query. Ordinary mementos can select registered Class values and change actual relation constraints.

Class-valued metadata uses the same runtime environment as standalone values and graph codecs. Native models obtain inherited kinds from registered types; inline scalar/collection values obtain their existing mapped class and ancestors from the same hierarchy. A portable adaptive model retains its actual MAAdaptiveModel ancestry and does not claim to be an application native class just because its description has a particular label.

The existing graph/4 Class tag and string class constraints are sufficient; no class-definition envelope, transport or executable language is added. Receivers must register the corresponding class identities before decoding them. Unknown incoming names fail and never register themselves. Relation class names are resolved through the runtime environment subject to existing legacy format feature gates. Registering a class does not change the meaning of existing Value tags or make a native object binding serializable. MAClassDescription's nonempty text reader remains unsupported, as upstream specifies; class lookup is provided by the class environment, not invented text-reader behavior.

The compatibility function portableClasses() now returns a fresh allClasses snapshot. The conformance class-registry/bootstrap-class-registry files are reference snapshots of a selected initial environment, not runtime acceptance lists. Test projections identify the available native environment explicitly; no production discovery filter freezes that environment to a fixture.

## Reference evidence and scope

The baseline remains upstream d67f318686b7779aed79416db121e257d1191f2e, rechecked against remote HEAD. registration-core-classes.json records the selected built-in hierarchy and its required ancestors as observed in GT, including labels and abstract flags. Magritte class declarations match their pinned source; kernel/Grease ancestor facts are image platform metadata, not a claim to implement their entire protocols or an external library dependency.

registration-reference.json/replay verify four classes added to the native environment after initial lookup: MAValueHolder, MADescriptionHolder, MACompositeAccessor and MAPluggableAccessor. These names already exist in GT; no image classes or methods are created. Reference queries are explicitly projected to the classes available in the native environment. The evidence includes direct/transitive/inclusive/concrete subclass sets, 300 includesBehavior/inheritsFrom cases, 80 scalar-class validation cases, native value-holder access, inherited relation validation, class options and metadata getters. Native-only tests additionally register application Person/Employee equivalents, check RTTI/metatype discovery, late registration after first lookup, immutable metadata snapshots, atomic failures, exact Unicode label identity and concurrent registration/discovery.

Eight inspected Magritte methods match pinned upstream ignoring whitespace in registration-live-methods.json. Existing recursive/reflection/bootstrap GT fixtures have been refreshed for discovery from the current seeded environment, removing the old class caps. Their original revisions remain in Git history.

Each port exports 33 descriptions and one adaptive object containing newly registered Class values and native class constraints. GT reconstructs and validates them, edits the allowed classes through an actual checked metadata memento, restores the original constraint and reexports equivalent data. registration-roundtrip-reference.json/replay record this check. Native inputs come from `magritte-registration-tests /private/tmp/magritte-cpp-registration-native.json` and `MAGRITTE_REGISTRATION_EXPORT=/private/tmp/magritte-swift-registration-native.json swift test`.

The full suite is seven CTest targets and 38 Swift tests. Debug C++, ASan/UBSan, fixture hashes and an installed CMake consumer are checked on macOS arm64; LeakSanitizer remains unavailable. GT runs use CCNativeMcpLease and post-release completion markers. They allocate no native Runtime resources, change no persistent Smalltalk source and modify no GT-registered checkout. The scope is class identity, native registration, hierarchy discovery and the existing Magritte interpreters that consume those facts. No complete scalar/interpreter/hierarchy implementation or additional platform execution is claimed.

Phase 0.9 adds the implemented `MADescriptionBuilder` to the seed declarations (72 at that revision). The phase 0.8 reference fixtures retain their recorded 71-class initial environment; those counts describe historical evidence, not a discovery ceiling. New metadata queries the whole current registered environment.
