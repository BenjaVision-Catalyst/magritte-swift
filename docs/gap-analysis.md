# Magritte port gap analysis — 27 October 2026

Both ports implement a substantial headless Magritte profile, but they are not yet faithful across the full model protocol. The most consequential remaining gaps are **inherited execution for registered description subclasses, default reference semantics, persistent container state and mutable collection identity**. Adding more class names or small convenience methods will not close those gaps.

Start with **MAG-001: inherited executable description behavior**. Runtime class registration already works; using a registered description subclass consistently through validation, metadata and interchange does not. Follow it with reference defaults and grouped options, then container mutation/order and collection identity. These phases strengthen the existing metamodel before adding more value domains.

This report is the current planning snapshot. Older phase documents retain historical evidence and historical “remaining work” lists; some of those items were completed later. The [structured ledger](gap-analysis.json) contains stable gap IDs, dependencies, source locations, native locations and acceptance gates. No implementation changes are proposed as already completed by this audit.

## Scope and evidence

The target is the headless [`Magritte-Model` package](https://github.com/magritte-metamodel/magritte/tree/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model) at **d67f318686b7779aed79416db121e257d1191f2e**. An independent read-only upstream checkout and `git ls-remote` agree on that revision as remote HEAD on the audit date. No GT tools were used and no GT-managed source was changed.

| Baseline | Revision / result |
| --- | --- |
| C++ source | `dca317aed794ec138966a547dcc205d1ed7f2133` (0.26) |
| Swift source | `93588d0abc2ebca9fa31b033aa0330648e4fcea1` (0.26) |
| Fresh standalone checks | 25 CTest targets and 98 Swift tests passed; 126 shared fixture payloads verified in each repository |
| Focused audit probes | Same observations in both ports; sources and reproduction instructions below |
| Execution environment | macOS arm64; no fresh sanitizer, leak or other-platform run |
| Live-reference evidence | Historical selected GT evidence only; fresh comparison/replay remains deferred at the user's request |

The [source inventory](upstream-inventory.json) contains **93 class records**, including a package manifest. Core also has **one trait and 17 extension files**. The class files declare **982 methods: 791 instance and 191 class-side**; including trait/extensions gives **1,056 method declarations**. These are source-size counts, not coverage percentages: inheritance, platform extensions, convenience methods and abstract definitions make class/method counts unsuitable as a completion metric.

The audit reviewed the inventory, implemented protocol families, explicit refusal paths, existing conformance boundaries and selected upstream methods/tests. It adds focused native probes for high-impact findings. It does **not** establish exhaustive selector-by-selector equivalence, execute the entire upstream Smalltalk test suite, or turn native agreement into independent reference validation.

Both validators/codecs currently accept **15 canonical description classes**: containers and priority containers; String, Symbol, Memo, Password, Token, Number, Boolean and Class descriptions; to-one, to-many and scalar-to-many relations; single and multiple options. The complete list is in the ledger. Upstream's description subtree has 32 class records: those 15, six abstract bases and eleven additional domain classes. Some additional classes need platform extensions to supply useful kinds/concreteness; they are not eleven equally complete drop-in implementations.

## What is already present

Keep the implemented work when planning: runtime class registration and native class bindings; method/pragma discovery and recursive caches; adaptive models and generic model adapters; represented accessors including composite/pluggable behavior; finite portable and local conditions; relations, static/dynamic options and reference display side effects; visitors/builders/flattening; description composition and selective copying; straight/cached/checked mementos; recursive description/accessor/memento metadata; stored property and lazy operations; display, sorting, printing and error text.

The recent generic-object nil-read fallback is implemented. So are default initialization and nil/default-aware `isSameAs` within their documented profiles. Reopening those phases as wholly missing would waste work. Existing graph identity covers description nodes and referenced relationship objects, including cycles; the missing identity concerns inline mutable collection objects.

## Prioritized gap map

Statuses below apply to **both** ports. “Limited” denotes an intentional current profile that still omits source behavior; “evidence” denotes an unverified claim, not an implementation defect. P1 is foundational, P2 is remaining core profile work, and P3 is later families/platform work. These priorities are dependency-based judgments, not effort estimates.

| ID | Priority | Gap and current boundary |
| --- | --- | --- |
| MAG-001 | P1 | Registered subclasses: discovery works, but kind/predicates, validation, metadata and codecs still use exact implemented class names. |
| MAG-002 | P1 | References: explicit bindings work; lazy default references, Boolean self-reference and relation `allClasses`/`commonClass` are missing. |
| MAG-003 | P1 | Containers: raw child mutation and rich enumeration exist; source mutation APIs and stored priority-order behavior are incomplete. |
| MAG-004 | P1 | Collection identity: inline Values are snapshots; mutable aliases/cycles and associated memento/copy behavior are missing. |
| MAG-005 | P2 | Validation: flat String leaf errors; no source-shaped nested error/continuation protocol, container conditions or nil-message emission. |
| MAG-006 | P2 | Interpreters: default reader/writer/validator classes only; wider local selection, stateful streaming and message writers are incomplete. |
| MAG-007 | P2 | Properties: stored operations exist; announcements/subscriptions and wider object-valued property-owner behavior do not. |
| MAG-008 | P2 | Options: accessor-valued `groupBy`/`isGrouped` and its metadata are absent. |
| MAG-009 | P2 | Self-description: selected schemas and recursive bootstrap exist; complete inherited annotations/adapters for the executable profile do not. |
| MAG-010 | P2 | Temporal values: Date, Time, DateAndTime and Duration descriptions lack executable native value/validation/text/schema support. |
| MAG-011 | P2 | Numbers/text: bounded numbers, decimal reader and ASCII matching/inflection; richer numeric domains/grammar and Unicode behavior remain limited. |
| MAG-012 | P3 | Other domains: Block, Color, Directory, File, Icon, Table and Url descriptions, plus file/table models, remain outside execution. |
| MAG-013 | P3 | Actions: `MAActionDescription`, action invocation/enabling and action pragma discovery are missing headless model behavior. |
| MAG-014 | P3 | Utilities: source-shaped holders and selected object/accessor extensions remain; host bindings in tests are not those utility implementations. |
| MAG-015 | P2, deferred | Evidence: later source-backed phases need fresh live-source comparison and replay when GT use is authorized again. |
| MAG-016 | P3 | Evidence: other toolchains/OSes and broader ownership/concurrency guarantees need explicit verification. |
| MAG-017 | Decision | Optional packages: automatic merging, money, filesystem and UI/platform integrations require separate scope decisions. |

The ledger supplies source evidence and acceptance gates for every row. Grouped rows such as numbers/text and other domains must be split into coherent implementation phases rather than treated as a single large ticket.

## Findings that determine the next phases

### Registered identity is open; inherited execution is incomplete

A newly registered subclass of `MAStringDescription` is discoverable and reaches `visitStringDescription` through inherited visitor dispatch. The same description is rejected by validation and graph export, and its built-in metadata factory fails. A registered Number subclass defaults to Object kind; registered container and to-many subclasses answer false to the relevant predicates. Both ports produced those results.

The native evidence is in C++ `src/magritte.cpp`, `src/collections.cpp`, `src/self_description.cpp` and their Swift counterparts; `src/visitor.cpp` / `Visitor.swift` show the inherited behavior that already works. Upstream methods inherit through its [description hierarchy](https://github.com/magritte-metamodel/magritte/blob/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model/MADescription.class.st).

**Acceptance gate:** register no-override subclasses of every implemented family without changing library class-name lists; verify defaults, kind, predicates, validation, text, metadata, visitor dispatch and identity-preserving graph round trips. Use explicit inherited behavior bindings and explicit native override boundaries. Registration of a name must not silently authorize unsupported behavior or serialize callback code.

### Reference getters have observable construction and identity behavior

[MAReferenceDescription](https://github.com/magritte-metamodel/magritte/blob/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model/MAReferenceDescription.class.st) lazily creates/stores a String description by default, then propagates display configuration. Boolean `reference` returns the Boolean description itself. Both native getters instead require a retained explicit reference, including on Boolean descriptions. The existing display propagation for bound references is implemented and should remain.

**Acceptance gate:** default allocation, repeated access, explicit nil reset, Boolean identity, display propagation, copy/lifetime and graph ownership must agree. Add relation `allClasses`/`commonClass` using source behavior, including the empty-class result. Resolve generated IDs and default ownership deliberately so weak links do not discard new defaults.

There is a source caveat: `MARelationDescription>>reference` has a nil fallback to a common-class template, but its superclass getter normally creates a nonnil String description first. Do not specify an always-active automatic template intersection from a comment or historical paper. Audit that actual branch and relevant platform overrides before implementing it.

### Container state is more than sorted output

The ports expose child arrays/vectors and sort a fresh view whenever `orderedChildren` runs. A two-child priority container changes observed order immediately after one child's priority is mutated, without an explicit resort. Upstream [MAPriorityContainer](https://github.com/magritte-metamodel/magritte/blob/d67f318686b7779aed79416db121e257d1191f2e/source/Magritte-Model/MAPriorityContainer.class.st) stores a SortedCollection, converts it in `setChildren:`, provides `resort`, and refuses move operations. An automatically re-sorted projection does not establish equivalent backing-state behavior.

**Acceptance gate:** source-shaped add/addAll/remove/removeAll/setChildren/move/resort APIs, absent removal, duplicates/equality, return values and before/after ordering traces. Full backing-collection aliasing belongs to MAG-004. Keep existing enumeration, composition and graph behavior covered while changing state semantics.

### Collection identity is the largest foundation gap

Inline Array/OrderedCollection/Set/Bag values and strings have snapshot semantics. They cannot express a shared mutable collection object or a collection cycle. Consequently, source memento scenarios involving live collection aliases remain explicitly unsupported; cloning the elements again cannot fix that.

**Acceptance gate:** first model and test local collection-object identity, in-place mutation, shallow/deeper copy boundaries and memento conflict/reset/commit behavior. Then decide whether a new graph representation is required, with backward feature gates and failure tests. This should be a dedicated phase, not a side effect of adding a collection tag.

## Important follow-on boundaries

Validation currently accumulates leaf errors with String messages. It refuses container conditions and fails when explicit nil error text must be emitted. Upstream has resumable errors and nested `MAMultipleErrors`. Preserve the observable nesting and continuation behavior through a native result/error protocol; implementing a Smalltalk VM is not required. Description-selected custom interpreters also need local behavior bindings: subclassing the existing standalone Visitor does not automatically make that visitor the description's validator or string writer.

The grouping gap has a subtle nil rule. Upstream `groupBy:` applies `asAccessor`; setting nil creates a **MANullAccessor**, so `isGrouped` is true. An absent/raw nil property is different. Its annotated `descriptionGroupBy` uses MASymbolDescription although the getter returns an accessor. Resolve that mismatch with source evidence rather than changing the getter to fit a guessed schema. No grouping UI algorithm is implied.

Self-description expansion should be driven by an annotated-selector inventory, inherited overrides and actual metadata editing. Do not invent fields for conditions/mementos whose upstream annotated schemas are empty. New temporal/domain implementations will need schemas and recursive closure as part of their acceptance gates, not a later cosmetic pass.

The native Number writer emits `(1/2)` for a supported Fraction, but the native Number reader rejects that text in both ports. That is a concrete round-trip profile limit. The audit does not establish the exact external NumberParser grammar; audit that dependency before selecting syntax or arbitrary-precision/scaled-decimal representations. Unicode matching/inflection is a separate source/platform task. Preserve the current explicit exact mixed-number ordering policy unless a deliberate compatibility decision replaces it.

Some upstream source needs investigation rather than literal copying: `MAMessagingStringWriter>>messageSend:` contains an application-specific employee/Halt debugging expression; the relation fallback and grouping annotation issues are described above. The older GT validator also differs from pinned upstream in undefined comparison and aggregate error arrangement. Keep such differences visible in future acceptance evidence.

## Suggested delivery order and completion gates

1. **Inherited description execution (MAG-001).** Close the registered-subclass inconsistency across the current 15-class profile. No new scalar domains are needed for this phase.
2. **Reference and option semantics (MAG-002, then MAG-008).** Add faithful default/self references and grouped-option accessors; verify metadata and ownership rather than adding UI behavior.
3. **Container mutation/order (MAG-003).** Establish persistent source-shaped state and explicit mutations. Document the still-deferred mutable collection alias boundary.
4. **Collection identity and mementos (MAG-004).** Handle local identity/copy semantics first; extend interchange only where required and specified.
5. **Validation, interpreter selection, announcements and schema closure (MAG-005–007 and MAG-009).** Deliver as separate coherent changes using the ledger's dependencies. Reuse the implemented visitor, property and method-registration layers.
6. **Expand value/model families (MAG-010–014).** Temporal values and numeric round-trip closure are useful early candidates; then select source-defined table/file, action or utility families. Keep Unicode and arbitrary-precision work separately testable.

For each phase: pin the relevant upstream methods/tests, author focused semantic traces, run the shared fixtures plus relevant native suites, and check copy/lifetime/metadata/interchange boundaries. Push tested component commits before updating workspace pointers. Add fresh GT evidence only after the user lifts the current restriction, and then follow the workspace lease/completion-marker workflow. Estimates should follow a concrete design for collection ownership and inherited execution; class counts are not a sizing model.

## Scope decisions and evidence debt

The [upstream FEATURES document](https://github.com/magritte-metamodel/magritte/blob/d67f318686b7779aed79416db121e257d1191f2e/FEATURES.md) concerns optional **Magritte-Merging**. Checked-memento conflict/reset support does not implement that package's automatic merge blocks. UI/Seaside/GT views, money, GemStone and filesystem packages also need explicit scope decisions. Headless action, table and in-memory file models should not be dismissed merely because UI adapters consume them.

Explicit native reflection bindings, local-only callbacks and bounded non-executable interchange are legitimate platform bridges. Their acceptance criterion is faithful supported behavior plus clear rejection at the boundary. Broadening the native model need not make arbitrary Smalltalk blocks/messages remotely executable or introduce Catalyst dependencies.

Historical GT results cover selected profiles through 0.16. Phase 0.17 captured selected method sources but deferred fresh behavioral runs/replay; 0.18–0.26 are source/native phases. Current standalone tests establish regression confidence in the documented profile. They do not certify full upstream behavior, cross-platform support, thread-safe mutable builders or asynchronous task-local dynamic caches.

## Reproducing the focused native observations

The independently authored [C++ probe](gap-analysis-probes/cpp.cpp) and [Swift probe](gap-analysis-probes/swift.swift) report observations, including refusals; they do not encode missing features as permanent success tests. Their identical output is embedded in `evidence.observations_in_both_ports` in the ledger. It is pinned to the source baselines above and should be refreshed when these gaps close.

For C++, use the normal installed CMake package, link `Magritte::magritte`, and compile the probe with the repository's `vendor` directory on its private include path for the reporting-only JSON dependency. For Swift, after `swift test`, compile the probe with `swiftc`, the build's `Modules` include directory and `Magritte.build/*.swift.o` objects. These are standalone processes with no GT connection. Probe inputs cover registered subclasses, absent references, grouped-option metadata/export, priority mutation, Fraction text, nil error emission, property announcer refusal and container conditions.
