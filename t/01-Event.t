#!/usr/bin/perl

use strictures 2;

use Test2::V0 -no_srand => 1;
# use Test2::Plugin::BailOnFail; # bail out of testing on the first failure
use Clone 'clone';

# use Net::Nostr;
use Net::Nostr::Event;

# A real-world note from fiatjaf
my $EVENT = Net::Nostr::Event->new(
    id => 'deb8b23368b6c658c36cf16396927a045dee0b7707b4133d714fb67264cc10cc',
    kind => 1,
    pubkey => '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
    created_at => 1673361254,
    content => 'hello',
    tags => [],
    sig => 'f5e5e8a477c6749ef8562c23cdfec7a6917c975ec55075489cb3319b8a2ccb78317335a6850fb3a3714777b1c22611419d6c81ce4b0b88db86e2d1662bb17540'
);

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
    # these tests are based off results from python_nostr

    my $event = Net::Nostr::Event->new(
        content => $EVENT->content,
        pubkey => $EVENT->pubkey,
        kind => $EVENT->kind,
        sig => $EVENT->sig,
    );


};

done_testing;
