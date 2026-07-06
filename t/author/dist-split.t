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
        ok(!-e "$root/cpanfile", "$dist does not have cpanfile");
        ok(!-e "$root/README.md", "$dist does not have README.md");
        ok(-e "$root/Changes", "$dist has Changes");

        for my $file (@{ $expected{$dist} }) {
            ok(-e "$root/$file", "$dist ships $file");
        }
    }
};

subtest 'legacy distribution root no longer owns shipped modules' => sub {
    ok(!-d 'lib/Net/Nostr', 'top-level lib/Net/Nostr moved into dist roots');
};

subtest 'distribution versions are self-consistent' => sub {
    # Each distribution's $VERSION must match the version of its most recent
    # Changes entry. This keeps code and changelog in step per distribution
    # without hardcoding version numbers here (which would force this test to
    # be edited on every release) and without requiring unrelated
    # distributions to share a version.
    my %main_module = (
        'Net-Nostr-Core'   => 'lib/Net/Nostr/Core.pm',
        'Net-Nostr-Client' => 'lib/Net/Nostr/Client.pm',
        'Net-Nostr-Relay'  => 'lib/Net/Nostr/Relay.pm',
        'Net-Nostr'        => 'lib/Net/Nostr.pm',
    );

    my %version_of;
    for my $dist (sort keys %main_module) {
        my $source = _slurp("dist/$dist/$main_module{$dist}");
        my ($version) = $source =~ /^our \$VERSION = '([^']+)';/m;
        ok(defined $version, "$dist declares a \$VERSION") or next;
        $version_of{$dist} = $version;

        my $changes = _slurp("dist/$dist/Changes");
        my ($top) = $changes =~ /\A(\S+)\s+\d{4}-\d{2}-\d{2}/;
        ok(defined $top, "$dist Changes opens with a dated release entry") or next;
        is($version, $top,
            "$dist \$VERSION ($version) matches its latest Changes entry ($top)");
    }

    # The shim keeps its own 2.x version line; the split-out distributions
    # stay on the 1.x line. This guards against version/Changes
    # cross-contamination from the original split, not against independent
    # per-distribution version bumps.
    like($version_of{'Net-Nostr'} // '', qr/\A2\./, 'shim keeps its 2.x version line');
    for my $dist (qw(Net-Nostr-Core Net-Nostr-Client Net-Nostr-Relay)) {
        like($version_of{$dist} // '', qr/\A1\./, "$dist keeps its 1.x version line");
        unlike(_slurp("dist/$dist/Changes"), qr/^2\.\d+/m,
            "$dist Changes does not carry Net-Nostr 2.x release entries");
    }

    my %intra_distribution_dependencies = (
        'Net-Nostr-Client/Makefile.PL' => [qw(Net::Nostr::Core)],
        'Net-Nostr-Relay/Makefile.PL'  => [qw(Net::Nostr::Core)],
        'Net-Nostr/Makefile.PL'        => [qw(Net::Nostr::Core Net::Nostr::Client Net::Nostr::Relay)],
    );

    for my $path (sort keys %intra_distribution_dependencies) {
        my $source = _slurp("dist/$path");
        for my $module (@{ $intra_distribution_dependencies{$path} }) {
            like(
                $source,
                qr/'\Q$module\E'\s*=>\s*0\b/,
                "$path leaves $module unversioned"
            );
            unlike(
                $source,
                qr/'\Q$module\E'\s*=>\s*['"]?[1-9]/,
                "$path does not set a version floor for $module"
            );
        }
    }
};

subtest 'NIP-05 HTTP dependency is optional in Core and required by shim' => sub {
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

    my $shim_makefile = _slurp('dist/Net-Nostr/Makefile.PL');
    like(
        $shim_makefile,
        qr/'AnyEvent::HTTP'\s*=>\s*0/,
        'shim Makefile.PL requires AnyEvent::HTTP'
    );
};

subtest 'Makefile.PL is dependency source of truth' => sub {
    for my $dist (sort keys %expected) {
        my $root = "dist/$dist";
        ok(!-e "$root/cpanfile", "$dist has no cpanfile");

        my $manifest_skip = _slurp("$root/MANIFEST.SKIP");
        unlike($manifest_skip, qr/cpanfile/, "$dist MANIFEST.SKIP does not allow cpanfile");
        unlike($manifest_skip, qr/README\\\.md|README\.md/, "$dist MANIFEST.SKIP does not allow README.md");
    }

    my $workflow = _slurp('.github/workflows/test.yml');
    unlike($workflow, qr/cpanfile/, 'CI does not reference cpanfile');
    like(
        $workflow,
        qr/hashFiles\('dist\/\*\/Makefile\.PL', '\.github\/workflows\/test\.yml'\)/,
        'CI cache key tracks Makefile.PL files'
    );
    for my $dist (sort keys %expected) {
        like(
            $workflow,
            qr/cpanm --local-lib ~\/perl5 --installdeps \.\/dist\/\Q$dist\E/,
            "CI installs $dist dependencies from a local path"
        );
        unlike(
            $workflow,
            qr/cpanm --local-lib ~\/perl5 --installdeps dist\/\Q$dist\E/,
            "CI does not ask cpanm to resolve $dist as a CPAN target"
        );
    }

    my $agents = _slurp('AGENTS.md');
    unlike($agents, qr/cpanfile/, 'AGENTS.md does not document cpanfile usage');
    like(
        $agents,
        qr/Dependencies are managed in each distribution's C<Makefile\.PL>|Dependencies are managed in each distribution's `Makefile\.PL`/,
        'AGENTS.md documents Makefile.PL as dependency source'
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

subtest 'unrecommended NIPs removed from supported surface' => sub {
    my @removed_nips = qw(NIP-15 NIP-28 NIP-72 NIP-90);
    my @removed_files = qw(
        dist/Net-Nostr-Core/lib/Net/Nostr/Marketplace.pm
        dist/Net-Nostr-Core/lib/Net/Nostr/Channel.pm
        dist/Net-Nostr-Core/lib/Net/Nostr/Community.pm
        dist/Net-Nostr-Core/lib/Net/Nostr/DVM.pm
        dist/Net-Nostr-Core/t/25-Marketplace.t
        dist/Net-Nostr-Core/t/29-Community.t
        dist/Net-Nostr-Core/t/36-Channel.t
        dist/Net-Nostr-Core/t/56-DVM.t
        dist/Net-Nostr-Core/t/nip/15.t
        dist/Net-Nostr-Core/t/nip/28.t
        dist/Net-Nostr-Core/t/nip/72.t
        dist/Net-Nostr-Core/t/nip/90.t
    );
    my @removed_modules = qw(
        Net::Nostr::Marketplace
        Net::Nostr::Channel
        Net::Nostr::Community
        Net::Nostr::DVM
    );

    ok(!-e $_, "$_ removed") for @removed_files;

    for my $doc (qw(README.md dist/Net-Nostr/lib/Net/Nostr.pm)) {
        my $source = _slurp($doc);
        unlike($source, qr/\Q$_\E/, "$doc does not list $_") for @removed_nips;
        unlike($source, qr/\Q$_\E/, "$doc does not list $_") for @removed_modules;
    }
};

subtest 'supported NIP lists match conformance tests' => sub {
    my @expected = _supported_nips_from_conformance_tests();

    is(
        [_readme_supported_nips('README.md')],
        \@expected,
        'README.md supported NIP list matches conformance tests'
    );
    is(
        [_pod_supported_nips('dist/Net-Nostr/lib/Net/Nostr.pm')],
        \@expected,
        'Net::Nostr POD supported NIP list matches conformance tests'
    );
};

subtest 'NIP conformance target is documented in public entry points' => sub {
    my $target = '8f8444d05a8842c40211ded5d10af3521541f865';
    for my $doc (
        qw(
            README.md
            dist/Net-Nostr-Core/lib/Net/Nostr/Core.pm
            dist/Net-Nostr/lib/Net/Nostr.pm
        )
    ) {
        my $source = _slurp($doc);
        like($source, qr/nostr-protocol\/nips/, "$doc names the NIP repository");
        like($source, qr/\Q$target\E/, "$doc documents the exact NIP commit");
    }
};

subtest 'docs do not explain historical Core module naming' => sub {
    for my $doc (
        qw(
            README.md
            AGENTS.md
            dist/Net-Nostr-Core/lib/Net/Nostr/Core.pm
            dist/Net-Nostr/lib/Net/Nostr.pm
        )
    ) {
        my $source = _slurp($doc);
        unlike($source, qr/Net::Nostr::Core::\*/, "$doc does not mention Net::Nostr::Core::*");
        unlike($source, qr/not renamed under/i, "$doc does not explain modules were not renamed");
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

sub _supported_nips_from_conformance_tests {
    my %seen;
    for my $path (glob 'dist/*/t/nip/*.t') {
        $path =~ m{/([^/]+)\.t\z} or next;
        $seen{$1} = 1;
    }
    return _sort_nips(keys %seen);
}

sub _readme_supported_nips {
    my ($file) = @_;
    my $source = _slurp($file);
    return _sort_nips($source =~ /^- \[NIP-([0-9A-Z]+)\]/mg);
}

sub _pod_supported_nips {
    my ($file) = @_;
    my $source = _slurp($file);
    return _sort_nips($source =~ /^=item L<NIP-([0-9A-Z]+)\|/mg);
}

sub _sort_nips {
    return sort {
        _nip_sort_key($a) cmp _nip_sort_key($b)
    } @_;
}

sub _nip_sort_key {
    my ($nip) = @_;
    return sprintf 'B%04d', substr($nip, 1) if $nip =~ /^B[0-9]+\z/;
    return sprintf 'A%04d', $nip;
}
