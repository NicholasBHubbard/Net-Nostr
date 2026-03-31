#!/usr/bin/perl

use strictures 2;

use Test2::V0 -no_srand => 1;
# use Test2::Plugin::BailOnFail; # bail out of testing on the first failure
use Clone 'clone';

use lib 't/lib';
use TestFixtures qw(%FIATJAF_EVENT);

# use Net::Nostr;
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
        pubkey => 0,
        kind => 1,
        sig => ''
    );
    is($event->created_at, time(), 'automatically determines created_at');

};

subtest 'json_serialize()' => sub {
    my $event = Net::Nostr::Event->new(
        content => 'hello',
        pubkey => '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
        kind => 1,
        sig => '',
        created_at => 1673361254,
        tags => [['p', 'abc123'], ['e', 'def456']]
    );
    my $json = $event->json_serialize;
    my $decoded = JSON::decode_json($json);
    is($decoded->[4], [['p', 'abc123'], ['e', 'def456']], 'tags serialize as array of arrays');
};

subtest 'add_pubkey_ref()' => sub {
    my $event = Net::Nostr::Event->new(
        content => 'hello',
        pubkey => 'abc',
        kind => 1,
        sig => '',
        created_at => 1673361254,
        tags => [['e', 'event1']]
    );
    $event->add_pubkey_ref('pubkey1');
    is($event->tags, [['e', 'event1'], ['p', 'pubkey1']], 'appends p tag without nesting');
};

subtest 'add_event_ref()' => sub {
    my $event = Net::Nostr::Event->new(
        content => 'hello',
        pubkey => 'abc',
        kind => 1,
        sig => '',
        created_at => 1673361254,
        tags => [['p', 'pubkey1']]
    );
    $event->add_event_ref('event1');
    is($event->tags, [['p', 'pubkey1'], ['e', 'event1']], 'appends e tag without nesting');
};

done_testing;
