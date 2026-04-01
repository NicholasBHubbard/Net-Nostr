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
    my ($self, $url) = @_;
    croak "url is required" unless defined $url;

    my $cv = AnyEvent->condvar;
    $self->_ws_client->connect($url)->cb(sub {
        my $conn = eval { shift->recv };
        if ($@) {
            $cv->croak("WebSocket connect failed: $@");
            return;
        }
        $self->_conn($conn);
        $self->_setup_handlers;
        $cv->send(1);
    });
    return $cv;
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
