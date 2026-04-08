use strictures 2;
use Test::More;
use Test::Fatal;

use Net::Nostr::Negentropy;

###############################################################################
# POD example: basic reconciliation
###############################################################################

subtest 'POD: basic reconciliation' => sub {
    my $client = Net::Nostr::Negentropy->new;
    $client->add_item(1000, '01' x 32);
    $client->add_item(2000, '02' x 32);
    $client->seal;

    my $server = Net::Nostr::Negentropy->new;
    $server->add_item(1000, '01' x 32);
    $server->add_item(3000, '03' x 32);
    $server->seal;

    my $q = $client->initiate;
    ok(defined $q, 'initiate returns hex message');
    like($q, qr/\A[0-9a-f]+\z/, 'message is hex-encoded');

    my ($a, $shave, $sneed) = $server->reconcile($q);
    ok(defined $a, 'server returns response');

    my ($q2, $chave, $cneed) = $client->reconcile($a);
    is_deeply([sort @$chave], ['02' x 32], 'client has 02');
    is_deeply([sort @$cneed], ['03' x 32], 'client needs 03');
};

###############################################################################
# POD example: empty sets
###############################################################################

subtest 'POD: empty sets' => sub {
    my $ne = Net::Nostr::Negentropy->new;
    $ne->seal;
    my $msg = $ne->initiate;
    ok(defined $msg, 'empty set produces a message');
};

###############################################################################
# Constructor
###############################################################################

subtest 'constructor: no args' => sub {
    my $ne = Net::Nostr::Negentropy->new;
    isa_ok($ne, 'Net::Nostr::Negentropy');
};

subtest 'constructor: unknown args rejected' => sub {
    like(
        exception { Net::Nostr::Negentropy->new(bogus => 1) },
        qr/unknown/i,
        'unknown arg rejected'
    );
};

###############################################################################
# exports
###############################################################################

subtest 'POD: constructor with frame_size_limit' => sub {
    my $ne = Net::Nostr::Negentropy->new(frame_size_limit => 4096);
    isa_ok($ne, 'Net::Nostr::Negentropy');
};

subtest 'exports: public methods available' => sub {
    can_ok('Net::Nostr::Negentropy', qw(new add_item seal initiate reconcile));
};

done_testing;
