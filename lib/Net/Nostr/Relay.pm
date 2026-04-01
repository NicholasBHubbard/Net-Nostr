package Net::Nostr::Relay;

use strictures 2;

use Net::Nostr::Message;
use Net::Nostr::Filter;

use AnyEvent::Socket qw(tcp_server);
use AnyEvent::WebSocket::Server;
use Digest::SHA qw(sha256_hex);
use JSON;

use Class::Tiny qw(
    server
    connections
    subscriptions
    events
    _guard
);

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->server(AnyEvent::WebSocket::Server->new()) unless $self->server;
    return $self;
}

sub start {
    my ($self, $host, $port) = @_;
    $self->_guard(tcp_server($host, $port, sub {
        my ($fh) = @_;
        $self->server->establish($fh)->cb(sub {
            my $conn = eval { shift->recv };
            return warn "WebSocket handshake failed: $@\n" if $@;
            $self->_on_connection($conn);
        });
    }));
}

sub stop {
    my ($self) = @_;
    $self->_guard(undef);
    for my $conn (values %{$self->connections || {}}) {
        $conn->close;
    }
    $self->connections({});
    $self->subscriptions({});
}

sub broadcast {
    my ($self, $event) = @_;
    my $subs = $self->subscriptions || {};
    for my $conn_id (keys %$subs) {
        my $conn = $self->connections->{$conn_id} or next;
        for my $sub_id (keys %{$subs->{$conn_id}}) {
            my $filters = $subs->{$conn_id}{$sub_id};
            if (Net::Nostr::Filter->matches_any($event, @$filters)) {
                $conn->send(Net::Nostr::Message->new(type => 'EVENT', subscription_id => $sub_id, event => $event)->serialize);
            }
        }
    }
}

my $CONN_ID = 0;

sub _on_connection {
    my ($self, $conn) = @_;
    my $conn_id = ++$CONN_ID;

    $self->{connections} //= {};
    $self->{subscriptions} //= {};
    $self->{events} //= [];

    $self->connections->{$conn_id} = $conn;

    $conn->on(each_message => sub {
        my ($conn, $message) = @_;
        my $msg = eval { Net::Nostr::Message->parse($message->body) };
        return warn "bad message: $@\n" if $@;

        if ($msg->type eq 'EVENT') {
            $self->_handle_event($conn_id, $msg->event);
        } elsif ($msg->type eq 'REQ') {
            $self->_handle_req($conn_id, $msg->subscription_id, @{$msg->filters});
        } elsif ($msg->type eq 'CLOSE') {
            $self->_handle_close($conn_id, $msg->subscription_id);
        }
    });

    $conn->on(finish => sub {
        delete $self->connections->{$conn_id};
        delete $self->subscriptions->{$conn_id};
    });
}

my $HEX64  = qr/\A[0-9a-f]{64}\z/;
my $HEX128 = qr/\A[0-9a-f]{128}\z/;

sub _validate_event {
    my ($self, $event) = @_;
    return 'invalid: bad id format'     unless defined $event->id     && $event->id     =~ $HEX64;
    return 'invalid: bad pubkey format' unless defined $event->pubkey && $event->pubkey =~ $HEX64;
    return 'invalid: bad sig format'    unless defined $event->sig    && $event->sig    =~ $HEX128;

    my $expected_id = sha256_hex($event->json_serialize);
    return 'invalid: id does not match hash' unless $event->id eq $expected_id;

    return undef;
}

sub _is_newer {
    my ($new, $existing) = @_;
    return 1 if $new->created_at > $existing->created_at;
    return 1 if $new->created_at == $existing->created_at && $new->id lt $existing->id;
    return 0;
}

sub _handle_event {
    my ($self, $conn_id, $event) = @_;
    my $conn = $self->connections->{$conn_id};

    my $error = $self->_validate_event($event);
    if ($error) {
        $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => ($event->id // ''), accepted => 0, message => $error)->serialize);
        return;
    }

    # duplicate detection
    for my $existing (@{$self->{events}}) {
        if ($existing->id eq $event->id) {
            $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 1, message => 'duplicate: already have this event')->serialize);
            return;
        }
    }

    # ephemeral events: broadcast but don't store
    if ($event->is_ephemeral) {
        $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 1, message => '')->serialize);
        $self->broadcast($event);
        return;
    }

    # replaceable events: keep only latest per pubkey+kind
    if ($event->is_replaceable) {
        for my $i (0 .. $#{$self->{events}}) {
            my $existing = $self->{events}[$i];
            if ($existing->pubkey eq $event->pubkey && $existing->kind == $event->kind) {
                if (_is_newer($event, $existing)) {
                    splice @{$self->{events}}, $i, 1;
                } else {
                    $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 1, message => 'duplicate: have a newer version')->serialize);
                    return;
                }
                last;
            }
        }
    }

    # addressable events: keep only latest per pubkey+kind+d_tag
    if ($event->is_addressable) {
        my $d = $event->d_tag;
        for my $i (0 .. $#{$self->{events}}) {
            my $existing = $self->{events}[$i];
            if ($existing->pubkey eq $event->pubkey && $existing->kind == $event->kind && $existing->d_tag eq $d) {
                if (_is_newer($event, $existing)) {
                    splice @{$self->{events}}, $i, 1;
                } else {
                    $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 1, message => 'duplicate: have a newer version')->serialize);
                    return;
                }
                last;
            }
        }
    }

    push @{$self->{events}}, $event;
    $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 1, message => '')->serialize);
    $self->broadcast($event);
}

sub _handle_req {
    my ($self, $conn_id, $sub_id, @filters) = @_;
    my $conn = $self->connections->{$conn_id};

    $self->{subscriptions}{$conn_id} //= {};
    $self->{subscriptions}{$conn_id}{$sub_id} = \@filters;

    # collect matching events
    my @matching;
    for my $event (@{$self->{events}}) {
        push @matching, $event if Net::Nostr::Filter->matches_any($event, @filters);
    }

    # sort by created_at DESC, then id ASC for ties
    @matching = sort {
        $b->created_at <=> $a->created_at || $a->id cmp $b->id
    } @matching;

    # apply limit (use minimum limit across filters that specify one)
    my $limit;
    for my $f (@filters) {
        if (defined $f->limit) {
            $limit = $f->limit if !defined $limit || $f->limit < $limit;
        }
    }
    splice @matching, $limit if defined $limit && $limit < @matching;

    for my $event (@matching) {
        $conn->send(Net::Nostr::Message->new(type => 'EVENT', subscription_id => $sub_id, event => $event)->serialize);
    }

    $conn->send(Net::Nostr::Message->new(type => 'EOSE', subscription_id => $sub_id)->serialize);
}

sub _handle_close {
    my ($self, $conn_id, $sub_id) = @_;
    delete $self->{subscriptions}{$conn_id}{$sub_id} if $self->{subscriptions}{$conn_id};
}

1;

__END__

=head1 NAME

Net::Nostr::Relay - Nostr WebSocket relay server

=head1 SYNOPSIS

    use Net::Nostr::Relay;

    my $relay = Net::Nostr::Relay->new;
    $relay->start('127.0.0.1', 8080);

    # Run the event loop
    AnyEvent->condvar->recv;

    # Shut down
    $relay->stop;

=head1 DESCRIPTION

An in-process Nostr relay implementing NIP-01. Accepts WebSocket connections,
stores events, manages subscriptions, and broadcasts new events to matching
subscribers.

Supports all NIP-01 event semantics:

=over 4

=item * Regular events - stored and broadcast

=item * Replaceable events (kinds 0, 3, 10000-19999) - only latest per pubkey+kind

=item * Ephemeral events (kinds 20000-29999) - broadcast but never stored

=item * Addressable events (kinds 30000-39999) - only latest per pubkey+kind+d_tag

=back

=head1 CONSTRUCTOR

=head2 new

    my $relay = Net::Nostr::Relay->new;

Creates a new relay instance with a default WebSocket server.

=head1 METHODS

=head2 start

    $relay->start($host, $port);
    $relay->start('127.0.0.1', 8080);

Starts listening for WebSocket connections on the given host and port.

=head2 stop

    $relay->stop;

Stops the relay, closes all connections, and clears all subscriptions.
Safe to call on an unstarted relay.

=head2 broadcast

    $relay->broadcast($event);

Sends the event to all connected clients whose subscriptions match.
Normally called internally when a new event is accepted, but can be
called directly for testing or custom event injection.

    # Manually inject an event to subscribers
    $relay->broadcast($event);

=head2 server

    my $ws_server = $relay->server;

Returns the underlying L<AnyEvent::WebSocket::Server> instance.

=head2 connections

    my $conns = $relay->connections;  # hashref { conn_id => $conn }

Returns the hashref of active WebSocket connections.

=head2 subscriptions

    my $subs = $relay->subscriptions;
    # { conn_id => { sub_id => [$filter, ...], ... } }

Returns the hashref of active subscriptions, keyed by connection ID
then subscription ID.

=head2 events

    my $events = $relay->events;  # arrayref of Net::Nostr::Event

Returns the arrayref of stored events.

=head1 SEE ALSO

L<Net::Nostr>, L<Net::Nostr::Client>, L<Net::Nostr::Event>

=cut
