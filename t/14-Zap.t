use strictures 2;
use Test2::V0;
use JSON ();

use lib 't/lib';
use TestFixtures qw(make_event make_key_from_hex);

use Net::Nostr::Zap qw(
    lud16_to_url
    encode_lnurl decode_lnurl
    bolt11_amount
    callback_url
    calculate_splits
);

###############################################################################
# Construction
###############################################################################

subtest 'new_request basic' => sub {
    my $zap = Net::Nostr::Zap->new_request(
        p      => 'b' x 64,
        relays => ['wss://r.com'],
    );
    isa_ok $zap, 'Net::Nostr::Zap';
    is $zap->p, 'b' x 64, 'p accessor';
    is $zap->relays, ['wss://r.com'], 'relays accessor';
};

subtest 'new_receipt basic' => sub {
    my $zap = Net::Nostr::Zap->new_receipt(
        p           => 'b' x 64,
        bolt11      => 'lnbc1test',
        description => '{"kind":9734}',
    );
    isa_ok $zap, 'Net::Nostr::Zap';
    is $zap->p, 'b' x 64, 'p accessor';
    is $zap->bolt11, 'lnbc1test', 'bolt11 accessor';
};

###############################################################################
# to_event
###############################################################################

subtest 'request to_event passes through extra args' => sub {
    my $zap = Net::Nostr::Zap->new_request(
        p      => 'b' x 64,
        relays => ['wss://r.com'],
    );
    my $event = $zap->to_event(pubkey => 'a' x 64, created_at => 1234567890);
    is $event->pubkey, 'a' x 64, 'pubkey passed through';
    is $event->created_at, 1234567890, 'created_at passed through';
};

subtest 'receipt to_event passes through extra args' => sub {
    my $zap = Net::Nostr::Zap->new_receipt(
        p           => 'b' x 64,
        bolt11      => 'lnbc1test',
        description => '{}',
    );
    my $event = $zap->to_event(pubkey => 'd' x 64, created_at => 9999);
    is $event->created_at, 9999, 'created_at passed through';
};

###############################################################################
# lud16_to_url
###############################################################################

subtest 'lud16_to_url POD examples' => sub {
    is lud16_to_url('alice@example.com'),
        'https://example.com/.well-known/lnurlp/alice',
        'basic lightning address';
    is lud16_to_url('bob@pay.domain.org'),
        'https://pay.domain.org/.well-known/lnurlp/bob',
        'subdomain lightning address';
};

subtest 'lud16_to_url lowercases username' => sub {
    is lud16_to_url('User@Example.COM'),
        'https://example.com/.well-known/lnurlp/user',
        'lowercased';
};

###############################################################################
# bolt11_amount edge cases
###############################################################################

subtest 'bolt11_amount with spec receipt invoice' => sub {
    my $bolt11 = 'lnbc10u1p3unwfusp5t9r3yymhpfqculx78u027lxspgxcr2n2987mx2j55nnfs95nxnzqpp5jmrh92pfld78spqs78v9euf2385t83uvpwk9ldrlvf6ch7tpascqhp5zvkrmemgth3tufcvflmzjzfvjt023nazlhljz2n9hattj4f8jq8qxqyjw5qcqpjrzjqtc4fc44feggv7065fqe5m4ytjarg3repr5j9el35xhmtfexc42yczarjuqqfzqqqqqqqqlgqqqqqqgq9q9qxpqysgq079nkq507a5tw7xgttmj4u990j7wfggtrasah5gd4ywfr2pjcn29383tphp4t48gquelz9z78p4cq7ml3nrrphw5w6eckhjwmhezhnqpy6gyf0';
    is bolt11_amount($bolt11), 1_000_000, 'spec example bolt11 = 1,000,000 millisats';
};

###############################################################################
# encode_lnurl / decode_lnurl
###############################################################################

subtest 'encode_lnurl produces lowercase bech32' => sub {
    my $encoded = encode_lnurl('https://example.com');
    is $encoded, lc($encoded), 'all lowercase';
    like $encoded, qr/^lnurl1/, 'lnurl prefix';
};

###############################################################################
# callback_url
###############################################################################

subtest 'callback_url with existing query params' => sub {
    my $event = make_event(
        kind    => 9734,
        pubkey  => 'a' x 64,
        content => '',
        tags    => [['p', 'b' x 64]],
    );
    my $url = callback_url('https://pay.test/cb?token=abc', amount => 1000, nostr => $event);
    like $url, qr{token=abc}, 'existing params preserved';
    like $url, qr{amount=1000}, 'amount added';
};

done_testing;
