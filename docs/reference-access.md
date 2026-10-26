# Reference getter and option setter behavior (0.20)

**0.28 update:** lazy allocation, Boolean self-reference and relation helpers are now implemented; see [default-references.md](default-references.md). The explicit-reference evidence below remains the historical 0.20 profile.

Both ports now implement the display side effect of `MAReferenceDescription>>reference` and the reference update performed by `MAOptionDescription>>undefined:` for explicitly bound reference graphs. This corrects a gap exposed by the earlier display phase: an independently configured child formatter does not survive reading the parent's reference. The parent supplies the current display setting each time the getter is sent.

## Upstream audit and evidence

The source baseline remains [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), with remote HEAD reconfirmed on 2026-10-27. `reference-access-upstream-methods.json` records twenty whitespace-normalized fingerprints for reference access/copy/defaults, display/undefined configuration, option formatting/text conversion and reader/writer call sites.

`reference-access-scenarios.json` contains 24 getter cases and 24 undefined setter cases across single/multiple options, tokens and the three relation classes. Both ports consume the same source-derived expectations. Additional native checks cover shared references, partial failure, copy/codec behavior, getter timing, validation membership, cascade bounds, and equivalent snapshots. Three earlier reference-specific display assumptions were corrected in the native tests; the prior shared fixture payloads remain unchanged.

**GT was not accessed, as requested.** These checks establish upstream-source/native agreement for the stated profile, not fresh live-image behavior. Live GT comparison and replay remain deferred.

## Getter behavior

`referenceDescription()` retains the bound target, assigns the owner's current display setting to it, and returns that same object. A block is shared with its original identity; a Symbol or explicit nil is copied as data. The callback receives the description being formatted, so a propagated block's description argument is the child when the child writer invokes it. Other metadata, including the child's label, kind and undefined text, is unaffected by this getter.

Reading a shared reference changes that shared object in place. Another owner keeps its own configured display, and a later read through that owner reapplies its setting. Subsequent changes to the owner's display take effect on the next reference read; they are not broadcast eagerly to every child.

An absent owner display resets the child's override to the default `#greaseString`. The native data representation removes the child's explicit setting for this case instead of materializing a new Symbol property. Effective display is the same; this prevents ordinary formatting from introducing a graph/3-only feature into a legacy graph. Explicit Symbol and nil settings retain their presence. This is a representation projection rather than a claim of identical underlying Smalltalk property-dictionary presence.

The weak `reference` slot remains available as the native graph edge. Structural validation, ownership retention, copying, schema traversal, import and export inspect that edge without sending an imperative getter. In particular, encoding cannot clear a callback by applying the owner's default first. A native block anywhere still causes export to fail. Copying preserves the stored child display until the copied parent's getter is actually used, matching the raw-slot reference copy in upstream `postCopy`.

## Execution call sites

String readers obtain the reference when parsing an actual referenced element. Token and to-many writers obtain it for every element, allowing changes made by one formatter call to affect the next. To-one writing obtains it for its single reference conversion. Relation and token displays therefore take effect through the child; the earlier expectation that a relation's display was ignored is corrected.

Single/multiple option labels continue to use the option description's own display, with explicit labels taking precedence. Sorted option operands are converted through the reference getter and writer for each comparison. A singleton/empty sort performs no reference read. Empty multiple-option writing uses its undefined text without reading a reference. Validation reads the reference when it validates an extensible nonmember, but does not do so for an existing option member.

The recursive metadata adapter's reference and optionsTextual getters/setters, and actual relation-builder composition, use the behavioral getter. Pure schema/ownership traversal uses raw graph edges. This keeps saved state separate from executing Magritte protocols.

## Undefined setter

C++:

```cpp
using namespace magritte;
auto option = std::make_shared<Description>();
option->id = "choice";
option->className = "MASingleOptionDescription";
auto text = std::make_shared<Description>();
text->id = "text";
option->reference = text;
option->display("asString");
option->setUndefined(Value("(missing)"));
// Both option and text now have undefined text "(missing)".
```

Swift:

```swift
let option = Description(id: "choice", className: "MASingleOptionDescription")
let text = Description(id: "text")
option.reference = text
option.display("asString")
try option.setUndefined(.string("(missing)"))
// Both option and text now have undefined text "(missing)".
```

`setUndefined` accepts String or nil within the existing text-property profile and returns self. It first sets the owner's text. For an option, it sends the reference getter for the nil test and again for the child setter, following upstream, then invokes the child's setter. Nested options therefore cascade; other reference-description kinds set only their own text. This does not change the separate `undefinedValue` sentinel.

The `MASelectorAccessor` setter `undefined:` uses the same protocol, including metadata/memento writes. Direct mutation of the low-level `properties` map remains a raw state edit and does not invoke a setter. Getter-induced display propagation occurs as part of the option cascade.

Depth/work limits bound cyclic or oversized option cascades. Errors preserve the partial updates already performed; no atomic rollback or fabricated valid schema is introduced. A missing bound reference still throws after the owner's text was set. Native callbacks and mutable descriptions retain their existing synchronization/ownership requirements.

## Scope and remaining work

No graph format, value tag, class registry or application dependency is added. Codecs preserve supported stored settings without executing the getter or setter. The explicit reference ownership profile is retained: callers must bind and retain reference descriptions. Lazy default-reference allocation, relation template derivation, and Boolean's separate self-reference convenience remain outside this phase. Fingerprints for upstream defaults/fallback record that boundary rather than claiming it implemented.

Native callback identity stays local. Display/undefined behavior outside the existing supported Value and text profiles, general property announcements and the remaining audit gaps are not claimed complete.

## Executed standalone checks

On macOS arm64, all nineteen CTest targets and 74 Swift tests pass. Focused reference tests also verify that encoding a child callback fails without first clearing it. The C++ reference target passes 262 checks under both ordinary and AddressSanitizer/UndefinedBehaviorSanitizer builds (leak detection disabled). An independently installed CMake 0.20 consumer runs; an independent Swift consumer type-checks. All 114 shared fixture checksums verify, with the earlier 112 payloads unchanged.

Reproduce native snapshot comparison after building:

```sh
# In magritte-cpp:
build/magritte-reference-access-tests /tmp/reference-cpp.json
# In magritte-swift:
MAGRITTE_REFERENCE_ACCESS_EXPORT=/tmp/reference-swift.json swift test --filter ReferenceAccessTests
# In magritte-cpp:
python3 tools/compare-graphs.py /tmp/reference-cpp.json /tmp/reference-swift.json
```

These checks use standalone ports and saved fixtures only, with no GT connection.
