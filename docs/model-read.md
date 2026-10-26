# Generic-object nil-read fallback (0.26)

Both ports now implement upstream Object>>readUsing:'s nil-only fallback: perform the accessor read once, then return the description's current undefinedValue if that result is nil. This closes the generic-object read gap recorded in phase 0.25. Declared defaults, initial answers, validation and lazy-default caching remain separate protocols.

## Upstream verification

The baseline remains [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), with remote HEAD reconfirmed on 2026-10-27. The audit checked all readUsing: definitions in Magritte-Model: Object provides the generic fallback; MAAdaptiveModel returns actual/absent nil; MAMemento is abstract; straight and cached mementos provide their own read methods. Checked mementos inherit cached reads.

`model-read-upstream-methods.json` fingerprints fifteen methods covering the generic hook, accessor reads, undefinedValue configuration, adaptive/memento overrides and validator order. `model-read-scenarios.json` contains 441 cases across nine generic adapter paths and seven memento cases. These are source-derived native expectations. Additional tests check absent versus stored nil, single evaluation and post-read metadata, errors, raw chain stages, explicit overrides, validation/printing/comparison, reflective adapters, session lifetime/limits and ordinary graph snapshots.

**GT was not accessed, as requested.** This phase supplies upstream-source and standalone native evidence. Fresh live-GT execution/replay remains deferred. All preceding fixture payloads remain unchanged.

## Read boundary

Generic model reads now behave as follows:

| Accessor result | Model read result |
| --- | --- |
| nil | Current description undefinedValue, including nil |
| false, zero, empty string/collection, Symbol or reference | The original non-nil Value |
| Accessor/callback failure | The same failure propagates |

The undefinedValue lookup occurs after the accessor finishes. A reader that changes that setting and returns nil therefore exposes the new setting. The reader is not retried. No default function, declared default, initialAnswer, validation, UI flag or shouldCacheDefault operation is consulted. The hook does not write the returned sentinel into the model or cache. Existing Value snapshot/reference ownership semantics are unchanged.

Direct Accessor.read and readSlot remain raw operations. In particular, chain stages use raw accessors: an intermediate nil that prevents further traversal raises the existing error, and a completed chain returning nil falls back only once at the outer model boundary. Missing selector bindings, null accessors and throwing native readers are not converted into undefined values.

## Native coverage and API

The fallback applies to NativeModel (both direct nativeRead callbacks and bound accessors), DictionaryModel, Description reads, and recursive description/accessor/condition adapters. Resolver-aware adapters retain their existing Graph context. Condition adapters still have empty annotated schemas; supported explicit accessor reads now use the generic hook without inventing condition metadata fields. Recursive adapters retain their session lifetime and result-encoding limits.

C++ Model::readUsing now has a default implementation instead of being pure virtual. Swift Model supplies the corresponding public default protocol implementation. A model exposing raw readSlot behavior may inherit it; specialized models may still implement their own read method. Graph-dependent custom models retain responsibility for their resolver-aware overrides, as before.

C++:

```cpp
using namespace magritte;
Description field;
field.id = field.key = "value";
field.properties["undefinedValue"] = Value("missing");
DictionaryModel dictionary;
auto value = dictionary.readUsing(field); // "missing"
auto raw = field.effectiveAccessor().read(dictionary); // nil
// dictionary.values remains empty.
```

Swift:

```swift
let field = Description(id: "value", key: "value")
field.properties["undefinedValue"] = .string("missing")
let dictionary = DictionaryModel()
let value = try dictionary.read(using: field) // .string("missing")
let raw = try field.effectiveAccessor.read(dictionary) // .undefined
// dictionary.values remains empty.
```

Absent dictionary/property slots and explicitly stored nil produce the same model read result while retaining their different stored presence. Direct Description metadata reads use the reading field's undefinedValue, not the target description's sentinel as a second fallback layer.

## Adaptive models, mementos and consumers

MAAdaptiveModel's override is preserved: absent or stored nil stays nil. Explicit custom Model overrides also remain authoritative. The generic hook is not an interceptor around every override.

Memento algorithms are unchanged, but their underlying generic model reads now expose the correct sentinel. A straight memento substitutes the declared default only if the underlying model result is nil; a non-nil sentinel remains a sentinel. Cached/checked mementos cook values equal to undefinedValue into defaults when pulling. Checked original values retain the underlying model result. A staged nil returned by a cached memento stays nil; it is not passed through another generic fallback. Adaptive-backed mementos keep their existing rules.

Validation, printing, readToString, builders and isSameAs consume Model read hooks and consequently see the corrected result. For example, a required generic field whose raw slot is nil and whose undefinedValue is a non-nil Symbol exposes that sentinel and follows the validator's undefined-value skip. The corresponding absent adaptive value stays nil and can produce required and kind errors. A non-nil sentinel also reaches ordinary printing; it is not skipped as raw nil or replaced by a declared default. Comparison's own nil/default algorithm is unchanged and observes the supplied model's read result.

## Bounds and interchange

No graph version, Value tag, semantic property, annotation field or class registry entry is added. undefinedValue was already part of the shared representation. Import/export preserves stored values and absence without invoking model reads or materializing sentinels. Generic dictionary/native adapters remain local adapters; graph object-table entries retain MAAdaptiveModel semantics.

The generic read hook retains the existing no-Limits method signature. Accessor checks and bounded interpreter/session operations retain their contracts; recursive adapters check the substituted Value against session encoding limits. Reference-valued sentinels retain their IDs and require the normal resolver context in consumers that resolve/validate them. No mutable collection-object identity, automatic default creation or arbitrary callable Value support is added. Callers synchronize model/description/callback mutation as before; callbacks are not preempted.

## Executed standalone checks

On macOS arm64, all 25 CTest targets and 98 Swift tests pass. The focused C++ target passes 1,416 checks in ordinary and AddressSanitizer/UndefinedBehaviorSanitizer builds (leak detection disabled). An independently installed CMake 0.26 consumer runs, and an independent Swift consumer type-checks a model inheriting the generic read implementation. All 126 shared fixtures verify; the preceding 124 payloads remain unchanged. Both native graph exports compare equivalently, preserving an adaptive object's absent field while an imported description supplies the dictionary fallback.

```sh
# In magritte-cpp:
build/magritte-model-read-tests /tmp/model-read-cpp.json
# In magritte-swift:
MAGRITTE_MODEL_READ_EXPORT=/tmp/model-read-swift.json swift test --filter ModelReadTests
# In magritte-cpp:
python3 tools/compare-graphs.py /tmp/model-read-cpp.json /tmp/model-read-swift.json
```

All checks use standalone code and saved fixtures, with no GT connection.
