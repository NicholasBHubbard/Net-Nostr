requires 'strictures';
requires 'AnyEvent';
requires 'AnyEvent::WebSocket::Client';
requires 'AnyEvent::WebSocket::Server';
requires 'AnyEvent::Socket';
requires 'AnyEvent::HTTP';
requires 'Crypt::KeyDerivation';
requires 'Crypt::Mac::HMAC';
requires 'Crypt::PK::ECC';
requires 'Crypt::PK::ECC::Schnorr';
requires 'Crypt::PRNG';
requires 'Crypt::Stream::ChaCha';
requires 'Digest::SHA';
requires 'JSON';
requires 'Class::Tiny';
requires 'Bitcoin::Crypto::Bech32';
requires 'Bitcoin::Crypto::Key::ExtPrivate';
requires 'Bitcoin::BIP39';

on 'test' => sub {
    requires 'Test2::V0';
    requires 'Test::Pod';
    requires 'Test::Pod::Coverage';
    requires 'Clone';
};
