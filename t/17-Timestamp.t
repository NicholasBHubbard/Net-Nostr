#!/usr/bin/perl

use strictures 2;

use Test2::V0 -no_srand => 1;
use MIME::Base64 ();

use lib 't/lib';
use TestFixtures qw(make_event);

use Net::Nostr::Event;
use Net::Nostr::Timestamp;

my $my_pubkey = 'a' x 64;
my $target_event_id = '1' x 64;

my $ots_base64 = MIME::Base64::encode_base64("fake-ots-proof-data", '');

###############################################################################
# POD SYNOPSIS examples
###############################################################################

subtest 'POD: create a timestamp attestation' => sub {
    my $ts = Net::Nostr::Timestamp->new(
        pubkey    => $my_pubkey,
        event_id  => $target_event_id,
        kind      => 1,
        ots_data  => $ots_base64,
        relay_url => 'wss://relay.example.com',
    );
    my $event = $ts->to_event;
    is $event->kind, 1040, 'kind 1040';
    is $event->content, $ots_base64, 'content is OTS data';
};

subtest 'POD: parse a received timestamp attestation' => sub {
    my $event = make_event(
        pubkey  => $my_pubkey,
        kind    => 1040,
        content => $ots_base64,
        tags    => [
            ['e', $target_event_id, 'wss://relay.example.com'],
            ['k', '1'],
        ],
    );
    my $ts = Net::Nostr::Timestamp->from_event($event);
    is $ts->event_id, $target_event_id, 'event_id';
    is $ts->kind, 1, 'kind';
    is $ts->relay_url, 'wss://relay.example.com', 'relay_url';
};

subtest 'new() rejects unknown arguments' => sub {
    like(
        dies { Net::Nostr::Timestamp->new(pubkey => 'a' x 64, bogus => 'value') },
        qr/unknown.+bogus/i,
        'unknown argument rejected'
    );
};

done_testing;
