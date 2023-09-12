#!/usr/bin/perl

use strictures 2;

use Test2::V0 -no_srand => 1;
# use Test2::Plugin::BailOnFail; # bail out of testing on the first failure

# use Net::Nostr;
use Net::Nostr::Event;

my $NOSTR = Net::Nostr->new;
my $EVENT;

subtest 'new()' => sub {
    $EVENT = Net::Nostr::Event->new(pubkey => $NOSTR->pubkey_raw);
    ok($EVENT, 'create new event with no args');

};

done_testing;
