# Stored property operations (0.21)

Both ports now expose the stored-Value part of `MATPropertyOwner` on their Description models: strict/fallback lookup, conditional lazy operations, property writes and nil-removing writes. These operate on stored presence. They do not replace the existing default-aware `property` getter or turn the properties map into a second schema language.

## Audit and evidence

The baseline remains [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), with remote HEAD reconfirmed on 2026-10-27. The audit found that both ports exposed raw dictionaries and selected metadata getters, but lacked this trait protocol.

`properties-upstream-methods.json` records 21 whitespace-normalized fingerprints covering the trait storage operations, shallow property-copy intent, MAPropertyAccessor integration and six upstream MAObject test methods. The announcement methods are recorded to identify the excluded subscribed case; their presence is not an implementation claim.

`properties-scenarios.json` contains fifty independently written cases: ten operations across absent, nil, false, numeric and textual stored states. Each port checks the result, stored state, presence and callback trace. Further native tests cover default-aware versus strict reads, reentrant/throwing callbacks, accessor integration, local callback boundaries, copy isolation, codec snapshots and limits. Both ports export equivalent ordinary description graphs preserving an explicitly stored nil property.

**GT was not accessed, as requested.** These results are upstream-source/native evidence; fresh GT comparison and replay remain deferred.

## API mapping

| Upstream selector | Native operation |
| --- | --- |
| `hasProperty:` | `hasProperty` |
| `propertyAt:` | `propertyAt(key)` |
| `propertyAt:ifAbsent:` | C++ `propertyAt(key, fallback)`; Swift `propertyAt(key, ifAbsent:)` |
| `propertyAt:ifAbsentPut:` | `propertyAtIfAbsentPut` |
| `propertyAt:ifPresent:` | `propertyAtIfPresent` |
| `propertyAt:ifPresent:ifAbsent:` | `propertyAtIfPresentOrElse` |
| `propertyAt:ifPresent:ifAbsentPut:` | `propertyAtIfPresentOrPut` |
| `propertyAt:put:` | `propertyPut` |
| `propertyAt:putRemovingNil:` | `propertyPutRemovingNil` |

C++:

```cpp
using namespace magritte;
Description description;
description.id = "example";
auto first = description.propertyAtIfAbsentPut("metadata:note", [] {
    return Value("created once");
});
auto removed = description.propertyPutRemovingNil("metadata:note", Value());
// removed is "created once"; hasProperty("metadata:note") is now false.
```

Swift:

```swift
let description = Description(id: "example")
let first = try description.propertyAtIfAbsentPut("metadata:note") {
    .string("created once")
}
let removed = try description.propertyPutRemovingNil("metadata:note", .undefined)
// removed is .string("created once"); the key is now absent.
```

A strict missing lookup throws a native error labelled `MAPropertyError`. A default-aware description getter may still return a default when no entry exists: for example, `property("visible")` returns true while `hasProperty("visible")` is false and `propertyAt("visible")` fails.

Stored nil and false are present values. They never trigger an absent branch. `ifPresent` returns nil for an absent key; when present, it returns the callback result without storing that result. The combined present/absent-put operation stores the fallback only on the absent path. Non-storing fallback operations do not insert anything.

`propertyPut` stores and returns the supplied value, including nil. For `propertyPutRemovingNil`, a non-nil argument follows that same rule; a nil argument removes the entry and returns its old value, or nil if absent. This old-value return is distinct from the supplied nil.

Only the chosen callback runs. A value passed to a present callback is retained as a native Value snapshot before callback execution, so removing its dictionary entry during the callback is safe. An absent-put callback may itself write the key; its returned value is then stored by the outer operation. Exceptions propagate with any callback side effects already performed; no rollback is invented. Callback results remain within the supported local Value profile.

## Accessors, copies and local slots

MAPropertyAccessor now delegates Description storage reads/writes to these operations, using an absent-nil fallback as upstream does. Property writes are storage operations, not calls to description-specific setters. For example, writing the `undefined` property directly does not perform the option/reference cascade of `setUndefined` or selector `undefined:`.

Copying descriptions keeps independent dictionaries with the existing Value snapshot/reference semantics. Changing a copied entry leaves the original dictionary unchanged. Full mutable collection-object aliasing is still outside this profile.

Local display blocks have no Value representation. `hasProperty("displayBlockOrSymbol")` recognizes their presence, but a Value lookup or nil-removing operation that would have to return the block fails explicitly. A property/accessor write of a supported data setting replaces the block and returns the new Value. Existing direct native default-function and other callback slots remain separate local APIs; this phase does not make arbitrary callable objects into Values.

## Scope, bounds and interchange

This phase implements the storage protocol with no propertyAnnouncer installed. Subscription delivery, weak subscribers, MAPropertyChangedAnnouncement objects and general property announcements remain unimplemented. The property API rejects writes to the reserved `propertyAnnouncer` slot and refuses storage mutation when raw state contains that slot, rather than pretending to announce changes. It is not a general announcement framework or a complete MAObject hierarchy implementation.

Stored keys use the existing nonempty printable ASCII identity profile. Values and callback results are checked against existing byte/item/depth/work limits. Arbitrary native callback execution is not preempted by those limits. Callers synchronize dictionary/model/captured-state mutation as before.

No new graph version, tag or semantic property allowlist entry is added. Supported stored presence, including nil, survives snapshots. Unknown semantic names may be stored locally but still fail graph export; `metadata:` retains its existing explicitly opaque consumer-metadata meaning. Default-aware getters, validators and codecs retain their existing contracts. Direct access to the low-level `properties` map remains available and bypasses the checked operation API.

Phase 0.22 adds nil-only lazy default initialization through `maLazyPropertyUsing:`; see [lazy.md](lazy.md). Full mutable property-object identity and the other audit gaps remain separate phases.

## Executed standalone checks

On macOS arm64, all twenty CTest targets and 78 Swift tests pass. The C++ property target passes 236 checks under ordinary and AddressSanitizer/UndefinedBehaviorSanitizer builds (leak detection disabled). An independently installed CMake 0.21 consumer runs, and an independent Swift consumer type-checks. All 116 shared fixture checksums verify; the preceding 114 payloads remain unchanged.

Reproduce native graph comparison after building:

```sh
# In magritte-cpp:
build/magritte-property-tests /tmp/properties-cpp.json
# In magritte-swift:
MAGRITTE_PROPERTIES_EXPORT=/tmp/properties-swift.json swift test --filter PropertiesTests
# In magritte-cpp:
python3 tools/compare-graphs.py /tmp/properties-cpp.json /tmp/properties-swift.json
```

These checks use standalone code and saved fixtures, with no GT connection.

Phase 0.24 adds local print-hook slots under `maPrintString` and `maPrintStringSeparator`, with the same explicit Value-versus-callable boundary. `hasProperty` sees installed hooks; Value lookup/removal cannot return them, and a checked Value write replaces the local slot. Typed clear operations remove presence. These settings remain rejected by all graph formats. See [printing.md](printing.md).
