package Net::Nostr::_KeyFileWin32;

use strictures 2;
use Carp qw(croak);
use Config qw(%Config);
use Symbol qw(gensym);
use Win32::API ();
use Win32API::File ();

# Win32::API's N is pointer-sized; I is always a 32-bit DWORD.
my $get_security = Win32::API::More->new('advapi32', 'GetSecurityInfo', 'NIIPPPPP', 'I')
    or croak "cannot load GetSecurityInfo: $^E";
my $set_security = Win32::API::More->new('advapi32', 'SetSecurityInfo', 'NIINNPN', 'I')
    or croak "cannot load SetSecurityInfo: $^E";
my $local_free = Win32::API::More->new('kernel32', 'LocalFree', 'N', 'N')
    or croak "cannot load LocalFree: $^E";

sub _open {
    my ($path) = @_;
    # OPEN_ALWAYS preserves contents until the handle's permissions are verified.
    # Share=0 also refuses files with an existing reader/writer, and prevents
    # readers from opening a newly created file before its inherited ACL is fixed.
    my $handle = Win32API::File::createFile($path, {
        Access => Win32API::File::GENERIC_WRITE() | 0x00020000 | 0x00040000,
        Create => Win32API::File::OPEN_ALWAYS(),
        Share => 0,
    }) or croak "cannot open $path exclusively: $^E";
    my $fh = gensym;
    unless (Win32API::File::OsFHandleOpen($fh, $handle, 'wb')) {
        my $error = "$!";
        Win32API::File::CloseHandle($handle);
        croak "cannot open Perl handle for $path: $error";
    }
    return $fh;
}

sub _restrict {
    my ($fh) = @_;
    my $handle = Win32API::File::GetOsFHandle($fh);
    my ($owner) = _security($handle);

    # ACL_REVISION=2, one ACCESS_ALLOWED_ACE (type=0, no inheritance),
    # FILE_ALL_ACCESS=0x1f01ff. The SID comes from this open file's owner.
    my $ace = pack('CCvV', 0, 0, 8 + length($owner), 0x1f01ff) . $owner;
    my $acl = pack('CCvvv', 2, 0, 8 + length($ace), 1, 0) . $ace;
    # SE_FILE_OBJECT=1; DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION.
    my $error = $set_security->Call($handle, 1, 0x80000004, 0, 0, $acl, 0);
    croak "cannot restrict private key file permissions: Windows error $error" if $error;

    my ($actual_owner, $actual_acl, $control) = _security($handle);
    croak "cannot verify private key file permissions"
        unless $actual_owner eq $owner && defined($actual_acl) && $actual_acl eq $acl
            && ($control & 0x1000); # SE_DACL_PROTECTED
    return 1;
}

sub _security {
    my ($handle) = @_;
    my ($owner_ptr, $acl_ptr, $sd_ptr) = map { "\0" x $Config{ptrsize} } 1..3;
    # OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION.
    my $error = $get_security->Call($handle, 1, 5, $owner_ptr, 0, $acl_ptr, 0, $sd_ptr);
    croak "cannot read private key file permissions: Windows error $error" if $error;
    my $sd_address = unpack('J', $sd_ptr);
    croak "missing private key file security descriptor" unless $sd_address;

    my @security;
    my $ok = eval {
        croak "missing private key file owner" unless unpack('J', $owner_ptr);
        # A SID has an 8-byte header followed by SubAuthorityCount DWORDs.
        my $sid_header = unpack('P8', $owner_ptr);
        my $sid_length = 8 + 4 * ord(substr($sid_header, 1, 1));
        my $owner = unpack("P$sid_length", $owner_ptr);
        my $acl;
        if (unpack('J', $acl_ptr)) {
            my $acl_length = unpack('x2v', unpack('P8', $acl_ptr));
            $acl = unpack("P$acl_length", $acl_ptr);
        }
        my $control = unpack('x2v', unpack('P4', $sd_ptr));
        @security = ($owner, $acl, $control);
        1;
    };
    my $exception = $@;
    $local_free->Call($sd_address);
    die $exception unless $ok;
    return @security;
}

1;

__END__

=head1 NAME

Net::Nostr::_KeyFileWin32 - Internal Windows private key file permissions

=head1 DESCRIPTION

Opens a file exclusively and applies a protected owner-only DACL through
the same native handle used to write it. This is an internal implementation
detail of L<Net::Nostr::Key/save_privkey>, not a public API.

=head1 SEE ALSO

L<Win32API::File>, L<Win32::API>,
L<GetSecurityInfo|https://learn.microsoft.com/en-us/windows/win32/api/aclapi/nf-aclapi-getsecurityinfo>,
L<SetSecurityInfo|https://learn.microsoft.com/en-us/windows/win32/api/aclapi/nf-aclapi-setsecurityinfo>

=cut
