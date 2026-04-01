#!/usr/bin/perl

use strictures 2;

use Test2::V0 -no_srand => 1;
use AnyEvent;
use IO::Socket::INET;

use Net::Nostr;
use Net::Nostr::Event;
use Net::Nostr::Filter;

sub free_port {
    my $sock = IO::Socket::INET->new(
        Listen => 1, LocalAddr => '127.0.0.1', LocalPort => 0,
    );
    my $port = $sock->sockport;
    close $sock;
    return $port;
}

###############################################################################
# Construction and key management
###############################################################################

subtest 'new generates a keypair by default' => sub {
    my $nostr = Net::Nostr->new;
    isa_ok($nostr, 'Net::Nostr');
    ok($nostr->key, 'has a key');
    like($nostr->key->pubkey_hex, qr/^[0-9a-f]{64}$/, 'pubkey is valid hex');
};

subtest 'new accepts privkey argument' => sub {
    my $ref = Net::Nostr->new;
    my $privkey = $ref->key->privkey_der;
    my $nostr = Net::Nostr->new(privkey => \$privkey);
    is($nostr->key->pubkey_hex, $ref->key->pubkey_hex, 'same privkey produces same pubkey');
};

###############################################################################
# create_event
###############################################################################

subtest 'create_event builds and signs an event' => sub {
    my $nostr = Net::Nostr->new;
    my $event = $nostr->create_event(kind => 1, content => 'hello nostr');

    isa_ok($event, 'Net::Nostr::Event');
    is($event->pubkey, $nostr->key->pubkey_hex, 'pubkey set from key');
    is($event->kind, 1, 'kind preserved');
    is($event->content, 'hello nostr', 'content preserved');
    like($event->id, qr/^[0-9a-f]{64}$/, 'id computed');
    like($event->sig, qr/^[0-9a-f]{128}$/, 'sig computed');
    ok($event->verify_sig($nostr->key), 'signature verifies');
};

subtest 'create_event accepts tags' => sub {
    my $nostr = Net::Nostr->new;
    my $event = $nostr->create_event(
        kind    => 1,
        content => 'tagged',
        tags    => [['t', 'nostr']],
    );
    is($event->tags, [['t', 'nostr']], 'tags preserved');
};

subtest 'create_event accepts created_at' => sub {
    my $nostr = Net::Nostr->new;
    my $event = $nostr->create_event(
        kind       => 1,
        content    => 'timestamped',
        created_at => 1700000000,
    );
    is($event->created_at, 1700000000, 'created_at preserved');
};

###############################################################################
# sign_event
###############################################################################

subtest 'sign_event signs an existing event' => sub {
    my $nostr = Net::Nostr->new;
    my $event = Net::Nostr::Event->new(
        pubkey  => $nostr->key->pubkey_hex,
        kind    => 1,
        content => 'unsigned',
        tags    => [],
    );
    ok(!$event->sig, 'event starts unsigned');

    my $sig = $nostr->sign_event($event);
    like($sig, qr/^[0-9a-f]{128}$/, 'returns hex signature');
    is($event->sig, $sig, 'sig set on event');
    ok($event->verify_sig($nostr->key), 'signature verifies');
};

###############################################################################
# client factory
###############################################################################

subtest 'client returns a Net::Nostr::Client' => sub {
    my $nostr = Net::Nostr->new;
    my $client = $nostr->client;
    isa_ok($client, 'Net::Nostr::Client');
};

###############################################################################
# relay factory
###############################################################################

subtest 'relay returns a Net::Nostr::Relay' => sub {
    my $nostr = Net::Nostr->new;
    my $relay = $nostr->relay;
    isa_ok($relay, 'Net::Nostr::Relay');
};

###############################################################################
# End-to-end: create event, publish via client, query back
###############################################################################

subtest 'end-to-end: create, publish, subscribe' => sub {
    my $port = free_port();
    my $nostr = Net::Nostr->new;

    my $relay = $nostr->relay;
    $relay->start('127.0.0.1', $port);

    my $client = $nostr->client;
    my $event = $nostr->create_event(kind => 1, content => 'e2e test');

    my $cv = AnyEvent->condvar;
    my $timeout = AnyEvent->timer(after => 5, cb => sub { $cv->croak("timeout") });

    my @received;

    $client->on(ok => sub {
        my $filter = Net::Nostr::Filter->new(kinds => [1]);
        $client->subscribe('e2e', $filter);
    });

    $client->on(event => sub {
        my ($sub_id, $evt) = @_;
        push @received, $evt;
    });

    $client->on(eose => sub { $cv->send });

    $client->connect("ws://127.0.0.1:$port")->cb(sub {
        eval { shift->recv };
        my $t; $t = AnyEvent->timer(after => 0.15, cb => sub {
            undef $t;
            $client->publish($event);
        });
    });

    $cv->recv;

    is(scalar @received, 1, 'received one event');
    is($received[0]->id, $event->id, 'event id matches');
    is($received[0]->content, 'e2e test', 'content matches');
    ok($received[0]->verify_sig($nostr->key), 'signature valid on received event');

    $client->disconnect;
    $relay->stop;
};

done_testing;
