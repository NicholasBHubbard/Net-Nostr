#!/usr/bin/perl

use v5.10;
use strictures 2;
use autodie;

use Test2::V0 -no_srand => 1;
# use Test2::Plugin::BailOnFail; # bail out of testing on the first failure
use File::Temp;

use Net::Nostr::Key;

my $TEST_KEY;
my $CRYPTPKECC = Crypt::PK::ECC->new->generate_key('secp256k1');;

$TEST_KEY = Net::Nostr::Key->new;
ok($TEST_KEY->privkey_loaded, 'generates new key if constructed with no args');

$TEST_KEY = Net::Nostr::Key->new(privkey => \$CRYPTPKECC->export_key_der('private'));
ok($TEST_KEY->privkey_loaded, q(loads private key from 'privkey' constructor arg));
is($TEST_KEY->privkey_der, $CRYPTPKECC->export_key_der('private'), 'loads the correct key');
is($TEST_KEY->pubkey_der, $CRYPTPKECC->export_key_der('public'), 'derives public key from private key');

$TEST_KEY = do {
    my $fh = File::Temp->new(TEMPLATE => 'Net-Nostr-Key.tXXXX', SUFFIX => '.der');
    print $fh $CRYPTPKECC->export_key_der('private');
    close $fh;
    Net::Nostr::Key->new(privkey => "$fh");
};
is($TEST_KEY->privkey_der, $CRYPTPKECC->export_key_der('private'), 'loads Key From file');

$TEST_KEY = Net::Nostr::Key->new(pubkey => \$CRYPTPKECC->export_key_der('public'));
ok(($TEST_KEY->pubkey_loaded && not $TEST_KEY->privkey_loaded), q(loads public key from 'pubkey' constructor arg));
