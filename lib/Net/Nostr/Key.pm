package Net::Nostr::Key;

use strictures 2;

use Net::Nostr::Event;

use Crypt::PK::ECC;
use Crypt::PK::ECC::Schnorr;
use Bitcoin::Crypto::Bech32 qw(encode_bech32);

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
    my $hex = pack 'H*', $self->pubkey_raw;
    return $hex;
}

sub privkey_hex {
    my ($self) = @_;
    my $hex = pack 'H*', $self->privkey_raw;
    return $hex;
}

sub pubkey_bech32 {
    my ($self) = @_;
    my $pubkey_bech32 = encode_bech32($self->pubkey_hex);
    return $pubkey_bech32;
}

sub privkey_bech32 {
    my ($self) = @_;
    my $privkey_bech32 = encode_bech32($self->privkey_hex);
    return $privkey_bech32;
}

1;

__END__
