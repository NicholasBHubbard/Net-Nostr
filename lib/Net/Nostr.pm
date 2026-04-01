package Net::Nostr;

use strictures 2;

use Net::Nostr::Key;
use Net::Nostr::Event;
use Net::Nostr::Client;
use Net::Nostr::Relay;
use Class::Tiny qw(key);

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->{_constructor_args} = { @_ };
    $self->key(Net::Nostr::Key->new($self->_key_args));
    return $self;
}

sub create_event {
    my ($self, %args) = @_;
    $args{pubkey} = $self->key->pubkey_hex;
    my $event = Net::Nostr::Event->new(%args);
    $self->sign_event($event);
    return $event;
}

sub sign_event {
    my ($self, $event) = @_;
    my $sig_raw = $self->key->schnorr_sign($event->id);
    my $sig_hex = unpack 'H*', $sig_raw;
    $event->sig($sig_hex);
    return $sig_hex;
}

sub client {
    my ($self) = @_;
    return Net::Nostr::Client->new;
}

sub relay {
    my ($self) = @_;
    return Net::Nostr::Relay->new;
}

sub _key_args {
    my ($self) = @_;
    my %args = %{ $self->{_constructor_args} };
    my %key_args;
    my @key_keys = Net::Nostr::Key->constructor_keys;
    for my $k (keys %args) {
        $key_args{$k} = $args{$k} if grep { $_ eq $k } @key_keys;
    }
    return %key_args;
}

1;

__END__

=head1 NAME

Net::Nostr - Perl client and relay library for the Nostr protocol

=head1 SYNOPSIS

    use Net::Nostr;
    use Net::Nostr::Filter;

    # Generate a new identity
    my $nostr = Net::Nostr->new;

    # Or use an existing private key (DER-encoded scalar ref)
    my $nostr = Net::Nostr->new(privkey => \$der_bytes);

    # Create a signed event
    my $event = $nostr->create_event(
        kind    => 1,
        content => 'hello nostr',
        tags    => [['t', 'introduction']],
    );

    # Publish to a relay
    my $client = $nostr->client;
    $client->on(ok    => sub { my ($id, $accepted, $msg) = @_; ... });
    $client->on(event => sub { my ($sub_id, $event) = @_;      ... });
    $client->on(eose  => sub { my ($sub_id) = @_;              ... });

    $client->connect("ws://relay.example.com")->recv;
    $client->publish($event);

    # Subscribe to events
    my $filter = Net::Nostr::Filter->new(kinds => [1], limit => 20);
    $client->subscribe('my-feed', $filter);

    # Close a subscription
    $client->close('my-feed');
    $client->disconnect;

    # Run a relay
    my $relay = $nostr->relay;
    $relay->start('127.0.0.1', 8080);
    AnyEvent->condvar->recv;  # run the event loop

=head1 DESCRIPTION

Net::Nostr is the top-level entry point for working with the Nostr protocol
in Perl. It manages your identity (keypair) and provides factory methods for
creating clients and relays.

For basic use cases, this module and L<Net::Nostr::Filter> are all you need.
The lower-level modules are available for advanced usage.

=head1 METHODS

=head2 new

    my $nostr = Net::Nostr->new;
    my $nostr = Net::Nostr->new(privkey => \$der_bytes);
    my $nostr = Net::Nostr->new(pubkey  => \$der_bytes);

Creates a new Net::Nostr instance. Without arguments, generates a fresh
secp256k1 keypair. Pass C<privkey> or C<pubkey> as a scalar reference to
DER-encoded key data to use an existing identity.

=head2 create_event

    my $event = $nostr->create_event(
        kind       => 1,
        content    => 'hello',
        tags       => [['p', $pubkey_hex]],
        created_at => time(),
    );

Creates a L<Net::Nostr::Event>, automatically setting C<pubkey> from the
instance's key, computing the event C<id>, and signing it. Returns the
signed event ready for publishing.

C<kind> and C<content> are required. C<tags> defaults to C<[]> and
C<created_at> defaults to the current time.

=head2 sign_event

    my $sig_hex = $nostr->sign_event($event);

Signs an existing L<Net::Nostr::Event> with this instance's private key.
Sets C<< $event->sig >> and returns the 128-character hex signature string.

=head2 client

    my $client = $nostr->client;

Returns a new L<Net::Nostr::Client> instance for connecting to relays.

=head2 relay

    my $relay = $nostr->relay;

Returns a new L<Net::Nostr::Relay> instance for running a relay server.

=head2 key

    my $key = $nostr->key;

Returns the L<Net::Nostr::Key> instance managing this identity's keypair.

    say $nostr->key->pubkey_hex;   # 64-char hex public key
    say $nostr->key->privkey_hex;  # 64-char hex private key

=head1 LOWER-LEVEL MODULES

=over 4

=item L<Net::Nostr::Event>

Nostr event object. Handles serialization, ID computation, tag management,
and signature verification. Knows about event kind ranges (regular,
replaceable, ephemeral, addressable).

    my $event = Net::Nostr::Event->new(
        pubkey  => $hex, kind => 1,
        content => 'hi', tags => [],
    );
    say $event->id;              # sha256 hex
    say $event->json_serialize;  # canonical JSON for hashing

=item L<Net::Nostr::Client>

WebSocket client for connecting to Nostr relays. Supports publishing events,
subscribing with filters, and receiving live events.

    my $client = Net::Nostr::Client->new;
    $client->connect("ws://relay.example.com")->recv;
    $client->on(event => sub { my ($sub_id, $event) = @_; ... });
    $client->subscribe('sub1', $filter1, $filter2);
    $client->publish($event);
    $client->close('sub1');
    $client->disconnect;

=item L<Net::Nostr::Relay>

WebSocket relay server implementing NIP-01 event storage, subscription
management, and broadcasting. Handles replaceable, ephemeral, and
addressable event semantics.

    my $relay = Net::Nostr::Relay->new;
    $relay->start('127.0.0.1', 8080);
    $relay->stop;

=item L<Net::Nostr::Filter>

Filter objects for querying events. Supports filtering by C<ids>, C<authors>,
C<kinds>, C<since>, C<until>, C<limit>, and C<#E<lt>letterE<gt>> tag filters.

    my $filter = Net::Nostr::Filter->new(
        kinds   => [1],
        authors => [$pubkey_hex],
        since   => time() - 3600,
        limit   => 50,
    );

=item L<Net::Nostr::Key>

Secp256k1 keypair management. Generates keys, exports in multiple formats
(hex, raw, DER, PEM), and produces BIP-340 Schnorr signatures.

    my $key = Net::Nostr::Key->new;
    say $key->pubkey_hex;
    my $sig = $key->schnorr_sign($message);

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
