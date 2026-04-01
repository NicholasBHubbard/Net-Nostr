package Net::Nostr::Message;

use strictures 2;

use Carp qw(croak);
use JSON;
use Net::Nostr::Event;
use Net::Nostr::Filter;
use Class::Tiny qw(type subscription_id event event_id accepted message prefix filters);

my $JSON = JSON->new->utf8;

sub _validate_subscription_id {
    my ($sub_id) = @_;
    croak "subscription_id must be a non-empty string"
        unless defined $sub_id && length($sub_id) > 0;
    croak "subscription_id must be at most 64 characters"
        unless length($sub_id) <= 64;
}

sub _extract_prefix {
    my ($message) = @_;
    return undef unless defined $message && $message =~ /^([a-z-]+): /;
    return $1;
}

sub new {
    my $class = shift;
    my %args = @_;
    my $self = bless {}, $class;

    croak "type is required" unless defined $args{type};
    $self->type($args{type});

    my $type = $args{type};

    if ($type eq 'EVENT') {
        croak "event is required for EVENT message" unless $args{event};
        $self->event($args{event});
        $self->subscription_id($args{subscription_id}) if defined $args{subscription_id};
    } elsif ($type eq 'REQ') {
        _validate_subscription_id($args{subscription_id});
        $self->subscription_id($args{subscription_id});
        croak "req requires at least one filter"
            unless $args{filters} && @{$args{filters}};
        $self->filters($args{filters});
    } elsif ($type eq 'CLOSE') {
        _validate_subscription_id($args{subscription_id});
        $self->subscription_id($args{subscription_id});
    } elsif ($type eq 'OK') {
        $self->event_id($args{event_id});
        $self->accepted($args{accepted} ? 1 : 0);
        $self->message($args{message} // '');
        $self->prefix(_extract_prefix($self->message));
    } elsif ($type eq 'EOSE') {
        $self->subscription_id($args{subscription_id});
    } elsif ($type eq 'NOTICE') {
        $self->message($args{message});
    } elsif ($type eq 'CLOSED') {
        $self->subscription_id($args{subscription_id});
        $self->message($args{message});
        $self->prefix(_extract_prefix($self->message));
    } else {
        croak "unknown message type: $type";
    }

    return $self;
}

sub serialize {
    my ($self) = @_;
    my $type = $self->type;

    if ($type eq 'EVENT') {
        if (defined $self->subscription_id) {
            return $JSON->encode(['EVENT', $self->subscription_id, $self->event->to_hash]);
        }
        return $JSON->encode(['EVENT', $self->event->to_hash]);
    } elsif ($type eq 'REQ') {
        return $JSON->encode(['REQ', $self->subscription_id, map { $_->to_hash } @{$self->filters}]);
    } elsif ($type eq 'CLOSE') {
        return $JSON->encode(['CLOSE', $self->subscription_id]);
    } elsif ($type eq 'OK') {
        return $JSON->encode(['OK', $self->event_id, $self->accepted ? JSON::true : JSON::false, $self->message]);
    } elsif ($type eq 'EOSE') {
        return $JSON->encode(['EOSE', $self->subscription_id]);
    } elsif ($type eq 'NOTICE') {
        return $JSON->encode(['NOTICE', $self->message]);
    } elsif ($type eq 'CLOSED') {
        return $JSON->encode(['CLOSED', $self->subscription_id, $self->message]);
    }
}

my %PARSERS = (
    EVENT => sub {
        my ($arr) = @_;
        # client-to-relay: ["EVENT", {event}]
        if (@$arr == 2 && ref($arr->[1]) eq 'HASH') {
            my $event_hash = $arr->[1];
            return (
                event => Net::Nostr::Event->new(%$event_hash, id => $event_hash->{id}),
            );
        }
        # relay-to-client: ["EVENT", sub_id, {event}]
        croak "EVENT message requires 2 or 3 elements\n" unless @$arr == 3;
        my $event_hash = $arr->[2];
        return (
            subscription_id => $arr->[1],
            event           => Net::Nostr::Event->new(%$event_hash, id => $event_hash->{id}),
        );
    },
    OK => sub {
        my ($arr) = @_;
        croak "OK message requires 4 elements\n" unless @$arr == 4;
        return (
            event_id => $arr->[1],
            accepted => $arr->[2] ? 1 : 0,
            message  => $arr->[3],
        );
    },
    EOSE => sub {
        my ($arr) = @_;
        croak "EOSE message requires 2 elements\n" unless @$arr == 2;
        return (
            subscription_id => $arr->[1],
        );
    },
    CLOSED => sub {
        my ($arr) = @_;
        croak "CLOSED message requires 3 elements\n" unless @$arr == 3;
        return (
            subscription_id => $arr->[1],
            message         => $arr->[2],
        );
    },
    NOTICE => sub {
        my ($arr) = @_;
        croak "NOTICE message requires 2 elements\n" unless @$arr == 2;
        return (
            message => $arr->[1],
        );
    },
    REQ => sub {
        my ($arr) = @_;
        croak "REQ message requires at least 3 elements\n" unless @$arr >= 3;
        my @filters;
        for my $i (2 .. $#$arr) {
            push @filters, Net::Nostr::Filter->new(%{$arr->[$i]});
        }
        return (
            subscription_id => $arr->[1],
            filters         => \@filters,
        );
    },
    CLOSE => sub {
        my ($arr) = @_;
        croak "CLOSE message requires 2 elements\n" unless @$arr == 2;
        return (
            subscription_id => $arr->[1],
        );
    },
);

sub parse {
    my ($class, $raw) = @_;
    my $arr = eval { $JSON->decode($raw) };
    croak "invalid JSON: $@\n" if $@;
    croak "message must be a JSON array\n" unless ref($arr) eq 'ARRAY';
    croak "message array must not be empty\n" unless @$arr;

    my $type = $arr->[0];
    croak "unknown message type: $type\n" unless $PARSERS{$type};

    my %fields = $PARSERS{$type}->($arr);
    return $class->new(type => $type, %fields);
}

1;
