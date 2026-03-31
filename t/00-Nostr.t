#!/usr/bin/perl

use strictures 2;
use autodie;

use Test2::V0 -no_srand => 1;
# use Test2::Plugin::BailOnFail; # bail out of testing on the first failure

use lib 't/lib';
use TestFixtures qw(%FIATJAF_EVENT);

use Net::Nostr;
use Net::Nostr::Event;

my $EVENT = Net::Nostr::Event->new(%FIATJAF_EVENT);

# TODO: figure out api
