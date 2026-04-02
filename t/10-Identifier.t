#!/usr/bin/perl

# Unit tests for Net::Nostr::Identifier

use strictures 2;

use Test2::V0 -no_srand => 1;

use Net::Nostr::Identifier;

###############################################################################
# Constructor and accessors
###############################################################################

subtest 'new creates identifier object' => sub {
    my $ident = Net::Nostr::Identifier->new;
    isa_ok($ident, 'Net::Nostr::Identifier');
};

subtest 'base_url accessor' => sub {
    my $ident = Net::Nostr::Identifier->new(base_url => 'http://localhost:8080');
    is $ident->base_url, 'http://localhost:8080', 'base_url set';

    my $default = Net::Nostr::Identifier->new;
    is $default->base_url, undef, 'base_url defaults to undef';
};

###############################################################################
# parse
###############################################################################

subtest 'parse requires a defined identifier' => sub {
    like dies { Net::Nostr::Identifier->parse(undef) },
        qr/invalid/i, 'undef rejected';
};

subtest 'parse returns list context' => sub {
    my @result = Net::Nostr::Identifier->parse('alice@relay.example.com');
    is scalar @result, 2, 'returns two values';
    is $result[0], 'alice', 'local-part';
    is $result[1], 'relay.example.com', 'domain';
};

###############################################################################
# url
###############################################################################

subtest 'url croaks on invalid identifier' => sub {
    like dies { Net::Nostr::Identifier->url('INVALID') },
        qr/invalid/i, 'invalid identifier rejected';
};

###############################################################################
# display_name
###############################################################################

subtest 'display_name croaks on invalid identifier' => sub {
    like dies { Net::Nostr::Identifier->display_name('!!!') },
        qr/invalid/i, 'invalid identifier rejected';
};

###############################################################################
# verify required arguments
###############################################################################

subtest 'verify croaks without identifier' => sub {
    my $ident = Net::Nostr::Identifier->new;
    like dies {
        $ident->verify(
            pubkey     => 'a' x 64,
            on_success => sub {},
            on_failure => sub {},
        )
    }, qr/identifier required/i, 'missing identifier';
};

subtest 'verify croaks without pubkey' => sub {
    my $ident = Net::Nostr::Identifier->new;
    like dies {
        $ident->verify(
            identifier => 'bob@example.com',
            on_success => sub {},
            on_failure => sub {},
        )
    }, qr/pubkey required/i, 'missing pubkey';
};

subtest 'verify croaks without on_success' => sub {
    my $ident = Net::Nostr::Identifier->new;
    like dies {
        $ident->verify(
            identifier => 'bob@example.com',
            pubkey     => 'a' x 64,
            on_failure => sub {},
        )
    }, qr/on_success/i, 'missing on_success';
};

subtest 'verify croaks without on_failure' => sub {
    my $ident = Net::Nostr::Identifier->new;
    like dies {
        $ident->verify(
            identifier => 'bob@example.com',
            pubkey     => 'a' x 64,
            on_success => sub {},
        )
    }, qr/on_failure/i, 'missing on_failure';
};

###############################################################################
# lookup required arguments
###############################################################################

subtest 'lookup croaks without identifier' => sub {
    my $ident = Net::Nostr::Identifier->new;
    like dies {
        $ident->lookup(
            on_success => sub {},
            on_failure => sub {},
        )
    }, qr/identifier required/i, 'missing identifier';
};

subtest 'lookup croaks without on_success' => sub {
    my $ident = Net::Nostr::Identifier->new;
    like dies {
        $ident->lookup(
            identifier => 'bob@example.com',
            on_failure => sub {},
        )
    }, qr/on_success/i, 'missing on_success';
};

subtest 'lookup croaks without on_failure' => sub {
    my $ident = Net::Nostr::Identifier->new;
    like dies {
        $ident->lookup(
            identifier => 'bob@example.com',
            on_success => sub {},
        )
    }, qr/on_failure/i, 'missing on_failure';
};

done_testing;
