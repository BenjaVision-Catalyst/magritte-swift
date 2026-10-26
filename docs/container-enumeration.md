# Container lookup and enumeration (0.14)

Both ports now expose the direct collection query and enumeration protocol of `MAContainer` and `MAPriorityContainer`. The phase adds no new description hierarchy, wire format, consumer framework or executable property. It complements the previously implemented composition/copy operations.

## Audit and reference

The upstream audit remains pinned to [d67f318](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), confirmed against remote HEAD on 2026-10-26. Both native APIs had composition operations but no direct equivalents for the following `MAContainer` methods. All thirteen inspected live methods match pinned upstream after whitespace removal; `container-protocol-live-methods.json` records their SHA-256 fingerprints.

| Upstream selector | Native function (both ports) |
| --- | --- |
| `at:` / `at:ifAbsent:` | `childAt` with throwing/default and lazy fallback overloads |
| `includes:` | `includesDescription` |
| `detect:` / `detect:ifNone:` | `detectDescription` with throwing/default and lazy fallback overloads |
| `allSatisfy:` | `allDescriptionsSatisfy` |
| `anySatisfy:` | `anyDescriptionSatisfies` |
| `noneSatisfy:` | `noDescriptionSatisfies` |
| `do:` | `forEachDescription` |
| `do:separatedBy:` | `forEachDescriptionSeparated` |
| `keysAndValuesDo:` | `forEachDescriptionIndexed` |
| `inject:into:` | `reduceDescriptions` |
| `with:do:` | `forEachDescriptionPaired` |

Fresh GT execution exercises ordinary and priority containers, each populated and empty. The shared reference contains 22 observations per case, including callback traces, fallback counts, result identities by accessor name, callback failures and paired size errors. Both native tests reconstruct each entire observation dictionary and compare it to GT. The only reference projection is subtracting one from Smalltalk enumeration indices to match native zero-based indexing. Error observations compare occurrence and callback traces, not Smalltalk exception classes.

Replay: execute `container-protocol-replay.json`'s `reference` request through GT MCP, then wait outside GT for `container-protocol-mcp-gate.json` before inspecting the report or making another GT call. The reference executes under `CCNativeMcpLease`. It creates only temporary Magritte objects: no plugin, native C++ bridge or Runtime resources are allocated, so there is no independent Runtime owner to clean up. Native suites are separate standalone processes. No GT-managed source or registered checkout was changed.

## Semantics

Enumeration visits direct children in container order and retains the same child objects, including duplicates. It never recursively traverses nested children or references. Priority containers use their existing priority ordering. Detection returns the first matching object; membership uses Magritte description equality (class/accessor/children), rather than IDs or labels. Callback errors propagate immediately.

`all` stops at the first false result; `any` and `none` stop at the first true result. Empty results are respectively true, false and true. Missing index/detection raises a native error by default. Explicit fallback callbacks execute once only when absent and may return a null shared pointer in C++ or `nil` in Swift. Fallbacks are typed as descriptions; arbitrary Smalltalk fallback object types are outside these typed lookup APIs.

Separators run only between children. Indexed enumeration uses zero-based indices. Reduction accepts an arbitrary native accumulator type and returns the initial accumulator unchanged for an empty container. Paired enumeration accepts arbitrary native element types and rejects unequal lengths before invoking the body, including an empty/nonempty pair. These match the executed GT delegation behavior.

Native-only checks cover retained identity, duplicate visits, direct nested-container traversal, generic accumulator results, nullable and throwing fallbacks, errors in predicates/separators/reducers/paired bodies, invalid receivers and limits. Container size/work bounds are checked before any callback. Membership shares the composition equality work/depth budget across comparisons; it does not reset the budget per child. C++ rejects null child entries. Callbacks remain ordinary local code with caller-controlled execution time.

## Boundaries

`enumerationChildren` is the shared bounded native snapshot helper. Structural mutation of the source container during enumeration is outside this profile; no claim is made for Smalltalk's backing-collection mutation behavior. The native zero-based convention also applies to negative indices in Swift (absent) and out-of-range unsigned indices in C++. Operations retain child identity and do not copy descriptions or validate models. Existing priority tie policy and mutable collection-object identity limits remain unchanged.

The audit also inspected `MAComposedDescriptionBuilder` and `MADescriptionFlattener`, and single-option `groupBy` metadata. They require further builder/reflection/accessor metadata semantics and remain open. Composite accessors/conflicts, scalar domains, Unicode inflection, full builder/cache/interpreter protocols and arbitrary reflection remain separate gaps. This phase does not claim the complete Smalltalk collection protocol, especially moving and backing-collection mutation operations.

## Examples

C++:

```cpp
auto field = magritte::detectDescription(*root, [](const auto& d) { return d.key == "name"; });
auto count = magritte::reduceDescriptions(*root, std::size_t{0},
    [](auto n, const auto&) { return n + 1; });
magritte::forEachDescriptionIndexed(*root, [](auto index, const auto& d) { /* use d */ });
```

Swift:

```swift
let field = try detectDescription(root, where: { $0.key == "name" }, ifNone: { nil })
let count = try reduceDescriptions(root, initial: 0) { n, _ in n + 1 }
try forEachDescriptionIndexed(root) { index, description in /* use description */ }
```

No graph schema changes are needed: these APIs operate on the same descriptions returned by existing graph import and recursive metadata sessions. All earlier interchange conformance tests remain enabled.

Executed validation on macOS arm64: all 13 CTest targets, all 13 targets with AddressSanitizer/UndefinedBehaviorSanitizer, and all 48 Swift tests pass. LeakSanitizer is disabled on this host; no leak-check claim is made. A separate installed CMake consumer runs the new public functions, including a move-only accumulator and string pairing. A separate Swift consumer type-checks the public API. All 93 shared fixture hashes match.
