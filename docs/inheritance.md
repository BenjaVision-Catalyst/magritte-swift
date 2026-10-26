# Inherited description execution (0.27)

Both ports execute registered description subclasses through the implemented behavior of their ancestors. Runtime registration no longer stops at class discovery: inherited kind/defaults, predicates, validation, text conversion, options, metadata selectors and schemas now work together. MAG-001 is closed for subclasses of the currently implemented description profile.

## Source and verification

The source target is [Magritte d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), reconfirmed against remote HEAD on 2026-10-27 in an independent read-only checkout. `inheritance-upstream-methods.json` fingerprints 101 inspected methods. `inheritance-scenarios.json` supplies independently authored source-derived expectations for all 15 implemented description classes. Neither file contains executed GT results. **GT was not accessed.**

Upstream `MADescription>>kind` calls the receiving class's `defaultKind`; `type` calls its class's `label`. Subclasses inherit the default-kind, visitor, validation, predicate and annotated-description methods unless overridden. `MAObject` equality compares species before fields; sharing executable behavior must therefore preserve the actual class identity. These source rules determine the native behavior below.

The shared scenarios register an abstract intermediate class and a concrete descendant for each implemented family. Both native suites check inherited kind/defaults, source-specific property acceptance, positive/negative validation, supported reads/writes, exact visitor selection, inherited/suppressed metadata fields, metadata editing, recursive bootstrap, selective copies and identity-preserving graph round trips. Additional checks cover priority-container roots/order, memento commits through inherited fields, numeric range/condition failures, Boolean options, password operations, explicit kind/default/class-label overrides, callback export refusal, unsupported/abstract classes and legacy format refusal.

## Runtime behavior and identity

The existing runtime class registry remains open. A private execution resolver walks its immutable superclass definitions to the nearest implemented description ancestor. Its implementation bindings name the code the ports actually provide; they do not enumerate or cap application classes. Registering another subclass requires no change to those bindings. Ancestor predicates use the same registered hierarchy. Inherited visitor dispatch already worked and remains unchanged.

For example, register a Number subclass with the existing API:

```cpp
using namespace magritte;
ClassRegistry::global().registerClass({"ReadingDescription", "MANumberDescription", false, "Number"});
Description field;
field.id = field.key = "reading";
field.className = "ReadingDescription";
field.properties["min"] = Value(std::int64_t(0));
auto errors = validateValue(field, Value(std::int64_t(-1))); // MARangeError
```

```swift
try ClassRegistry.shared.registerClass(
  ClassInfo(name: "ReadingDescription", superclass: "MANumberDescription", label: "Number"))
let field = Description(id: "reading", className: "ReadingDescription", key: "reading")
field.properties["min"] = .integer(0)
let errors = try validateValue(.integer(-1), using: field) // MARangeError
```

`ClassInfo.label` is the existing host binding for the class-side label value. Supply the inherited label for a class without a label override, or a new label to represent an explicit class-side override. Its pre-existing default remains the registered name. The description's `type` now reads this actual registered value instead of consulting a separate fixed type-name map. This preserves explicit empty and Unicode labels and does not change registration defaults.

The description retains `ReadingDescription` as its class. Copies retain that species, and it is unequal to a base MANumberDescription even if their fields/accessors agree. Generated default/min/max metadata descriptions also retain the actual class where source methods construct through `self class`. Metadata uses inherited family fields; Boolean descendants continue to suppress the required annotation. Existing defaults, property overrides and local callback slots retain their precedence.

Unknown class names, unrelated registered classes, abstract receiver classes and hierarchies without an implemented concrete-family ancestor fail execution explicitly. An abstract intermediate ancestor does not prevent a concrete descendant from inheriting a supported implementation. Registration does not add arbitrary method bodies, compile source or invent support for an unimplemented scalar domain.

## Interchange and local behavior

Registered description subclasses require **graph/4**. The existing `class` field carries the actual name, while inherited behavior determines the node's shape and semantic checks. The receiver must register the corresponding class hierarchy before decoding; incoming data never registers classes or executable implementations. Graph/1–3 reject subclass identities, and existing canonical-class feature gates remain in force. Metadata factories select graph/4 when their target is a registered descendant.

No new tag, class-definition envelope or executable format is added. Native callback defaults, conditions, accessors, display/printing hooks and host read/write bindings retain their existing explicit serialization boundaries. A supported ancestor does not make a closure portable. Description-selected custom interpreter classes remain MAG-006 work; arbitrary method overrides are not serialized or reconstructed.

The phase does not implement reference defaults/Boolean self-reference (MAG-002), persistent priority-container backing state (MAG-003), collection-object identity (MAG-004), grouped options (MAG-008), or complete annotation coverage (MAG-009). It makes the existing executable profile inheritable. Earlier gap-analysis observations remain pinned historical evidence for the 0.26 baseline; the ledger records this closure separately.

## Standalone checks

On macOS arm64, all 26 CTest targets and all 100 Swift tests pass. The 26 C++ targets also pass with AddressSanitizer/UndefinedBehaviorSanitizer; leak detection is disabled on this host. Both fixture mirrors verify 128 payloads. Native exports compare semantically and each port reimports the other port's graph. An installed CMake consumer and an independent Swift executable exercise the public inheritance API. These checks provide source/native evidence, not fresh live-image parity.

To capture/replay the graph with the C++ test executable, pass output and optional peer-input paths as its first and second arguments. Swift's InheritanceTests use `MAGRITTE_INHERITANCE_OUTPUT` and `MAGRITTE_INHERITANCE_INPUT`. Class registrations live only in these independent test processes.
