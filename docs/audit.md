# Semantic baseline and phased implementation

The scalar, relationship/collection, portable behavior, editing, recursive metadata, composition and class/accessor reflection and visitor/builder phases are implemented for the documented profiles. This is still not a complete Magritte port; see [relationship evidence](relationships.md) and [portable behavior evidence and boundaries](portable-behavior.md) and [editing/self-description evidence](editing.md) and [recursive composition evidence](composition.md) and [class/accessor reflection evidence](reflection.md).

The authoritative upstream is [magritte-metamodel/magritte](https://github.com/magritte-metamodel/magritte), revision **d67f318686b7779aed79416db121e257d1191f2e** (2025-04-29). Paths below resolve against that commit. The target is its headless Magritte model, not an application-specific schema system. The graph representation serializes instances of that description hierarchy; there is no second field-schema model.

For the current prioritized backlog and acceptance gates, see the [27 October 2026 gap analysis](gap-analysis.md) and its [structured ledger](gap-analysis.json). Historical phase notes below are evidence for their stated profiles, not a current completion checklist.

## Reading and provenance

Reviewed the upstream README, FEATURES, baseline package, model hierarchy and its tests. `upstream-inventory.json` records every class and selector in `source/Magritte-Model` at the pinned revision; this inventory is a source audit, not a coverage claim. Focused semantic references:

| Area | Upstream source and tests inspected |
| --- | --- |
| Properties, required, undefined, read-only, visibility, self-description | MADescription, MAElementDescription, MATPropertyOwner; MADescriptionTest, MAElementDescriptionTest |
| Composition and ordering | MAContainer, MAPriorityContainer; MAContainerTest, MAPriorityContainerTest |
| Scalar kinds and range | MAStringDescription, MABooleanDescription, MANumberDescription, MAMagnitudeDescription; corresponding description tests |
| Native access | MAAccessor, MADictionaryAccessor, MAPropertyAccessor, MASelectorAccessor; accessor tests |
| Adaptive objects | MAAdaptiveModel and MAAdaptiveModelTest |
| Validation | MAValidatorVisitor, MAValidationError and subclasses; required/kind/condition/range tests in description tests |
| Conditions | MACondition, MAPluggableCondition, MAConjunctiveCondition, MANegationCondition |
| References and options | MAReferenceDescription, MARelationDescription, MAToOneRelationDescription, MAToManyRelationDescription, MAOptionDescription and single/multiple subclasses |
| Interpreters | MAVisitor, MAReader, MAWriter, MAStringReader, MAStringWriter |
| Editing | MAMemento, MAStraightMemento, MACachedMemento, MACheckedMemento; MAMementoTest |

Original publications consulted:

- Lukas Renggli, [Magritte – Meta-Described Web Application Development](https://scg.unibe.ch/assets/archive/masters/Reng06a.pdf), 2006, chapter 2, especially sections 2.2–2.4 and the accessor/condition/memento class reference. The original README's older host was unavailable; this is the university archive copy.
- Lukas Renggli, Stéphane Ducasse, Adrian Kuhn, [Magritte – A Meta-Driven Approach to Empower Developers and End Users](https://scg.unibe.ch/archive/papers/Reng07aMagritte.pdf), 2007, sections 2–4. Runtime metamodel editing, adaptive objects, shared descriptions, and generic interpreters motivate this architecture. Publications establish design intent; the pinned source establishes current behavior when historical examples differ.

The running GT image was inspected only through GT MCP. The relevant installed classes are in Magritte-Model, but package membership alone does not establish upstream provenance. `conformance/live-methods.json` identifies the exact inspected live methods by source hash. No installed Magritte Git revision was exposed by the image's IceRepository registry. In particular, the installed MAValidatorVisitor uses `sameContentAs:` for undefined checks, where pinned upstream uses `=`; aggregate error handling is arranged differently. This increment checks the shared scalar behavior and flattened leaf error classes, not equivalence of either entire implementation. Extension selectors seen in the image, including serialization and UI stencils, are excluded.

## Support matrix (both ports)

I = implemented; R = executed against the live reference for the stated subset; N = not yet implemented; X = not portable through this interchange profile. Native-only tests are distinct from R.

| Feature | State | Evidence / boundary |
| --- | --- | --- |
| MAContainer insertion order | I, R | reference containerOrder; graph child identities preserved |
| MAPriorityContainer ascending order | I, R (sorted view) | reference priorityOrder; native reads re-sort a snapshot; persistent state/resort gap in MAG-003; upstream tie policy not claimed |
| Container add/remove | I (raw children only) | source mutation APIs and priority backing-state semantics remain partial; gap-analysis.md, MAG-003 |
| Container lookup, detection and enumeration | I, R (direct children) | lazy fallbacks, equality membership, short-circuit predicates, indexed/separated/paired iteration and reduction; container-enumeration.md |
| Nested containers | I, R | identity access for native models; stored child values for adaptive models |
| Concatenation/union/intersection/select/collect/copy protocol | I, R (profile) | equality-class composition, selective reference copies and shared container children; range/exclusion/empty copies; full collection protocol N |
| MAStringDescription | I, R | required empty string remains valid; exact UTF-8 content; no normalization |
| MABooleanDescription | I, R | false is present; fixed options, aliases and configurable true/false text |
| MANumberDescription | I, R (Int64/binary64) | inclusive bounds; finite floats; documented exact mixed-order policy |
| Bounded exact Fractions | I, R | Int64 numerator/positive denominator, exact priority arithmetic/order and graph/4; builders.md |
| Arbitrary precision integers, scaled decimals, full NumberParser grammar | N | explicit rejection; MANumberDescription remains partial |
| Symbol, Memo, Password and Token descriptions | I, R | graph/3 scalar kinds, masking and token text conversion |
| Date/time/duration, URL, color/icon/file/directory/block/action/table descriptions | N | unsupported class fails import; see complete inventory |
| Required/optional, custom undefinedValue | I, R | required checks nil; undefined sentinel skips kind/specific/conditions |
| Model default initialization / isSameAs | I (explicit description/provider and native Value profile), fresh R deferred | raw default writes, right-readability gating, nil/default equivalence and host equality; model-protocol.md |
| Generic Object readUsing nil fallback | I (native/metadata adapter profile), fresh R deferred | one accessor read then current undefinedValue only for nil; raw accessors and adaptive/memento overrides retain their contracts; model-read.md |
| Explicit defaults | I, R (property only) | defaultValue exposes declared default; generic model nil reads use undefinedValue, not default; raw accessors/adaptive reads retain nil |
| shouldCacheDefault | I, R | editing default filtering, including pinned/live difference; see editing.md |
| Memento default substitution/cache | I, R | straight nil/default and cached sentinel/default cooking; raw models unchanged |
| Lazy default initialization | I (Value profile), fresh R deferred | nil-only substitution, conditional raw write and selector-backed property bridge; lazy.md; mutable collection identity/default copying remain unsupported |
| Read-only/hidden validation skip | I, R | flags affect interpreter, raw write still writes |
| MADictionaryAccessor | I, R | raw missing-key accessor read returns nil; DictionaryModel.readUsing applies the generic fallback |
| Accessor-derived names and labels | I, R (ASCII inflection profile) | exact name kinds, chain ordering, nil/empty overrides and default metadata; Unicode inflection N; accessor-inference.md |
| Description property/selector accessors | I, R (selected fields) | retained seven-property bootstrap plus class-specific selector metadata graphs |
| Local pluggable native accessors | I, R (first-class accessor profile), X (wire) | independent block slots, identity equality/copy, chains/mementos and empty annotated schema; pluggable-accessors.md; direct Description callbacks remain separate |
| Selector/variable/identity/null/chain strategies | I, R (profile) | graph/3 strategies and explicit host bindings; delegator and composite configurations in graph/4 |
| MACompositeAccessor / MACompositeConflict | I, R (native Value profile) | binary traversal, capabilities, species equality, copy/kind/label semantics and memento editing; local conflict objects, explicit host message lookup; composites.md |
| Accessor canRead/canWrite protocol | I, R (nine represented strategies) | host selector/variable discovery, absent slots, short-circuit/error/side-effect traces; accessor-capabilities.md |
| Native local scalar conditions | I, X | executed natively; kind errors skip conditions; nil sentinel skips them |
| MACondition selector/receiver, conjunction and negation objects | I, R (finite protocol) | labelled bounded graph/3 data; arbitrary messages/blocks and container conditions X |
| Structured validation errors | I, R (leaf codes) | description identity, code, message; native validator accumulates leaf errors |
| Description error messages | I (String emission profile), fresh R deferred | required/kind/range/conflict defaults and overrides, generated range formatting; messages.md; nil emission fails explicitly |
| Upstream nested exception trees/custom validator overrides | N | nested/resumable exceptions, nil exception-message defaults and custom validators remain unsupported |
| Common and relation/option metadata | I, R (selected properties) | ordered/distinct/definitive/sorted/extensible retained; no invented coercion/uniqueness rules |
| Stored property dictionary protocol | I (Value profile without announcer), fresh R deferred | strict/lazy/conditional access, nil removal and MAPropertyAccessor; properties.md; unknown semantic wire fields still reject |
| Property announcements | N | subscribers and announcers remain unsupported |
| Reference identity between description nodes | I | shared child instances survive import/export |
| Relationship object identity, cycles, to-one/to-many/scalar-to-many | I, R | graph/2 explicit references and class constraints; no automatic validation cascade |
| Static single/multiple options | I, R | membership/extensibility/prepared lists/identity-safe labels |
| Runtime native class registration and hierarchy discovery | I, R (platform bridge) | typed bindings, inherited constraints, live discovery for new metadata and registered class interchange |
| Dynamic option providers | I, R (native Value profile), X (wire) | live completion/membership/reader callbacks, provider identity, copy/array-wrapper semantics; dynamic-options.md |
| Description display selectors/blocks and option-label fallback | I (native Value profile), fresh R deferred | culled display arguments, host message bindings, reference-based sort conversion and selector snapshots; display.md |
| Option grouping / arbitrary interpreter instances | N, X (current wire) | grouping and MAMessagingStringWriter remain separate gaps |
| Mutable collection-object identity | N, X (current wire) | inline collections are value snapshots; object references retain identity |
| Array/OrderedCollection/Set/Bag values | I, R | kind/order/multiplicity/equality and relation/option validation; Character bridge for String collections |
| Visitor dispatch and base description builder | I, R (represented hierarchy) | 21 dispatch points, superclass fallback, explicit traversal, stateful copy/enrichment; visitors.md |
| Builder composition / MADescriptionFlattener | I, R (native model profile) | ordered pipelines, target/model context, shared expansion and exact priorities; missing upstream hooks require explicit bindings; builders.md |
| MAPragmaBuilder / dynamic description cache / defining contexts | I (native bridge), fresh R deferred | inherited runtime method discovery, identity/dynamic scope, recursive fields and graph/4 snapshots; pragma-discovery.md |
| MASortBlock / isSortable | I (native Value/Model profile), fresh R deferred | ordered accessor reads, shared identity, explicit binary host messages and inherited sortability; sorting.md |
| Reference display / option undefined setter | I (bound-reference profile), fresh R deferred | getter side effects, repeated interpreter access, bounded option cascades and raw snapshot traversal; reference-access.md |
| Graph callback traversal | I | bounded composition/reference traversal, cycles terminate; distinct from MAVisitor dispatch |
| Description/value JSON import/export | I, R | graph/1–4; GT -> both ports -> GT, aliases/cycles/nested objects/collections |
| Described-object printing | I (native model/Value profile), fresh R deferred | readToString, element printFor, container print, local field/separator hooks and bounded native stream; printing.md; hooks X on wire |
| MAStringReader/Writer text conversion | I, R (profile) | scalars/options/tokens; writers also containers/relations; other interpreters N |
| Self-description | I, R (selected class-specific profile) | fifteen supported classes in reflective profile; staged metadata edits govern subsequent model validation |
| Recursive description self-description | I, R (selected profile) | lazy bounded sessions; children/reference/name/optionsTextual; three metadata levels and imported-schema edits |
| MAClassDescription and class-valued metadata | I, R | runtime-registered identities, class/subclass discovery and graph/4; registration.md |
| Accessor/condition self-description | I, R (selected profile) | nine accessor classes (pluggable has no annotated fields); three conditions have no annotated fields; actual local accessor identity and memento edits |
| Memento self-description and finite recursive bootstrap | I, R (profile) | exact represented schema identity; nested editors; 74-node reachable bootstrap and current schema closure; bootstrap.md |
| Complete hierarchy self-description and arbitrary reflection | N | selected annotations remain explicit; no arbitrary message execution; full class-protocol coverage remains pending |
| Straight/cached/checked mementos, conflict handling | I, R (direct field profile) | 48 scenarios/201 snapshots; raw commit, destructive conflict reset, checked selective push; collection alias gap in editing.md |
| Native user interfaces, persistence interpreters | N | headless consumers may be added separately |
| GemStone/platform adapters | N | deferred |

## Deliberate differences and decisions

1. Descriptions have stable external IDs. Adaptive values are keyed by those IDs, so an application may explicitly adopt a replacement description graph without schema-specific mapping. Upstream keys values by description objects using Smalltalk equality. Reusing an ID asserts semantic continuity; changing an ID creates a distinct field. Adoption is explicit (`model.description = newRoot`), not an implicit migration. Removed values stay in the local model until the application handles them; export rejects undescribed values.
2. This profile accepts nonempty printable ASCII identities, accessor keys and property names. Text values support arbitrary valid UTF-8 including NUL and supplementary characters. No Unicode normalization occurs. C++ and Swift use exact string-content equality for Values.
3. Accessor-derived names and ASCII labels now follow Magritte, including chain order, nil/empty overrides and lazy null defaults. Native Unicode accessor names require explicit labels for presentation; full Unicode inflection remains pending. See accessor-inference.md for current evidence and the isolated historical fixture projection.
4. Native validation returns a flat collection of structured leaf errors. Description-specific required/kind/range/conflict text follows the String emission profile in messages.md; condition errors retain their condition labels. Upstream may signal nested resumable exceptions, whose full trees and nil-message default protocol remain unsupported. Historical reference fixtures test codes/description identities; phase 0.23 source-derived cases also check message content.
5. The bootstrap's seven common properties are represented by ordinary descriptions and can be read/written/validated by the same Model/validator APIs. It is a seed for full self-description, not a separately maintained schema language.
6. Native scalar condition and accessor functions and explicit default functions are local behavior. Export rejects every such function, including on hidden nodes. No closure, VM, RPC or expression-language evaluation is introduced. `defaultFunction` is explicitly evaluated by defaultValue and by memento default/filter operations; raw models and their ordinary validation do not evaluate it implicitly. Container-local conditions are currently rejected by model validation.
7. Graph/2 adds the audited relationship/option hierarchy; identity is independent of a description’s label or shape. Imported class names refer to real supported native equivalents, not schema IDs. See relationships.md for phase evidence and interchange.md for remaining boundaries.

8. A finite allowlist of description classes, accessor forms and semantic properties is intentional for this increment. Extending that list requires implementing and testing the semantics. Opaque `metadata:` properties cannot introduce executable behavior.

## Phases and exit criteria

1. **First slice (delivered):** audit and provenance, independent native libraries, scalar/adaptive/accessor core, bootstrap, bounded description/value interchange, shared GT-established Person fixture, runtime evolution, and explicit rejection tests. Install/package and test locally; publish precise gaps.
2. **References and collections (delivered for the documented profile):** explicit reference graphs, static relationship/options hierarchy, object IDs/cycles, collection kind/equality/required rules, nested containers and bounded operations are implemented and checked against upstream source and GT. Remaining dynamic/reflective and collection-identity facilities are explicitly tracked in relationships.md, not claimed complete.
3. **Portable behavior (delivered for the documented profile):** finite MACondition objects, broader access strategies, Symbol/Memo/Password/Token descriptions, finite binary64 and MAStringReader/Writer operations. Full numeric/scalar domains remain future work; arbitrary executable behavior continues to fail export.
4. **Editing (delivered for the documented profile), meta-model completeness (pending):** straight/cached/checked mementos, original/cache/default rules, conflict behavior and selected class-specific metadata editing are implemented and checked against GT/upstream. Selected recursive description metadata and composition/copy semantics are delivered in 0.5. The 0.6 class/accessor reflection profile is delivered; full mutable collection identity, arbitrary message reflection remains future work. Memento self-description and the finite bootstrap are delivered in 0.7. Only then assess a complete headless-core claim against the inventory.
5. **Optional interpreters:** native inspectors/presentation tools in separate targets. No networking, deployment or application-specific integration enters these core libraries.

Each phase needs independently reviewed GT results and shared fixtures, not merely agreement between the two ports. Tests in this increment are newly written behavioral tests; upstream test source was not copied.

Phase 0.3 adds Symbol, Memo, Password and Token descriptions and finite binary64, with text conversion and portable condition/accessor forms checked against live GT. Arbitrary integers/rationals/scaled decimals and date/time/color/URL/file descriptions remain N (Class is added in 0.6). Read portable-behavior.md for the two explicit GT/pinned-source or VM-dependent numeric policies; no complete scalar-domain claim is made.

Phase 0.4 adds the bounded editing and class-specific self-description profiles. The eight shouldWrite matrix differences from installed GT intentionally follow the pinned upstream symmetric rule; mutable collection alias behavior remains unsupported. editing.md records both boundaries and the live evidence.

Phase 0.5 implements recursive description metadata sessions and selective composition/copy semantics for the current hierarchy. composition.md records the live GT evidence, supported annotation selection and explicit label/class-list/SortedCollection projections. This is not a complete reflective metamodel or graph deep-clone claim.

Phase 0.6 implements MAClassDescription, finite class values and class-valued relation/interpreter metadata, plus live accessor-object editing and faithful condition self-description. reflection.md records the 26 source matches, GT schema/getter/editing evidence, graph/4 round trips and explicit identity/registry limits.

Phase 0.7 adds exact memento model-description identity, local editor bindings and finite reachable-description bootstrap. bootstrap.md records the GT state/schema evidence, 12 matching upstream fingerprints and graph/4 round trips. It does not invent cache/model annotation fields.

Phase 0.8 replaces class acceptance lists with runtime registration, typed native lookup and hierarchy discovery. registration.md records the exact GT projections, source evidence, class-valued interchange and boundaries. Existing executable type implementations remain explicit.

Phase 0.9 implements visitor dispatch for the represented description hierarchy and the base `MADescriptionBuilder` protocol. [visitors.md](visitors.md) records the fresh audit, 55 method fingerprints, live behavioral traces and graph/4 round trips. Dynamic option providers, mutable collection identity, accessor capabilities/inferred labels, scalar domains and full builder/cache/interpreter protocols remain separate gaps.

Phase 0.10 implements native `MADynamicOptions` and explicit Options collection/provider results. [dynamic-options.md](dynamic-options.md) records the audit, 25 matching Magritte source fingerprints, actual kernel wrapping behavior, an explicit GT String prefix projection, callback traces and graph/4 snapshot round trips. Grouping, mutable collection identity, accessor capabilities/inferred labels, scalar domains and full cache/interpreter protocols remain open.

Phase 0.11 implements capability discovery for the eight represented accessors and independent absent selector slots. [accessor-capabilities.md](accessor-capabilities.md) records 54 GT cases, 15 matching source fingerprints and accessor-record round trips. Composite/pluggable accessor objects, inferred labels, arbitrary host reflection and the other documented gaps remain open.

Phase 0.12 implements first-class local MAPluggableAccessor behavior, identity-bearing block slots, accessor equality and shallow-copy/composition/editing semantics. [pluggable-accessors.md](pluggable-accessors.md) records 17 matching source fingerprints, actual GT traces and portable graph round trips after explicit accessor replacement. Composite conflicts, inferred labels, arbitrary host reflection, mutable collection identity and the remaining scalar/cache/interpreter protocols remain pending.

Phase 0.13 replaces raw-key label fallback with the audited accessor name/default-label protocol and faithful lazy null defaults. [accessor-inference.md](accessor-inference.md) records 70 GT cases, fifteen class defaults, twenty matching Magritte source fingerprints plus one kernel method, unprojected metadata tests and graph round trips. Composite conflicts, full Unicode inflection, mutable collection identity and the remaining scalar/reflection/cache/interpreter protocols remain pending.

Phase 0.14 implements direct MAContainer lookup and enumeration in both ports. [container-enumeration.md](container-enumeration.md) records thirteen matching live/upstream method fingerprints, four complete GT observation cases, native bounds/identity/error tests and typed zero-based APIs. Full backing-collection mutation and other documented gaps remain open.

Phase 0.15 implements MACompositeAccessor and local MACompositeConflict objects, plus the declared description kinds required by via:using:. [composites.md](composites.md) records 35 matching live/upstream fingerprints, 25 composite trace scenarios, conflict/kind/copy/annotation/editing evidence and eight GT accessor round-trip cases. Local conflicts are rejected by interchange; the existing Value equality/reflection boundaries remain explicit.

Phase 0.16 implements builder composition and description flattening with explicit host description/hook bindings and bounded exact Fraction priorities. [builders.md](builders.md) records the missing upstream selectors, 18 matching source fingerprints, 19/24/9 behavioral case groups, 130 numeric comparisons, probe cleanup and flattened graph round trips. Pragma/cache orchestration and arbitrary reflection remain separate gaps.

Phase 0.17 implements runtime pragma description discovery, dynamic identity caches/described-object scope and defining contexts. [pragma-discovery.md](pragma-discovery.md) records eighteen captured GT method sources (sixteen exact whitespace-normalized matches and two gsCode-only additions), seventeen source-derived native scenarios, ownership/error bounds and graph/4 snapshots. At the user’s request GT was left unused after the initial source inspection; fresh live-GT behavior and replay remain deferred. The I status for this phase does not imply R.

Phase 0.18 implements description display selectors/native blocks, option fallback and comparator-time reference formatting. [display.md](display.md) records 22 upstream fingerprints, 39 source-derived scenarios, native ownership/message/bounds tests and equivalent graph snapshots. GT was not accessed at the user’s request; no fresh R status or GT replay is claimed. Full scalar reflection, grouping and arbitrary interpreter instances remain pending.

Phase 0.19 implements local MASortBlock evaluation, Value-target identity/delegator/chain access and inherited/native-overridable sortability queries. [sorting.md](sorting.md) records fourteen upstream fingerprints, 69 comparison cases, fifteen sortability cases, native trace/identity/error tests and equivalent imported-schema snapshots. GT was not accessed at the user’s request; no fresh R or live replay is claimed. No executable sort plan or unrelated sorting framework is introduced.

Phase 0.20 implements reference getter display propagation and option undefined setter cascades for explicitly bound references. [reference-access.md](reference-access.md) records twenty upstream fingerprints, 24 getter and 24 setter cases, corrected reference-specific display expectations, codec/copy boundaries and native timing/error checks. GT was not accessed; fresh R remains deferred. Lazy reference creation/template derivation and Boolean self-reference convenience remain gaps.

Phase 0.21 implements MATPropertyOwner stored-Value lookup/conditional/update semantics on descriptions and connects MAPropertyAccessor to that storage protocol. [properties.md](properties.md) records 21 selected source fingerprints, fifty state/result/trace cases, reentrant/error/copy/wire tests and explicit no-announcer boundaries. GT was not accessed; fresh R remains deferred. No generic event system or new schema language is introduced.

Phase 0.22 implements element nil-only lazy initialization, selector-backed maLazyPropertyUsing: and initialAnswer fallback/storage. [lazy.md](lazy.md) records twelve source fingerprints, 144 lazy/six answer cases, write/error/reference/copy/wire tests and explicit callback/collection boundaries. No new annotated fields are invented. GT was not accessed; fresh R remains deferred.

Phase 0.23 implements description-specific required/kind/range/conflict messages, generated range writer behavior, and checked-memento conflict text after reset. [messages.md](messages.md) records 22 source fingerprints, 35 getter/forty validation cases, native callback/child/error/reset/copy/wire tests and the explicit String emission boundary. GT was not accessed; fresh R remains deferred.

Phase 0.24 implements described-object readToString/printFor/container print and local maPrintString/maPrintStringSeparator hooks. [printing.md](printing.md) records sixteen source fingerprints, 54 container/five element cases, callback/read/separator timing, partial failures, shallow copy identity, codec rejection and native output bounds. Ordinary writers are unchanged. GT was not accessed; fresh R remains deferred.

Phase 0.25 implements explicit-description/provider model initialization and isSameAs:using: comparison. [model-protocol.md](model-protocol.md) records fourteen Magritte source fingerprints, separately attributed Pharo membership review, 48 initialization/384 comparison cases, timing/failure/default/container/provider/reference/bounds tests and portable models. The generic Object nil-read fallback gap is now explicit. Callable default Values, automatic per-object discovery and model hashing remain separate gaps. GT was not accessed; fresh R remains deferred.

Phase 0.26 implements Object>>readUsing: nil-only undefinedValue fallback in generic native/dictionary/description and reflective model adapters, with a default Model implementation. [model-read.md](model-read.md) records fifteen source fingerprints, 441 adapter/seven memento cases, single-read/error/chain/override/consumer/lifetime/bounds checks and equivalent graphs. Raw accessors and adaptive/memento read overrides are preserved. GT was not accessed; fresh R remains deferred.
