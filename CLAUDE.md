# Net::Nostr

Perl Nostr protocol library providing both client and relay functionality. Must work on all platforms. Minimum Perl version: 5.16.

Absolute compliance with supported NIPs is the highest priority for this library.

## Spec

The complete Nostr spec can be cloned into the project for direct reference:

    git clone https://github.com/nostr-protocol/nips.git nips/

The `nips/` directory is gitignored. Read the relevant NIP file (e.g. `nips/01.md`) when implementing or testing against the spec.

When naming things, always match terminology from the spec.

Implement every MAY in a spec unless there's good reason not to. Pick sane defaults (e.g. unlimited, disabled) so MAY features are opt-in without breaking existing behavior.

The POD in `lib/Net/Nostr.pm` has a list of supported NIPs. Update it when adding support for a new NIP.

## Testing

Follow TDD strictly: write tests first, run them to confirm they fail, then implement until they pass. We care very deeply about our tests.

Shared test helpers live in `t/lib/TestFixtures.pm`. Use it whenever implementing something that could be re-used across multiple test files.

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

## Code Style

All modules must `use strictures 2;`.

Always `use JSON ()` (empty import list) in library modules. The default JSON exports have prototypes that conflict with `Class::Tiny` accessor generation.

The library uses OO design. Always use `Class::Tiny` for accessor generation, with a custom `new()` constructor (do not use `BUILD`).

Use `croak` (from `Carp`) for public API validation errors. Use `warn` in async callbacks where exceptions cannot propagate (e.g. AnyEvent handlers).

## Documentation

All public functions (those not prefixed with `_`) must have POD documentation. When modifying a public function, check its POD and update it to reflect the changes.

POD should be rich in code examples. Every code example in POD must have a corresponding test, since users are very likely to copy and run examples directly.

Every module's `SEE ALSO` section must link to the NIP spec it implements (e.g. `L<NIP-01|https://github.com/nostr-protocol/nips/blob/master/01.md>`).

## Dependencies

Dependencies are managed in `cpanfile`. Dependencies also appear in `Makefile.PL`.

## Releases

The `Changes` file tracks user-facing changes. Add an entry when implementing a new NIP or making notable changes.
