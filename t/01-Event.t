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
        content => 'hello',
        pubkey => '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d',
        created_at => 1673361254,
        kind => 1,
        sig => 'f5e5e8a477c6749ef8562c23cdfec7a6917c975ec55075489cb3319b8a2ccb78317335a6850fb3a3714777b1c22611419d6c81ce4b0b88db86e2d1662bb17540'
    );

    is($event->id, $EVENT->id, 'automatically calculates id from constructor');
};

# getters/setters
subtest 'id()' => sub {
    is($EVENT->id, 'deb8b23368b6c658c36cf16396927a045dee0b7707b4133d714fb67264cc10cc');
};

subtest 'pubkey()' => sub {
    is($EVENT->pubkey, '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d');
};

subtest 'created_at()' => sub {
    is($EVENT->created_at, 1673361254);
};

subtest 'kind()' => sub {
    is($EVENT->kind, 1);
};

subtest 'tags()' => sub {
    is($EVENT->tags, []);
};

subtest 'content()' => sub {
    is($EVENT->content, 'hello');
};

subtest 'sig()' => sub {
    is($EVENT->sig, 'f5e5e8a477c6749ef8562c23cdfec7a6917c975ec55075489cb3319b8a2ccb78317335a6850fb3a3714777b1c22611419d6c81ce4b0b88db86e2d1662bb17540');
};

subtest 'set_id()' => sub {
    my $event = clone($EVENT);
    is($event->set_id(12), 12);
    is($event->id, 12);
};

subtest 'set_pubkey()' => sub {
    my $event = clone($EVENT);
    is($event->set_pubkey(12), 12);
    is($event->pubkey, 12);
};

subtest 'set_created_at()' => sub {
    my $event = clone($EVENT);
    is($event->set_created_at(12), 12);
    is($event->created_at, 12);
};

subtest 'set_kind()' => sub {
    my $event = clone($EVENT);
    is($event->set_kind(12), 12);
    is($event->kind, 12);
};

subtest 'set_tags()' => sub {
    my $event = clone($EVENT);
    is($event->set_tags(12), 12);
    is($event->tags, 12);
};

subtest 'set_content()' => sub {
    my $event = clone($EVENT);
    is($event->set_content(12), 12);
    is($event->content, 12);
};

subtest 'set_sig()' => sub {
    my $event = clone($EVENT);
    is($event->set_sig(12), 12);
    is($event->sig, 12);
};

done_testing;
