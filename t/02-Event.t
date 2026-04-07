#!/usr/bin/perl

use strictures 2;

use Test2::V0 -no_srand => 1;
# use Test2::Plugin::BailOnFail; # bail out of testing on the first failure
use Clone 'clone';

use lib 't/lib';
use TestFixtures qw(%FIATJAF_EVENT);

use Net::Nostr::Key;
use Net::Nostr::Event;

my $EVENT = Net::Nostr::Event->new(%FIATJAF_EVENT);

subtest 'new()' => sub {
    my $event = Net::Nostr::Event->new(
        content => $EVENT->content,
        pubkey => $EVENT->pubkey,
        kind => $EVENT->kind,
        sig => $EVENT->sig,
        created_at => $EVENT->created_at
    );
    is($event->id, $EVENT->id, 'automatically calculates id');
    is(ref($event), 'Net::Nostr::Event', 'constructs a Net::Nostr::Event');

    $event = Net::Nostr::Event->new(
        content => '',
        pubkey => 'b' x 64,
        kind => 1,
    );
    is($event->created_at, time(), 'automatically determines created_at');

};

subtest 'json_serialize()' => sub {
    my $event = Net::Nostr::Event->new(
        content => 'hello',
        pubkey => '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
        kind => 1,
        created_at => 1673361254,
        tags => [['p', 'abc123'], ['e', 'def456']]
    );
    my $json = $event->json_serialize;
    my $decoded = JSON::decode_json($json);
    is($decoded->[4], [['p', 'abc123'], ['e', 'def456']], 'tags serialize as array of arrays');
};

###############################################################################
# Immutability: body fields are read-only after construction
###############################################################################

subtest 'body fields are read-only' => sub {
    my $event = Net::Nostr::Event->new(
        content => 'hello', pubkey => 'b' x 64, kind => 1,
        created_at => 1673361254, tags => [['e', 'event1']],
    );
    like(dies { $event->id('f' x 64) }, qr/read-only/, 'id is read-only');
    like(dies { $event->pubkey('c' x 64) }, qr/read-only/, 'pubkey is read-only');
    like(dies { $event->kind(2) }, qr/read-only/, 'kind is read-only');
    like(dies { $event->content('changed') }, qr/read-only/, 'content is read-only');
    like(dies { $event->tags([]) }, qr/read-only/, 'tags is read-only');
    like(dies { $event->created_at(9999) }, qr/read-only/, 'created_at is read-only');
};

subtest 'sig is writable (does not affect event ID)' => sub {
    my $event = Net::Nostr::Event->new(
        content => 'hello', pubkey => 'b' x 64, kind => 1,
        created_at => 1673361254, tags => [],
    );
    ok(lives { $event->sig('a' x 128) }, 'sig can be set after construction');
    is($event->sig, 'a' x 128, 'sig value updated');
    ok(lives { $event->sig(undef) }, 'sig can be cleared');
};

subtest 'created_at 0 is preserved' => sub {
    my $event = Net::Nostr::Event->new(
        content => '', pubkey => 'b' x 64, kind => 1,
        created_at => 0, tags => []
    );
    is($event->created_at, 0, 'created_at of 0 is not overwritten');
};

subtest 'to_hash()' => sub {
    my $event = Net::Nostr::Event->new(%FIATJAF_EVENT);
    my $h = $event->to_hash;
    is($h->{id}, $event->id, 'id');
    is($h->{pubkey}, $event->pubkey, 'pubkey');
    is($h->{created_at}, $event->created_at, 'created_at');
    is($h->{kind}, $event->kind, 'kind');
    is($h->{tags}, $event->tags, 'tags');
    is($h->{content}, $event->content, 'content');
    is($h->{sig}, $event->sig, 'sig');
    is(scalar keys %$h, 7, 'exactly 7 fields');
};

subtest 'kind classification' => sub {
    for my $k (1, 2, 4, 44, 1000, 9999) {
        my $e = Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => $k, content => '', created_at => 1, tags => []
        );
        ok($e->is_regular, "kind $k is regular");
        ok(!$e->is_replaceable, "kind $k is not replaceable");
        ok(!$e->is_ephemeral, "kind $k is not ephemeral");
        ok(!$e->is_addressable, "kind $k is not addressable");
    }
    for my $k (0, 3, 10000, 19999) {
        my $e = Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => $k, content => '', created_at => 1, tags => []
        );
        ok($e->is_replaceable, "kind $k is replaceable");
        ok(!$e->is_regular, "kind $k is not regular");
    }
    for my $k (20000, 25000, 29999) {
        my $e = Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => $k, content => '', created_at => 1, tags => []
        );
        ok($e->is_ephemeral, "kind $k is ephemeral");
        ok(!$e->is_regular, "kind $k is not regular");
    }
    for my $k (30000, 35000, 39999) {
        my $e = Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => $k, content => '', created_at => 1, tags => []
        );
        ok($e->is_addressable, "kind $k is addressable");
        ok(!$e->is_regular, "kind $k is not regular");
    }
};

subtest 'POD: d_tag returns d tag value' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 30023,
        content => '', tags => [['d', 'my-article']],
    );
    is($event->d_tag, 'my-article', 'd_tag returns value of d tag');
};

subtest 'POD: d_tag returns empty string when no d tag' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 30023,
        content => '', tags => [['t', 'nostr']],
    );
    is($event->d_tag, '', 'd_tag returns empty string without d tag');
};

subtest 'POD: d_tag returns empty string for d tag with no value' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 30023,
        content => '', tags => [['d']],
    );
    is($event->d_tag, '', 'd_tag returns empty string for valueless d tag');
};

subtest 'POD: expiration returns timestamp' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'temp',
        tags => [['expiration', '1600000000']],
    );
    is $event->expiration, 1600000000, 'expiration returns numeric timestamp';
};

subtest 'POD: expiration returns undef without tag' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'no expiry',
    );
    ok !defined($event->expiration), 'expiration is undef without tag';
};

subtest 'POD: is_expired' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'temp',
        tags => [['expiration', '1600000000']],
    );
    ok $event->is_expired, 'event with past expiration is expired';

    my $far_future = time() + 86400 * 365 * 10;
    my $fresh = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'fresh',
        tags => [['expiration', "$far_future"]],
    );
    ok !$fresh->is_expired, 'event with future expiration is not expired';

    my $permanent = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'permanent',
    );
    ok !$permanent->is_expired, 'event without expiration is not expired';
};

subtest 'POD: is_expired with custom time' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'temp',
        tags => [['expiration', '1600000000']],
    );
    ok $event->is_expired(1600000001), 'expired when now > expiration';
    ok !$event->is_expired(1500000000), 'not expired when now < expiration';
};

subtest 'verify_sig()' => sub {
    my $key = Net::Nostr::Key->new;
    my $event = Net::Nostr::Event->new(
        pubkey => $key->pubkey_hex, kind => 1, content => 'test',
        created_at => 1000, tags => []
    );
    my $sig_hex = unpack 'H*', $key->schnorr_sign($event->id);
    $event->sig($sig_hex);
    ok($event->verify_sig($key), 'valid sig verifies');

    my $other_key = Net::Nostr::Key->new;
    like(dies { $event->verify_sig($other_key) },
        qr/pubkey does not match/, 'wrong key croaks');
};

subtest 'validate()' => sub {
    my $key = Net::Nostr::Key->new;
    my $event = $key->create_event(kind => 1, content => 'validate me', tags => []);
    ok($event->validate, 'fully signed event validates');
};

subtest 'validate() recomputes id' => sub {
    my $key = Net::Nostr::Key->new;
    my $event = $key->create_event(kind => 1, content => 'test', tags => []);
    # Tamper with the stored id by constructing with a wrong id
    my $bad = Net::Nostr::Event->new(
        id => 'f' x 64,
        pubkey => $event->pubkey, kind => 1, content => 'test',
        created_at => $event->created_at, tags => [],
        sig => $event->sig,
    );
    like(dies { $bad->validate }, qr/id does not match/, 'tampered id detected');
};

subtest 'validate() requires sig' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'unsigned',
    );
    like(dies { $event->validate }, qr/sig is required/, 'unsigned event fails validate');
};

subtest 'validate() detects bad signature' => sub {
    my $key = Net::Nostr::Key->new;
    my $event = Net::Nostr::Event->new(
        pubkey => $key->pubkey_hex, kind => 1, content => 'test',
        created_at => 1000, tags => [],
        sig => 'a' x 128,
    );
    like(dies { $event->validate }, qr/signature is invalid/, 'bad sig fails validate');
};

subtest 'new() rejects missing pubkey' => sub {
    like(
        dies { Net::Nostr::Event->new(kind => 1, content => 'hello') },
        qr/pubkey is required/,
        'missing pubkey croaks'
    );
};

subtest 'new() rejects invalid pubkey' => sub {
    like(
        dies { Net::Nostr::Event->new(pubkey => 'abc', kind => 1, content => 'hello') },
        qr/pubkey must be 64-char lowercase hex/,
        'short pubkey croaks'
    );
    like(
        dies { Net::Nostr::Event->new(pubkey => 'G' x 64, kind => 1, content => 'hello') },
        qr/pubkey must be 64-char lowercase hex/,
        'non-hex pubkey croaks'
    );
    like(
        dies { Net::Nostr::Event->new(pubkey => 'A' x 64, kind => 1, content => 'hello') },
        qr/pubkey must be 64-char lowercase hex/,
        'uppercase hex pubkey croaks'
    );
};

subtest 'new() rejects missing kind' => sub {
    like(
        dies { Net::Nostr::Event->new(pubkey => 'a' x 64, content => 'hello') },
        qr/kind is required/,
        'missing kind croaks'
    );
};

subtest 'new() rejects missing content' => sub {
    like(
        dies { Net::Nostr::Event->new(pubkey => 'a' x 64, kind => 1) },
        qr/content is required/,
        'missing content croaks'
    );
};

subtest 'new() rejects invalid sig' => sub {
    like(
        dies { Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => 1, content => 'hello',
            sig => 'not-a-sig',
        ) },
        qr/sig must be 128-char lowercase hex/,
        'invalid sig croaks'
    );
};

subtest 'new() rejects invalid id' => sub {
    like(
        dies { Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => 1, content => 'hello',
            id => 'short',
        ) },
        qr/id must be 64-char lowercase hex/,
        'invalid id croaks'
    );
};

subtest 'new() allows empty sig (unsigned event)' => sub {
    my $event = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'hello',
    );
    ok !defined($event->sig) || $event->sig eq '', 'unsigned event OK';
};


###############################################################################
# created_at validation
###############################################################################

subtest 'new() rejects non-numeric created_at' => sub {
    like(
        dies { Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => 1, content => 'test',
            created_at => 'not-a-number',
        ) },
        qr/created_at must be a non-negative integer/,
        'non-numeric created_at rejected'
    );
};

subtest 'new() rejects negative created_at' => sub {
    like(
        dies { Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => 1, content => 'test',
            created_at => -1,
        ) },
        qr/created_at must be a non-negative integer/,
        'negative created_at rejected'
    );
};

subtest 'new() rejects float created_at' => sub {
    like(
        dies { Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => 1, content => 'test',
            created_at => 1000.5,
        ) },
        qr/created_at must be a non-negative integer/,
        'float created_at rejected'
    );
};

subtest 'new() accepts valid created_at values' => sub {
    ok(lives { Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'test',
        created_at => 0, tags => [],
    ) }, 'created_at 0 accepted');
    ok(lives { Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'test',
        created_at => 1700000000, tags => [],
    ) }, 'created_at epoch accepted');
};

###############################################################################
# tags validation
###############################################################################

subtest 'new() rejects non-arrayref tags' => sub {
    like(
        dies { Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => 1, content => 'test',
            tags => 'not-an-array',
        ) },
        qr/tags must be an arrayref/,
        'string tags rejected'
    );
};

subtest 'new() rejects tag that is not an arrayref' => sub {
    like(
        dies { Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => 1, content => 'test',
            tags => ['not-an-arrayref'],
        ) },
        qr/each tag must be an arrayref/,
        'non-arrayref tag rejected'
    );
};

subtest 'new() rejects tag with undef element' => sub {
    like(
        dies { Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => 1, content => 'test',
            tags => [['e', undef]],
        ) },
        qr/tag elements must be defined strings/,
        'undef tag element rejected'
    );
};

subtest 'new() rejects tag with ref element' => sub {
    like(
        dies { Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => 1, content => 'test',
            tags => [['e', { nested => 1 }]],
        ) },
        qr/tag elements must be defined strings/,
        'hashref tag element rejected'
    );
};

subtest 'new() accepts valid tags' => sub {
    ok(lives { Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'test',
        tags => [['p', 'b' x 64], ['e', 'c' x 64, 'wss://relay.com']],
    ) }, 'valid tags accepted');
    ok(lives { Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => 'test',
        tags => [],
    ) }, 'empty tags array accepted');
};

subtest 'new() rejects unknown arguments' => sub {
    like(
        dies { Net::Nostr::Event->new(
            pubkey => 'a' x 64, kind => 1, content => 'test',
            tags => [], bogus => 'value',
        ) },
        qr/unknown.+bogus/i,
        'unknown argument rejected'
    );
};

done_testing;
