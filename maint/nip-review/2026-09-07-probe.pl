# Read-only NIP drift observations; see 2026-09-07.md for scope and invocation.
use strict;
use warnings;
use JSON ();
use Net::Nostr::Comment;
use Net::Nostr::Group;
use Net::Nostr::List;
use Net::Nostr::Message;
use Net::Nostr::WalletConnect;
use Net::Nostr::RemoteSigning;
use Net::Nostr::Relay;
use Net::Nostr::RelayInfo;
use TestFixtures qw(make_event make_key_from_hex);

my $json = JSON->new->canonical->pretty;
my @observations;
sub observe {
    my ($name, $code) = @_;
    my $result = eval { $code->() };
    my $error = $@;
    push @observations, { name => $name, ($error ? (error => "$error") : (result => $result)) };
}
my $owner = make_key_from_hex(('0' x 63) . '1');
my $other = make_key_from_hex(('0' x 63) . '2');
my $pk = $owner->pubkey_hex;
sub signed_event {
    my (%args) = @_;
    my $event = make_event(pubkey => $pk, created_at => time(), %args);
    $owner->sign_event($event);
    return $event;
}
observe('NIP-22 kind-1 comment', sub {
    return Net::Nostr::Comment->comment(pubkey => $pk, event => signed_event(kind => 1), content => 'reply')->to_hash;
});
observe('NIP-42/67 EOSE auth hint', sub {
    return Net::Nostr::Message->parse('["EOSE","sub4",["auth","finish"]]')->serialize;
});
observe('NIP-29 invite identifier', sub {
    my $id = Net::Nostr::Group->format_id(pubkey => $pk, group_id => 'tech', relay => 'wss://relay.example');
    return Net::Nostr::Group->parse_id($id . '?invite=hello');
});
observe('NIP-29 metadata builder new tags', sub {
    return Net::Nostr::Group->metadata(pubkey => $pk, group_id => 'nostr', banner => 'https://example.com/banner.png', parent => 'tech', child => ['nip29'])->tags;
});
observe('NIP-29 metadata parser new tags', sub {
    return Net::Nostr::Group->metadata_from_event(signed_event(kind => 39000, tags => [['d','nostr'], ['banner','https://example.com/banner.png'], ['parent','tech'], ['child','nip29']]));
});
observe('NIP-29 NIP-11 subgroup advertisement round trip', sub {
    my $info = Net::Nostr::RelayInfo->from_json('{"supported_nips":[29],"nip29":{"subgroups":true}}');
    return JSON->new->decode($info->to_json);
});
observe('NIP-51 favorite follow sets round trip', sub {
    my $list = Net::Nostr::List->new(kind => 10011);
    $list->add('a', "30000:$pk:friends");
    my $parsed = Net::Nostr::List->from_event($list->to_event(pubkey => $pk));
    return { kind => $parsed->kind, items => $parsed->items };
});
observe('NIP-47 extensions builder', sub {
    return Net::Nostr::WalletConnect->info_event(pubkey => $pk, capabilities => ['pay_invoice'], encryption => ['nip44_v2'], extensions => ['02','03','04'])->tags;
});
observe('NIP-47 extensions parser', sub {
    my $info = Net::Nostr::WalletConnect->parse_info(signed_event(kind => 13194, content => 'pay_invoice', tags => [['encryption','nip44_v2'],['extensions','02 03 04']]));
    return { parsed_keys => [sort keys %$info], extensions_accessor => $info->can('extensions') ? 1 : 0 };
});
observe('NIP-46 unsupported method error round trip', sub {
    my $request = Net::Nostr::RemoteSigning->parse_request(Net::Nostr::RemoteSigning->request(id => 'test-id', method => 'unknown-method', params => []));
    my $response = Net::Nostr::RemoteSigning->parse_response(Net::Nostr::RemoteSigning->response(id => $request->id, error => 'unsupported method'));
    return { id => $response->id, error => $response->error };
});
{
    package CaptureConnection;
    sub new { bless { messages => [] }, shift }
    sub send { push @{$_[0]{messages}}, JSON->new->decode($_[1]); }
}
sub relay_with_connections {
    my (%args) = @_;
    my $relay = Net::Nostr::Relay->new(%args);
    $relay->_connections({ map { $_ => CaptureConnection->new } qw(writer reader) });
    $relay->_subscriptions({});
    $relay->_authenticated({ writer => {}, reader => {} });
    return $relay;
}
observe('NIP-01 zero limit stored/live and EOSE', sub {
    my $relay = relay_with_connections(default_limit => 5, max_limit => 10);
    $relay->store->store(signed_event(kind => 1, content => 'stored'));
    $relay->_handle_req('reader', 'zero', Net::Nostr::Filter->new(kinds => [1], limit => 0));
    my @initial = @{$relay->_connections->{reader}{messages}};
    $relay->broadcast(signed_event(kind => 1, content => 'live'));
    return { initial => [map { $_->[0] } @initial], after_live => [map { $_->[0] } @{$relay->_connections->{reader}{messages}}], active => exists($relay->_subscriptions->{reader}{zero}) ? 1 : 0 };
});
observe('NIP-01 zero limit plus nonzero filter', sub {
    my $relay = relay_with_connections();
    $relay->store->store(signed_event(kind => 1, content => 'one'));
    $relay->store->store(signed_event(kind => 2, content => 'two'));
    $relay->_handle_req('reader', 'mixed', Net::Nostr::Filter->new(kinds => [1], limit => 0), Net::Nostr::Filter->new(kinds => [2], limit => 1));
    return [map { $_->[0] eq 'EVENT' ? ['EVENT', $_->[2]{kind}] : [$_->[0]] } @{$relay->_connections->{reader}{messages}}];
});
for my $kind (78, 30078) {
    observe("NIP-78 kind $kind unauthenticated publish/read", sub {
        my $relay = relay_with_connections();
        my $event = signed_event(kind => $kind, content => 'owner data', tags => [['d','settings']]);
        $relay->_handle_event('writer', $event);
        $relay->_handle_req('reader', 'private-data', Net::Nostr::Filter->new(kinds => [$kind]));
        return { accepted => $relay->_connections->{writer}{messages}[0][2] ? 1 : 0, stored_read => [map { $_->[0] } @{$relay->_connections->{reader}{messages}}] };
    });
    observe("NIP-78 kind $kind live delivery to another authenticated key", sub {
        my $relay = relay_with_connections();
        $relay->_authenticated->{writer}{$pk} = 1;
        $relay->_authenticated->{reader}{$other->pubkey_hex} = 1;
        $relay->_handle_req('reader', 'private-data', Net::Nostr::Filter->new(kinds => [$kind], limit => 0));
        $relay->_handle_event('writer', signed_event(kind => $kind, content => 'owner data', tags => [['d','settings']]));
        return [map { $_->[0] } @{$relay->_connections->{reader}{messages}}];
    });
}
print $json->encode(\@observations);
