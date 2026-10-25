# Relationships, references, collections and options

Version 0.2 extends the first increment against upstream Magritte revision **d67f318686b7779aed79416db121e257d1191f2e**. It is still not a complete Magritte port. Both language implementations are independent and headless.

Implemented in both ports:

- To-one, to-many and scalar to-many relations with allowed-class validation and explicit reference descriptions.
- Runtime object resolution, aliases, reciprocal/cyclic object links, weak description-reference edges and bounded reference-aware description traversal.
- Nested containers with distinct adaptive stored-value and native identity-access semantics.
- Array, OrderedCollection, Set and Bag value semantics; String-as-Collection iteration through Unicode Characters.
- Static single/multiple options, extensibility/reference validation, stored versus prepared options, optional undefined entries, scalar sorting and supported identity-safe labels.
- Graph/2 import/export, graph/1 compatibility, dangling-reference checks everywhere, decoder composition-cycle preflight, comparison/traversal bounds and explicit unsupported-input failures.
- Local native object bindings and caller-supplied native class ancestry; these explicitly cannot be exported.

## Independent semantic evidence

`conformance/relations-v2.json` was created/exported in GT through MCP, not manufactured by either native implementation. Every element fixture explicitly selects MADictionaryAccessor; the exporter does not substitute an accessor strategy. It contains 23 Magritte description objects, two initial adaptive objects, reciprocal spouse references and repeated friend references. `relations-reference.json` records **109 validation cases**, **12 option-list cases**, and explicit label checks. Both native suites consume these exact expected results, including leaf error description IDs.

Upstream source/tests inspected for this phase: MAReferenceDescription, MARelationDescription, MAToOneRelationDescription, MAToManyRelationDescription, MAToManyScalarRelationDescription, MAOptionDescription, MASingleOptionDescription, MAMultipleOptionDescription, Collection>>maAllOptionsFor:, MAContainer defaultAccessor, MAAdaptiveModel model access, MAVisitor and MAValidatorVisitor; corresponding reference/relation/single-option/multiple-option tests. Tests were independently written; upstream source/test implementation was not copied. The existing licensing/attribution policy remains unchanged.

The references specifically establish behavior that is easy to accidentally change:

- Relationship validation does not cascade into referenced fields.
- Listed options bypass their reference constraints; unlisted extensible options invoke those constraints.
- Duplicate selections remain valid with distinct=true. Empty multiple Collections are rejected only when required.
- String is Collection, but its elements are Characters rather than one-character Strings.
- Array and OrderedCollection remain distinct in equality, while Set order and Bag enumeration order are immaterial.
- Adaptive nested containers read stored values, unlike the default identity accessor on native/dictionary objects. Absent optional nested values skip their children.

Both native tests then edit the same loaded graph generically, supplying Bob's required values and adding a third adaptive object whose nested container stores a reference to Bob. GT imports both outputs, validates all three objects and reexports **23 descriptions/three objects** while preserving reciprocal aliases and collection kinds. `relations-roundtrip-reference.json` and the replay tool request record that independent check. `tools/compare-graphs.py` compares the native and GT graphs semantically, allowing only ordering differences where ordering has no meaning.

All GT reference operations used the existing isolation lease, with completion markers checked outside GT. These operations allocated no native integration resources and changed no persistent Smalltalk methods/classes. The native tests are standalone library tests, not an integration run. Never edit a checkout registered with a live image or bypass a busy lease to replay these checks.

## Remaining boundaries

The wire contract details the material limits: explicit/materialized reference descriptions; a finite portable class universe with real MAAdaptiveModel class identity; value collections without mutable collection-object identity; static rather than dynamic options; identity-safe label keys; ASCII sorting; and partial self-description. Native class bindings and closures are local only. Reflective class/template discovery, implicit reference construction, arbitrary option renderers/grouping, arbitrary Smalltalk conditions, full numeric domains, full meta-description and mementos remain future work. Phase 0.3 supplies finite binary64, text readers/writers and Boolean option/text specializations. Unsupported inputs fail explicitly. This phase does not claim complete upstream core coverage.

Executed platforms remain macOS arm64 (Apple Clang 21/CMake 4.4.3; Swift 6.3.3). C++ Debug (284 conformance checks), the address/undefined-behavior sanitizer suite, installed-library consumer compilation and Swift package tests (14 tests) passed locally. Linux/Windows portability remains unexecuted, not certified.

The later 0.3 increment adds real MAStringReader/Writer operations and fixes option fallback rendering to use displayStringFor:, while sorting continues to use reference conversion. Numeric equality now spans Int64/binary64 and String/Symbol equality follows String ancestry; identity-safe labels still distinguish these types. See portable-behavior.md for current support and explicit boundaries. Earlier phase counts and graphs remain historical evidence.
