# Description error messages (0.23)

Both ports now use Magritte's description-specific required, kind, numeric-range and checked-memento conflict messages. This replaces the generic native failure text for those errors. Existing leaf codes, description identities, validation ordering and memento reset behavior retain their contracts.

## Upstream audit and evidence

The baseline remains [d67f318686b7779aed79416db121e257d1191f2e](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model), with remote HEAD reconfirmed on 2026-10-27. The audit reviewed MADescription's message getters/setters and validation, MAMagnitudeDescription's generated range text, the validator's call order, option/relation failures, checked-memento conflict validation and upstream message tests.

`messages-upstream-methods.json` fingerprints 22 selected methods, including four upstream test methods. `messages-scenarios.json` provides 35 getter cases and forty validation cases, covering absence, overrides, empty strings, Unicode/NUL, stored nil, open/closed ranges and scalar/option/relation errors. Expected results are derived from upstream source and shared by both native suites. Further tests cover display-writer call order and mutation, override short-circuiting, formatter failures, child-option error attribution, conflict reset timing, selector access, copy isolation, codecs and limits.

**GT was not accessed, as requested.** The evidence is pinned upstream source and standalone native execution. Fresh live-image comparison and replay remain deferred. Older GT fixtures remain historical and unchanged.

## Native API

Each Description exposes `requiredErrorMessage`, `kindErrorMessage`, `conflictErrorMessage`, and `rangeErrorMessage`, plus the corresponding `setRequiredErrorMessage`, `setKindErrorMessage`, `setConflictErrorMessage`, and `setRangeErrorMessage` methods. Swift operations throw; C++ uses its existing Error contract. Getters return Value so a stored nil and an unbounded range's absent generated message can be represented. Setters return the receiver.

C++:

```cpp
using namespace magritte;
Description age;
age.id = age.key = "age";
age.className = "MANumberDescription";
age.properties["min"] = Value(std::int64_t(18));
age.setRangeErrorMessage(Value("Must be an adult"));
auto errors = validateValue(age, Value(std::int64_t(17)));
// errors[0].code == "MARangeError"; message == "Must be an adult".
```

Swift:

```swift
let age = Description(id: "age", className: "MANumberDescription", key: "age")
age.properties["min"] = .integer(18)
try age.setRangeErrorMessage(.string("Must be an adult"))
let errors = try validateValue(.integer(17), using: age)
// errors[0].code == "MARangeError"; message == "Must be an adult".
```

Ordinary metadata selector reads/writes use these operations, and default-aware `property` reads return the same results. Raw property lookup still distinguishes absence from a stored value. The methods have no upstream Magritte description annotations, so no annotated self-description fields are invented.

## Default and overridden text

An absent required message is `Input is required but no input given`; an absent kind message is `Invalid input given`; an absent conflict message is `Input is conflicting with concurrent modification`. An explicitly stored empty string is an override, and is retained as the emitted message. Setting an override to nil stores nil; removing its property restores fallback behavior.

For numeric range messages, the getter first formats min, then max, using that same description's string writer. It then tests the current bounds, preserving changes made by a native formatter callback. The generated text is recomputed rather than stored:

| Bounds | Generated message |
| --- | --- |
| Both present | `Input must be between {min} and {max}` |
| Min only | `Input must be above or equeal to {min}` |
| Max only | `Input must be below or equal to {max}` |
| Both absent | nil |

The spelling `equeal` follows the pinned source. Bound formatting respects display configuration, undefined text and the existing numeric writer profile. A stored override bypasses both formatter calls. Errors from formatting propagate, along with any prior callback effects. Range getters/setters require a magnitude description; Number is the currently implemented concrete magnitude type.

Validation obtains text when it emits the corresponding error. Required/kind failures use the failing description; an extensible option's referenced-description failure keeps the child's identity and message. Condition errors continue to use each condition's own label. Hidden/read-only/undefined and kind-failure rules retain their existing behavior; this phase adds no validation rule or read/write coercion.

Checked-memento conflict validation resets the memento before obtaining the represented container's conflict text, following upstream. A failure obtaining the text leaves the completed reset in place.

## Supported message profile and interchange

Phase 0.31 emits explicit nil as optional signalText on native validation issues, while the verified Pharo messageText protocol computes an empty String. Flat ValidationError.message projects that computed text. Nested groups, tag identity, continuation and printing are documented in [validation](validation.md). Custom interpreter selection remains MAG-006.

Graph/3–4 accepts `requiredErrorMessage`, `kindErrorMessage` and `conflictErrorMessage` on descriptions, and `rangeErrorMessage` on the supported magnitude description. Values are String or nil, preserving presence. Graph/1–2 rejects these fields, including nil. Copying retains independent property dictionaries. No new graph version, Value tag, callable message representation or event mechanism is introduced. Unsupported semantic fields continue to fail export/import.

Checked storage, formatting and codec operations use existing byte/item/depth/work limits. Native callbacks are not preempted, and callers synchronize mutable metadata/model state as before.

## Executed standalone checks

On macOS arm64, all 22 CTest targets and 86 Swift tests pass. The focused C++ message target passes 224 checks under ordinary and AddressSanitizer/UndefinedBehaviorSanitizer builds (leak detection disabled). An independently installed CMake 0.23 consumer runs, and an independent Swift consumer type-checks. All 120 shared fixtures verify; the previous 118 payloads are unchanged. Both native message-configured graph exports compare equivalently.

```sh
# In magritte-cpp:
build/magritte-message-tests /tmp/messages-cpp.json
# In magritte-swift:
MAGRITTE_MESSAGES_EXPORT=/tmp/messages-swift.json swift test --filter MessagesTests
# In magritte-cpp:
python3 tools/compare-graphs.py /tmp/messages-cpp.json /tmp/messages-swift.json
```

These are standalone checks with saved fixtures and no GT connection.
