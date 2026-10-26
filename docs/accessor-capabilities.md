# Accessor capabilities

Phase 0.11 implements `canRead` and `canWrite` for the eight represented Magritte accessor strategies. The upstream baseline remains [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e), verified against upstream HEAD on 2026-10-26. The live GT implementations of all 15 distinct inspected capability/read/write methods match that source ignoring whitespace; fingerprints are in `accessor-capabilities-live-methods.json`.

## Rules

| Accessor | canRead | canWrite |
| --- | --- | --- |
| MADictionaryAccessor / MAPropertyAccessor | true | true |
| MASelectorAccessor | non-nil read selector understood by the target | non-nil write selector understood by the target |
| MAVariableAccessor | target has the named instance slot | same slot-existence test |
| MAIdentityAccessor | true | false |
| MANullAccessor | false | false |
| MADelegatorAccessor | delegate's canRead | delegate's canWrite |
| MAChainAccessor | every intermediate accessor can read; terminal canRead | every intermediate accessor can read; terminal canWrite |

These are Magritte capability queries. They do not validate values, enforce description flags, check selector arity, execute setters, or guarantee that a subsequent operation succeeds. Dictionary/property accessors answer true even for an incompatible model or a missing key. Variable checks use slot existence independently of the available getter/setter bindings. Selector checks use method presence independently of whether the binding is registered as a getter or setter.

Leaf capability checks do not execute bound getters, setters or defaults. Chains read intermediate targets after checking each intermediate accessor's canRead, including during canWrite. They short-circuit when a head cannot read and propagate errors from getters. A head need not have a setter. A nested head chain can therefore execute its intermediate getters twice: once during its own capability check, then again when reading that head. The terminal getter is not executed.

## Native protocol bridge

C++ `Model` and Swift `Model` expose `respondsToSelector` and `hasVariable` hooks. Their defaults are false. Applications implementing a custom Model with selector/variable access override these hooks to describe their exported host protocol. There is no attempt to discover arbitrary C++ members, Swift properties or Smalltalk methods by executing them.

`NativeModel` derives selector presence from the union of its `MASelectorAccessor:` reader/writer bindings. It derives variable existence from the union of its `MAVariableAccessor:` bindings. These maps declare the exported method/slot surface, including inherited members supplied by the adapter. A variable declared with only a reader still answers true for both capability queries; an unbound write continues to fail explicitly. Removing or adding a binding changes discovery immediately. An empty C++ std::function does not declare an executable binding; a null C++ target has no exported host protocol.

Description models and recursive description/accessor adapters report their already implemented selector surface, with class-specific fields determined at query time. The hooks do not materialize accessor objects, evaluate defaults or require a metadata field's current value to be non-nil. Expired recursive sessions fail explicitly. This remains the selected native metadata protocol, not discovery of every method in an entire Smalltalk image. Other Model implementations inherit the empty host selector/variable surface unless they provide hooks; their existing readUsing/writeUsing protocols remain independent.

C++:

```cpp
magritte::Accessor accessor;
accessor.className = "MASelectorAccessor";
accessor.name = "contents";
accessor.writeName = "contents:";
// model's existing NativeModel bindings declare the exported selectors.
bool readable = accessor.canRead(model);
bool writable = accessor.canWrite(model);
```

Swift:

```swift
let accessor = Accessor(
    className: "MASelectorAccessor", name: "contents", writeName: "contents:")
let readable = try accessor.canRead(model)
let writable = try accessor.canWrite(model)
```

Pass a Graph resolver for intermediate object references, as for existing chain read/write operations. Receiver-independent terminal checks (dictionary/property/identity/null, or an absent selector) do not require resolving an intermediate value, including nil. Traversal needing a model uses the existing reference-based native object profile; arbitrary inline scalar/collection reflection remains unsupported and fails explicitly. Query work and accessor structure obey the existing configurable visit/depth limits. Host callbacks can have ordinary side effects and remain responsible for their own execution time and synchronization. No capability result is cached.

## Absent selectors and interchange

An empty `name` or `writeName` in a selector accessor represents its corresponding nil selector. Both absent slots answer false independently. Calling read/write with an absent selector fails before consulting a binding. The existing wire fields `readSelector` and `writeSelector` use an empty string for absence, symmetrically; nonempty selectors retain the printable ASCII identity rules. This extends the earlier getter-only profile to setter-only and fully unconfigured selector accessors without adding another graph format. An actual empty Smalltalk Symbol is outside this profile.

Accessor-object snapshots preserve these slots. Reading the annotated `selector` field of a selector accessor with a nil read selector returns nil, matching GT. Existing `selector:` metadata writes still require the supported String/Symbol setter protocol. Graph round trips preserve setter-only descriptions. Capability results and host bindings are derived local state and are never serialized. Existing local Description.nativeRead/nativeWrite callbacks remain separate from an Accessor object; they do not manufacture a first-class MAPluggableAccessor or a portable closure.

## Evidence and limits

`accessor-capabilities-reference.json` records 54 actual GT scenarios and 108 capability queries, with getter/setter counts on an independently authored temporary MAValueHolder subclass. Coverage includes all eight represented strategies, inherited variables, absent/missing/swapped-arity selectors, incompatible dictionary/property targets, delegation, multi-step/nested chains, nil intermediate values, short circuits and propagated errors. Nil selector metadata is also checked directly in GT. Both ports check the shared results and invocation traces; native Error/throws are checked as failures rather than claiming Smalltalk exception-class equivalence.

`accessor-capabilities-replay.json` contains the GT MCP class creation, method compilation, reference evaluation and class cleanup requests. Replay create/compile before reference. The probe was compiled only through GT MCP, removed afterward, and verified absent. It has no persistent source checkout. The native C++ test optionally exports its 54 accessor configurations to a supplied output path; Swift does the same with MAGRITTE_CAPABILITIES_EXPORT. `accessor-capabilities-roundtrip-replay.json` imports each port's emitted records into actual GT accessors and reruns the queries. The two roundtrip-reference files reproduce every original result and trace exactly.

Reference operations ran inside CCNativeMcpLease. After each lease completed, the controller checked its completion marker outside GT before inspecting output or making another GT call. These pure Magritte queries allocated no native Runtime/plugin resources. Workspace GT-managed checkouts were identified through the image registry and were not changed.

Native-only checks cover binding updates, protocol direction independence, absent-selector operation failures, description flags, selected recursive metadata discovery and expiry, live accessor snapshots, graph interchange and work/depth failures. Validation on macOS arm64: ten CTest targets, all ten again with AddressSanitizer/UndefinedBehaviorSanitizer, and 44 Swift tests (plus the expanded capability cases rerun). LeakSanitizer was disabled on this host; no leak-check claim is made. Installed CMake and external Swift import checks exercise the public APIs.

MACompositeAccessor/conflict objects, a first-class native MAPluggableAccessor, inferred camel-case labels, arbitrary host reflection, mutable collection-object identity, the remaining scalar domains and complete builder/cache/interpreter protocols remain separate missing Magritte semantics. This phase adds no consumer framework, networking or unrelated platform behavior.

Phase 0.12 adds the separate first-class MAPluggableAccessor protocol; see [pluggable-accessors.md](pluggable-accessors.md). The eight-strategy evidence above remains the 0.11 reference profile.

Phase 0.13 implements the current ASCII accessor name/label inference profile and isolates older raw-key metadata projections; see [accessor-inference.md](accessor-inference.md).
