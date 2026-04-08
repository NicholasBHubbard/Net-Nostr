# Net::Nostr

A [Nostr](https://nostr.org/) library for Perl.

Net::Nostr provides both client and relay functionality, implementing 35+
NIPs covering identity, messaging, encryption, social features, and more.

## Installation

```
$ cpanm Net::Nostr
```

## Documentation

Full API documentation: https://metacpan.org/pod/Net::Nostr

## Supported NIPs

- [NIP-01](https://github.com/nostr-protocol/nips/blob/master/01.md) - Basic protocol flow
- [NIP-02](https://github.com/nostr-protocol/nips/blob/master/02.md) - Follow list
- [NIP-03](https://github.com/nostr-protocol/nips/blob/master/03.md) - OpenTimestamps attestations for events
- [NIP-05](https://github.com/nostr-protocol/nips/blob/master/05.md) - Mapping Nostr keys to DNS-based internet identifiers
- [NIP-06](https://github.com/nostr-protocol/nips/blob/master/06.md) - Basic key derivation from mnemonic seed phrase
- [NIP-09](https://github.com/nostr-protocol/nips/blob/master/09.md) - Event deletion request
- [NIP-10](https://github.com/nostr-protocol/nips/blob/master/10.md) - Text notes and threads
- [NIP-11](https://github.com/nostr-protocol/nips/blob/master/11.md) - Relay information document
- [NIP-13](https://github.com/nostr-protocol/nips/blob/master/13.md) - Proof of Work
- [NIP-15](https://github.com/nostr-protocol/nips/blob/master/15.md) - Nostr Marketplace
- [NIP-17](https://github.com/nostr-protocol/nips/blob/master/17.md) - Private direct messages
- [NIP-18](https://github.com/nostr-protocol/nips/blob/master/18.md) - Reposts
- [NIP-19](https://github.com/nostr-protocol/nips/blob/master/19.md) - bech32-encoded entities
- [NIP-21](https://github.com/nostr-protocol/nips/blob/master/21.md) - `nostr:` URI scheme
- [NIP-22](https://github.com/nostr-protocol/nips/blob/master/22.md) - Comment
- [NIP-23](https://github.com/nostr-protocol/nips/blob/master/23.md) - Long-form content
- [NIP-24](https://github.com/nostr-protocol/nips/blob/master/24.md) - Extra metadata fields and tags
- [NIP-27](https://github.com/nostr-protocol/nips/blob/master/27.md) - Text note references
- [NIP-25](https://github.com/nostr-protocol/nips/blob/master/25.md) - Reactions
- [NIP-28](https://github.com/nostr-protocol/nips/blob/master/28.md) - Public chat
- [NIP-29](https://github.com/nostr-protocol/nips/blob/master/29.md) - Relay-based groups
- [NIP-32](https://github.com/nostr-protocol/nips/blob/master/32.md) - Labeling
- [NIP-34](https://github.com/nostr-protocol/nips/blob/master/34.md) - git stuff
- [NIP-36](https://github.com/nostr-protocol/nips/blob/master/36.md) - Sensitive Content / Content Warning
- [NIP-40](https://github.com/nostr-protocol/nips/blob/master/40.md) - Expiration timestamp
- [NIP-42](https://github.com/nostr-protocol/nips/blob/master/42.md) - Authentication of clients to relays
- [NIP-44](https://github.com/nostr-protocol/nips/blob/master/44.md) - Encrypted payloads (versioned)
- [NIP-45](https://github.com/nostr-protocol/nips/blob/master/45.md) - Event counts
- [NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) - Nostr Remote Signing
- [NIP-47](https://github.com/nostr-protocol/nips/blob/master/47.md) - Nostr Wallet Connect
- [NIP-49](https://github.com/nostr-protocol/nips/blob/master/49.md) - Private key encryption
- [NIP-50](https://github.com/nostr-protocol/nips/blob/master/50.md) - Search capability
- [NIP-51](https://github.com/nostr-protocol/nips/blob/master/51.md) - Lists
- [NIP-56](https://github.com/nostr-protocol/nips/blob/master/56.md) - Reporting
- [NIP-57](https://github.com/nostr-protocol/nips/blob/master/57.md) - Lightning Zaps
- [NIP-58](https://github.com/nostr-protocol/nips/blob/master/58.md) - Badges
- [NIP-59](https://github.com/nostr-protocol/nips/blob/master/59.md) - Gift wrap
- [NIP-60](https://github.com/nostr-protocol/nips/blob/master/60.md) - Cashu wallets
- [NIP-61](https://github.com/nostr-protocol/nips/blob/master/61.md) - Nutzaps
- [NIP-65](https://github.com/nostr-protocol/nips/blob/master/65.md) - Relay list metadata
- [NIP-66](https://github.com/nostr-protocol/nips/blob/master/66.md) - Relay Discovery and Liveness Monitoring
- [NIP-70](https://github.com/nostr-protocol/nips/blob/master/70.md) - Protected Events
- [NIP-78](https://github.com/nostr-protocol/nips/blob/master/78.md) - Arbitrary Custom App Data
- [NIP-72](https://github.com/nostr-protocol/nips/blob/master/72.md) - Moderated Communities
- [NIP-77](https://github.com/nostr-protocol/nips/blob/master/77.md) - Negentropy Syncing
- [NIP-86](https://github.com/nostr-protocol/nips/blob/master/86.md) - Relay Management API
- [NIP-89](https://github.com/nostr-protocol/nips/blob/master/89.md) - Recommended Application Handlers
- [NIP-92](https://github.com/nostr-protocol/nips/blob/master/92.md) - Media Attachments
- [NIP-94](https://github.com/nostr-protocol/nips/blob/master/94.md) - File Metadata
- [NIP-98](https://github.com/nostr-protocol/nips/blob/master/98.md) - HTTP auth
- [NIP-99](https://github.com/nostr-protocol/nips/blob/master/99.md) - Classified Listings
- [NIP-B7](https://github.com/nostr-protocol/nips/blob/master/B7.md) - Blossom media

NIP-04 (legacy encrypted DMs) is deprecated and not supported.
