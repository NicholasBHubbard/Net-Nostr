#!/usr/bin/perl

use strictures 2;

use Test2::V0 -no_srand => 1;

use lib 't/lib';
use TestFixtures qw(make_event);

use Net::Nostr::Event;
use Net::Nostr::Comment;

my $alice_pk = 'a' x 64;
my $bob_pk   = 'b' x 64;

my $event_id = '1' x 64;

###############################################################################
# POD SYNOPSIS examples
###############################################################################

subtest 'POD: comment on a nostr event' => sub {
    my $blog_post = make_event(
        id => $event_id, pubkey => $alice_pk, kind => 30023,
        content => '', tags => [['d', 'slug']],
    );
    my $comment = Net::Nostr::Comment->comment(
        event     => $blog_post,
        pubkey    => $bob_pk,
        content   => 'Great blog post!',
        relay_url => 'wss://relay.example.com',
    );
    is $comment->kind, 1111, 'kind 1111';
    ok scalar(grep { $_->[0] eq 'A' } @{$comment->tags}), 'has A tag';
};

subtest 'POD: comment on external identifier' => sub {
    my $comment = Net::Nostr::Comment->comment(
        identifier => 'https://abc.com/articles/1',
        kind       => 'web',
        pubkey     => $bob_pk,
        content    => 'Nice article!',
    );
    is $comment->kind, 1111, 'kind 1111';
    my @I = grep { $_->[0] eq 'I' } @{$comment->tags};
    is $I[0][1], 'https://abc.com/articles/1', 'I tag value';
};

subtest 'POD: reply to comment' => sub {
    my $parent = make_event(
        id => $event_id, pubkey => $alice_pk, kind => 1111,
        content => 'Great!',
        tags => [
            ['E', '2' x 64, 'wss://r.com', $alice_pk],
            ['K', '1063'],
            ['P', $alice_pk],
            ['e', '2' x 64, 'wss://r.com', $alice_pk],
            ['k', '1063'],
            ['p', $alice_pk],
        ],
    );
    my $reply = Net::Nostr::Comment->reply(
        to        => $parent,
        pubkey    => $bob_pk,
        content   => 'I agree!',
        relay_url => 'wss://relay.example.com',
    );
    is $reply->kind, 1111, 'kind 1111';
    my @k = grep { $_->[0] eq 'k' } @{$reply->tags};
    is $k[0][1], '1111', 'parent kind is comment';
};

subtest 'POD: from_event' => sub {
    my $event = make_event(
        pubkey => $bob_pk, kind => 1111, content => 'Nice!',
        tags => [
            ['E', $event_id, '', $alice_pk],
            ['K', '1063'],
            ['P', $alice_pk],
            ['e', $event_id, '', $alice_pk],
            ['k', '1063'],
            ['p', $alice_pk],
        ],
    );
    my $info = Net::Nostr::Comment->from_event($event);
    ok defined $info, 'returns Comment object';
    is $info->root_kind, '1063', 'root_kind accessor';
    is $info->parent_kind, '1063', 'parent_kind accessor';
    is $info->root_pubkey, $alice_pk, 'root_pubkey accessor';
};

subtest 'POD: validate' => sub {
    my $event = make_event(
        pubkey => $bob_pk, kind => 1111, content => 'Nice!',
        tags => [
            ['E', $event_id, '', $alice_pk],
            ['K', '1063'],
            ['P', $alice_pk],
            ['e', $event_id, '', $alice_pk],
            ['k', '1063'],
            ['p', $alice_pk],
        ],
    );
    ok lives { Net::Nostr::Comment->validate($event) }, 'validate succeeds';

    my $bad = make_event(pubkey => $bob_pk, kind => 1, content => 'hi', tags => []);
    ok dies { Net::Nostr::Comment->validate($bad) }, 'validate rejects non-1111';
};

subtest 'POD: comment on NIP-94 file' => sub {
    my $file = make_event(
        id => $event_id, pubkey => $alice_pk, kind => 1063, content => '',
    );
    my $comment = Net::Nostr::Comment->comment(
        event   => $file,
        pubkey  => $bob_pk,
        content => 'Great file!',
    );
    is $comment->kind, 1111, 'kind 1111';
    my @E = grep { $_->[0] eq 'E' } @{$comment->tags};
    is $E[0][1], $event_id, 'E tag event id';
};

subtest 'POD: podcast comment' => sub {
    my $comment = Net::Nostr::Comment->comment(
        identifier => 'podcast:item:guid:d98d189b-...',
        kind       => 'podcast:item:guid',
        pubkey     => $bob_pk,
        content    => 'Great episode!',
        hint       => 'https://fountain.fm/episode/...',
    );
    is $comment->kind, 1111, 'kind 1111';
    my @K = grep { $_->[0] eq 'K' } @{$comment->tags};
    is $K[0][1], 'podcast:item:guid', 'K tag';
};

done_testing;
