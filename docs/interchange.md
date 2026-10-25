# Magritte graph interchange, initial profile

`magritte.graph/1` is a transport-independent representation of a supported graph of Magritte descriptions and adaptive described values. It is deliberately incomplete. A future incompatible extension needs a new format identifier; unsupported input fails today.

## Bootstrap and graph identities

The finite bootstrap recognizes MAContainer, MAPriorityContainer, MAStringDescription, MABooleanDescription and the signed-integer subset of MANumberDescription. These are description objects themselves, not an alternative schema vocabulary. Native Description objects hold a property dictionary and are Models. descriptionModel() creates an ordinary container describing the initial common-property subset. The codec necessarily knows the identity/class/property/child/accessor envelope to bootstrap decoding; there is no claim yet that the complete codec can be generated from self-description.

The envelope has exactly `format`, `root`, `descriptions`, `objects`. Descriptions and objects are arrays with unique nonempty IDs. IDs, dictionary accessor keys and property names are printable non-space ASCII. A description has exactly `id`, `class`, `properties`, plus `children` for a container or `accessor` for a scalar. `children` is an ordered array of description IDs. The root is a container ID. Scalars can be shared between containers; import resolves each ID to one native Description instance. Duplicate child IDs are rejected in this profile; repeated shared IDs across different containers preserve aliases. Nested containers and cyclic composition are not implemented.

An accessor has exactly `class: "MADictionaryAccessor"` and `key: "name"` (for example). For DictionaryModel the key addresses a native dictionary. AdaptiveModel instead addresses values by the description ID, as Magritte adaptive models address descriptions directly. NativeModel supports local function accessors, which cannot be serialized. Swift retains its native object; C++ borrows a caller-owned pointer and invokes caller-supplied typed callbacks. A missing native callback throws rather than manufacturing a value.

An object has exactly `id`, `description` (a container ID), `values` (a dictionary keyed by that container's scalar description IDs). Absent entries remain absent on round trip. Explicit nil entries remain present with nil values. Both read as nil and ordinary reads do not materialize defaults. Invalid described values may be imported for editing; validation is a separate operation. Structurally invalid or unsupported descriptions fail import before use. Invalid/unknown fields fail rather than disappearing.

## Values

All values, including properties, are tagged. JSON numbers are never used to represent Magritte numbers.

| Magritte value | Wire value | Native value |
| --- | --- | --- |
| nil | `{"type":"nil"}` | C++ monostate / Swift Value.undefined |
| Boolean | `{"type":"boolean","value":false}` | Bool, distinct from integer zero |
| String | `{"type":"string","value":"Ada"}` | exact valid UTF-8 content, no normalization |
| Integer (this profile) | `{"type":"integer","value":"9007199254740993"}` | exact Int64, canonical base-10 string |
| Ordered value array | `{"type":"array","value":[...]}` | recursive value array; order and nil preserved |

Canonical integers have no plus sign, leading zeros, exponent, fraction or negative zero. The inclusive range is -9223372036854775808 through 9223372036854775807. Larger Smalltalk integers, fractions, scaled decimals, floats (including NaN/infinities), dates, symbols, object references, sets, bags, maps and executable values are **unsupported** and must be reported explicitly. Arrays here provide lossless value/property storage; they do not imply implementation of Magritte collection/relation descriptions. Object reference/identity interchange is reserved for the relationship phase; the current object table identifies objects but has no reference-valued fields.

## Properties and executable behavior

Properties interpreted by this profile: required/readOnly/visible (Boolean), priority (integer), label/comment/group/undefined (string or nil), min/max (integer or nil, number descriptions only), default and undefinedValue (any supported value). The upstream defaults are required=false, readOnly=false, visible=true, priority=0, undefinedValue=nil. Unspecified default is nil; the display undefined string is empty. Container scalar properties are retained but container value/default validation is not yet implemented. Consumer properties prefixed `metadata:` are retained as opaque, non-executable data. Every other semantic property is rejected, including custom kinds, validators, string reader/writer overrides, conditions, display functions and unknown future validation properties.

Raw Model writes do not validate and do not enforce presentation flags, matching Magritte's separation of model access from interpreters. Validate explicitly before accepting edits. Required means non-nil for the scalar subset: an empty required String is valid. Values equal to undefinedValue skip kind/range/conditions after required checks. Read-only and hidden descriptions skip validation, as upstream does. Inclusive number bounds apply after kind checking.

Local native condition/accessor/default functions run only through the explicit local APIs. Any graph containing them fails export, even if a description is hidden or unused. This prevents export from silently weakening validation. Existing selector/receiver conditions and composite conditions are audited candidates for portable representations, not supported wire input yet. No arbitrary code or Smalltalk VM is involved.

## Limits, errors and ownership

Limits are explicitly configurable for each decode, encode and traversal: input/output bytes (1 MiB default), JSON/value/description depth (64), descriptions and objects (10,000 each), JSON parser work/items (100,000) and traversal visits (100,000). These are library defaults, not transport requirements. The item counter includes parser structure events; it is a work bound, not an application collection cardinality limit. Whitespace counts toward bytes. Depth and duplicate keys are checked before constructing an untrusted graph. Parsers reject malformed UTF-8/JSON, duplicate keys including escaped spellings, unknown members, invalid property kinds, duplicate identities, dangling IDs, unsupported semantics, and budget overruns. Nothing is truncated.

C++ failures use magritte::Error (a std::runtime_error); caller-provided functions may propagate their own exceptions. Swift failures throw MagritteError or the underlying Foundation/callback Error. Validation returns structured errors (description ID, Magritte leaf error code, generic message). Graph import is all-or-nothing and does not mutate an existing graph. Export validates graph registration and pointer identity. Graph maps and child/description references share native description objects; this initial profile rejects cyclic imported composition. Locally constructed reference cycles must be broken by their owner after a failed traversal (shared_ptr/ARC cannot collect cycles).

Models and descriptions are mutable and require external synchronization; neither library claims concurrent mutation safety. Updating descriptions changes subsequent interpretation without recompilation. To apply a new decoded graph to an existing adaptive object, explicitly replace its description reference and keep stable field IDs; then run validation. The library performs no silent data conversion or migration.

Serialization preserves supported semantic data, identity links, explicit property presence and value presence, not JSON whitespace, key order or description-table order. Both exporters sort table identities for reproducibility; container child order is preserved as stored and MAPriorityContainer sorts for interpretation. Native-to-GT round-trip checks use semantic JSON comparison.
