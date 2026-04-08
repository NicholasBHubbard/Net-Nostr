use strictures 2;
use Test2::V0 -no_srand => 1;

use JSON ();
use MIME::Base64 qw(decode_base64);
use Digest::SHA qw(sha256_hex);

use lib 't/lib';
use TestFixtures qw(make_key_from_hex);

use Net::Nostr::HttpAuth qw(
    create_auth_event
    create_auth_header
    parse_auth_header
    validate_auth_event
);

###############################################################################
# POD example: create Authorization header for GET
###############################################################################

subtest 'POD: create_auth_header GET' => sub {
    my $key = make_key_from_hex('01' x 32);
    my $header = create_auth_header(
        key    => $key,
        url    => 'https://api.example.com/data',
        method => 'GET',
    );
    like($header, qr/\ANostr /, 'header starts with Nostr scheme');
};

###############################################################################
# POD example: POST with payload hash
###############################################################################

subtest 'POD: create_auth_header POST with payload' => sub {
    my $key = make_key_from_hex('01' x 32);
    my $body = '{"name":"test"}';
    my $header = create_auth_header(
        key     => $key,
        url     => 'https://api.example.com/upload',
        method  => 'POST',
        payload => $body,
    );
    my ($scheme, $b64) = split / /, $header, 2;
    my $data = JSON->new->utf8->decode(decode_base64($b64));
    my @payload = grep { $_->[0] eq 'payload' } @{$data->{tags}};
    is($payload[0][1], sha256_hex($body), 'payload hash in header');
};

###############################################################################
# POD example: server parse and validate
###############################################################################

subtest 'POD: parse and validate' => sub {
    my $key = make_key_from_hex('01' x 32);
    my $header = create_auth_header(
        key    => $key,
        url    => 'https://api.example.com/data',
        method => 'GET',
    );
    my $event = parse_auth_header($header);
    is(
        dies { validate_auth_event($event, url => 'https://api.example.com/data', method => 'GET') },
        undef,
        'parsed event validates'
    );
};

###############################################################################
# POD example: create_auth_event
###############################################################################

subtest 'POD: create_auth_event' => sub {
    my $event = create_auth_event(
        pubkey => 'aa' x 32,
        url    => 'https://api.example.com/data',
        method => 'GET',
    );
    is($event->kind, 27235, 'kind 27235');
    is($event->content, '', 'empty content');
};

###############################################################################
# POD example: validate failure returns 401
###############################################################################

subtest 'POD: validate failure for 401' => sub {
    my $key = make_key_from_hex('01' x 32);
    my $header = create_auth_header(
        key    => $key,
        url    => 'https://example.com/api',
        method => 'GET',
    );
    my $event = parse_auth_header($header);
    my $err = dies { validate_auth_event($event, url => 'https://other.com', method => 'GET') };
    ok(defined $err, 'validation failure gives error for 401 response');
};

###############################################################################
# exports
###############################################################################

subtest 'exports: all functions available' => sub {
    ok(defined &create_auth_event, 'create_auth_event exported');
    ok(defined &create_auth_header, 'create_auth_header exported');
    ok(defined &parse_auth_header, 'parse_auth_header exported');
    ok(defined &validate_auth_event, 'validate_auth_event exported');
};

done_testing;
