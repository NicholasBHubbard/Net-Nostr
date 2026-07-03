package Net::Nostr::Core;

use strictures 2;

our $VERSION = '1.001000';

1;

__END__

=head1 NAME

Net::Nostr::Core - Core Perl tooling for the Nostr protocol

=head1 SYNOPSIS

    use Net::Nostr::Event;
    use Net::Nostr::Key;
    use Net::Nostr::Message;

    my $key = Net::Nostr::Key->new;
    my $event = Net::Nostr::Event->new(
        pubkey  => $key->pubkey_hex,
        kind    => 1,
        content => 'hello',
    );

    $key->sign_event($event);

=head1 DESCRIPTION

Net::Nostr::Core is the distribution that provides the protocol and NIP
tooling used by the Nostr client and relay distributions. It intentionally
keeps the long-standing public module names such as L<Net::Nostr::Event>,
L<Net::Nostr::Key>, L<Net::Nostr::Filter>, and L<Net::Nostr::Message>; those
modules are not renamed under C<Net::Nostr::Core::*>.

Install L<Net::Nostr::Client> for a WebSocket relay client, L<Net::Nostr::Relay>
for a relay server, or L<Net::Nostr> for the compatibility shim that installs
both.

=head1 OPTIONAL DEPENDENCIES

L<Net::Nostr::Identifier> includes pure NIP-05 helpers that work with only this
distribution installed. Its network methods, C<lookup> and C<verify>, require
L<AnyEvent::HTTP> and load it only when those methods are called.

C<AnyEvent::HTTP> is declared as a recommended dependency for this distribution
instead of a hard requirement. Installing the L<Net::Nostr> shim distribution
pulls it in as a hard dependency for users who want the historical full-stack
install.

=head1 SEE ALSO

L<Net::Nostr>, L<Net::Nostr::Client>, L<Net::Nostr::Relay>,
L<NIP-01|https://github.com/nostr-protocol/nips/blob/master/01.md>

=cut
