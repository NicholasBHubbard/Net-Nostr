requires 'strictures';
requires 'AnyEvent';
requires 'AnyEvent::WebSocket::Client';
requires 'AnyEvent::WebSocket::Server';
requires 'AnyEvent::HTTP';
requires 'CryptX';
requires 'Crypt::PK::ECC::Schnorr';
requires 'Crypt::ScryptKDF';
requires 'JSON';
requires 'Class::Tiny';
requires 'Bitcoin::Crypto';
requires 'Bitcoin::BIP39';

on 'test' => sub {
    requires 'Test2::V0';
    requires 'Test::Pod';
    requires 'Test::Pod::Coverage';
    requires 'Clone';
    requires 'IO::Socket::SSL';
};
