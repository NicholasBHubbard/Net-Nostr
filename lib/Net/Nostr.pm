package Net::Nostr;

use strictures 2;

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
    $client->connect("ws://relay.example.com")->recv;

    # Run a relay
    my $relay = Net::Nostr->relay;
    $relay->start('127.0.0.1', 8080);

=head1 DESCRIPTION

Net::Nostr is the top-level entry point for working with the Nostr protocol
in Perl. It provides two factory methods that return client and relay objects.

For identity and key management see L<Net::Nostr::Key>. For event creation
and signing see L<Net::Nostr::Event>.

=head1 METHODS

=head2 client

    my $client = Net::Nostr->client;

Returns a new L<Net::Nostr::Client> instance for connecting to relays.

    my $client = Net::Nostr->client;
    $client->on(event => sub { my ($sub_id, $event) = @_; ... });
    $client->connect("ws://relay.example.com")->recv;
    $client->subscribe('my-feed', $filter);
    $client->publish($event);
    $client->disconnect;

=head2 relay

    my $relay = Net::Nostr->relay;

Returns a new L<Net::Nostr::Relay> instance for running a relay server.

    my $relay = Net::Nostr->relay;
    $relay->start('127.0.0.1', 8080);
    AnyEvent->condvar->recv;  # run the event loop

=head1 LOWER-LEVEL MODULES

=over 4

=item L<Net::Nostr::Key>

Secp256k1 keypair management. Generates keys, exports in multiple formats
(hex, raw, DER, PEM), produces BIP-340 Schnorr signatures, and creates
signed events.

    my $key = Net::Nostr::Key->new;
    say $key->pubkey_hex;
    my $event = $key->create_event(kind => 1, content => 'hello');

=item L<Net::Nostr::Event>

Nostr event object. Handles serialization, ID computation, tag management,
and signature verification.

    my $event = Net::Nostr::Event->new(
        pubkey  => $hex, kind => 1,
        content => 'hi', tags => [],
    );
    say $event->id;
    say $event->json_serialize;

=item L<Net::Nostr::Client>

WebSocket client for connecting to Nostr relays. Supports publishing events,
subscribing with filters, and receiving live events.

    my $client = Net::Nostr::Client->new;
    $client->connect("ws://relay.example.com")->recv;
    $client->subscribe('sub1', $filter);
    $client->publish($event);
    $client->disconnect;

=item L<Net::Nostr::Relay>

WebSocket relay server implementing NIP-01 event storage, subscription
management, and broadcasting.

    my $relay = Net::Nostr::Relay->new;
    $relay->start('127.0.0.1', 8080);
    $relay->stop;

=item L<Net::Nostr::Filter>

Filter objects for querying events. Supports filtering by C<ids>, C<authors>,
C<kinds>, C<since>, C<until>, C<limit>, and C<#E<lt>letterE<gt>> tag filters.

    my $filter = Net::Nostr::Filter->new(
        kinds   => [1],
        authors => [$pubkey_hex],
        limit   => 50,
    );

=item L<Net::Nostr::Message>

Protocol message serialization and parsing. Handles all NIP-01 message types:
C<EVENT>, C<REQ>, C<CLOSE>, C<OK>, C<EOSE>, C<CLOSED>, C<NOTICE>.

    my $msg = Net::Nostr::Message->new(
        type => 'REQ', subscription_id => 'sub1',
        filters => [$filter],
    );
    my $json = $msg->serialize;
    my $parsed = Net::Nostr::Message->parse($json);

=back

=head1 SEE ALSO

L<https://github.com/nostr-protocol/nips/blob/master/01.md> - NIP-01 specification

=cut
