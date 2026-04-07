package Net::Nostr::Relay;

use strictures 2;

use Carp qw(croak);
use Net::Nostr::Message;
use Net::Nostr::Filter;
use Net::Nostr::Deletion;

use AnyEvent::Socket qw(tcp_server);
use AnyEvent::WebSocket::Server;
use Crypt::PK::ECC;
use Crypt::PK::ECC::Schnorr;
use Crypt::PRNG qw(random_bytes);
use Digest::SHA qw(sha256_hex);
use JSON ();
use Socket qw(MSG_PEEK);

use Net::Nostr::RelayInfo;

use Class::Tiny qw(
    _server
    connections
    subscriptions
    events
    _guard
    verify_signatures
    max_connections_per_ip
    relay_url
    relay_info
    _conn_count_by_ip
    _run_cv
    _challenges
    _authenticated
    _nip11_watchers
    min_pow_difficulty
);

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;
    my %known; @known{Class::Tiny->get_all_attributes_for($class)} = ();
    my @unknown = grep { !exists $known{$_} } keys %$self;
    croak "unknown argument(s): " . join(', ', sort @unknown) if @unknown;
    $self->verify_signatures(1) unless defined $self->verify_signatures;
    $self->_server(AnyEvent::WebSocket::Server->new());
    return $self;
}

sub start {
    my ($self, $host, $port) = @_;
    $self->_conn_count_by_ip({});
    $self->_nip11_watchers({});
    $self->_guard(tcp_server($host, $port, sub {
        my ($fh, $peer_host) = @_;
        if (defined $self->max_connections_per_ip) {
            my $count = $self->_conn_count_by_ip->{$peer_host} || 0;
            if ($count >= $self->max_connections_per_ip) {
                close $fh;
                return;
            }
        }
        $self->_conn_count_by_ip->{$peer_host}++;

        if ($self->relay_info) {
            $self->_handle_nip11_or_ws($fh, $peer_host);
        } else {
            $self->_establish_ws($fh, $peer_host);
        }
    }));
}

sub _establish_ws {
    my ($self, $fh, $peer_host) = @_;
    $self->_server->establish($fh)->cb(sub {
        my $conn = eval { shift->recv };
        if ($@) {
            $self->_conn_count_by_ip->{$peer_host}--;
            warn "WebSocket handshake failed: $@\n";
            return;
        }
        $self->_on_connection($conn, $peer_host);
    });
}

sub _handle_nip11_or_ws {
    my ($self, $fh, $peer_host) = @_;
    my $fileno = fileno($fh);
    my $buf = '';
    my ($w, $timer);

    my $cleanup = sub {
        undef $w;
        undef $timer;
        delete $self->_nip11_watchers->{$fileno};
    };

    my $dispatch = sub {
        if ($buf =~ /^OPTIONS\s/i) {
            sysread($fh, my $discard, 8192);
            syswrite($fh, Net::Nostr::RelayInfo->cors_preflight_response);
            close $fh;
            $self->_conn_count_by_ip->{$peer_host}--;
            return;
        }

        if ($buf =~ /Accept:\s*application\/nostr\+json/i
            && $buf !~ /Upgrade:\s*websocket/i) {
            sysread($fh, my $discard, 8192);
            syswrite($fh, $self->relay_info->to_http_response);
            close $fh;
            $self->_conn_count_by_ip->{$peer_host}--;
            return;
        }

        $self->_establish_ws($fh, $peer_host);
    };

    $w = AnyEvent->io(fh => $fh, poll => 'r', cb => sub {
        my $chunk = '';
        recv($fh, $chunk, 8192, MSG_PEEK);
        $buf = $chunk;  # MSG_PEEK returns the full buffer each time

        if ($buf =~ /\r\n\r\n/ || length($buf) >= 8192) {
            $cleanup->();
            $dispatch->();
        }
    });

    $timer = AnyEvent->timer(after => 5, cb => sub {
        $cleanup->();
        # Timed out waiting for headers — fall through to WebSocket
        $self->_establish_ws($fh, $peer_host);
    });

    $self->_nip11_watchers->{$fileno} = [$w, $timer];
}

sub run {
    my ($self, $host, $port) = @_;
    $self->start($host, $port);
    $self->_run_cv(AnyEvent->condvar);
    $self->_run_cv->recv;
    $self->_run_cv(undef);
    $self->_stop_cleanup;
}

sub stop {
    my ($self) = @_;
    if ($self->_run_cv) {
        $self->_run_cv->send;
        return;
    }
    $self->_stop_cleanup;
}

sub authenticated_pubkeys {
    my ($self) = @_;
    return { %{$self->_authenticated || {}} };
}

sub _stop_cleanup {
    my ($self) = @_;
    $self->_guard(undef);
    for my $conn (values %{$self->connections || {}}) {
        $conn->close;
    }
    $self->connections({});
    $self->subscriptions({});
    $self->_conn_count_by_ip({});
    $self->_challenges({});
    $self->_authenticated({});
    $self->_nip11_watchers({});
}

sub broadcast {
    my ($self, $event) = @_;
    # NIP-40: Do not broadcast expired events
    return if $event->is_expired;
    my $subs = $self->subscriptions || {};
    for my $conn_id (keys %$subs) {
        my $conn = $self->connections->{$conn_id} or next;
        for my $sub_id (keys %{$subs->{$conn_id}}) {
            my $filters = $subs->{$conn_id}{$sub_id};
            if (Net::Nostr::Filter->matches_any($event, @$filters)) {
                $conn->send(Net::Nostr::Message->new(type => 'EVENT', subscription_id => $sub_id, event => $event)->serialize);
            }
        }
    }
}

my $CONN_ID = 0;

sub _on_connection {
    my ($self, $conn, $peer_host) = @_;
    my $conn_id = ++$CONN_ID;

    $self->connections($self->connections // {});
    $self->subscriptions($self->subscriptions // {});
    $self->events($self->events // []);
    $self->_challenges($self->_challenges // {});
    $self->_authenticated($self->_authenticated // {});

    $self->connections->{$conn_id} = $conn;

    # Send AUTH challenge
    my $challenge = unpack('H*', random_bytes(32));
    $self->_challenges->{$conn_id} = $challenge;
    $self->_authenticated->{$conn_id} = {};
    $conn->send(Net::Nostr::Message->new(type => 'AUTH', challenge => $challenge)->serialize);

    $conn->on(each_message => sub {
        my ($conn, $message) = @_;
        my $arr = eval { JSON::decode_json($message->body) };
        return warn "bad message: $@\n" if $@ || ref($arr) ne 'ARRAY' || !@$arr;

        my $type = $arr->[0];

        if ($type eq 'REQ') {
            my $sub_id = $arr->[1] // '';
            my $msg = eval { Net::Nostr::Message->parse($message->body) };
            if ($@) {
                $conn->send(Net::Nostr::Message->new(
                    type => 'CLOSED', subscription_id => $sub_id,
                    message => "error: $@"
                )->serialize);
                return;
            }
            $self->_handle_req($conn_id, $msg->subscription_id, @{$msg->filters});
            return;
        }

        if ($type eq 'COUNT') {
            my $sub_id = $arr->[1] // '';
            my $msg = eval { Net::Nostr::Message->parse($message->body) };
            if ($@) {
                $conn->send(Net::Nostr::Message->new(
                    type => 'CLOSED', subscription_id => $sub_id,
                    message => "error: $@"
                )->serialize);
                return;
            }
            $self->_handle_count($conn_id, $msg->subscription_id, @{$msg->filters});
            return;
        }

        my $msg = eval { Net::Nostr::Message->parse($message->body) };
        if ($@) {
            if ($type eq 'EVENT' || $type eq 'AUTH') {
                my $event_id = (ref($arr->[1]) eq 'HASH' ? $arr->[1]{id} : '') // '';
                my $reason = $@;
                $reason =~ s/\n\z//;
                $conn->send(Net::Nostr::Message->new(
                    type => 'OK', event_id => $event_id,
                    accepted => 0, message => "invalid: $reason"
                )->serialize);
            }
            return;
        }

        if ($msg->type eq 'EVENT') {
            $self->_handle_event($conn_id, $msg->event);
        } elsif ($msg->type eq 'CLOSE') {
            $self->_handle_close($conn_id, $msg->subscription_id);
        } elsif ($msg->type eq 'AUTH') {
            $self->_handle_auth($conn_id, $msg->event);
        }
    });

    $conn->on(finish => sub {
        delete $self->connections->{$conn_id};
        delete $self->subscriptions->{$conn_id};
        delete $self->_challenges->{$conn_id};
        delete $self->_authenticated->{$conn_id};
        $self->_conn_count_by_ip->{$peer_host}-- if defined $peer_host;
    });
}

sub _relay_host_matches {
    my ($expected, $got) = @_;
    my ($es, $eh, $ep, $epath) = $expected =~ m{^(wss?)://([^:/]+)(?::(\d+))?(/.*)?\z}i;
    my ($gs, $gh, $gp, $gpath) = $got      =~ m{^(wss?)://([^:/]+)(?::(\d+))?(/.*)?\z}i;
    return 0 unless defined $es && defined $gs;
    return 0 unless lc($es) eq lc($gs);
    return 0 unless lc($eh) eq lc($gh);
    my %defaults = (wss => 443, ws => 80);
    $ep //= $defaults{lc $es};
    $gp //= $defaults{lc $gs};
    return 0 unless $ep == $gp;
    $epath = '/' unless defined $epath && length $epath;
    $gpath = '/' unless defined $gpath && length $gpath;
    return $epath eq $gpath;
}

my $HEX64  = qr/\A[0-9a-f]{64}\z/;
my $HEX128 = qr/\A[0-9a-f]{128}\z/;

sub _validate_event {
    my ($self, $event) = @_;
    return 'invalid: bad id format'     unless defined $event->id     && $event->id     =~ $HEX64;
    return 'invalid: bad pubkey format' unless defined $event->pubkey && $event->pubkey =~ $HEX64;
    return 'invalid: bad sig format'    unless defined $event->sig    && $event->sig    =~ $HEX128;

    my $expected_id = sha256_hex($event->json_serialize);
    return 'invalid: id does not match hash' unless $event->id eq $expected_id;

    if ($self->verify_signatures) {
        my $sig_valid = eval {
            my $pubkey_raw = pack('H*', $event->pubkey);
            # BIP-340 x-only pubkey: prepend 02 prefix for compressed point
            my $compressed = "\x02" . $pubkey_raw;
            my $pk = Crypt::PK::ECC->new;
            $pk->import_key_raw($compressed, 'secp256k1');
            my $verifier = Crypt::PK::ECC::Schnorr->new(\$pk->export_key_der('public'));
            my $sig_raw = pack('H*', $event->sig);
            $verifier->verify_message($event->id, $sig_raw);
        };
        return 'invalid: bad signature' unless $sig_valid;
    }

    return undef;
}

sub _is_newer {
    my ($new, $existing) = @_;
    return 1 if $new->created_at > $existing->created_at;
    return 1 if $new->created_at == $existing->created_at && $new->id lt $existing->id;
    return 0;
}

sub _handle_event {
    my ($self, $conn_id, $event) = @_;
    my $conn = $self->connections->{$conn_id};

    my $error = $self->_validate_event($event);
    if ($error) {
        $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => ($event->id // ''), accepted => 0, message => $error)->serialize);
        return;
    }

    # NIP-13: Proof of Work check
    if (defined $self->min_pow_difficulty) {
        my $min = $self->min_pow_difficulty;
        my $committed = $event->committed_target_difficulty;
        if (!defined $committed || $committed < $min) {
            $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 0, message => "pow: difficulty commitment below required $min")->serialize);
            return;
        }
        if ($event->difficulty < $min) {
            $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 0, message => "pow: insufficient proof of work (need $min bits)")->serialize);
            return;
        }
    }

    # NIP-40: Relays SHOULD drop expired events on publish
    # (expiration does not affect ephemeral events)
    if ($event->is_expired && !$event->is_ephemeral) {
        $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 0, message => 'invalid: event has expired')->serialize);
        return;
    }

    # Relays MUST exclude kind 22242 events from being broadcasted (NIP-42)
    if ($event->kind == 22242) {
        $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 0, message => 'invalid: auth events should use AUTH message')->serialize);
        return;
    }

    # duplicate detection
    for my $existing (@{$self->events}) {
        if ($existing->id eq $event->id) {
            $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 1, message => 'duplicate: already have this event')->serialize);
            return;
        }
    }

    # ephemeral events: broadcast but don't store
    if ($event->is_ephemeral) {
        $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 1, message => '')->serialize);
        $self->broadcast($event);
        return;
    }

    # replaceable events: keep only latest per pubkey+kind
    if ($event->is_replaceable) {
        for my $i (0 .. $#{$self->events}) {
            my $existing = $self->events->[$i];
            if ($existing->pubkey eq $event->pubkey && $existing->kind == $event->kind) {
                if (_is_newer($event, $existing)) {
                    splice @{$self->events}, $i, 1;
                } else {
                    $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 1, message => 'duplicate: have a newer version')->serialize);
                    return;
                }
                last;
            }
        }
    }

    # addressable events: keep only latest per pubkey+kind+d_tag
    if ($event->is_addressable) {
        my $d = $event->d_tag;
        for my $i (0 .. $#{$self->events}) {
            my $existing = $self->events->[$i];
            if ($existing->pubkey eq $event->pubkey && $existing->kind == $event->kind && $existing->d_tag eq $d) {
                if (_is_newer($event, $existing)) {
                    splice @{$self->events}, $i, 1;
                } else {
                    $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 1, message => 'duplicate: have a newer version')->serialize);
                    return;
                }
                last;
            }
        }
    }

    # deletion requests: remove matching events, but not other kind 5 events
    if ($event->kind == 5) {
        $self->_handle_deletion($event);
    }

    push @{$self->events}, $event;
    $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 1, message => '')->serialize);
    $self->broadcast($event);
}

sub _handle_deletion {
    my ($self, $del_event) = @_;
    my $del = Net::Nostr::Deletion->from_event($del_event);
    my $del_pubkey = $del_event->pubkey;
    my $del_ts = $del_event->created_at;

    my @kept;
    for my $stored (@{$self->events}) {
        # Never delete other kind 5 events
        if ($stored->kind == 5) {
            push @kept, $stored;
            next;
        }
        # Check e tags: delete if pubkey matches and event is referenced
        my $dominated = 0;
        if ($stored->pubkey eq $del_pubkey) {
            for my $id (@{$del->event_ids}) {
                if ($stored->id eq $id) {
                    $dominated = 1;
                    last;
                }
            }
            # Check a tags: delete addressable events up to deletion timestamp
            if (!$dominated && $stored->is_addressable) {
                my $addr = $stored->kind . ':' . $stored->pubkey . ':' . $stored->d_tag;
                for my $del_addr (@{$del->addresses}) {
                    if ($addr eq $del_addr && $stored->created_at <= $del_ts) {
                        $dominated = 1;
                        last;
                    }
                }
            }
        }
        push @kept, $stored unless $dominated;
    }
    $self->events(\@kept);
}

sub _handle_auth {
    my ($self, $conn_id, $event) = @_;
    my $conn = $self->connections->{$conn_id};

    # Validate the event structure first
    my $error = $self->_validate_event($event);
    if ($error) {
        $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => ($event->id // ''), accepted => 0, message => $error)->serialize);
        return;
    }

    # Kind must be 22242
    unless ($event->kind == 22242) {
        $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 0, message => 'invalid: auth event must be kind 22242')->serialize);
        return;
    }

    # created_at must be within ~10 minutes
    my $now = time();
    unless (abs($event->created_at - $now) <= 600) {
        $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 0, message => 'invalid: auth event timestamp too far from current time')->serialize);
        return;
    }

    # Relay tag must match (if relay_url is configured)
    if (defined $self->relay_url) {
        my $got_relay;
        for my $tag (@{$event->tags}) {
            if ($tag->[0] eq 'relay') {
                $got_relay = $tag->[1];
                last;
            }
        }
        unless (defined $got_relay && _relay_host_matches($self->relay_url, $got_relay)) {
            $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 0, message => 'invalid: relay URL does not match')->serialize);
            return;
        }
    }

    # Challenge tag must match
    my $expected_challenge = $self->_challenges->{$conn_id};
    my $got_challenge;
    for my $tag (@{$event->tags}) {
        if ($tag->[0] eq 'challenge') {
            $got_challenge = $tag->[1];
            last;
        }
    }
    unless (defined $got_challenge && $got_challenge eq $expected_challenge) {
        $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 0, message => 'invalid: challenge does not match')->serialize);
        return;
    }

    # Track the authenticated pubkey for this connection
    $self->_authenticated->{$conn_id}{$event->pubkey} = 1;

    $conn->send(Net::Nostr::Message->new(type => 'OK', event_id => $event->id, accepted => 1, message => '')->serialize);
}

sub _handle_req {
    my ($self, $conn_id, $sub_id, @filters) = @_;
    my $conn = $self->connections->{$conn_id};

    $self->subscriptions->{$conn_id} //= {};
    $self->subscriptions->{$conn_id}{$sub_id} = \@filters;

    # NIP-01: limit applies per filter, not globally.
    # Evaluate each filter independently, apply its own limit,
    # then union/dedupe across filters.
    my %seen;
    for my $filter (@filters) {
        my @matched;
        for my $event (@{$self->events}) {
            next if $event->is_expired;
            push @matched, $event if $filter->matches($event);
        }

        # sort by created_at DESC, then id ASC for ties
        @matched = sort {
            $b->created_at <=> $a->created_at || $a->id cmp $b->id
        } @matched;

        # apply this filter's limit
        if (defined $filter->limit) {
            splice @matched, $filter->limit if $filter->limit < @matched;
        }

        for my $event (@matched) {
            $seen{$event->id} //= $event;
        }
    }

    # deterministic emission order: created_at DESC, id ASC for ties
    my @results = sort {
        $b->created_at <=> $a->created_at || $a->id cmp $b->id
    } values %seen;

    for my $event (@results) {
        $conn->send(Net::Nostr::Message->new(type => 'EVENT', subscription_id => $sub_id, event => $event)->serialize);
    }

    $conn->send(Net::Nostr::Message->new(type => 'EOSE', subscription_id => $sub_id)->serialize);
}

sub _handle_count {
    my ($self, $conn_id, $sub_id, @filters) = @_;
    my $conn = $self->connections->{$conn_id};

    my $count = 0;
    for my $event (@{$self->events}) {
        next if $event->is_expired;
        $count++ if Net::Nostr::Filter->matches_any($event, @filters);
    }

    $conn->send(Net::Nostr::Message->new(
        type => 'COUNT', subscription_id => $sub_id, count => $count,
    )->serialize);
}

sub _handle_close {
    my ($self, $conn_id, $sub_id) = @_;
    delete $self->subscriptions->{$conn_id}{$sub_id} if $self->subscriptions->{$conn_id};
}

1;

__END__

=head1 NAME

Net::Nostr::Relay - Nostr WebSocket relay server

=head1 SYNOPSIS

    use Net::Nostr::Relay;

    # Standalone relay (blocks until stop is called)
    my $relay = Net::Nostr::Relay->new;
    $relay->run('127.0.0.1', 8080);

    # Non-blocking: run a relay and client together
    use Net::Nostr::Key;
    use Net::Nostr::Client;

    my $relay = Net::Nostr::Relay->new;
    $relay->start('127.0.0.1', 8080);

    my $key    = Net::Nostr::Key->new;
    my $client = Net::Nostr::Client->new;
    $client->connect('ws://127.0.0.1:8080');

    my $event = $key->create_event(kind => 1, content => 'hello', tags => []);
    $client->publish($event);

=head1 DESCRIPTION

An in-process Nostr relay. Accepts WebSocket connections, stores events in
memory, manages subscriptions, and broadcasts new events to matching
subscribers. Events do not persist across restarts.

Implements:

=over 4

=item * L<NIP-01|https://github.com/nostr-protocol/nips/blob/master/01.md> - Basic protocol flow

=item * L<NIP-09|https://github.com/nostr-protocol/nips/blob/master/09.md> - Event deletion requests

=item * L<NIP-11|https://github.com/nostr-protocol/nips/blob/master/11.md> - Relay information document

=item * L<NIP-13|https://github.com/nostr-protocol/nips/blob/master/13.md> - Proof of Work

=item * L<NIP-40|https://github.com/nostr-protocol/nips/blob/master/40.md> - Expiration timestamp

=item * L<NIP-42|https://github.com/nostr-protocol/nips/blob/master/42.md> - Authentication of clients to relays

=item * L<NIP-45|https://github.com/nostr-protocol/nips/blob/master/45.md> - Event counts (HyperLogLog not supported)

=back

Supports all NIP-01 event semantics:

=over 4

=item * Regular events - stored and broadcast

=item * Replaceable events (kinds 0, 3, 10000-19999) - only latest per pubkey+kind

=item * Ephemeral events (kinds 20000-29999) - broadcast but never stored

=item * Addressable events (kinds 30000-39999) - only latest per pubkey+kind+d_tag

=back

=head1 CONSTRUCTOR

=head2 new

    my $relay = Net::Nostr::Relay->new;
    my $relay = Net::Nostr::Relay->new(verify_signatures => 0);
    my $relay = Net::Nostr::Relay->new(max_connections_per_ip => 10);
    my $relay = Net::Nostr::Relay->new(relay_url => 'wss://relay.example.com/');
    my $relay = Net::Nostr::Relay->new(relay_info => $info);
    my $relay = Net::Nostr::Relay->new(min_pow_difficulty => 16);

Creates a new relay instance. Options:

=over 4

=item C<verify_signatures> - Enable Schnorr signature verification (default: true).
Pass C<0> to disable (useful for testing with synthetic events).

=item C<max_connections_per_ip> - Maximum simultaneous WebSocket connections
allowed from a single IP address. Connections beyond this limit are rejected
at the TCP level. Default: C<undef> (unlimited).

=item C<relay_url> - The relay's own WebSocket URL (e.g. C<wss://relay.example.com/>).
When set, NIP-42 AUTH events are validated to ensure the C<relay> tag matches
this URL (scheme, host, port, and path comparison; case-insensitive host).
Default: C<undef> (relay tag not validated).

=item C<min_pow_difficulty> - Minimum Proof of Work difficulty required for
events (NIP-13). Events must have a C<nonce> tag committing to at least this
difficulty, and the event ID must have at least this many leading zero bits.
Events without a difficulty commitment are also rejected. Default: C<undef>
(no PoW required).

    my $relay = Net::Nostr::Relay->new(min_pow_difficulty => 16);

=item C<relay_info> - A L<Net::Nostr::RelayInfo> object (NIP-11). When set, the
relay serves the information document in response to HTTP requests with
C<Accept: application/nostr+json>, and handles CORS preflight OPTIONS requests.
Default: C<undef> (NIP-11 disabled).

    use Net::Nostr::RelayInfo;

    my $relay = Net::Nostr::Relay->new(
        relay_info => Net::Nostr::RelayInfo->new(
            name           => 'My Relay',
            supported_nips => [1, 9, 11, 42],
            version        => '1.0.0',
        ),
    );

Croaks on unknown arguments.

=back

=head1 METHODS

=head2 run

    $relay->run('127.0.0.1', 8080);

Starts the relay and blocks until C<stop> is called. Equivalent to
calling C<start> followed by a blocking event loop.

=head2 start

    $relay->start('127.0.0.1', 8080);

Starts listening for WebSocket connections on the given host and port.
Returns immediately without blocking. Use this when you want to embed
the relay in a larger application, run a client and relay in the same
process, or compose with other AnyEvent watchers.

    # Run a relay and client together
    my $relay = Net::Nostr::Relay->new;
    $relay->start('127.0.0.1', 8080);

    my $client = Net::Nostr::Client->new;
    $client->connect('ws://127.0.0.1:8080');

=head2 stop

    $relay->stop;

Stops the relay, closes all connections, and clears all subscriptions.
If the relay was started with C<run>, also unblocks it.
Safe to call on an unstarted relay.

=head2 broadcast

    $relay->broadcast($event);

Sends the event to all connected clients whose subscriptions match.
Normally called internally when a new event is accepted, but can be
called directly for testing or custom event injection.

=head2 connections

    my $conns = $relay->connections;  # hashref

Returns the hashref of active connections.

=head2 subscriptions

    my $subs = $relay->subscriptions;  # hashref

Returns the hashref of active subscriptions, keyed by connection ID
then subscription ID.

=head2 events

    my $events = $relay->events;  # arrayref of Net::Nostr::Event

Returns the arrayref of stored events. This list is kept in memory only
and reflects replaceable/addressable semantics (only the latest version
of each replaceable or addressable event is retained). Ephemeral events
are never stored here.

=head2 verify_signatures

    my $bool = $relay->verify_signatures;

Returns whether Schnorr signature verification is enabled (default: true).

=head2 max_connections_per_ip

    my $limit = $relay->max_connections_per_ip;

Returns the maximum number of simultaneous connections allowed per IP
address, or C<undef> if unlimited (the default).

    my $relay = Net::Nostr::Relay->new(max_connections_per_ip => 10);
    $relay->start('0.0.0.0', 8080);

=head2 min_pow_difficulty

    my $min = $relay->min_pow_difficulty;

Returns the minimum Proof of Work difficulty required for events (NIP-13),
or C<undef> if not set (the default).

    my $relay = Net::Nostr::Relay->new(min_pow_difficulty => 16);
    $relay->start('0.0.0.0', 8080);

=head2 relay_url

    my $url = $relay->relay_url;

Returns the relay's own WebSocket URL, or C<undef> if not set.
Used for NIP-42 relay tag validation.

    my $relay = Net::Nostr::Relay->new(relay_url => 'wss://relay.example.com/');
    $relay->start('0.0.0.0', 8080);

=head2 relay_info

    my $info = $relay->relay_info;

Returns the L<Net::Nostr::RelayInfo> object (NIP-11), or C<undef> if not set.

    my $relay = Net::Nostr::Relay->new(
        relay_info => Net::Nostr::RelayInfo->new(name => 'My Relay'),
    );
    $relay->start('0.0.0.0', 8080);

    # Clients can now fetch: curl -H 'Accept: application/nostr+json' http://localhost:8080/

=head2 authenticated_pubkeys

    my $auth = $relay->authenticated_pubkeys;

Returns a hashref of authenticated pubkeys per connection (NIP-42).
Keys are connection IDs, values are hashrefs of pubkey hex strings.

    my $auth = $relay->authenticated_pubkeys;
    for my $conn_id (keys %$auth) {
        for my $pubkey (keys %{$auth->{$conn_id}}) {
            say "Connection $conn_id authenticated as $pubkey";
        }
    }

=head1 SEE ALSO

L<NIP-01|https://github.com/nostr-protocol/nips/blob/master/01.md>,
L<Net::Nostr>, L<Net::Nostr::Client>, L<Net::Nostr::Event>, L<Net::Nostr::RelayInfo>

=cut
