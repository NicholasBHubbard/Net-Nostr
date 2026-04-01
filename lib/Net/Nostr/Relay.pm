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
            if (Net::Nostr::Filter::matches_any($event, @$filters)) {
                $conn->send(Net::Nostr::Message::relay_event_msg($sub_id, $event));
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
        my $msg = eval { Net::Nostr::Message::parse($message->body) };
        return warn "bad message: $@\n" if $@;

        if ($msg->{type} eq 'EVENT') {
            $self->_handle_event($conn_id, $msg->{event});
        } elsif ($msg->{type} eq 'REQ') {
            $self->_handle_req($conn_id, $msg->{subscription_id}, @{$msg->{filters}});
        } elsif ($msg->{type} eq 'CLOSE') {
            $self->_handle_close($conn_id, $msg->{subscription_id});
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

sub _handle_event {
    my ($self, $conn_id, $event) = @_;
    my $conn = $self->connections->{$conn_id};

    my $error = $self->_validate_event($event);
    if ($error) {
        $conn->send(Net::Nostr::Message::ok_msg($event->id // '', 0, $error));
        return;
    }

    # duplicate detection
    for my $existing (@{$self->{events}}) {
        if ($existing->id eq $event->id) {
            $conn->send(Net::Nostr::Message::ok_msg($event->id, 1, 'duplicate: already have this event'));
            return;
        }
    }

    push @{$self->{events}}, $event;
    $conn->send(Net::Nostr::Message::ok_msg($event->id, 1, ''));
    $self->broadcast($event);
}

sub _handle_req {
    my ($self, $conn_id, $sub_id, @filters) = @_;
    my $conn = $self->connections->{$conn_id};

    # store the first filter for this subscription (used by broadcast)
    $self->{subscriptions}{$conn_id} //= {};
    $self->{subscriptions}{$conn_id}{$sub_id} = \@filters;

    # send stored events matching any filter
    for my $event (@{$self->{events}}) {
        if (Net::Nostr::Filter::matches_any($event, @filters)) {
            $conn->send(Net::Nostr::Message::relay_event_msg($sub_id, $event));
        }
    }

    $conn->send(Net::Nostr::Message::eose_msg($sub_id));
}

sub _handle_close {
    my ($self, $conn_id, $sub_id) = @_;
    delete $self->{subscriptions}{$conn_id}{$sub_id} if $self->{subscriptions}{$conn_id};
}

1;
