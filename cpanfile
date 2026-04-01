requires 'strictures';
requires 'AnyEvent::WebSocket::Client';
requires 'AnyEvent::WebSocket::Server';
requires 'AnyEvent::Socket';
requires 'Crypt::PK::ECC';
requires 'Crypt::PK::ECC::Schnorr';
requires 'JSON';
requires 'Class::Tiny';

on 'test' => sub {
    requires 'Test2::V0';
    requires 'Test::Pod';
    requires 'Clone';
};
