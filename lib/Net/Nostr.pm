package Net::Nostr;

use strictures 2;

use Net::Nostr::Key;
use Net::Nostr::Event;

use Crypt::PK::ECC::Schnorr;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->{_key} = Net::Nostr::Key->new(@_);
    return $self;
}

sub key { shift->{_key} }

sub sign_event {
    my ($self, $event) = @_;
    my $sig = $self->key->schnorr_sign($event->id);
    $event->set_sig($sig);
    return $sig;
}

1;
