# Accessor-derived names and labels

Phase 0.13 implements accessor name/label inference and its use by description metadata. The baseline remains [upstream d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e), verified against upstream HEAD on 2026-10-26. Twenty inspected Magritte methods, including String's Magritte normalizeCamelCase extension, match live GT ignoring whitespace. The separately attributed String capitalized method belongs to Pharo Collections-Strings. `accessor-inference-live-methods.json` records all 21 fingerprints.

## Audited behavior

The preceding implementation returned a raw key for missing labels and approximated accessor-derived names in recursive adapters. This phase uses the actual Magritte accessor protocol for the nine represented strategies:

| Accessor | Name | Default label |
| --- | --- | --- |
| Dictionary / property | key as Symbol | normalized key, first character capitalized |
| Selector | read selector as Symbol, or nil | normalized read selector; nil becomes `Nil` |
| Variable | configured String | description class default label (empty for represented classes) |
| Identity / null / pluggable | nil | description class default label (empty) |
| Delegator | next accessor's name | next accessor's default label |
| Chain | next name, `::`, head name | head label, `::`, next label |

Names retain their Symbol/String result kind. In a chain, the receiver of concatenation determines that kind: a String tail produces a String result, while a Symbol tail produces a Symbol. Chains with a nil name fail explicitly rather than printing a made-up name. Empty labels in a chain remain empty components, including their separators. Arbitrary accessor subclasses and their custom methods remain outside the finite executable profile.

The upstream normalizer inserts a space before an uppercase character when the preceding output character is not uppercase. It preserves acronym runs, punctuation and existing whitespace. Capitalization changes only the first character. Thus firstName becomes `First Name`, someURLValue becomes `Some URLValue`, and a_B becomes `A_ B`. These are the observed Magritte rules, without additional word splitting or typography changes.

Inference implements the existing portable ASCII accessor-name domain. Native Unicode names still retain their exact String/Symbol content, but automatic label inflection for non-ASCII names fails explicitly. Applications can supply an explicit Unicode label; no normalization or casing is applied to explicit text. Two actual GT Unicode results remain in the fixture as unsupported inference cases. This phase does not claim full Unicode casing compatibility or expand the interchange identity alphabet.

## Description behavior and metadata

A missing label is computed from the current effective accessor. A present label property, including nil or an empty String, is returned as stored and bypasses accessor traversal. `hasLabel` is false for nil/empty text and true for nonempty text. `defaultLabel` always asks the accessor, independently of an explicit label. An explicit name property similarly overrides the accessor name, including nil, and does not affect label inference.

Changes to accessor keys or a live AccessorObject are reflected by later derived reads; no derived label is cached into the property dictionary. Explicit properties and copy semantics remain independent. Generic Model selector access supports name/name:, defaultLabel and hasLabel, with the last two read-only. Recursive description adapters delegate name lookup to this same protocol. Inference never executes native accessor blocks.

`descriptionModelFor` sets the label field's default from actual defaultLabel, even when the target has an explicit label. Metadata construction takes a snapshot of that default, as upstream descriptionLabel does; this is not a new description-cache invalidation mechanism. The fresh fixture verifies defaults across all fifteen represented description classes. Native tests also check a further metadata level, staged editing of an empty label and ordinary graph interchange.

An unconfigured scalar description uses Magritte's null-accessor default. Its 16-byte comparison token is created lazily, remains stable for that description, and differs between independently initialized defaults. A copy made before accessor initialization obtains its own default later; a copy made after initialization preserves the existing token. GT checks both equality outcomes. Containers use identity, and the native convenience key continues to select a dictionary accessor when present. Explicit null-accessor records retain their supplied tokens, including nil. Mutable descriptions and this lazy state require caller synchronization.

## Native APIs and migration

C++:

```cpp
magritte::Description field;
field.key = "firstName";
auto name = field.property("name"); // Symbol firstName
// The accessor record's public name member is configuration; accessorName is its protocol getter.
auto accessorName = field.effectiveAccessor().accessorName();
auto label = field.property("label"); // String First Name
bool present = field.hasLabel();
field.properties["label"] = magritte::Value();
bool absent = !field.hasLabel(); // Explicit nil label overrides inference.
auto fallback = field.defaultLabel(); // First Name
```

Swift:

```swift
let field = Description(id: "field", key: "firstName")
let name = try field.property("name")
let accessorName = try field.effectiveAccessor.accessorName()
let label = try field.property("label")
let present = try field.hasLabel()
field.properties["label"] = .undefined
let absent = try !field.hasLabel()
let fallback = try field.defaultLabel()
```

Swift property reads now throw: existing calls need `try`. This is a source API change from 0.12, required to propagate malformed/cyclic accessor state, unsupported inference and configurable resource-limit failures. It avoids returning a fabricated fallback. C++ property/effectiveAccessor methods accept an optional Limits argument while preserving existing call syntax; C++ already uses exceptions. `Accessor.defaultLabelFor(description, limits)` / Swift `defaultLabel(for:limits:)` expose the underlying accessor protocol.

Derived name/label operations validate accessor structure and bound their work, traversal depth and output. Label/name property values are checked with the Value codec limits. Live accessor snapshots are bounded and reject cycles. An explicit label can still be read without traversing a malformed/cyclic accessor, matching the upstream property-first lookup. Other property behavior, raw writes, UI flags and validation remain separate protocols. Native callbacks and default functions are not invoked by inference.

## Reference evidence and historical fixtures

`accessor-inference-reference.json` records 70 GT accessor cases, including two unsupported Unicode inference oracles, name kinds, chain errors/order, explicit overrides, fifteen class metadata defaults, live key/accessor edits, three memento snapshots and lazy null-accessor copy/equality behavior. `accessor-inference-replay.json` is the GT MCP request. No Smalltalk classes or methods were modified. The running image's registered checkout paths were inspected and left unchanged.

Earlier metadata fixtures deliberately projected inferred label defaults to raw keys. They remain historical evidence with unchanged bytes. Their test comparisons now omit only the default of the annotated label descriptor (read selector label); all other graph fields remain checked. The new inference tests assert the actual unprojected default for every supported accessor case and every represented description class. This isolates the older projection without manufacturing new GT results or retaining it in production behavior.

`accessor-inference-roundtrip-replay.json` imports the graphs emitted by both ports, validates and reads their edited adaptive objects, checks the inferred `First Name` label, writes their string representation, and re-exports the supported data. `accessor-inference-roundtrip-reference.json` records both two-description/one-object runs. Semantic graph comparison passes without adding an explicit label property to either wire graph. Derived names/labels and lazy default state add no new graph format.

Reference runs used CCNativeMcpLease, and the controller checked each completion marker outside GT before inspecting results or making another GT call. These were pure Magritte operations with no native Runtime/plugin resources. Native validation on macOS arm64: twelve CTest targets, all twelve with AddressSanitizer/UndefinedBehaviorSanitizer, 46 Swift tests, an installed CMake consumer and an independent Swift API import. LeakSanitizer is disabled on this host; no leak-check claim is made.

Composite accessors/conflict objects, full Unicode inflection, mutable collection-object identity, broader scalar domains, arbitrary host reflection and the remaining full builder/cache/interpreter protocols remain pending. This is the current metadata/accessor profile, not a complete Magritte port.
