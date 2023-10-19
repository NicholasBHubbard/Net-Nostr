package Net::Nostr::Event;

use strictures 2;

use JSON;
use Digest::SHA qw(sha256_hex);

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
    $self->created_at(time())  unless $self->created_at;
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
        [ map { $_ . '' } @{$self->tags} ],
        $self->content . ''
    ]);
    return $json_serialized;
}

sub add_pubkey_ref {
    my ($self, $pubkey) = @_;
    $self->tags([$self->tags, ['p', $pubkey]]);
}

sub add_event_ref {
    my ($self, $event_id) = @_;
    $self->tags([$self->tags, ['e', $event_id]]);
}

sub _calc_id {
    my ($self) = @_;
    my $id = sha256_hex($self->json_serialize);
    return $id;
}

1;

__END__
