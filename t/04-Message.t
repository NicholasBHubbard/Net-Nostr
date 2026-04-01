#!/usr/bin/perl

use strictures 2;

use Test2::V0 -no_srand => 1;
use JSON;

use lib 't/lib';
use TestFixtures qw(%FIATJAF_EVENT);

use Net::Nostr::Event;
use Net::Nostr::Filter;
use Net::Nostr::Message;

my $EVENT = Net::Nostr::Event->new(%FIATJAF_EVENT);

###############################################################################
# Client-to-relay: EVENT
###############################################################################

subtest 'event_msg() produces ["EVENT", <event hash>]' => sub {
    my $json = Net::Nostr::Message::event_msg($EVENT);
    my $decoded = JSON::decode_json($json);
    is($decoded->[0], 'EVENT', 'first element is EVENT');
    is(ref($decoded->[1]), 'HASH', 'second element is event object');
    is($decoded->[1]{id}, $EVENT->id, 'event id');
    is($decoded->[1]{pubkey}, $EVENT->pubkey, 'event pubkey');
    is($decoded->[1]{created_at}, $EVENT->created_at, 'event created_at');
    is($decoded->[1]{kind}, $EVENT->kind, 'event kind');
    is($decoded->[1]{tags}, $EVENT->tags, 'event tags');
    is($decoded->[1]{content}, $EVENT->content, 'event content');
    is($decoded->[1]{sig}, $EVENT->sig, 'event sig');
    is(scalar keys %{$decoded->[1]}, 7, 'event has exactly 7 fields');
    is(scalar @$decoded, 2, 'message has exactly 2 elements');
};

###############################################################################
# Client-to-relay: REQ
###############################################################################

subtest 'req_msg() with one filter' => sub {
    my $filter = Net::Nostr::Filter->new(kinds => [1], limit => 10);
    my $json = Net::Nostr::Message::req_msg('sub1', $filter);
    my $decoded = JSON::decode_json($json);
    is($decoded->[0], 'REQ', 'first element is REQ');
    is($decoded->[1], 'sub1', 'subscription id');
    is(ref($decoded->[2]), 'HASH', 'third element is filter');
    is($decoded->[2]{kinds}, [1], 'filter kinds');
    is($decoded->[2]{limit}, 10, 'filter limit');
    is(scalar @$decoded, 3, 'message has 3 elements');
};

subtest 'req_msg() with multiple filters' => sub {
    my $f1 = Net::Nostr::Filter->new(kinds => [1]);
    my $f2 = Net::Nostr::Filter->new(kinds => [0], authors => ['aa' x 32]);
    my $json = Net::Nostr::Message::req_msg('sub2', $f1, $f2);
    my $decoded = JSON::decode_json($json);
    is($decoded->[0], 'REQ', 'first element is REQ');
    is($decoded->[1], 'sub2', 'subscription id');
    is($decoded->[2]{kinds}, [1], 'first filter');
    is($decoded->[3]{kinds}, [0], 'second filter');
    is($decoded->[3]{authors}, ['aa' x 32], 'second filter authors');
    is(scalar @$decoded, 4, 'message has 4 elements');
};

subtest 'req_msg() with filter containing tag filters' => sub {
    my $f = Net::Nostr::Filter->new('#e' => ['aa' x 32], kinds => [1]);
    my $json = Net::Nostr::Message::req_msg('sub3', $f);
    my $decoded = JSON::decode_json($json);
    is($decoded->[2]{'#e'}, ['aa' x 32], 'tag filter in message');
};

subtest 'req_msg() validates subscription_id' => sub {
    my $f = Net::Nostr::Filter->new(kinds => [1]);
    ok(dies { Net::Nostr::Message::req_msg('', $f) }, 'empty subscription id rejected');
    ok(dies { Net::Nostr::Message::req_msg('x' x 65, $f) }, 'subscription id > 64 chars rejected');
    ok(lives { Net::Nostr::Message::req_msg('x' x 64, $f) }, 'subscription id of 64 chars accepted');
    ok(lives { Net::Nostr::Message::req_msg('a', $f) }, 'single char subscription id accepted');
};

subtest 'req_msg() requires at least one filter' => sub {
    ok(dies { Net::Nostr::Message::req_msg('sub1') }, 'no filters rejected');
};

###############################################################################
# Client-to-relay: CLOSE
###############################################################################

subtest 'close_msg() produces ["CLOSE", <subscription_id>]' => sub {
    my $json = Net::Nostr::Message::close_msg('sub1');
    my $decoded = JSON::decode_json($json);
    is($decoded->[0], 'CLOSE', 'first element is CLOSE');
    is($decoded->[1], 'sub1', 'subscription id');
    is(scalar @$decoded, 2, 'message has exactly 2 elements');
};

subtest 'close_msg() validates subscription_id' => sub {
    ok(dies { Net::Nostr::Message::close_msg('') }, 'empty subscription id rejected');
    ok(dies { Net::Nostr::Message::close_msg('x' x 65) }, 'subscription id > 64 chars rejected');
    ok(lives { Net::Nostr::Message::close_msg('x' x 64) }, 'subscription id of 64 chars accepted');
};

###############################################################################
# Parsing relay messages
###############################################################################

subtest 'parse() relay EVENT message' => sub {
    my $raw = JSON->new->utf8->encode(['EVENT', 'sub1', $EVENT->to_hash]);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{type}, 'EVENT', 'type is EVENT');
    is($msg->{subscription_id}, 'sub1', 'subscription id');
    is(ref($msg->{event}), 'Net::Nostr::Event', 'event is a Net::Nostr::Event');
    is($msg->{event}->id, $EVENT->id, 'event id preserved');
    is($msg->{event}->pubkey, $EVENT->pubkey, 'event pubkey preserved');
    is($msg->{event}->created_at, $EVENT->created_at, 'event created_at preserved');
    is($msg->{event}->kind, $EVENT->kind, 'event kind preserved');
    is($msg->{event}->tags, $EVENT->tags, 'event tags preserved');
    is($msg->{event}->content, $EVENT->content, 'event content preserved');
    is($msg->{event}->sig, $EVENT->sig, 'event sig preserved');
};

subtest 'parse() OK message (accepted)' => sub {
    my $raw = JSON->new->utf8->encode(['OK', 'aa' x 32, JSON::true, '']);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{type}, 'OK', 'type is OK');
    is($msg->{event_id}, 'aa' x 32, 'event id');
    is($msg->{accepted}, 1, 'accepted is true');
    is($msg->{message}, '', 'message is empty string');
};

subtest 'parse() OK message (rejected with prefix)' => sub {
    my $raw = JSON->new->utf8->encode([
        'OK', 'bb' x 32, JSON::false, 'blocked: you are banned'
    ]);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{type}, 'OK', 'type is OK');
    is($msg->{event_id}, 'bb' x 32, 'event id');
    is($msg->{accepted}, 0, 'accepted is false');
    is($msg->{message}, 'blocked: you are banned', 'full message');
    is($msg->{prefix}, 'blocked', 'machine-readable prefix extracted');
};

subtest 'parse() OK message prefix extraction' => sub {
    my @prefixes = qw(duplicate pow blocked rate-limited invalid restricted mute error);
    for my $prefix (@prefixes) {
        my $raw = JSON->new->utf8->encode([
            'OK', 'cc' x 32, JSON::false, "$prefix: details"
        ]);
        my $msg = Net::Nostr::Message::parse($raw);
        is($msg->{prefix}, $prefix, "prefix '$prefix' extracted");
    }
};

subtest 'parse() OK accepted with message' => sub {
    my $raw = JSON->new->utf8->encode([
        'OK', 'aa' x 32, JSON::true, 'duplicate: already have this event'
    ]);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{accepted}, 1, 'accepted is true');
    is($msg->{prefix}, 'duplicate', 'prefix extracted even when accepted');
    is($msg->{message}, 'duplicate: already have this event', 'full message preserved');
};

subtest 'parse() EOSE message' => sub {
    my $raw = JSON->new->utf8->encode(['EOSE', 'sub1']);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{type}, 'EOSE', 'type is EOSE');
    is($msg->{subscription_id}, 'sub1', 'subscription id');
};

subtest 'parse() CLOSED message' => sub {
    my $raw = JSON->new->utf8->encode([
        'CLOSED', 'sub1', 'error: shutting down idle subscription'
    ]);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{type}, 'CLOSED', 'type is CLOSED');
    is($msg->{subscription_id}, 'sub1', 'subscription id');
    is($msg->{message}, 'error: shutting down idle subscription', 'full message');
    is($msg->{prefix}, 'error', 'machine-readable prefix extracted');
};

subtest 'parse() CLOSED message with all standard prefixes' => sub {
    my @prefixes = qw(duplicate pow blocked rate-limited invalid restricted mute error);
    for my $prefix (@prefixes) {
        my $raw = JSON->new->utf8->encode([
            'CLOSED', 'sub1', "$prefix: details"
        ]);
        my $msg = Net::Nostr::Message::parse($raw);
        is($msg->{prefix}, $prefix, "CLOSED prefix '$prefix' extracted");
    }
};

subtest 'parse() NOTICE message' => sub {
    my $raw = JSON->new->utf8->encode(['NOTICE', 'this is a human-readable notice']);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{type}, 'NOTICE', 'type is NOTICE');
    is($msg->{message}, 'this is a human-readable notice', 'message');
};

###############################################################################
# parse() error handling
###############################################################################

subtest 'parse() rejects invalid JSON' => sub {
    ok(dies { Net::Nostr::Message::parse('not json') }, 'invalid JSON rejected');
};

subtest 'parse() rejects non-array JSON' => sub {
    ok(dies { Net::Nostr::Message::parse('{"type":"EVENT"}') }, 'JSON object rejected');
};

subtest 'parse() rejects empty array' => sub {
    ok(dies { Net::Nostr::Message::parse('[]') }, 'empty array rejected');
};

subtest 'parse() rejects unknown message type' => sub {
    my $raw = JSON->new->utf8->encode(['UNKNOWN', 'data']);
    ok(dies { Net::Nostr::Message::parse($raw) }, 'unknown type rejected');
};

###############################################################################
# parse() validates structure of each message type
###############################################################################

subtest 'parse() EVENT requires 3 elements' => sub {
    my $raw = JSON->new->utf8->encode(['EVENT', 'sub1']);
    ok(dies { Net::Nostr::Message::parse($raw) }, 'EVENT with 2 elements rejected');
};

subtest 'parse() OK requires 4 elements' => sub {
    my $raw = JSON->new->utf8->encode(['OK', 'aa' x 32, JSON::true]);
    ok(dies { Net::Nostr::Message::parse($raw) }, 'OK with 3 elements rejected');
};

subtest 'parse() EOSE requires 2 elements' => sub {
    my $raw = JSON->new->utf8->encode(['EOSE']);
    ok(dies { Net::Nostr::Message::parse($raw) }, 'EOSE with 1 element rejected');
};

subtest 'parse() CLOSED requires 3 elements' => sub {
    my $raw = JSON->new->utf8->encode(['CLOSED', 'sub1']);
    ok(dies { Net::Nostr::Message::parse($raw) }, 'CLOSED with 2 elements rejected');
};

subtest 'parse() NOTICE requires 2 elements' => sub {
    my $raw = JSON->new->utf8->encode(['NOTICE']);
    ok(dies { Net::Nostr::Message::parse($raw) }, 'NOTICE with 1 element rejected');
};

###############################################################################
# Round-trip: construct then parse
###############################################################################

subtest 'event_msg round-trips through parse as client EVENT' => sub {
    # Client EVENT is ["EVENT", <event>] — parse handles relay EVENT ["EVENT", <sub>, <event>]
    # so this tests construction format, not parse round-trip
    my $json = Net::Nostr::Message::event_msg($EVENT);
    my $decoded = JSON::decode_json($json);
    is($decoded->[0], 'EVENT', 'client EVENT constructed');
    is(scalar @$decoded, 2, 'client EVENT has 2 elements (no subscription_id)');
};

subtest 'parse preserves event id (not recalculated)' => sub {
    my $raw = JSON->new->utf8->encode(['EVENT', 'sub1', $EVENT->to_hash]);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{event}->id, $FIATJAF_EVENT{id}, 'known-good event id preserved by parse');
};

done_testing;
