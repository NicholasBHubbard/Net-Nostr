package Net::Nostr::Message;

use strictures 2;

use JSON;
use Net::Nostr::Event;

my $JSON = JSON->new->utf8;

my %RELAY_TYPES = map { $_ => 1 } qw(EVENT OK EOSE CLOSED NOTICE);

sub _validate_subscription_id {
    my ($sub_id) = @_;
    die "subscription_id must be a non-empty string\n"
        unless defined $sub_id && length($sub_id) > 0;
    die "subscription_id must be at most 64 characters\n"
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
    die "req_msg requires at least one filter\n" unless @filters;
    return $JSON->encode(['REQ', $sub_id, map { $_->to_hash } @filters]);
}

sub close_msg {
    my ($sub_id) = @_;
    _validate_subscription_id($sub_id);
    return $JSON->encode(['CLOSE', $sub_id]);
}

# Relay-to-client message parsing

my %PARSERS = (
    EVENT => sub {
        my ($arr) = @_;
        die "EVENT message requires 3 elements\n" unless @$arr == 3;
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
