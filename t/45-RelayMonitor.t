use strictures 2;
use Test::More;
use Test::Fatal;

use Net::Nostr::RelayMonitor;

my $PK = 'a' x 64;

###############################################################################
# POD example: discovery event
###############################################################################

subtest 'POD: build discovery event' => sub {
    my $event = Net::Nostr::RelayMonitor->discovery_event(
        pubkey       => $PK,
        relay_url    => 'wss://relay.example.com/',
        network      => 'clearnet',
        nips         => [1, 11, 42],
        rtt_open     => '150',
        requirements => ['!payment', 'auth'],
    );
    is($event->kind, 30166, 'kind is 30166');
    is($event->d_tag, 'wss://relay.example.com/', 'd tag is relay URL');

    my $mon = Net::Nostr::RelayMonitor->from_event($event);
    is($mon->relay_url, 'wss://relay.example.com/', 'relay_url round-trips');
    is($mon->network, 'clearnet', 'network round-trips');
    is($mon->rtt_open, '150', 'rtt_open round-trips');
};

###############################################################################
# POD example: announcement event
###############################################################################

subtest 'POD: build announcement event' => sub {
    my $event = Net::Nostr::RelayMonitor->announcement_event(
        pubkey    => $PK,
        frequency => '3600',
        checks    => [qw(ws nip11 ssl dns)],
        timeouts  => [{ test => 'open', ms => '5000' }],
    );
    is($event->kind, 10166, 'kind is 10166');

    my $mon = Net::Nostr::RelayMonitor->from_event($event);
    is($mon->frequency, '3600', 'frequency round-trips');
    is_deeply($mon->checks, [qw(ws nip11 ssl dns)], 'checks round-trip');
};

###############################################################################
# POD example: parse from event
###############################################################################

subtest 'POD: from_event' => sub {
    use Net::Nostr::Event;
    my $event = Net::Nostr::Event->new(
        pubkey => $PK, kind => 30166, content => '',
        tags => [
            ['d', 'wss://relay.example.com/'],
            ['n', 'clearnet'],
            ['N', '1'],
            ['N', '11'],
        ],
    );
    my $mon = Net::Nostr::RelayMonitor->from_event($event);
    is($mon->relay_url, 'wss://relay.example.com/');
    is($mon->network, 'clearnet');
    is_deeply($mon->nips, ['1', '11']);
};

###############################################################################
# Constructor
###############################################################################

subtest 'constructor: no args' => sub {
    my $mon = Net::Nostr::RelayMonitor->new;
    isa_ok($mon, 'Net::Nostr::RelayMonitor');
};

subtest 'constructor: unknown args rejected' => sub {
    like(
        exception { Net::Nostr::RelayMonitor->new(bogus => 1) },
        qr/unknown/i,
        'unknown arg rejected'
    );
};

###############################################################################
# POD example: validate
###############################################################################

subtest 'POD: validate' => sub {
    my $event = Net::Nostr::RelayMonitor->discovery_event(
        pubkey    => $PK,
        relay_url => 'wss://relay.example.com/',
    );
    ok(Net::Nostr::RelayMonitor->validate($event), 'validate returns true');

    my $bad = Net::Nostr::Event->new(
        pubkey => $PK, kind => 30166, content => '', tags => [],
    );
    eval { Net::Nostr::RelayMonitor->validate($bad) };
    ok($@, 'validate croaks on invalid event');
};

###############################################################################
# exports
###############################################################################

subtest 'public methods available' => sub {
    can_ok('Net::Nostr::RelayMonitor',
        qw(new discovery_event announcement_event from_event validate
           relay_url network relay_type nips requirements topics kinds
           geohash languages rtt_open rtt_read rtt_write nip11
           frequency timeouts checks));
};

done_testing;
