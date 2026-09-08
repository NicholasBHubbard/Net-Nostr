# September NIP updates: implementation and verification

Implements the supported-NIP findings in [the release audit](2026-09-07.md)
against nostr-protocol/nips commit
[c3fd9af17939316bf6d0d83a5759100f8b0a1bdb](https://github.com/nostr-protocol/nips/commit/c3fd9af17939316bf6d0d83a5759100f8b0a1bdb)
(2026-09-04). Also adds optional NIP-67 and NIP-A3 support. The earlier
probe/results files record the original main-branch behavior, before these fixes.

## Requirements and implementation

| Spec sections consulted | Result and conformance coverage |
| --- | --- |
| NIP-01: zero-limit REQ clarification | Relay `t/nip/01.t` exercises real WebSocket EOSE, stored suppression, mixed filters, configured limits, and live delivery. Existing behavior confirmed. |
| NIP-22: comment scope | Removed obsolete kind-1 prohibition; root/parent references and nested replies round-trip in Core `t/nip/22.t`. |
| NIP-29: group references | UTF-8 invite suffix parsing/formatting, malformed encoding rejection, join code propagation. Core `t/nip/29.t`. |
| NIP-29: metadata and pins | Banner, parent and ordered children; kind-9010 full pin replacements and kind-39005 snapshots; strict reference validation and empty clears. Core and Relay `t/nip/29.t`. |
| NIP-29: subgroup rules and membership | Optional RelayGroups validates both groups' administration, existing parents, cycles, complete child lists, ordering, reparenting and deletion. Signed metadata reflects transitions; memberships and roles do not inherit. Relay `t/nip/29.t`. |
| NIP-29: migration/fork detection | GroupDiscovery caches authenticated admins, coordinates periodic/offline kind-10009 lookups through an application-supplied transport, rejects stale/forged results, notifies about candidate hints, and builds explicitly requested signed migration lists preserving other forks and private entries. Client `t/nip/29.t` and tested Client adapter in `t/03-GroupDiscovery.t`. |
| NIP-34: pull requests | Removal of GRASP push instructions changes no event schema or Git helper behavior. Existing Core unit/conformance tests pass; no implementation change needed. |
| NIP-42 and NIP-67 | Hinted EOSE parsing, unknown strings, empty/absent round trips, Client callback hints, opt-in relay finish/more/auth, AUTH ordering, ties, NIP-11 advertisement. Core/Client/Relay `t/nip/67.t`. |
| NIP-46: unknown methods | Preserve request IDs and unknown method names, construct an error reply; document the application's dispatcher obligation. Core `t/nip/46.t`. |
| NIP-47: Info Event, get_info, external extensions | Discover extensible identifiers; strict discovery token validation; retain generic commands and legacy notifications. Core `t/nip/47.t`. External NWC specs reviewed at `6b408adedbd38da584035f949c48a368a792bd8b`; references updated. |
| NIP-51: standard lists | Favorite follow sets (10011) round-trip through the existing generic List API. Core `t/nip/51.t`; kind-specific item semantics remain application responsibility. |
| NIP-78: AUTH | Author authentication required for kinds 78/30078. Owner visibility precedes limits and covers stored/live/COUNT/negentropy, including multiple identities. Relay `t/nip/78.t`. |
| NIP-A3: tags, example, rendering | New strict PaymentTargets object; exact spec vectors, unknown types, empty lists, metadata round trips, URI component escaping. Core `t/nip/A3.t`. URI syntax checked against [RFC 8905 sections 2–3](https://datatracker.ietf.org/doc/html/rfc8905#section-2). |

## Public API and validation changes

- App data on kinds 78 and 30078 now requires authentication as its author to
  publish or read. Migrate public interchange data to a dedicated kind.
- Message adds validated `hints`; Client's `eose` callback retains subscription
  ID first and adds the optional hint array second (undef for legacy EOSE).
- Relay adds opt-in `eose_hints` and `groups`. Unlimited backend queries must
  return the complete matching set: authorization is applied before limits.
- Group adds invite/metadata fields and pin builders/parsers. WalletConnect
  Info adds `extensions` and `supports_extension`; malformed discovery lists
  and duplicate/malformed discovery tags now croak.
- New modules: Core `PaymentTargets`, Client `GroupDiscovery`, Relay `RelayGroups`.
- POD and all four distribution Changes files updated. README/shim supported
  lists and Core/shim conformance targets updated. Client Makefile includes
  its NIP tests. No version bump or CPAN release is part of this change.

## TDD record

Tests were written and run before each implementation cycle. Successful legacy
behavior (zero limits, generic lists, and remote-signing error payloads) was
recorded as passing without manufacturing failures. New-module test files
initially failed their module-load assertion, then exercised their full API
once implemented. Syntax/harness mistakes in initial test drafts were fixed
before relying on a functional failure.

Local logs are under `/tmp/net-nostr-nip-update/`:

| Cycle | Red evidence | Green evidence |
| --- | --- | --- |
| Comments and hints | `red-message-comment-valid.log` | `green-message-comment.log` |
| Relay app privacy and hints | `red-relay-privacy-hints-valid.log`, `red-relay-live-privacy.log` | `green-relay-privacy-hints.log` |
| Client hint callback | `red-client-hints.log` | `green-client-hints.log` |
| Wallet discovery | `red-wallet-discovery.log` | `green-wallet-discovery.log` |
| Group helpers | `red-group-helpers-functional.log`, `red-pin-timeline.log` | `green-group-helpers.log`, `green-pin-timeline.log` |
| Group relay policy | `red-group-policy-complete.log`, `red-group-boundaries.log`, `red-relay-timeline-scope.log` | `green-group-policy.log`, `green-group-boundaries.log`, `green-relay-timeline-scope.log` |
| Migration discovery | `red-group-discovery.log`, `red-discovery-trust.log`, `red-group-reference-discovery.log` | `green-group-discovery.log`, `green-discovery-trust.log`, `final-client.log` |
| Payment targets | `red-payment-targets-small-coverage.log` | `green-payment-targets-small-coverage.log` |
| Packaging and conformance target | `red-client-author-target.log`, `red-core-target.log`, `red-shim-target.log` | final author checks |

Additional regressions cover NUL-containing group IDs in child-list comparisons,
negentropy snapshots after membership revocation, admin roster changes during
an in-flight discovery request, timeouts, duplicate callbacks, and pin limit
defaults and cross-group relay timeline references. These tests exposed and then verified fixes to the new implementation.

## Verification

Full regular and author suites were run from each distribution root with
`prove -lv t/*.t t/nip/*.t t/author/*.t` using Linux Perl 5.44.0 and isolated
compatible dependency prefixes. Repository-local XS binaries from another
Perl were excluded. Source targets Perl 5.16; platform execution is checked by the CI matrix.

- Core: 100 files / 3406 reported tests, PASS (`full-core.log`).
- Client: 6 files / 51 reported tests, PASS (`final-client.log`).
- Relay: 8 files / 236 reported tests, PASS (`final-relay.log`).
- Shim: 13 files / 360 reported tests, PASS (`full-shim.log`).
- Core and shim author suites passed again after the conformance target update.
- Modified POD was reread; author tests check syntax and public-method coverage.
- `git diff --check` passed. Platform CI results are recorded on the PR.

## Deliberate scope and operational limits

Group enforcement and periodic discovery are opt-in. GroupDiscovery requires
application-owned lookup transport, reachability signals, cache persistence,
and user confirmation before migration; it does not silently switch relays.
The documented single-author Client adapter is tested through its real message
handlers. External live discovery services were not used as test dependencies.

RelayGroups supports an explicit admin policy and basic group access. It does
not implement LiveKit services, automatic membership propagation, history
import, or replica management. Those optional/deployment-specific services
need separate application integration; AV metadata edits are rejected. Durable
groups require a persistent backend retaining signed group state. In-memory
capacity eviction can remove that state. Group state changes close negentropy
sessions to prevent stale access; clients may reopen them. Custom stores are
responsible for transaction/durability guarantees if writes fail.

PaymentTargets deliberately leaves network-specific account/checksum checks
to applications: a generic cross-network list cannot guarantee their validity.
It renders targets but never initiates a payment.

Unadvertised NIPs 30, 84, B0, and optional NWC-321 remain outside this supported-
NIP update. This is verification of changed requirements and regression suites,
not a new independent audit of every requirement in the unchanged NIPs.
