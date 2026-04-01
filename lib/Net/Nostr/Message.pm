package Net::Nostr::Message;

use strictures 2;

use Carp qw(croak);
use JSON;
use Net::Nostr::Event;

my $JSON = JSON->new->utf8;

my %RELAY_TYPES = map { $_ => 1 } qw(EVENT OK EOSE CLOSED NOTICE);
use Net::Nostr::Filter;

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

# Client-to-relay messages

sub event_msg {
    my ($event) = @_;
    return $JSON->encode(['EVENT', $event->to_hash]);
}

sub req_msg {
    my ($sub_id, @filters) = @_;
    _validate_subscription_id($sub_id);
    croak "req_msg requires at least one filter" unless @filters;
    return $JSON->encode(['REQ', $sub_id, map { $_->to_hash } @filters]);
}

sub close_msg {
    my ($sub_id) = @_;
    _validate_subscription_id($sub_id);
    return $JSON->encode(['CLOSE', $sub_id]);
}

# Relay-to-client messages

sub ok_msg {
    my ($event_id, $accepted, $message) = @_;
    $message //= '';
    return $JSON->encode(['OK', $event_id, $accepted ? JSON::true : JSON::false, $message]);
}

sub relay_event_msg {
    my ($sub_id, $event) = @_;
    return $JSON->encode(['EVENT', $sub_id, $event->to_hash]);
}

sub eose_msg {
    my ($sub_id) = @_;
    return $JSON->encode(['EOSE', $sub_id]);
}

sub notice_msg {
    my ($message) = @_;
    return $JSON->encode(['NOTICE', $message]);
}

sub closed_msg {
    my ($sub_id, $message) = @_;
    return $JSON->encode(['CLOSED', $sub_id, $message]);
}

# Relay-to-client message parsing

my %PARSERS = (
    EVENT => sub {
        my ($arr) = @_;
        # client-to-relay: ["EVENT", {event}]
        if (@$arr == 2 && ref($arr->[1]) eq 'HASH') {
            my $event_hash = $arr->[1];
            my $event = Net::Nostr::Event->new(%$event_hash, id => $event_hash->{id});
            return {
                type  => 'EVENT',
                event => $event,
            };
        }
        # relay-to-client: ["EVENT", sub_id, {event}]
        die "EVENT message requires 2 or 3 elements\n" unless @$arr == 3;
        my $event_hash = $arr->[2];
        my $event = Net::Nostr::Event->new(%$event_hash, id => $event_hash->{id});
        return {
            type            => 'EVENT',
            subscription_id => $arr->[1],
            event           => $event,
        };
    },
    OK => sub {
        my ($arr) = @_;
        die "OK message requires 4 elements\n" unless @$arr == 4;
        return {
            type     => 'OK',
            event_id => $arr->[1],
            accepted => $arr->[2] ? 1 : 0,
            message  => $arr->[3],
            prefix   => _extract_prefix($arr->[3]),
        };
    },
    EOSE => sub {
        my ($arr) = @_;
        die "EOSE message requires 2 elements\n" unless @$arr == 2;
        return {
            type            => 'EOSE',
            subscription_id => $arr->[1],
        };
    },
    CLOSED => sub {
        my ($arr) = @_;
        die "CLOSED message requires 3 elements\n" unless @$arr == 3;
        return {
            type            => 'CLOSED',
            subscription_id => $arr->[1],
            message         => $arr->[2],
            prefix          => _extract_prefix($arr->[2]),
        };
    },
    NOTICE => sub {
        my ($arr) = @_;
        die "NOTICE message requires 2 elements\n" unless @$arr == 2;
        return {
            type    => 'NOTICE',
            message => $arr->[1],
        };
    },
    REQ => sub {
        my ($arr) = @_;
        die "REQ message requires at least 3 elements\n" unless @$arr >= 3;
        my $sub_id = $arr->[1];
        my @filters;
        for my $i (2 .. $#$arr) {
            push @filters, Net::Nostr::Filter->new(%{$arr->[$i]});
        }
        return {
            type            => 'REQ',
            subscription_id => $sub_id,
            filters         => \@filters,
        };
    },
    CLOSE => sub {
        my ($arr) = @_;
        die "CLOSE message requires 2 elements\n" unless @$arr == 2;
        return {
            type            => 'CLOSE',
            subscription_id => $arr->[1],
        };
    },
);

sub parse {
    my ($raw) = @_;
    my $arr = eval { $JSON->decode($raw) };
    die "invalid JSON: $@\n" if $@;
    die "message must be a JSON array\n" unless ref($arr) eq 'ARRAY';
    die "message array must not be empty\n" unless @$arr;

    my $type = $arr->[0];
    die "unknown message type: $type\n" unless $PARSERS{$type};

    return $PARSERS{$type}->($arr);
}

1;
