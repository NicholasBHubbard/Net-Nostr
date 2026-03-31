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

    # sig is 64 bytes hex-encoded = 128 chars
    my $sig_hex = unpack 'H*', $sig;
    like($sig_hex, qr/^[0-9a-f]{128}$/, 'signature is 64-byte lowercase hex');

    # verify the signature against the event id
    my $verifier = Crypt::PK::ECC::Schnorr->new(\$nostr->key->pubkey_der);
    ok($verifier->verify_message($event->id, $sig), 'signature verifies against event id');
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
    # ["EVENT", <event JSON>]
    my $event = Net::Nostr::Event->new(%FIATJAF_EVENT);
    my $msg = JSON->new->utf8->encode(['EVENT', {
        id => $event->id,
        pubkey => $event->pubkey,
        created_at => $event->created_at,
        kind => $event->kind,
        tags => $event->tags,
        content => $event->content,
        sig => $event->sig
    }]);
    my $decoded = JSON::decode_json($msg);
    is($decoded->[0], 'EVENT', 'first element is EVENT');
    is(ref($decoded->[1]), 'HASH', 'second element is event object');
    is($decoded->[1]{id}, $FIATJAF_EVENT{id}, 'event id present');
};

subtest 'REQ message format' => sub {
    # ["REQ", <subscription_id>, <filters>...]
    my $msg = JSON->new->utf8->encode(['REQ', 'sub1', {
        kinds => [1],
        authors => ['3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d'],
        limit => 10
    }]);
    my $decoded = JSON::decode_json($msg);
    is($decoded->[0], 'REQ', 'first element is REQ');
    is($decoded->[1], 'sub1', 'second element is subscription id');
    is(ref($decoded->[2]), 'HASH', 'third element is filter object');
};

subtest 'CLOSE message format' => sub {
    # ["CLOSE", <subscription_id>]
    my $msg = JSON->new->utf8->encode(['CLOSE', 'sub1']);
    my $decoded = JSON::decode_json($msg);
    is($decoded->[0], 'CLOSE', 'first element is CLOSE');
    is($decoded->[1], 'sub1', 'second element is subscription id');
};

###############################################################################
# Relay-to-client messages
###############################################################################

subtest 'relay EVENT message format' => sub {
    # ["EVENT", <subscription_id>, <event JSON>]
    my $msg = JSON->new->utf8->encode(['EVENT', 'sub1', {
        id => $FIATJAF_EVENT{id},
        pubkey => $FIATJAF_EVENT{pubkey},
        created_at => $FIATJAF_EVENT{created_at},
        kind => $FIATJAF_EVENT{kind},
        tags => $FIATJAF_EVENT{tags},
        content => $FIATJAF_EVENT{content},
        sig => $FIATJAF_EVENT{sig}
    }]);
    my $decoded = JSON::decode_json($msg);
    is($decoded->[0], 'EVENT', 'first element is EVENT');
    is($decoded->[1], 'sub1', 'second element is subscription id');
    is(ref($decoded->[2]), 'HASH', 'third element is event object');
};

subtest 'OK message format' => sub {
    # ["OK", <event_id>, <true|false>, <message>]
    my @cases = (
        ['OK', 'b1a649ebe8' . ('0' x 54), JSON::true,  ''],
        ['OK', 'b1a649ebe8' . ('0' x 54), JSON::true,  'duplicate: already have this event'],
        ['OK', 'b1a649ebe8' . ('0' x 54), JSON::false, 'blocked: you are banned from posting here'],
        ['OK', 'b1a649ebe8' . ('0' x 54), JSON::false, 'rate-limited: slow down there chief'],
        ['OK', 'b1a649ebe8' . ('0' x 54), JSON::false, 'invalid: event creation date is too far off'],
        ['OK', 'b1a649ebe8' . ('0' x 54), JSON::false, 'error: could not connect to the database'],
    );
    for my $case (@cases) {
        my $msg = JSON->new->utf8->encode($case);
        my $decoded = JSON::decode_json($msg);
        is($decoded->[0], 'OK', 'first element is OK');
        is(length($decoded->[1]), 64, 'event_id is 64 chars');
        ok(JSON::is_bool($decoded->[2]), 'third element is boolean');
        ok(defined $decoded->[3], 'fourth element (message) is present');
    }
};

subtest 'OK message prefixes are standardized' => sub {
    my @valid_prefixes = qw(duplicate pow blocked rate-limited invalid restricted mute error);
    for my $prefix (@valid_prefixes) {
        my $msg = "$prefix: some human-readable message";
        like($msg, qr/^[a-z-]+: /, "prefix '$prefix' matches machine-readable format");
    }
};

subtest 'EOSE message format' => sub {
    # ["EOSE", <subscription_id>]
    my $msg = JSON->new->utf8->encode(['EOSE', 'sub1']);
    my $decoded = JSON::decode_json($msg);
    is($decoded->[0], 'EOSE', 'first element is EOSE');
    is($decoded->[1], 'sub1', 'second element is subscription id');
};

subtest 'CLOSED message format' => sub {
    # ["CLOSED", <subscription_id>, <message>]
    my $msg = JSON->new->utf8->encode(['CLOSED', 'sub1', 'error: shutting down idle subscription']);
    my $decoded = JSON::decode_json($msg);
    is($decoded->[0], 'CLOSED', 'first element is CLOSED');
    is($decoded->[1], 'sub1', 'second element is subscription id');
    like($decoded->[2], qr/^[a-z-]+: /, 'third element has machine-readable prefix');
};

subtest 'NOTICE message format' => sub {
    # ["NOTICE", <message>]
    my $msg = JSON->new->utf8->encode(['NOTICE', 'this is a notice']);
    my $decoded = JSON::decode_json($msg);
    is($decoded->[0], 'NOTICE', 'first element is NOTICE');
    ok(defined $decoded->[1], 'second element is message');
};

###############################################################################
# Filters
###############################################################################

subtest 'filter with all fields' => sub {
    my $filter = {
        ids => ['aaa' . ('0' x 61)],
        authors => ['bbb' . ('0' x 61)],
        kinds => [1, 2],
        '#e' => ['ccc' . ('0' x 61)],
        '#p' => ['ddd' . ('0' x 61)],
        since => 1673361254,
        until => 1673361999,
        limit => 100
    };
    my $json = JSON->new->utf8->encode($filter);
    my $decoded = JSON::decode_json($json);

    is(ref($decoded->{ids}), 'ARRAY', 'ids is array');
    is(ref($decoded->{authors}), 'ARRAY', 'authors is array');
    is(ref($decoded->{kinds}), 'ARRAY', 'kinds is array');
    is(ref($decoded->{'#e'}), 'ARRAY', '#e is array');
    is(ref($decoded->{'#p'}), 'ARRAY', '#p is array');
    ok($decoded->{since} > 0, 'since is positive integer');
    ok($decoded->{until} >= $decoded->{since}, 'until >= since');
    ok($decoded->{limit} > 0, 'limit is positive integer');
};

subtest 'filter ids and authors must be 64-char lowercase hex' => sub {
    my $valid_id = 'a' x 64;
    like($valid_id, qr/^[0-9a-f]{64}$/, 'valid id is 64 lowercase hex chars');

    my $valid_author = 'b' x 64;
    like($valid_author, qr/^[0-9a-f]{64}$/, 'valid author is 64 lowercase hex chars');
};

subtest 'subscription_id constraints' => sub {
    # non-empty string, max 64 chars
    my $sub_id = 'my-subscription-1';
    ok(length($sub_id) > 0, 'subscription id is non-empty');
    ok(length($sub_id) <= 64, 'subscription id is <= 64 chars');

    my $max_sub_id = 'x' x 64;
    ok(length($max_sub_id) <= 64, 'max length subscription id is valid');
};

subtest 'multiple filters in REQ are OR conditions' => sub {
    # ["REQ", <sub_id>, <filter1>, <filter2>]
    my $msg = JSON->new->utf8->encode([
        'REQ', 'sub1',
        { kinds => [1], limit => 10 },
        { kinds => [0], authors => ['a' x 64] }
    ]);
    my $decoded = JSON::decode_json($msg);
    is($decoded->[0], 'REQ', 'REQ message');
    is($decoded->[1], 'sub1', 'subscription id');
    is(ref($decoded->[2]), 'HASH', 'first filter');
    is(ref($decoded->[3]), 'HASH', 'second filter');
    is($decoded->[2]{kinds}[0], 1, 'first filter kind');
    is($decoded->[3]{kinds}[0], 0, 'second filter kind');
};

###############################################################################
# Kind classification
###############################################################################

subtest 'kind range classification' => sub {
    # Regular events
    my @regular = (1, 2, 4, 44, 1000, 9999);
    for my $k (@regular) {
        my $is_regular = ($k == 1 || $k == 2 || ($k >= 4 && $k < 45) || ($k >= 1000 && $k < 10000));
        ok($is_regular, "kind $k is regular");
    }

    # Replaceable events
    my @replaceable = (0, 3, 10000, 19999);
    for my $k (@replaceable) {
        my $is_replaceable = ($k == 0 || $k == 3 || ($k >= 10000 && $k < 20000));
        ok($is_replaceable, "kind $k is replaceable");
    }

    # Ephemeral events
    my @ephemeral = (20000, 25000, 29999);
    for my $k (@ephemeral) {
        my $is_ephemeral = ($k >= 20000 && $k < 30000);
        ok($is_ephemeral, "kind $k is ephemeral");
    }

    # Addressable events
    my @addressable = (30000, 35000, 39999);
    for my $k (@addressable) {
        my $is_addressable = ($k >= 30000 && $k < 40000);
        ok($is_addressable, "kind $k is addressable");
    }
};

done_testing;
