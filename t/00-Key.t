#!/usr/bin/perl

use v5.10;
use strictures 2;
use autodie;

use Test2::V0 -no_srand => 1;
# use Test2::Plugin::BailOnFail; # bail out of testing on the first failure

use Net::Nostr::Key;

my $KEY;
my $CRYPTPKECC = Crypt::PK::ECC->new->generate_key('secp256k1');;

### new() ###
$KEY = Net::Nostr::Key->new;
ok($KEY->privkey_loaded, 'generates new key if constructed with no args');

$KEY = Net::Nostr::Key->new(privkey => \$CRYPTPKECC->export_key_der('private'));
ok($KEY->privkey_loaded, q(loads private key from 'privkey' constructor arg));
is($KEY->privkey_der, $CRYPTPKECC->export_key_der('private'), 'loads the correct key');
is($KEY->pubkey_der, $CRYPTPKECC->export_key_der('public'), 'derives public key from private key');

$KEY = Net::Nostr::Key->new(pubkey => \$CRYPTPKECC->export_key_der('public'));
ok(($KEY->pubkey_loaded && not $KEY->privkey_loaded), q(loads public key from 'pubkey' constructor arg));

### sign_message ###

done_testing;
