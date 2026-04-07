# Net::Nostr

A [Nostr](https://nostr.org/) client and relay library for Perl.

Net::Nostr provides both client and relay functionality, implementing 35+
NIPs covering identity, messaging, encryption, social features, and more.

## Quick Start

### Client

```perl
use Net::Nostr::Key;
use Net::Nostr::Client;

my $key    = Net::Nostr::Key->new;
my $client = Net::Nostr::Client->new;
$client->connect('wss://relay.example.com');

my $event = $key->create_event(kind => 1, content => 'Hello Nostr!', tags => []);
$client->publish($event);
```

### Relay

```perl
use Net::Nostr::Relay;

my $relay = Net::Nostr::Relay->new;
$relay->run('127.0.0.1', 8080);
```

## Main Components

| Module | Description |
|--------|-------------|
| `Net::Nostr::Key` | Secp256k1 keypair management, BIP-340 Schnorr signatures |
| `Net::Nostr::Event` | Event creation, serialization, ID computation |
| `Net::Nostr::Client` | WebSocket client for connecting to relays |
| `Net::Nostr::Relay` | In-process WebSocket relay server |
| `Net::Nostr::Filter` | Event filtering for subscriptions |
| `Net::Nostr::Message` | NIP-01 wire protocol messages |
| `Net::Nostr::Encryption` | NIP-44 versioned encrypted payloads |
| `Net::Nostr::GiftWrap` | NIP-59 gift wrap (three-layer encryption) |
| `Net::Nostr::DirectMessage` | NIP-17 private direct messages |
| `Net::Nostr::Bech32` | NIP-19 bech32-encoded entities |

See [the full module list on MetaCPAN](https://metacpan.org/pod/Net::Nostr).

## Supported NIPs

NIP-01, 02, 03, 05, 06, 09, 10, 11, 13, 15, 17, 18, 19, 21, 22, 23,
25, 28, 29, 32, 34, 36, 40, 42, 44, 45, 46, 47, 50, 51, 56, 57, 59,
60, 61, 65, 72, 89, 92, 99, B7.

NIP-04 (legacy encrypted DMs) is deprecated and not supported.

## Security Notes

- `Net::Nostr::Message->parse` validates message structure but does **not**
  verify event signatures or ID hashes. Callers must verify events from
  untrusted sources separately.
- `Net::Nostr::GiftWrap->unwrap` decrypts and parses layered encryption
  but does **not** verify outer event signatures. Verify before unwrapping
  when processing events from untrusted relays.
- The relay (`Net::Nostr::Relay`) verifies signatures by default.

## Documentation

Full API documentation: https://metacpan.org/pod/Net::Nostr

## Building

```bash
perl Makefile.PL
make manifest
make dist
```
