#!/usr/bin/perl

# Unit tests for Net::Nostr::RelayList

use strictures 2;

use Test2::V0 -no_srand => 1;

use Net::Nostr::RelayList;

###############################################################################
# Constructor
###############################################################################

subtest 'new creates empty relay list' => sub {
    my $rl = Net::Nostr::RelayList->new;
    isa_ok($rl, 'Net::Nostr::RelayList');
    is($rl->count, 0, 'starts empty');
};

###############################################################################
# add validation
###############################################################################

subtest 'add requires a URL' => sub {
    my $rl = Net::Nostr::RelayList->new;
    like(dies { $rl->add(undef) }, qr/url required/i, 'undef rejected');
};

subtest 'add rejects invalid marker' => sub {
    my $rl = Net::Nostr::RelayList->new;
    like(dies { $rl->add('wss://r.com', marker => 'both') },
        qr/marker/, 'invalid marker rejected');
    like(dies { $rl->add('wss://r.com', marker => 'WRITE') },
        qr/marker/, 'uppercase marker rejected');
};

subtest 'add accepts valid markers' => sub {
    my $rl = Net::Nostr::RelayList->new;
    ok(lives { $rl->add('wss://r1.com') }, 'no marker ok');
    ok(lives { $rl->add('wss://r2.com', marker => 'read') }, 'read ok');
    ok(lives { $rl->add('wss://r3.com', marker => 'write') }, 'write ok');
    is($rl->count, 3, 'three relays added');
};

###############################################################################
# from_event validation
###############################################################################

subtest 'from_event requires kind 10002' => sub {
    require Net::Nostr::Event;
    my $event = Net::Nostr::Event->new(
        pubkey => 'a' x 64, kind => 1, content => '', tags => [],
    );
    like(dies { Net::Nostr::RelayList->from_event($event) },
        qr/kind 10002/, 'wrong kind rejected');
};

###############################################################################
# relays returns list in order
###############################################################################

subtest 'relays preserves insertion order' => sub {
    my $rl = Net::Nostr::RelayList->new;
    $rl->add('wss://first.com');
    $rl->add('wss://second.com');
    $rl->add('wss://third.com');

    my @relays = $rl->relays;
    is($relays[0]{url}, 'wss://first.com', 'first');
    is($relays[1]{url}, 'wss://second.com', 'second');
    is($relays[2]{url}, 'wss://third.com', 'third');
};

done_testing;
