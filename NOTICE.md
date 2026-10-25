# Attribution and source policy

These independent implementations implement concepts and behavior of Magritte, created by Lukas Renggli and developed by the Magritte contributors. Upstream: https://github.com/magritte-metamodel/magritte at d67f318686b7779aed79416db121e257d1191f2e. The original publications are cited in docs/audit.md.

Both native repositories began with an MIT LICENSE, retained unchanged. The audited upstream checkout has no top-level LICENSE/COPYING file and no explicit license text was found in the inspected model, tests or baseline files. We do not infer permission to relicense copied source from a missing notice: no upstream source or test implementation was copied. These are independently written native implementations and tests based on observed behavior; class/selector names and provenance identify the compatible concepts. Reassess upstream licensing before any future direct code/test translation or redistribution of upstream sources. Papers are referenced, not redistributed.

The C++ implementation privately vendors nlohmann/json 3.11.3 from its official repository, with its MIT license preserved in vendor/nlohmann/LICENSE.MIT and installed with library notices. Swift does not include that dependency.
