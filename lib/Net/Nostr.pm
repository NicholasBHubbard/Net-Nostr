package Net::Nostr;

use strictures 2;

our $VERSION = '0.002000';

use Net::Nostr::Client;
use Net::Nostr::Relay;

sub client { Net::Nostr::Client->new }

sub relay { Net::Nostr::Relay->new }

1;

__END__

=head1 NAME

Net::Nostr - Perl client and relay library for the Nostr protocol

=head1 SYNOPSIS

    use Net::Nostr;

    # Connect to a relay as a client
    my $client = Net::Nostr->client;
    $client->connect("ws://relay.example.com");

    # Run a relay
    my $relay = Net::Nostr->relay;
    $relay->run('127.0.0.1', 8080);

=head1 DESCRIPTION

Net::Nostr is a Perl implementation of the Nostr protocol that provides both
client and relay functionality. Most of the useful functionality lives in the
individual modules listed below -- start with L<Net::Nostr::Key> for identity
management and L<Net::Nostr::Event> for creating events.

=head1 SUPPORTED NIPS

=over 4

=item L<NIP-01|https://github.com/nostr-protocol/nips/blob/master/01.md> - Basic protocol flow

=item L<NIP-02|https://github.com/nostr-protocol/nips/blob/master/02.md> - Follow list

=item L<NIP-09|https://github.com/nostr-protocol/nips/blob/master/09.md> - Event deletion request

=item L<NIP-10|https://github.com/nostr-protocol/nips/blob/master/10.md> - Text notes and threads

=item L<NIP-11|https://github.com/nostr-protocol/nips/blob/master/11.md> - Relay information document

=item L<NIP-19|https://github.com/nostr-protocol/nips/blob/master/19.md> - bech32-encoded entities

=item L<NIP-28|https://github.com/nostr-protocol/nips/blob/master/28.md> - Public chat

=item L<NIP-42|https://github.com/nostr-protocol/nips/blob/master/42.md> - Authentication of clients to relays

=item L<NIP-44|https://github.com/nostr-protocol/nips/blob/master/44.md> - Encrypted payloads (versioned)

=item L<NIP-29|https://github.com/nostr-protocol/nips/blob/master/29.md> - Relay-based groups

=item L<NIP-51|https://github.com/nostr-protocol/nips/blob/master/51.md> - Lists

=back

NIP-04 (encrypted direct messages) is deprecated and not supported.
Use NIP-44 for encryption instead.

=head1 MODULES

=over 4

=item L<Net::Nostr::Client> - WebSocket client for connecting to Nostr relays

=item L<Net::Nostr::Relay> - WebSocket relay server implementing NIP-01

=item L<Net::Nostr::Event> - Nostr event serialization, ID computation, and verification

=item L<Net::Nostr::Filter> - Filter objects for querying events

=item L<Net::Nostr::Message> - Protocol message serialization and parsing

=item L<Net::Nostr::Key> - Secp256k1 keypair management and BIP-340 Schnorr signatures

=item L<Net::Nostr::Deletion> - NIP-09 event deletion requests

=item L<Net::Nostr::FollowList> - NIP-02 follow list management

=item L<Net::Nostr::Thread> - NIP-10 text note threading

=item L<Net::Nostr::Bech32> - NIP-19 bech32-encoded entities

=item L<Net::Nostr::Channel> - NIP-28 public chat channels

=item L<Net::Nostr::RelayInfo> - NIP-11 relay information document

=item L<Net::Nostr::Encryption> - NIP-44 versioned encrypted payloads

=item L<Net::Nostr::Group> - NIP-29 relay-based groups

=item L<Net::Nostr::List> - NIP-51 lists and sets

=back

=cut
