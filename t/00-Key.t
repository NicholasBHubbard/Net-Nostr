#!/usr/bin/perl

use v5.10;
use strictures 2;
use autodie;

use Test2::V0 -no_srand => 1;
# use Test2::Plugin::BailOnFail; # bail out of testing on the first failure
use File::Temp;

use Net::Nostr::Key;

my $CRYPTPKECC = Crypt::PK::ECC->new->generate_key('secp256k1');;

subtest 'new()' => sub {
    my $key = Net::Nostr::Key->new;
    ok($key->privkey_loaded, 'generates private key if not specified');

    $key = Net::Nostr::Key->new(privkey => \$CRYPTPKECC->export_key_der('private'));
    is($key->privkey_der, $CRYPTPKECC->export_key_der('private'), 'specify private key from constructor');
    ok($key->pubkey_loaded, 'automatically derives public key from private key');

    $key = Net::Nostr::Key->new(pubkey => \$CRYPTPKECC->export_key_der('public'));
    ok(($key->pubkey_loaded and not $key->privkey_loaded), 'load only a public key with \'pubkey\' constructor arg');

    ok(dies { my $key = Net::Nostr::Key->new(privkey => 12) }, 'die if passed invalid constructor key');
};

done_testing;
