# Net::Nostr::Core

Core Perl tooling for the Nostr protocol.

This distribution provides the existing public modules such as
`Net::Nostr::Event`, `Net::Nostr::Key`, `Net::Nostr::Filter`, and
`Net::Nostr::Message`. They are not renamed under `Net::Nostr::Core::*`.

`Net::Nostr::Identifier` includes pure NIP-05 helpers by default. Its network
methods, `lookup` and `verify`, require `AnyEvent::HTTP` and load it only when
called. Core recommends `AnyEvent::HTTP`; installing `Net::Nostr` requires it
for the full-stack install.
