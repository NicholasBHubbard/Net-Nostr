package Net::Nostr;

use strictures 2;

use Net::Nostr::Key;
use Net::Nostr::Event;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->{_constructor_args} = { @_ };
    $self->{_key} = Net::Nostr::Key->new($self->key_args);
    return $self;
}

sub key { shift->{_key} }

sub sign_event {
    my ($self, $event) = @_;
    my $sig_raw = $self->key->schnorr_sign($event->id);
    my $sig_hex = unpack 'H*', $sig_raw;
    $event->sig($sig_hex);
    return $sig_hex;
}

sub key_args {
    my ($self) = @_;
    my %args = %{ $self->{_constructor_args} };
    my %key_args;
    my @key_args = Net::Nostr::Key->constructor_keys;
    for my $k (keys %args) {
        $key_args{$k} = $args{$k} if grep { $_ eq $k } @key_args;
    }
    return %key_args;
}

1;
