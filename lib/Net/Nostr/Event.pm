package Net::Nostr::Event;

use strictures 2;

use JSON;
use Digest::SHA qw(sha256_hex);
use Crypt::PK::ECC::Schnorr;

use Class::Tiny qw(
    id
    pubkey
    created_at
    kind
    tags
    content
    sig
);

sub new { # pubkey, kind, content, and sig are required
    my $class = shift;
    my $self = bless { @_ }, $class;
    $self->created_at(time())  unless defined $self->created_at;
    $self->tags([])            unless $self->tags;
    $self->id($self->_calc_id) unless $self->id;
    return $self;
}

sub json_serialize {
    my ($self) = @_;
    my $json_serialized = JSON->new->utf8->encode([ # see how Perl is converted to JSON - https://metacpan.org/pod/JSON#PERL-%3E-JSON
        0,
        $self->pubkey . '',
        $self->created_at + 0,
        $self->kind + 0,
        $self->tags,
        $self->content . ''
    ]);
    return $json_serialized;
}

sub add_pubkey_ref {
    my ($self, $pubkey) = @_;
    $self->tags([@{$self->tags}, ['p', $pubkey]]);
}

sub add_event_ref {
    my ($self, $event_id) = @_;
    $self->tags([@{$self->tags}, ['e', $event_id]]);
}

sub to_hash {
    my ($self) = @_;
    return {
        id         => $self->id,
        pubkey     => $self->pubkey,
        created_at => $self->created_at,
        kind       => $self->kind,
        tags       => $self->tags,
        content    => $self->content,
        sig        => $self->sig,
    };
}

sub is_regular {
    my $k = shift->kind;
    return ($k == 1 || $k == 2 || ($k >= 4 && $k < 45) || ($k >= 1000 && $k < 10000));
}

sub is_replaceable {
    my $k = shift->kind;
    return ($k == 0 || $k == 3 || ($k >= 10000 && $k < 20000));
}

sub is_ephemeral {
    my $k = shift->kind;
    return ($k >= 20000 && $k < 30000);
}

sub is_addressable {
    my $k = shift->kind;
    return ($k >= 30000 && $k < 40000);
}

sub verify_sig {
    my ($self, $key) = @_;
    my $sig_raw = pack 'H*', $self->sig;
    my $verifier = Crypt::PK::ECC::Schnorr->new(\$key->pubkey_der);
    return $verifier->verify_message($self->id, $sig_raw);
}

sub _calc_id {
    my ($self) = @_;
    my $id = sha256_hex($self->json_serialize);
    return $id;
}

1;

__END__
