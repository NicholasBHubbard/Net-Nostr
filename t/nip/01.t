#!/usr/bin/perl

# NIP-01: Basic protocol flow
# https://github.com/nostr-protocol/nips/blob/master/01.md

use strictures 2;

use Test2::V0 -no_srand => 1;
use JSON;
use Digest::SHA qw(sha256_hex);

use lib 't/lib';
use TestFixtures qw(%FIATJAF_EVENT);

use Net::Nostr;
use Net::Nostr::Key;
use Net::Nostr::Event;
use Net::Nostr::Filter;
use Net::Nostr::Message;

###############################################################################
# Events and signatures
###############################################################################

subtest 'event id is sha256 of canonical serialization' => sub {
    my $event = Net::Nostr::Event->new(%FIATJAF_EVENT);
    my $expected_serialization = JSON->new->utf8->encode([
        0,
        $FIATJAF_EVENT{pubkey},
        $FIATJAF_EVENT{created_at} + 0,
        $FIATJAF_EVENT{kind} + 0,
        $FIATJAF_EVENT{tags},
        $FIATJAF_EVENT{content}
    ]);
    is($event->id, sha256_hex($expected_serialization), 'event id matches sha256 of [0, pubkey, created_at, kind, tags, content]');
    is($event->id, $FIATJAF_EVENT{id}, 'event id matches known-good fiatjaf event');
};

subtest 'event serialization format' => sub {
    my $event = Net::Nostr::Event->new(%FIATJAF_EVENT);
    my $json = $event->json_serialize;
    my $decoded = JSON::decode_json($json);

    is(scalar @$decoded, 6, 'serialization has exactly 6 elements');
    is($decoded->[0], 0, 'first element is 0');
    is($decoded->[1], $FIATJAF_EVENT{pubkey}, 'second element is pubkey string');
    is($decoded->[2], $FIATJAF_EVENT{created_at}, 'third element is created_at number');
    is($decoded->[3], $FIATJAF_EVENT{kind}, 'fourth element is kind number');
    is($decoded->[4], $FIATJAF_EVENT{tags}, 'fifth element is tags array');
    is($decoded->[5], $FIATJAF_EVENT{content}, 'sixth element is content string');

    # UTF-8, no whitespace
    unlike($json, qr/\n/, 'no newlines in serialized output');
    unlike($json, qr/  /, 'no extra spaces in serialized output');
};

subtest 'serialization types are correct for JSON' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'abc123',
        created_at => 1000,
        kind => 1,
        tags => [],
        content => 'test',
        sig => ''
    );
    my $json = $event->json_serialize;

    # created_at and kind must be numbers, not strings
    like($json, qr/,1000,/, 'created_at serialized as number');
    like($json, qr/,1,/, 'kind serialized as number');

    # pubkey and content must be strings
    like($json, qr/"abc123"/, 'pubkey serialized as string');
    like($json, qr/"test"/, 'content serialized as string');
};

subtest 'event id changes when content changes' => sub {
    my $event1 = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1, content => 'hello',
        sig => '', created_at => 1000, tags => []
    );
    my $event2 = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1, content => 'world',
        sig => '', created_at => 1000, tags => []
    );
    isnt($event1->id, $event2->id, 'different content produces different id');
};

subtest 'event id changes when tags change' => sub {
    my $event1 = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1, content => 'test',
        sig => '', created_at => 1000, tags => []
    );
    my $event2 = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1, content => 'test',
        sig => '', created_at => 1000, tags => [['p', 'def']]
    );
    isnt($event1->id, $event2->id, 'different tags produces different id');
};

subtest 'event id is 32-byte lowercase hex (64 chars)' => sub {
    my $event = Net::Nostr::Event->new(%FIATJAF_EVENT);
    like($event->id, qr/^[0-9a-f]{64}$/, 'id is 64 lowercase hex chars');
};

subtest 'content special characters are escaped in serialization' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1,
        content => "line1\nline2\ttab\\backslash\"quote\r\x08\x0C",
        sig => '', created_at => 1000, tags => []
    );
    my $json = $event->json_serialize;

    like($json, qr/\\n/, 'newline (0x0A) escaped as \\n');
    like($json, qr/\\t/, 'tab (0x09) escaped as \\t');
    like($json, qr/\\\\/, 'backslash (0x5C) escaped as \\\\');
    like($json, qr/\\"/, 'double quote (0x22) escaped as \\"');
    like($json, qr/\\r/, 'carriage return (0x0D) escaped as \\r');
    like($json, qr/\\b/, 'backspace (0x08) escaped as \\b');
    like($json, qr/\\f/, 'form feed (0x0C) escaped as \\f');

    # round-trip preserves content
    my $decoded = JSON::decode_json($json);
    is($decoded->[5], $event->content, 'content round-trips through JSON');
};

subtest 'empty content serializes correctly' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1, content => '',
        sig => '', created_at => 1000, tags => []
    );
    my $json = $event->json_serialize;
    my $decoded = JSON::decode_json($json);
    is($decoded->[5], '', 'empty content preserved');
};

subtest 'unicode content serializes as UTF-8' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1, content => "\x{1F600}",
        sig => '', created_at => 1000, tags => []
    );
    my $json = $event->json_serialize;
    my $decoded = JSON::decode_json($json);
    is($decoded->[5], "\x{1F600}", 'unicode emoji round-trips through serialization');
};

###############################################################################
# Tags
###############################################################################

subtest 'tags are arrays of arrays' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1, content => 'test',
        sig => '', created_at => 1000,
        tags => [
            ['e', '5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36', 'wss://nostr.example.com'],
            ['p', 'f7234bd4c1394dda46d09f35bd384dd30cc552ad5541990f98844fb06676e9ca'],
            ['a', '30023:f7234bd4c1394dda46d09f35bd384dd30cc552ad5541990f98844fb06676e9ca:abcd', 'wss://nostr.example.com'],
            ['alt', 'reply']
        ]
    );
    my $json = $event->json_serialize;
    my $decoded = JSON::decode_json($json);
    my $tags = $decoded->[4];

    is(ref($tags), 'ARRAY', 'tags is an array');
    is(scalar @$tags, 4, 'four tags');

    # e tag: event reference with relay hint
    is($tags->[0][0], 'e', 'e tag name');
    is($tags->[0][1], '5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36', 'e tag value is event id');
    is($tags->[0][2], 'wss://nostr.example.com', 'e tag relay hint');

    # p tag: pubkey reference
    is($tags->[1][0], 'p', 'p tag name');
    is($tags->[1][1], 'f7234bd4c1394dda46d09f35bd384dd30cc552ad5541990f98844fb06676e9ca', 'p tag value is pubkey');

    # a tag: addressable event reference
    is($tags->[2][0], 'a', 'a tag name');
    is($tags->[2][1], '30023:f7234bd4c1394dda46d09f35bd384dd30cc552ad5541990f98844fb06676e9ca:abcd', 'a tag value is kind:pubkey:d');

    # arbitrary tag
    is($tags->[3][0], 'alt', 'arbitrary tag name');
    is($tags->[3][1], 'reply', 'arbitrary tag value');
};

subtest 'empty tags array serializes correctly' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1, content => 'test',
        sig => '', created_at => 1000, tags => []
    );
    my $json = $event->json_serialize;
    my $decoded = JSON::decode_json($json);
    is($decoded->[4], [], 'empty tags serializes as empty array');
};

subtest 'add_pubkey_ref appends p tag' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1, content => 'test',
        sig => '', created_at => 1000, tags => []
    );
    $event->add_pubkey_ref('deadbeef' x 8);
    is($event->tags, [['p', 'deadbeef' x 8]], 'p tag appended');
};

subtest 'add_event_ref appends e tag' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1, content => 'test',
        sig => '', created_at => 1000, tags => []
    );
    $event->add_event_ref('deadbeef' x 8);
    is($event->tags, [['e', 'deadbeef' x 8]], 'e tag appended');
};

subtest 'multiple tags accumulate correctly' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 1, content => 'test',
        sig => '', created_at => 1000, tags => []
    );
    $event->add_pubkey_ref('aaa');
    $event->add_event_ref('bbb');
    $event->add_pubkey_ref('ccc');
    is($event->tags, [['p', 'aaa'], ['e', 'bbb'], ['p', 'ccc']], 'tags accumulate in order');
};

###############################################################################
# Keys and identity
###############################################################################

subtest 'pubkey is 32-byte lowercase hex (64 chars)' => sub {
    my $key = Net::Nostr::Key->new;
    my $hex = $key->pubkey_hex;
    like($hex, qr/^[0-9a-f]{64}$/, 'pubkey_hex is 64 lowercase hex chars');
};

subtest 'privkey is 32-byte hex (64 chars)' => sub {
    my $key = Net::Nostr::Key->new;
    my $hex = $key->privkey_hex;
    like($hex, qr/^[0-9a-f]{64}$/, 'privkey_hex is 64 lowercase hex chars');
};

subtest 'signatures use schnorr over secp256k1' => sub {
    my $key = Net::Nostr::Key->new;
    my $msg = 'test message';
    my $sig = $key->schnorr_sign($msg);
    ok(defined $sig, 'schnorr_sign returns a signature');
    is(length($sig), 64, 'signature is 64 bytes (BIP-340)');

    my $verifier = Crypt::PK::ECC::Schnorr->new(\$key->pubkey_der);
    ok($verifier->verify_message($msg, $sig), 'signature verifies with public key');
};

subtest 'signature does not verify with wrong key' => sub {
    my $key1 = Net::Nostr::Key->new;
    my $key2 = Net::Nostr::Key->new;
    my $sig = $key1->schnorr_sign('test');
    my $verifier = Crypt::PK::ECC::Schnorr->new(\$key2->pubkey_der);
    ok(!$verifier->verify_message('test', $sig), 'signature fails with wrong public key');
};

subtest 'signature does not verify with wrong message' => sub {
    my $key = Net::Nostr::Key->new;
    my $sig = $key->schnorr_sign('correct message');
    my $verifier = Crypt::PK::ECC::Schnorr->new(\$key->pubkey_der);
    ok(!$verifier->verify_message('wrong message', $sig), 'signature fails with wrong message');
};

###############################################################################
# Event signing (Net::Nostr facade)
###############################################################################

subtest 'sign_event produces valid schnorr signature over event id' => sub {
    my $nostr = Net::Nostr->new;
    my $event = Net::Nostr::Event->new(
        pubkey => $nostr->key->pubkey_hex,
        kind => 1,
        content => 'hello nostr',
        tags => []
    );

    my $sig = $nostr->sign_event($event);
    ok($sig, 'sign_event returns a signature');
    is($event->sig, $sig, 'signature is set on the event');

    # sig on wire is 128-char lowercase hex (64 bytes)
    like($sig, qr/^[0-9a-f]{128}$/, 'signature is 128-char lowercase hex');

    # verify via Event method
    ok($event->verify_sig($nostr->key), 'signature verifies via verify_sig');
};

subtest 'signed event has all required fields' => sub {
    my $nostr = Net::Nostr->new;
    my $event = Net::Nostr::Event->new(
        pubkey => $nostr->key->pubkey_hex,
        kind => 1,
        content => 'test',
        tags => []
    );
    $nostr->sign_event($event);

    ok(defined $event->id, 'event has id');
    ok(defined $event->pubkey, 'event has pubkey');
    ok(defined $event->created_at, 'event has created_at');
    ok(defined $event->kind, 'event has kind');
    ok(defined $event->tags, 'event has tags');
    ok(defined $event->content, 'event has content');
    ok(defined $event->sig, 'event has sig');

    like($event->id, qr/^[0-9a-f]{64}$/, 'id is 32-byte hex');
    like($event->pubkey, qr/^[0-9a-f]{64}$/, 'pubkey is 32-byte hex');
    ok($event->created_at > 0, 'created_at is positive integer');
    ok($event->kind >= 0 && $event->kind <= 65535, 'kind is in valid range');
    is(ref($event->tags), 'ARRAY', 'tags is an array');
};

###############################################################################
# Kind ranges
###############################################################################

subtest 'kind 0 is user metadata (replaceable)' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'abc', kind => 0,
        content => '{"name":"alice","about":"hi","picture":"https://example.com/pic.jpg"}',
        sig => '', created_at => 1000, tags => []
    );
    is($event->kind, 0, 'kind 0 event created');
    my $decoded_content = JSON::decode_json($event->content);
    ok(exists $decoded_content->{name}, 'metadata has name field');
};

###############################################################################
# Client-to-relay messages
###############################################################################

subtest 'EVENT message format' => sub {
    my $event = Net::Nostr::Event->new(%FIATJAF_EVENT);
    my $json = Net::Nostr::Message::event_msg($event);
    my $decoded = JSON::decode_json($json);
    is($decoded->[0], 'EVENT', 'first element is EVENT');
    is(ref($decoded->[1]), 'HASH', 'second element is event object');
    is($decoded->[1]{id}, $FIATJAF_EVENT{id}, 'event id present');
    is(scalar @$decoded, 2, 'client EVENT has 2 elements');
};

subtest 'REQ message format' => sub {
    my $filter = Net::Nostr::Filter->new(
        kinds => [1],
        authors => ['3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d'],
        limit => 10
    );
    my $json = Net::Nostr::Message::req_msg('sub1', $filter);
    my $decoded = JSON::decode_json($json);
    is($decoded->[0], 'REQ', 'first element is REQ');
    is($decoded->[1], 'sub1', 'second element is subscription id');
    is(ref($decoded->[2]), 'HASH', 'third element is filter object');
    is($decoded->[2]{kinds}, [1], 'filter kinds');
    is($decoded->[2]{limit}, 10, 'filter limit');
};

subtest 'CLOSE message format' => sub {
    my $json = Net::Nostr::Message::close_msg('sub1');
    my $decoded = JSON::decode_json($json);
    is($decoded->[0], 'CLOSE', 'first element is CLOSE');
    is($decoded->[1], 'sub1', 'second element is subscription id');
    is(scalar @$decoded, 2, 'CLOSE has exactly 2 elements');
};

###############################################################################
# Relay-to-client messages
###############################################################################

subtest 'relay EVENT message format' => sub {
    my $event = Net::Nostr::Event->new(%FIATJAF_EVENT);
    my $raw = JSON->new->utf8->encode(['EVENT', 'sub1', $event->to_hash]);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{type}, 'EVENT', 'type is EVENT');
    is($msg->{subscription_id}, 'sub1', 'subscription id');
    is(ref($msg->{event}), 'Net::Nostr::Event', 'event is a Net::Nostr::Event');
    is($msg->{event}->id, $FIATJAF_EVENT{id}, 'event id preserved');
};

subtest 'OK message format' => sub {
    my $eid = 'b1a649ebe8' . ('0' x 54);
    my @cases = (
        [JSON::true,  '',                                          1, undef],
        [JSON::true,  'duplicate: already have this event',        1, 'duplicate'],
        [JSON::false, 'blocked: you are banned from posting here', 0, 'blocked'],
        [JSON::false, 'rate-limited: slow down there chief',       0, 'rate-limited'],
        [JSON::false, 'invalid: event creation date is too far off', 0, 'invalid'],
        [JSON::false, 'error: could not connect to the database',  0, 'error'],
    );
    for my $case (@cases) {
        my $raw = JSON->new->utf8->encode(['OK', $eid, $case->[0], $case->[1]]);
        my $msg = Net::Nostr::Message::parse($raw);
        is($msg->{type}, 'OK', 'type is OK');
        is($msg->{event_id}, $eid, 'event_id');
        is($msg->{accepted}, $case->[2], 'accepted flag');
        is($msg->{prefix}, $case->[3], 'prefix extracted');
    }
};

subtest 'OK message prefixes are standardized' => sub {
    my $eid = 'aa' x 32;
    my @prefixes = qw(duplicate pow blocked rate-limited invalid restricted mute error);
    for my $prefix (@prefixes) {
        my $raw = JSON->new->utf8->encode(['OK', $eid, JSON::false, "$prefix: details"]);
        my $msg = Net::Nostr::Message::parse($raw);
        is($msg->{prefix}, $prefix, "prefix '$prefix' extracted");
    }
};

subtest 'EOSE message format' => sub {
    my $raw = JSON->new->utf8->encode(['EOSE', 'sub1']);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{type}, 'EOSE', 'type is EOSE');
    is($msg->{subscription_id}, 'sub1', 'subscription id');
};

subtest 'CLOSED message format' => sub {
    my $raw = JSON->new->utf8->encode(['CLOSED', 'sub1', 'error: shutting down idle subscription']);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{type}, 'CLOSED', 'type is CLOSED');
    is($msg->{subscription_id}, 'sub1', 'subscription id');
    is($msg->{message}, 'error: shutting down idle subscription', 'full message');
    is($msg->{prefix}, 'error', 'prefix extracted');
};

subtest 'NOTICE message format' => sub {
    my $raw = JSON->new->utf8->encode(['NOTICE', 'this is a notice']);
    my $msg = Net::Nostr::Message::parse($raw);
    is($msg->{type}, 'NOTICE', 'type is NOTICE');
    is($msg->{message}, 'this is a notice', 'message preserved');
};

###############################################################################
# Filters
###############################################################################

subtest 'filter with all fields' => sub {
    my $filter = Net::Nostr::Filter->new(
        ids => ['aaa' . ('0' x 61)],
        authors => ['bbb' . ('0' x 61)],
        kinds => [1, 2],
        '#e' => ['ccc' . ('0' x 61)],
        '#p' => ['ddd' . ('0' x 61)],
        since => 1673361254,
        until => 1673361999,
        limit => 100
    );
    my $h = $filter->to_hash;

    is(ref($h->{ids}), 'ARRAY', 'ids is array');
    is(ref($h->{authors}), 'ARRAY', 'authors is array');
    is(ref($h->{kinds}), 'ARRAY', 'kinds is array');
    is(ref($h->{'#e'}), 'ARRAY', '#e is array');
    is(ref($h->{'#p'}), 'ARRAY', '#p is array');
    is($h->{since}, 1673361254, 'since preserved');
    is($h->{until}, 1673361999, 'until preserved');
    is($h->{limit}, 100, 'limit preserved');
};

subtest 'filter ids and authors must be 64-char lowercase hex' => sub {
    ok(lives { Net::Nostr::Filter->new(ids => ['a' x 64]) }, 'valid 64-char hex id accepted');
    ok(lives { Net::Nostr::Filter->new(authors => ['b' x 64]) }, 'valid 64-char hex author accepted');
    ok(dies { Net::Nostr::Filter->new(ids => ['short']) }, 'short id rejected');
    ok(dies { Net::Nostr::Filter->new(authors => ['ABCD' x 16]) }, 'uppercase hex author rejected');
    ok(dies { Net::Nostr::Filter->new('#e' => ['xyz']) }, 'invalid #e value rejected');
    ok(dies { Net::Nostr::Filter->new('#p' => ['xyz']) }, 'invalid #p value rejected');
};

subtest 'subscription_id constraints' => sub {
    my $f = Net::Nostr::Filter->new(kinds => [1]);
    ok(lives { Net::Nostr::Message::req_msg('my-subscription-1', $f) }, 'normal sub id accepted');
    ok(lives { Net::Nostr::Message::req_msg('x' x 64, $f) }, 'max length sub id accepted');
    ok(lives { Net::Nostr::Message::req_msg('a', $f) }, 'single char sub id accepted');
    ok(dies { Net::Nostr::Message::req_msg('', $f) }, 'empty sub id rejected');
    ok(dies { Net::Nostr::Message::req_msg('x' x 65, $f) }, 'sub id > 64 chars rejected');
};

subtest 'multiple filters in REQ are OR conditions' => sub {
    my $f1 = Net::Nostr::Filter->new(kinds => [1], limit => 10);
    my $f2 = Net::Nostr::Filter->new(kinds => [0], authors => ['a' x 64]);
    my $json = Net::Nostr::Message::req_msg('sub1', $f1, $f2);
    my $decoded = JSON::decode_json($json);
    is($decoded->[0], 'REQ', 'REQ message');
    is($decoded->[1], 'sub1', 'subscription id');
    is($decoded->[2]{kinds}, [1], 'first filter kinds');
    is($decoded->[3]{kinds}, [0], 'second filter kinds');
    is(scalar @$decoded, 4, 'two filters = 4 elements');

    # matches_any: event matching either filter passes
    my $event = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 0, content => '', sig => '',
        created_at => 1000, tags => []
    );
    ok(Net::Nostr::Filter::matches_any($event, $f1, $f2), 'event matching second filter passes matches_any');
};

###############################################################################
# Kind classification
###############################################################################

subtest 'kind range classification' => sub {
    my $make = sub {
        Net::Nostr::Event->new(
            pubkey => 'a', kind => $_[0], content => '', sig => '',
            created_at => 1, tags => []
        );
    };

    for my $k (1, 2, 4, 44, 1000, 9999) {
        my $e = $make->($k);
        ok($e->is_regular, "kind $k is regular");
        ok(!$e->is_replaceable, "kind $k is not replaceable");
        ok(!$e->is_ephemeral, "kind $k is not ephemeral");
        ok(!$e->is_addressable, "kind $k is not addressable");
    }

    for my $k (0, 3, 10000, 19999) {
        my $e = $make->($k);
        ok($e->is_replaceable, "kind $k is replaceable");
        ok(!$e->is_regular, "kind $k is not regular");
    }

    for my $k (20000, 25000, 29999) {
        my $e = $make->($k);
        ok($e->is_ephemeral, "kind $k is ephemeral");
        ok(!$e->is_regular, "kind $k is not regular");
    }

    for my $k (30000, 35000, 39999) {
        my $e = $make->($k);
        ok($e->is_addressable, "kind $k is addressable");
        ok(!$e->is_regular, "kind $k is not regular");
    }
};

done_testing;
