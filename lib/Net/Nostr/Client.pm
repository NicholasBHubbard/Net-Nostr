package Net::Nostr::Client;

use strictures 2;

use Carp qw(croak);
use AnyEvent;
use AnyEvent::WebSocket::Client;
use Net::Nostr::Message;
use Class::Tiny qw(
    _ws_client
    _conn
    _callbacks
);

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->_ws_client(AnyEvent::WebSocket::Client->new);
    $self->_callbacks({});
    return $self;
}

sub connect {
    my ($self, $url, $cb) = @_;
    croak "url is required" unless defined $url;

    my $cv = AnyEvent->condvar;
    $self->_ws_client->connect($url)->cb(sub {
        my $conn = eval { shift->recv };
        if ($@) {
            $cv->croak("connect failed: $@");
            return;
        }
        $self->_conn($conn);
        $self->_setup_handlers;
        $cv->send;
    });

    if ($cb) {
        $cv->cb(sub { eval { shift->recv }; $cb->() });
        return;
    }

    $cv->recv;
    return $self;
}

sub is_connected {
    my ($self) = @_;
    return defined $self->_conn ? 1 : 0;
}

sub disconnect {
    my ($self) = @_;
    if ($self->_conn) {
        $self->_conn->close;
        $self->_conn(undef);
    }
}

sub publish {
    my ($self, $event) = @_;
    croak "not connected" unless $self->is_connected;
    my $msg = Net::Nostr::Message->new(type => 'EVENT', event => $event);
    $self->_conn->send($msg->serialize);
}

sub subscribe {
    my ($self, $sub_id, @filters) = @_;
    croak "not connected" unless $self->is_connected;
    my $msg = Net::Nostr::Message->new(
        type            => 'REQ',
        subscription_id => $sub_id,
        filters         => \@filters,
    );
    $self->_conn->send($msg->serialize);
}

sub close {
    my ($self, $sub_id) = @_;
    croak "not connected" unless $self->is_connected;
    my $msg = Net::Nostr::Message->new(type => 'CLOSE', subscription_id => $sub_id);
    $self->_conn->send($msg->serialize);
}

sub on {
    my ($self, $type, $cb) = @_;
    $self->_callbacks->{$type} = $cb;
}

sub _emit {
    my ($self, $type, @args) = @_;
    my $cb = $self->_callbacks->{$type};
    $cb->(@args) if $cb;
}

sub _setup_handlers {
    my ($self) = @_;
    $self->_conn->on(each_message => sub {
        my ($conn, $message) = @_;
        my $msg = eval { Net::Nostr::Message->parse($message->body) };
        return warn "bad message from relay: $@\n" if $@;

        if ($msg->type eq 'EVENT') {
            $self->_emit('event', $msg->subscription_id, $msg->event);
        } elsif ($msg->type eq 'OK') {
            $self->_emit('ok', $msg->event_id, $msg->accepted, $msg->message);
        } elsif ($msg->type eq 'EOSE') {
            $self->_emit('eose', $msg->subscription_id);
        } elsif ($msg->type eq 'NOTICE') {
            $self->_emit('notice', $msg->message);
        } elsif ($msg->type eq 'CLOSED') {
            $self->_emit('closed', $msg->subscription_id, $msg->message);
        }
    });

    $self->_conn->on(finish => sub {
        $self->_conn(undef);
    });
}

1;

__END__

=head1 NAME

Net::Nostr::Client - WebSocket client for Nostr relays

=head1 SYNOPSIS

    use Net::Nostr::Client;
    use Net::Nostr::Filter;

    my $client = Net::Nostr::Client->new;

    # Register callbacks before connecting
    $client->on(event => sub {
        my ($sub_id, $event) = @_;
        say "Got event: " . $event->content;
    });

    $client->on(ok => sub {
        my ($event_id, $accepted, $message) = @_;
        say $accepted ? "Accepted" : "Rejected: $message";
    });

    $client->on(eose => sub {
        my ($sub_id) = @_;
        say "End of stored events for $sub_id";
    });

    # Connect (blocks until connected)
    $client->connect("ws://127.0.0.1:8080");

    # Publish an event
    $client->publish($event);

    # Subscribe with one or more filters
    my $filter = Net::Nostr::Filter->new(kinds => [1], limit => 20);
    $client->subscribe('my-feed', $filter);

    # Close a subscription
    $client->close('my-feed');

    # Disconnect
    $client->disconnect;

=head1 DESCRIPTION

A WebSocket client for connecting to Nostr relays. Provides a callback-based
interface for publishing events, managing subscriptions, and receiving relay
messages.

=head1 CONSTRUCTOR

=head2 new

    my $client = Net::Nostr::Client->new;

Creates a new client instance. No connection is established until
C<connect> is called.

=head1 METHODS

=head2 connect

    $client->connect($url);

    # Non-blocking with callback:
    $client->connect($url, sub { ... });

Connects to the relay at the given WebSocket URL. Blocks until the
connection is established and returns C<$self> for chaining.

If a callback is provided, connects asynchronously and calls the
callback once connected. Returns immediately without blocking.

Croaks if C<$url> is not provided.

=head2 is_connected

    if ($client->is_connected) { ... }

Returns true if the client has an active WebSocket connection.

=head2 disconnect

    $client->disconnect;

Closes the WebSocket connection. C<is_connected> will return false
afterwards.

=head2 publish

    $client->publish($event);

Sends an EVENT message to the relay. The relay will respond with an OK
message (received via the C<ok> callback). Croaks if not connected.

=head2 subscribe

    $client->subscribe('sub-id', $filter1, $filter2);

Sends a REQ message to the relay with the given subscription ID and
filters. The relay will send matching stored events (via C<event>
callback), then an EOSE message (via C<eose> callback), then live
events as they arrive. Croaks if not connected.

=head2 close

    $client->close('sub-id');

Sends a CLOSE message to stop receiving events for the given
subscription ID. Croaks if not connected.

=head2 on

    $client->on($event_type => sub { ... });

Registers a callback for relay messages. Supported event types:

=over 4

=item C<event> - C<sub { my ($subscription_id, $event) = @_; }>

Called for each EVENT message from the relay (both stored and live).

=item C<ok> - C<sub { my ($event_id, $accepted, $message) = @_; }>

Called when the relay responds to a published event.

=item C<eose> - C<sub { my ($subscription_id) = @_; }>

Called when the relay finishes sending stored events for a subscription.

=item C<notice> - C<sub { my ($message) = @_; }>

Called when the relay sends a human-readable NOTICE.

=item C<closed> - C<sub { my ($subscription_id, $message) = @_; }>

Called when the relay closes a subscription.

=back

=head1 SEE ALSO

L<Net::Nostr>, L<Net::Nostr::Event>, L<Net::Nostr::Filter>, L<Net::Nostr::Relay>

=cut
