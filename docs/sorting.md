# Accessor-based comparison (0.19)

Both ports implement the local `MASortBlock` valuable and the inherited `isSortable` query. Earlier priority ordering and option sorting did not provide this upstream utility: MASortBlock reads two operands through one accessor and sends a configured one-argument message to the left projected value. It does not sort a collection itself or impose a Boolean return type.

## Source audit and evidence

The baseline is [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), with remote HEAD reconfirmed on 2026-10-27. `sorting-upstream-methods.json` records fourteen whitespace-normalized source fingerprints: all five MASortBlock methods, four sortability overrides/defaults, accessor identity/conversion, chain and delegator reads.

`sorting-scenarios.json` contains 69 source-directed comparisons over the existing scalar profile and fifteen concrete-description sortability expectations. Both native suites consume these expectations. Further tests cover exact read/error traces, shared accessor mutation/copy, native message dispatch, non-Boolean results, host identity and equality overrides, bounds, and reimported property-accessor comparisons. The ordinary description graphs exported by the ports are semantically equivalent.

**GT was not accessed, as requested.** These are upstream-source/native results, not live-image observations. Fresh GT comparison and replay remain deferred. Primitive number/equality/collection behavior retains the previously documented finite Value profile; the fingerprints do not establish every Smalltalk kernel method's equivalence.

## Public API

C++:

```cpp
using namespace magritte;
DictionaryModel first, second;
first.values["rank"] = Value(std::int64_t(3));
second.values["rank"] = Value(std::int64_t(7));
Accessor rank;
rank.name = "rank";
SortBlock comparison(rank, "<=");
auto result = comparison.value(first, second); // Boolean true
```

Swift:

```swift
let first = DictionaryModel(["rank": .integer(3)])
let second = DictionaryModel(["rank": .integer(7)])
let comparison = try SortBlock(accessor: Accessor(name: "rank"), selector: "<=")
let result = try comparison.value(first, second) // .boolean(true)
```

A selector-only constructor uses MAIdentityAccessor. `value` accepts either two Models or two Values and returns Value. When constructing from an inline Accessor configuration, the native bridge creates an owned AccessorObject; passing an existing AccessorObject retains its exact identity. An ordinary C++ copy or Swift `copy()` creates a shallow copy sharing that accessor. Swift assignment retains the same SortBlock instance. `fixTemps` does nothing and returns self, matching the empty upstream method.

Accessors are read **left first, then right**, before message dispatch. A left read failure prevents the right read. A right failure prevents dispatch. The accessor is materialized separately for each read, so mutations to its shared live configuration during the left read affect the right read. Configuration is not cached into permanent projected keys. The message selector is captured after the left read and before the right read, matching upstream argument evaluation. Native selector slots are immutable after initialization; ordinary C++ value assignment can replace the whole configuration. Printable ASCII nonempty selectors use the current native identity profile; incorrect message arity fails after both reads.

This valuable is not automatically a C++ strict weak comparator. Choose a suitable strict selector such as `<` and consume a Boolean result when adapting it to a native sorting algorithm. The implementation does not change MAContainer order, priority-container ordering, or the separate option reference-formatting comparator.

## Value targets and host dispatch

`Accessor.readValue` supports MAIdentityAccessor directly over represented Values, delegates through MADelegatorAccessor and executes chain stages in order. Other stages resolve object references through the supplied Graph and use the existing Model accessor protocol. This lets a chain end with identity after projecting a scalar, without inventing a boxed model identity. Raw scalar selector/variable/dictionary reflection and raw collection-object protocols remain outside this profile; bind host objects or use an existing native pluggable accessor on Models.

Primitive comparison selectors are `=`, `~=`, `<`, `<=`, `>` and `>=`. Numeric ordering uses the existing exact Int64/binary64/bounded-Fraction comparisons; equality uses the existing Value semantics. String/Symbol ordering compares exact Unicode scalar sequences through UTF-8 lexical order, without canonical normalization; Character ordering is supported against Character. Nil, Boolean, Class, collection and conflict ordering are not coerced into text. Unsupported operand pairs or scalar messages fail explicitly.

A projected reference dispatches through `Model.binaryMessage(selector, argument, graph)`. NativeModel exposes `binaryReaders`, keyed by selector, whose callback receives its host object, argument Value and resolver. It may return any supported Value, including a non-Boolean. The running callback is retained if it removes its own binding. Unknown unbound messages fail. Default Model equality compares model identity; NativeModel compares underlying host identity, including distinct adapters for the same object. Default `~=` invokes current `=` and negates its Boolean result, so an equality override is respected.

This is explicit platform protocol binding. No arbitrary Smalltalk evaluator, remote dispatch or executable wire language is introduced. Accessor snapshots, access operations, Value shapes and projected comparison work use the existing configurable Limits; cyclic or over-budget configurations throw. Native user callbacks remain arbitrary local code and cannot be preempted by those limits. Mutable accessors, models and callback state require caller synchronization.

## Sortability and interchange

`Description.isSortable` defaults to false, becomes true for String and Magnitude descriptions and is overridden to false for Password. Registered subclasses inherit those represented defaults. Native C++/Swift subclasses may override the virtual/open query. `isSortable` is also an available read-only metadata selector; it is not a new stored semantic property or annotated self-description field. It does not validate a comparator or forbid explicit comparisons of a value.

MASortBlock is registered as a runtime class under MABasicObject. Its instances and host callbacks remain local: there is no new Value tag, executable graph node or serialized sort plan. Existing portable accessor/description snapshots can be exported and later consumed by a newly created local SortBlock; graph formats are unchanged. Tests compare imported description priorities through MAPropertyAccessor and export the same ordinary three-description graph from each port. The previous fixture payloads retain their bytes.

Full object/collection identity, arbitrary scalar message reflection, additional scalar domains, complete self-description discovery and other gaps in the support matrix remain separate work.

## Executed standalone checks

On macOS arm64, all eighteen CTest targets and 70 Swift tests pass. The C++ sorting target additionally passes 233 checks under both the ordinary build and AddressSanitizer/UndefinedBehaviorSanitizer (leak detection disabled). An independent installed CMake 0.19 consumer runs; an independent Swift consumer type-checks. All 112 shared fixture checksums verify; the preceding 110 payloads remain unchanged.

To reproduce native schema export comparison after building:

```sh
# In magritte-cpp:
build/magritte-sorting-tests /tmp/sorting-cpp.json
# In magritte-swift:
MAGRITTE_SORTING_EXPORT=/tmp/sorting-swift.json swift test --filter SortingTests
# In magritte-cpp:
python3 tools/compare-graphs.py /tmp/sorting-cpp.json /tmp/sorting-swift.json
```

These checks use standalone code and saved fixtures, with no GT connection.
