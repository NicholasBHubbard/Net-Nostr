#!/usr/bin/perl

use strictures 2;

use Test2::V0 -no_srand => 1;

my %expected = (
    'Net-Nostr-Core' => [
        'lib/Net/Nostr/Core.pm',
        'lib/Net/Nostr/Event.pm',
        'lib/Net/Nostr/Identifier.pm',
        'lib/Net/Nostr/Message.pm',
    ],
    'Net-Nostr-Client' => [
        'lib/Net/Nostr/Client.pm',
    ],
    'Net-Nostr-Relay' => [
        'lib/Net/Nostr/Relay.pm',
        'lib/Net/Nostr/RelayStore.pm',
    ],
    'Net-Nostr' => [
        'lib/Net/Nostr.pm',
    ],
);

subtest 'distribution roots exist with expected modules' => sub {
    for my $dist (sort keys %expected) {
        my $root = "dist/$dist";
        ok(-d $root, "$dist root exists");
        ok(-e "$root/Makefile.PL", "$dist has Makefile.PL");
        ok(-e "$root/cpanfile", "$dist has cpanfile");
        ok(-e "$root/Changes", "$dist has Changes");

        for my $file (@{ $expected{$dist} }) {
            ok(-e "$root/$file", "$dist ships $file");
        }
    }
};

subtest 'legacy distribution root no longer owns shipped modules' => sub {
    ok(!-d 'lib/Net/Nostr', 'top-level lib/Net/Nostr moved into dist roots');
};

subtest 'distribution versions are aligned' => sub {
    my %versions = (
        'Net-Nostr-Core/lib/Net/Nostr/Core.pm'     => '1.001000',
        'Net-Nostr-Client/lib/Net/Nostr/Client.pm' => '1.001000',
        'Net-Nostr-Relay/lib/Net/Nostr/Relay.pm'   => '1.001000',
        'Net-Nostr/lib/Net/Nostr.pm'               => '2.002000',
    );

    for my $path (sort keys %versions) {
        my $source = _slurp("dist/$path");
        like(
            $source,
            qr/^our \$VERSION = '$versions{$path}';/m,
            "$path version is $versions{$path}"
        );
    }

    for my $dist (qw(Net-Nostr-Core Net-Nostr-Client Net-Nostr-Relay)) {
        my $changes = _slurp("dist/$dist/Changes");
        like($changes, qr/^1\.001000\s+2026-07-03/m, "$dist Changes starts at 1.001000");
        unlike($changes, qr/^2\.\d+/m, "$dist Changes does not carry Net-Nostr 2.x release entries");
    }

    my $shim_changes = _slurp('dist/Net-Nostr/Changes');
    like($shim_changes, qr/^2\.002000\s+2026-07-03/m, 'shim Changes stays at 2.002000');

    my %dependency_versions = (
        'Net-Nostr-Client/cpanfile'  => [qr/^requires 'Net::Nostr::Core', '1\.001000';/m],
        'Net-Nostr-Relay/cpanfile'   => [qr/^requires 'Net::Nostr::Core', '1\.001000';/m],
        'Net-Nostr/cpanfile'         => [
            qr/^requires 'Net::Nostr::Core', '1\.001000';/m,
            qr/^requires 'Net::Nostr::Client', '1\.001000';/m,
            qr/^requires 'Net::Nostr::Relay', '1\.001000';/m,
        ],
    );

    for my $path (sort keys %dependency_versions) {
        my $source = _slurp("dist/$path");
        like($source, $_, "$path dependency floor is 1.001000") for @{ $dependency_versions{$path} };
    }
};

subtest 'NIP-05 HTTP dependency is optional in Core and required by shim' => sub {
    my $core_cpanfile = _slurp('dist/Net-Nostr-Core/cpanfile');
    like(
        $core_cpanfile,
        qr/^recommends 'AnyEvent::HTTP';/m,
        'Core recommends AnyEvent::HTTP'
    );
    unlike(
        $core_cpanfile,
        qr/^requires 'AnyEvent::HTTP';/m,
        'Core does not require AnyEvent::HTTP'
    );

    my $core_makefile = _slurp('dist/Net-Nostr-Core/Makefile.PL');
    like(
        $core_makefile,
        qr/'meta-spec'\s*=>\s*\{\s*version\s*=>\s*2\s*\}/,
        'Core Makefile.PL emits CPAN Meta v2 metadata'
    );
    like(
        $core_makefile,
        qr/recommends\s*=>\s*\{\s*'AnyEvent::HTTP'\s*=>\s*0,\s*\}/s,
        'Core Makefile.PL recommends AnyEvent::HTTP'
    );
    my ($runtime_requires) = $core_makefile =~ /my %runtime_requires = \((.*?)\n\);/s;
    ok(defined $runtime_requires, 'Core Makefile.PL has a runtime requirements block');
    unlike(
        $runtime_requires,
        qr/'AnyEvent::HTTP'/,
        'Core Makefile.PL does not require AnyEvent::HTTP at runtime'
    );

    my $shim_cpanfile = _slurp('dist/Net-Nostr/cpanfile');
    like(
        $shim_cpanfile,
        qr/^requires 'AnyEvent::HTTP';/m,
        'shim requires AnyEvent::HTTP'
    );
};

subtest 'top-level module POD links related distributions' => sub {
    my %links = (
        'Net-Nostr-Core/lib/Net/Nostr/Core.pm' => [
            qw(Net::Nostr Net::Nostr::Client Net::Nostr::Relay)
        ],
        'Net-Nostr-Client/lib/Net/Nostr/Client.pm' => [
            qw(Net::Nostr Net::Nostr::Core Net::Nostr::Relay)
        ],
        'Net-Nostr-Relay/lib/Net/Nostr/Relay.pm' => [
            qw(Net::Nostr Net::Nostr::Core Net::Nostr::Client)
        ],
        'Net-Nostr/lib/Net/Nostr.pm' => [
            qw(Net::Nostr::Core Net::Nostr::Client Net::Nostr::Relay)
        ],
    );

    for my $path (sort keys %links) {
        my $source = _slurp("dist/$path");
        for my $module (@{ $links{$path} }) {
            like($source, qr/L<\Q$module\E>/, "$path links to $module");
        }
    }
};

done_testing;

sub _slurp {
    my ($file) = @_;
    open my $fh, '<', $file or die "open $file: $!";
    my $source = do { local $/; <$fh> };
    close $fh;
    return $source;
}
