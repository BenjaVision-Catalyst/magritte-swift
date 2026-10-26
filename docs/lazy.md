# Lazy initialization and initial answers (0.22)

Both ports implement the supported Value profile of `MAElementDescription>>lazilyInitializeFrom:for:`, `MATPropertyOwner>>maLazyPropertyUsing:` and `initialAnswer`/`initialAnswer:`. This phase extends the existing description/model protocol without adding a new schema or event framework.

## Audit and evidence

The baseline is [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), with remote HEAD reconfirmed on 2026-10-27. The preceding phase exposed stored-property operations but lacked these consumers of that protocol.

`lazy-upstream-methods.json` fingerprints twelve upstream methods, including the element initialization/answer/default methods, property-owner bridge, cache-default inheritance and adaptive-model write. `lazy-scenarios.json` records 144 source-derived lazy cases across four description classes, inherited/explicit caching, six current values and two defaults, plus six initial-answer cases. Both native suites consume that one expected-results set. Further tests check repeated nil writes, write failures, callable-default refusal, raw lookup, asymmetric selectors, reference identity, metadata access, copy isolation, graph snapshots and bounds.

**GT was not accessed, as requested.** This phase provides upstream-source and standalone native evidence. Fresh GT comparison and replay remain deferred.

## APIs and behavior

C++:

```cpp
using namespace magritte;
Description field;
field.id = field.key = "name";
field.properties["default"] = Value("Alan");
field.properties["shouldCacheDefault"] = Value(true);
AdaptiveModel model;
auto value = field.lazilyInitializeFrom(Value(), model);
// value and model.values.at("name") are "Alan".
field.setInitialAnswer(Value()); // Explicit nil; initialAnswer() now returns nil.
```

Swift:

```swift
let field = Description(id: "name", key: "name")
field.properties["default"] = .string("Alan")
field.properties["shouldCacheDefault"] = .boolean(true)
let model = AdaptiveModel(description: field)
let value = try field.lazilyInitializeFrom(.undefined, for: model)
// value and model.values["name"] are .string("Alan").
try field.setInitialAnswer(.undefined) // Explicit nil; initialAnswer() now returns nil.
```

The current value is supplied by the caller. A non-nil value is returned unchanged, including false, zero, an empty string/collection and a non-nil custom undefined sentinel. Otherwise the initializer obtains the declared default, writes it through the supplied model if `shouldCacheDefault` is true, then returns it. It does not read the model, validate the default, consult visibility/read-only flags or call `shouldWrite`. Cache inheritance is unchanged: to-many relation/scalar descriptions default true, other supported descriptions false.

A nil default is written when caching is true; another call with a nil current value writes again. A failed write propagates its error and retains any writer side effects. Defaults are not copied or evaluated. Reference Values keep their target identity, while inline collections retain the established snapshot boundary; shared mutable collection-object identity is still unsupported.

`initialAnswer()` returns a stored initial answer, including an explicitly stored nil, and otherwise returns the current declared default. The fallback is not stored. `setInitialAnswer` stores the Value and returns the receiver. Ordinary selector access (`initialAnswer`/`initialAnswer:`) uses these methods. Lazy initialization uses `default`, independently of `initialAnswer`.

The existing native `defaultFunction` represents an evaluated callback, not a raw block Value. The new methods therefore explicitly refuse that slot when they need a default. A non-nil current value or a stored initial answer bypasses it. Existing `defaultValue()` and memento callback behavior is unchanged; this phase does not introduce arbitrary callable Values.

## Property-owner bridge

Call `owner.maLazyPropertyUsing(field)` (Swift: `try owner.maLazyPropertyUsing(field)`) on a Description property owner. The field must have a selector accessor with a nonempty read selector. The bridge looks up the owner's raw stored property under that read-selector name, treating absence as nil, then calls the lazy initializer. It never invokes the getter, which avoids the recursive getter call that upstream's protocol is designed to prevent.

Caching still writes through the field's actual accessor. Its writer need not match its reader: a `label`/`comment:` pair reads raw `label` and caches through `comment:`. An absent writer works when caching is false and fails when a nil current value requires a cached write. Unsupported accessor kinds fail explicitly. Property-owner support remains the Description stored-Value profile; no general native trait/object-storage framework is added.

The initialization and initial-answer APIs require an element description. Containers reject them. Registered element descendants inherit this protocol through the existing runtime class environment.

## Interchange and scope

Graph/3–4 accepts the element property `initialAnswer` with any supported Value, preserving absence versus stored nil and existing reference rules. Graph/1–2 rejects it even when nil. No wire tag or graph version is added. Upstream does not annotate these methods as description fields, so the recursive annotated schema is unchanged. Existing copy operations preserve the stored property with independent dictionaries and the established Value/reference semantics.

Checked Value/property/accessor operations use the existing byte/item/depth/work limits. Arbitrary model callbacks are not preempted. Callers synchronize model and metadata mutation. Announcement subscriptions, mutable collection aliasing, default-object copying and the remaining audit gaps are separate work.

## Executed standalone checks

On macOS arm64, all 21 CTest targets and 82 Swift tests pass. The C++ lazy target passes 350 checks in ordinary and AddressSanitizer/UndefinedBehaviorSanitizer builds (leak detection disabled). An independently installed CMake 0.22 consumer runs, and an independent Swift consumer type-checks. All 118 shared fixture checksums verify; the preceding 116 payloads remain unchanged. Both native graph exports compare equivalently.

```sh
# In magritte-cpp:
build/magritte-lazy-tests /tmp/lazy-cpp.json
# In magritte-swift:
MAGRITTE_LAZY_EXPORT=/tmp/lazy-swift.json swift test --filter LazyTests
# In magritte-cpp:
python3 tools/compare-graphs.py /tmp/lazy-cpp.json /tmp/lazy-swift.json
```

These checks use standalone code and saved fixtures, with no GT connection.
