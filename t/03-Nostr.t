#!/usr/bin/perl

use strictures 2;
use autodie;

use Test2::V0 -no_srand => 1;
# use Test2::Plugin::BailOnFail; # bail out of testing on the first failure

use Net::Nostr::Event;

### sign_event() ###
my $event = Net::Nostr::Event->new();
