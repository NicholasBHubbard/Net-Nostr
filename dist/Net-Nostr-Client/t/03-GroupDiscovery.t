use strictures 2;
use Test2::V0 -no_srand => 1;
use JSON ();
use Net::Nostr::GroupDiscovery;
use Net::Nostr::Key;
use lib 't/lib';
use TestFixtures qw(client_connection);

subtest 'POD: dedicated Client transports discovery through EVENT and EOSE' => sub {
    my ($discovery_client,$connection) = client_connection();
    my $admin = Net::Nostr::Key->new;
    my $relay_key = Net::Nostr::Key->new;
    my ($admin_pubkey,$relay_pubkey) = ($admin->pubkey_hex,$relay_key->pubkey_hex);
    my @candidates;
    my $watch = Net::Nostr::GroupDiscovery->new(
        group_id => 'pizza', relay => 'wss://old.example',
        relay_pubkey => $relay_pubkey, admins => [$admin_pubkey],
        lookup => sub {
            my ($filter, $complete) = @_;
            my @events;
            $discovery_client->on(event => sub {
                push @events, $_[1] if $_[0] eq 'group-discovery';
            });
            $discovery_client->on(eose => sub {
                return unless $_[0] eq 'group-discovery';
                $discovery_client->close('group-discovery');
                $complete->(\@events, undef);
            });
            $discovery_client->subscribe('group-discovery', $filter);
        },
        on_candidate => sub { push @candidates, $_[0] },
    );
    $watch->primary_unreachable;
    is $connection->{sent}[0], ['REQ','group-discovery',{kinds=>[10009],authors=>[$admin_pubkey]}], 'wire discovery request';
    my $event=$admin->create_event(kind=>10009,content=>'',tags=>[['group','pizza','wss://new.example']]);
    $connection->receive(JSON::encode_json(['EVENT','group-discovery',$event->to_hash]));
    is \@candidates, [], 'waits for EOSE before selecting latest announcements';
    $connection->receive('["EOSE","group-discovery",["finish"]]');
    is $connection->{sent}[1], ['CLOSE','group-discovery'], 'one-shot lookup closes subscription';
    is $candidates[0]{relay},'wss://new.example','verified wire event produces a candidate';
};
done_testing;
