# Net::Nostr

Perl Nostr protocol library that works both as a client and a relay. Must work on all platforms.

Absolute compliance with supported NIPs is the highest priority for this library.

## Development

Follow TDD strictly: write tests first, run them to confirm they fail, then implement until they pass. Put great effort into making tests complete — cover edge cases, error conditions, and every MUST/SHOULD in the relevant NIP spec.

Each supported NIP has a dedicated conformance test file in `t/nip/` (e.g. `t/nip/01.t`). Unit tests for individual modules live in `t/` numbered by module.

The complete Nostr spec can be cloned into the project for direct reference:

    git clone https://github.com/nostr-protocol/nips.git nips/

The `nips/` directory is gitignored. Read the relevant NIP file (e.g. `nips/01.md`) when implementing or testing against the spec.

`README.md` has a checklist of supported NIPs. Update it when adding support for a new NIP.

All modules must `use strictures 2;`.

All public functions (those not prefixed with `_`) must have POD documentation. When modifying a public function, check its POD and update it to reflect the changes.

The library uses OO design. Always use `Class::Tiny` for accessor generation, with a custom `new()` constructor (do not use `BUILD`).

Use `croak` (from `Carp`) for public API validation errors. Use `warn` in async callbacks where exceptions cannot propagate (e.g. AnyEvent handlers).

Dependencies are managed in `cpanfile`.

Shared test helpers live in `t/lib/TestFixtures.pm`. Use it whenever implementing something that could be re-used across multiple test files.
