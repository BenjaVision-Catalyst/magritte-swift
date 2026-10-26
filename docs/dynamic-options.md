# Dynamic options (0.10)

This phase implements the existing `MADynamicOptions` protocol in both independent native ports. Upstream HEAD was rechecked against `d67f318686b7779aed79416db121e257d1191f2e` on 2026-10-26. The audit compared both ports' option storage, prepared lists, validation, copying, text access and export with upstream and live GT. Both ports previously assumed all options were materialized arrays. No UI, networking, framework, expression language or new wire format was added.

## Semantics

`Description.options` now holds an `Options` value: either a collection or a live provider. There is one source slot. `allOptions` returns the exact provider when that slot is dynamic. It does not query, sort, add an undefined entry or enumerate completions, regardless of required/sorted/extensible flags. Static sources retain their existing prepared-array behavior.

`DynamicOptions` has three independent callbacks:

- `block`: `selectMatching(query)` invokes it exactly once and returns its result unchanged. It does not filter or coerce the result to a collection. Changing captured application state affects subsequent requests.
- `includesBlock`: `includes(value)` invokes it for membership. Validation uses this callback, including for each occurrence in a multiple selection. Completion is not consulted. Members bypass reference constraints; unlisted extensible values are validated through the reference. Undefined sentinels, kind checks and required rules retain their earlier behavior.
- `reader`: `detect(completion)` converts a completion to its stored value. With no reader it returns the exact input value. This is a separate operation; generic string reading does not implicitly invoke it.

Missing completion or membership callbacks fail when requested. Native callback exceptions propagate. Ordinary description flags and reads do not eagerly execute callbacks. These are mutable local objects requiring caller synchronization. Callback inputs/outputs use the existing finite native `Value` domain, including explicit graph references for objects. Existing Value codec bounds check callback inputs/outputs; callbacks themselves remain ordinary host code without an execution-time budget.

Copying an option description follows upstream `postCopy`: the provider and reference description are copied. The copied provider shares the original callbacks and their captured state, but its callback slots can be replaced independently. C++ keeps each callable in shared ownership so copying a mutable lambda does not duplicate its state; invocation retains the callable through an in-flight slot replacement. Swift closures retain their capture environments. Captured application objects follow normal host-language ownership rules.

## Native APIs and migration

`options`, `allOptions()` and `allOptionsWith(...)` use `Options` rather than an array. This is a source API change from 0.9, needed because upstream can return an actual provider. Array literals still initialize static options in both languages. Extract a known static Value collection explicitly with `.values()`; this fails for a live provider or a collection containing provider objects. There is no implicit snapshot/query conversion.

C++:

```cpp
using namespace magritte;
auto provider = std::make_shared<DynamicOptions>([](const std::string& query) {
    return Value(Value::Array{Value(query)});
});
provider->includesBlock([](const Value& value) { return value == Value("known"); });
provider->reader([](const Value& completion) { return completion; });
description->options = provider;
auto choices = description->allOptions();
assert(choices.provider() == provider);
auto completions = choices.selectMatching("known");
auto selected = provider->detect(Value("known"));

// Explicitly replace local executable behavior with a static snapshot for export.
description->options = completions.elements();
auto array = description->allOptions().values();
```

Swift:

```swift
let provider = DynamicOptions { query in .array([.string(query)]) }
provider.includesBlock = { $0 == .string("known") }
provider.reader = { $0 }
description.options = .dynamic(provider)
let choices = try description.allOptions()
let live = try choices.provider()
assert(live === provider)
let completions = try choices.selectMatching("known")
let selected = try provider.detect(.string("known"))

// Snapshotting is an explicit caller decision.
description.options = Options(try completions.elements())
let array = try description.allOptions().values()
```

Use `Options.copy()` for the source's upstream copy semantics. A regular native Options assignment retains a provider's identity. `Options.entries()` exposes collection entries as Value/provider alternatives, preserving local object identity; it does not enumerate a provider. Native collection append/remove operations require a collection. `MADynamicOptions` is registered as an ordinary class with superclass `Object`; fresh class metadata discovers it, and its Class value uses existing graph/4 interchange.

## The allOptionsWith distinction

Upstream `allOptionsWith` assumes collection protocol that a dynamic provider does not fully implement. The installed kernel's `Object>>asArray` wraps its receiver in a singleton array. Therefore:

- With extensible=false, or with a nil/already-listed current value, `allOptionsWith` copies the provider and returns a collection containing that copy. An optional single-option description prepends its undefined value. A multiple-option description does not.
- With extensible=true and an unlisted non-nil current value, membership runs and `copyWith:` fails because the provider does not implement it.
- Sorting the singleton provider invokes no comparator. Completion never runs in these paths.

Both ports preserve this behavior, including short-circuit callback order, instead of fabricating an enumerated candidate list. Provider entries are local objects and cannot be extracted as portable Values or exported. This does not expand the finite Value domain into arbitrary Smalltalk objects or certify every collection protocol.

## Metadata, text and interchange

Reading `optionsTextual` from a provider fails because it is not a collection supporting the textual conversion protocol. Writing `optionsTextual` parses a new static collection and replaces the provider only after parsing succeeds; a failed parse preserves it. Existing reference conversion and metadata descriptions remain the same.

Export rejects live providers even on hidden descriptions and never invokes callbacks. Graph/1–4 still contain only explicit static options; no callback names, captured state, provider objects or automatic materialization are put on the wire. After the caller explicitly replaces the source with static options, normal validation, readers/writers, copies, mementos and interchange continue to use the same Magritte descriptions.

## Evidence and remaining gaps

`dynamic-options-reference.json` records real live GT objects and callbacks: 80 single/multiple validation cases with error-description identities and exact membership traces; 16 flag combinations proving allOptions provider identity and no eager execution; 48 allOptionsWith cases; live completion changes, reader conversion, shallow-copy identity/callback sharing and textual source replacement. `dynamic-options-live-methods.json` records 25 Magritte methods matching pinned upstream ignoring whitespace and separately attributes the installed kernel singleton-array method. No GT classes/methods or managed checkouts were changed.

The live `Collection>>maSelectMatching:` method matches upstream source but sends `startsWith:`, which is absent on the installed GT String. Its actual failure is retained in the reference. The ports implement the source-directed case-sensitive prefix operation for the already supported scalar string conversions; GT's equivalent `beginsWith:` supplies the separately labelled expected values. This is an explicit platform projection, not a claim that the broken live method executed successfully. C++ and Swift preserve exact UTF-8 content; arbitrary object/collection printing and full Unicode sorting remain outside the existing rendering profile.

`dynamic-options-roundtrip-reference.json` records GT reconstructing each port's explicit static replacement: five descriptions and one adaptive object with single/multiple selections and a provider Class value. GT validates it, reads its values, writes `42-42, member-MADynamicOptions` and reexports equivalent graph/4 data. Replay requests are included. Every reference run uses `CCNativeMcpLease`, with the controller checking its post-release completion marker outside GT before inspecting output or making the next GT call. No native integration resources were allocated.

Native tests also check callback failures, missing blocks, limits, scalar completion results, provider retention/copying, slot replacement during invocation, export rejection, failed text replacement and current unprojected class discovery. Generate the round-trip inputs with `magritte-options-tests /private/tmp/magritte-cpp-options-native.json` and `MAGRITTE_OPTIONS_EXPORT=/private/tmp/magritte-swift-options-native.json swift test --filter DynamicOptionsTests`.

This closes the native dynamic-provider gap for the represented value domain. Grouping/renderers, mutable collection-object identity, accessor capabilities and inferred labels, further scalar domains, full description caching/building and arbitrary interpreter classes remain separate gaps. Existing historical fixture comparisons retain their declared class environments; production class discovery remains open.
