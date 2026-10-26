# Description display conversion (0.18)

Both standalone ports implement the `MADescription>>display:` / `displayStringFor:` protocol for the current native Value profile. String writing and option-label fallback now use the description's configured selector or block. The default remains `#greaseString`. This adds a missing headless model protocol without a UI or application-framework dependency.

## Audit and evidence

The baseline remains [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), with remote HEAD reconfirmed on 2026-10-27. The audit found fixed scalar/option rendering in both ports despite upstream's configurable display protocol. It also found eager precomputed static-option sort keys, which made formatter calls observable even for a singleton, unlike upstream's comparator-based conversion.

`display-upstream-methods.json` records 22 whitespace-normalized source fingerprints covering description configuration/default/copy/conversion, writer dispatch, option label/sort behavior and the intent of upstream's display tests. `display-scenarios.json` contains 39 independently written expectations derived from those sources. The fixture is consumed by both ports and is explicitly source-backed, not an executed GT reference.

**GT was not accessed during this phase, as requested.** Fresh live-image comparison and GT graph replay remain deferred. Native tests exercise selector/block arity, nil handling, Boolean specialization, explicit labels, reference versus option rendering, sorting, local identity/copy, callback replacement, native message bindings, graph snapshots and bounds. Each port exports the same two-description graph with an adaptive object, validates it and writes `Ada`; the native graph comparator checks their semantic equality.

## Native API

C++:

```cpp
using namespace magritte;
auto d = std::make_shared<Description>();
d->id = "name";
d->key = "name";
d->display(std::make_shared<DisplayBlock>(
    [](const Value& value, const Description&) {
        return "[" + std::get<std::string>(value.data) + "]";
    }));
auto text = writeString(*d, Value("Ada")); // [Ada]
d->display("asString");                 // replaces the block
```

Swift:

```swift
let d = Description(id: "name", key: "name")
d.display(DisplayBlock { value, _ in
    guard case .string(let text) = value else { throw MagritteError("Expected String") }
    return "[" + text + "]"
})
let text = try writeString(.string("Ada"), using: d) // [Ada]
d.display("asString")                               // replaces the block
```

`DisplayBlock` accepts a native function with zero, one or two arguments, corresponding to upstream's culled arguments: candidate value and description. Functions return String and may propagate errors. Descriptions copied through the existing copy/build protocols share the same local block object; each call receives the actual description used for conversion. A running callback remains alive if it replaces its own display setting. `displayBlock` exposes local callable identity; `property("displayBlockOrSymbol")` returns the selector/default or explicit nil for data settings, and throws for a local block rather than fabricating a Value representation.

The display setter overloads replace the whole setting. Direct edits to the low-level properties map and callable slot require managing both slots explicitly. Descriptions/models/captured mutable state retain their existing caller-synchronization requirements.

## Selector dispatch

Selector settings are stored as Symbol values in `displayBlockOrSymbol`; absent means `#greaseString`, while explicit nil remains nil and fails if invoked. The current scalar bridge provides `greaseString`/`asString`, String `yourself`, and Class `label` using the open class registry. Unsupported scalar messages throw; arbitrary scalar reflection and complete Grease printing remain outside the represented profile. Applications can express other conversions through a native block.

Reference values dispatch through the provided Graph resolver to `Model.displayMessage`. ASCII unary selectors receive no description argument; binary or single-keyword selectors receive the description. More than one argument fails. NativeModel supplies `displayReaders` keyed by selector, with the host object and an optional description argument. An unbound unary display message falls back to existing `MASelectorAccessor` reader bindings. Bindings must return a String Value. No string evaluator, remote message send or Smalltalk compiler is introduced.

For example, register a `shortName` selector reader or a `caption:` display reader on a NativeModel, set `description.display("shortName")` or `description.display("caption:")`, and pass its owning resolver to `writeString` / `displayStringFor`. The option APIs also accept an optional resolver: C++ `labelForOption(value, limits, graph)` and `allOptions(limits, graph)`; Swift `labelForOption(value, graph:)` and `allOptions(graph:)`.

## Writer and option semantics

- Direct `displayStringFor` invokes the display even for nil. MAStringWriter's outer nil handling writes `undefined` without invoking it.
- Element formatting uses the display protocol. Boolean writing retains its specialized true/false strings; direct Boolean display can still be customized. Existing supported-kind boundaries, including Class writer input checks, remain.
- Container writing traverses its fields and ignores the container's own display. Relation writing uses its reference's writer. Token elements use reference visitor dispatch, including direct nil display rather than the outer undefined shortcut.
- Explicit identity-safe option labels take precedence. An unlabelled option uses the option description's display, not its reference's display. Multiple-option writing applies that rule to every element; empty collections write `undefined`.
- Static-option sorting converts the two operands through the reference's writer for each comparison. Empty and singleton collections invoke no formatter. Optional single-choice undefined entries are added after sorting. Native algorithms preserve equal-key order, but comparison counts/order are not claimed identical across C++, Swift or Smalltalk VMs. Formatters used for sorting must provide consistent ordering. Existing ASCII case-insensitive ordering remains the supported profile.

Text reading and validation do not apply display transformations. Display callbacks are local executable behavior; their side effects/errors are not rewritten as validation errors. Input Value shape, UTF-8, collection depth/items and work are checked. Display output has a byte/work limit independent of JSON-envelope overhead. User callbacks themselves remain arbitrary native code and are not preempted by those limits.

## Interchange and remaining gaps

Graph/3–4 can preserve `displayBlockOrSymbol` as Symbol or explicit nil with existing Value tags. Wrong property types fail import/export. Graph/1–2 reject this setting, including nil. Unknown selector names remain data until explicitly invoked through the receiver's supported protocol; loading a graph does not install host methods. No new graph version or competing schema is added.

Any local display block makes graph export fail, including on a hidden or otherwise unvisited node. Replacing it explicitly with a supported selector permits a portable snapshot. Shared callback identity, host method implementations and mutable captured state are never silently serialized.

MAMessagingStringWriter, arbitrary interpreter instances, option grouping, arbitrary object/collection printing, full Unicode case-insensitive sorting and the other unsupported scalar domains remain separate gaps. This phase does not claim full Magritte or full Smalltalk message semantics.

## Executed standalone checks

On macOS arm64, all 17 CTest targets and 65 Swift tests pass. Focused follow-up tests additionally check malformed wire types and explicit nil rejection in legacy formats. The C++ display target passes 126 checks under both the ordinary build and AddressSanitizer/UndefinedBehaviorSanitizer (leak detection disabled). An independently installed CMake 0.18 consumer runs; an independent Swift consumer type-checks. All 110 shared fixture checksums verify, and the previous 108 payloads remain byte-identical.

Reproduce native export comparison after building:

```sh
# In magritte-cpp:
build/magritte-display-tests /tmp/display-cpp.json
# In magritte-swift:
MAGRITTE_DISPLAY_EXPORT=/tmp/display-swift.json swift test --filter DisplayTests
# In magritte-cpp:
python3 tools/compare-graphs.py /tmp/display-cpp.json /tmp/display-swift.json
```

These checks use standalone libraries and saved fixtures only, with no GT connection.

Phase 0.20 corrects the reference-specific boundary of this phase: reading a reference overwrites its display from the owner, so a child renderer is not independent of that getter. Relation/token conversion inherits the owner setting through reference access, and sorting obtains that reference for each operand. Native tests were corrected to reflect the upstream getter; the scalar display fixtures remain unchanged. See [reference-access.md](reference-access.md).
