# Net::Nostr

Perl Nostr protocol library providing both client and relay functionality. Must work on all platforms. Minimum Perl version: 5.16.

Absolute compliance with supported NIPs is the highest priority for this library.

## Priorities

When rules conflict, follow this order:

1. NIP/spec correctness
2. Preserving documented public API behavior unless we are intentionally changing it
3. Existing tests, unless they conflict with the spec or documented intended behavior
4. Validation/documentation completeness
5. Local style rules

If a change tightens validation or otherwise changes public behavior, update tests, POD, and `Changes`.

## Spec

The complete Nostr spec can be cloned into the project for direct reference:

    git clone https://github.com/nostr-protocol/nips.git nips/

The `nips/` directory is gitignored. Read the relevant NIP file (e.g. `nips/01.md`) when implementing or testing against the spec.

When naming things, always match terminology from the spec.

Implement every MAY in a spec unless there's good reason not to. Pick sane defaults (e.g. unlimited, disabled) so MAY features are opt-in without breaking existing behavior.

The POD in `lib/Net/Nostr.pm` and the projects `README.md` has a list of supported NIPs. Update them when adding support for a new NIP.

## Testing

Follow TDD strictly: write tests first, run them to confirm they fail, then implement until they pass. We care very deeply about our tests.

Shared test helpers live in `t/lib/TestFixtures.pm`. Use it whenever implementing something that could be re-used across multiple test files.

Add round-trip tests for protocol-facing types where applicable. Parsing then serializing should not introduce unintended changes, and serializing then parsing should produce an equivalent valid object.

Run tests with `prove`. To run the full test suite use `prove -r t/`.

After making changes, always run the relevant tests and fix failures before considering the work done. If a fix introduces new failures, keep iterating until all tests pass. Similarly, re-read any POD you've added or modified to verify it is accurate and complete.

## Implementing a NIP

Each supported NIP has a dedicated conformance test file in `t/nip/` (e.g. `t/nip/01.t`). Unit tests for individual modules live in `t/` numbered by module (e.g. `t/05-Relay.t`). Conformance test files must fully cover the spec.

Put great effort into making tests complete -- cover edge cases, error conditions, and every MUST/SHOULD/MAY in the relevant NIP spec. Every implemented MAY should have a test demonstrating the behavior and its default.

Write negative tests: verify that invalid input is rejected, that spec violations produce errors, and that edge cases fail in the expected way. If the spec says a relay MUST reject something, test that it does.

NIP specs often include concrete JSON examples. Always use these examples directly in tests -- they are the most authoritative test vectors available.

NIPs often depend on each other. When implementing a NIP, check whether it introduces requirements on already-supported NIPs and add tests for those cross-NIP interactions.

After completing the implementation, read the NIP spec and the `t/nip/` test file side by side, line by line. Every requirement in the spec must have a corresponding test. If there's a gap, add the missing test before considering the work done.

Re-read all generated POD to verify accuracy, completeness, and that every code example is correct and tested.

## Validation

Be strict and be consistent. Callers should not have to guess where bad input gets rejected.

Rules:

- Public APIs must have one job:
  - strict builder/constructor
  - parser
  - raw/unvalidated constructor
  - semantic `validate()`
- Do not mix those roles in one method.

- Builders/constructors must reject obviously bad caller input up front.
  - missing required fields
  - bad hex
  - malformed bech32/URI/URL
  - bad ranges
  - invalid enums
  - broken structural field combinations

- Parsers must fully validate untrusted input.
  - events
  - tags
  - URIs
  - JSON
  - relay messages
  - remote responses

- `validate()` is only for higher-level spec rules that are reasonable to defer.
  - Use it for semantic constraints.
  - Do not use it as an excuse to skip basic format checks earlier.

- If we need a lax constructor for internal or partial objects, make that explicit.
  - Name it something like `new_raw` or `from_unvalidated`.
  - Document it clearly.
  - Do not hide a raw constructor behind a normal `new()` unless that is the project-wide rule.

- Do not do partial validation in constructors.
  - Either the constructor is strict, or it is raw.
  - “Validate one field and ignore the rest” is not acceptable.

- Docs must match reality.
  - Do not say fields are required unless the code actually enforces that at that layer.
  - Every public entry point should say whether it validates, and what it guarantees.

- Tests must cover rejection paths, not just happy paths.
  - malformed input
  - missing fields
  - boundary values
  - encoding edge cases
  - round-trip failures
  - every validation bug fix needs a regression test

- Never silently accept malformed protocol-critical data.
  - pubkeys
  - event ids
  - signatures
  - relay URLs
  - wallet connect secrets
  - tag shapes
  - protocol identifiers

- Validate as early as possible.
  - caller input: constructor/builder
  - wire input: parser
  - protocol semantics: `validate()`

If a caller cannot tell whether an API returns a valid object or just a bag of fields, the API is wrong.

## API Contracts

Public entry points must make their validation behavior obvious from both name and documentation.

Rules:

- `new()` must be strict unless a module explicitly documents otherwise.
- Parsers such as `from_json`, `from_uri`, `parse_*`, or `decode_*` must fully validate untrusted input.
- Raw constructors must be explicitly named, such as `new_raw` or `from_unvalidated`.
- Raw constructors are only for internal use, partial objects, or carefully documented advanced cases.
- `validate()` is only for semantic/spec checks that are reasonable to defer after basic parsing/structural checks.
- No public method may return an object whose validity is ambiguous.

Required documentation for every public constructor/parser:
- whether it validates
- what level of validation it performs
- whether returned objects are fully valid or require a later `validate()`

If a caller cannot tell whether an entry point is strict, raw, or semantic-only, the API is wrong.

## Behavior Changes

If a change affects public API behavior, say so explicitly.

If a change tightens validation or rejection behavior:
- add tests for the new rejection behavior
- update POD to match the new rules
- update `Changes`
- do not leave old tests or docs implying the old behavior is still accepted

Do not describe behavior as NIP-compliant unless it actually is.
Do not leave partial implementations undocumented.

## Documentation

All public functions (those not prefixed with `_`) must have POD documentation. When modifying a public function, check its POD and update it to reflect the changes.

POD should be rich in code examples. Every code example in POD must have a corresponding test, since users are very likely to copy and run examples directly.

Every module's `SEE ALSO` section must link to the NIP spec it implements (e.g. `L<NIP-01|https://github.com/nostr-protocol/nips/blob/master/01.md>`).

## Code Style

All modules must `use strictures 2;`.

Always `use JSON ()` (empty import list) in library modules. The default JSON exports have prototypes that conflict with `Class::Tiny` accessor generation.

The library uses OO design. Always use `Class::Tiny` for accessor generation, with a custom `new()` constructor (do not use `BUILD`).

Use `croak` (from `Carp`) for public API validation errors. Use `warn` in async callbacks where exceptions cannot propagate (e.g. AnyEvent handlers).

## Dependencies

Dependencies are managed in `cpanfile`. Dependencies also appear in `Makefile.PL`.

## Releases

The `Changes` file tracks user-facing changes. Add an entry when implementing a new NIP or making notable changes.

## Output Requirements

At the end of every task, report:

- files changed
- public API changes, if any
- validation behavior changes, if any
- tests run
- spec/NIP sections consulted
- POD updated or not
- `Changes` updated or not
- anything not verified
- any follow-up risks or edge cases still worth checking

Do not claim completion if required tests were not run or if relevant docs were not checked.

Be explicit about uncertainty.
