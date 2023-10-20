package Net::Nostr::Key;

use strictures 2;

use Net::Nostr::Event;

use Crypt::PK::ECC;
use Crypt::PK::ECC::Schnorr;

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class; # we can add more options later. For now its just 'privkey' and 'pubkey'
    $self->{_cryptpkecc} = Crypt::PK::ECC->new($self->{privkey} // $self->{pubkey} // ());
    delete @{$self}{qw(privkey pubkey)}; # keys are managed by Crypt::PK::ECC
    $self->_cryptpkecc->generate_key('secp256k1') unless $self->pubkey_loaded;
    return $self;
}

sub _cryptpkecc { shift->{_cryptpkecc} }

sub constructor_keys { qw(privkey pubkey) }

sub schnorr_sign { # TODO: test schnorr_sign()
    my ($self, $msg) = @_;
    my $sig = Crypt::PK::ECC::Schnorr->new(\$self->privkey_der)->sign_message($msg);
    return $sig;
}

sub privkey_loaded {
    my ($self) = @_;
    my $is_private = $self->_cryptpkecc->is_private;
    return 1 if $is_private;
    return 0;
}

sub pubkey_loaded {
    my ($self) = @_;
    my $is_private = $self->_cryptpkecc->is_private;
    return 1 if defined $is_private;
    return 0;
}

sub pubkey_der {
    my ($self) = @_;
    my $der = $self->_cryptpkecc->export_key_der('public');
    return $der;
}

sub privkey_der {
    my ($self) = @_;
    my $der = $self->_cryptpkecc->export_key_der('private');
    return $der;
}

sub pubkey_pem {
    my ($self) = @_;
    my $pem = $self->_cryptpkecc->export_key_pem('public');
    return $pem;
}

sub privkey_pem {
    my ($self) = @_;
    my $pem = $self->_cryptpkecc->export_key_pem('private');
    return $pem;
}

sub pubkey_raw {
    my ($self) = @_;
    my $raw = $self->_cryptpkecc->export_key_raw('public');
    return $raw;
}

sub privkey_raw {
    my ($self) = @_;
    my $raw = $self->_cryptpkecc->export_key_raw('private');
    return $raw;
}

sub pubkey_hex {
    my ($self) = @_;
    my $hex = sprintf '%x', $self->pubkey_raw;
    return $hex;
}

sub privkey_hex {
    my ($self) = @_;
    my $hex = sprintf '%x', $self->privkey_raw;
    return $hex;
}

1;

__END__
