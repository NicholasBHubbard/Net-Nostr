#!/usr/bin/perl

use strictures 2;

use Test2::V0 -no_srand => 1;
use Archive::Tar ();
use Config qw(%Config);
use Cwd qw(getcwd);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use JSON::PP ();
use Module::CoreList ();

my %expected_tests = (
    'Net-Nostr-Core'   => [qw(t/*.t t/nip/*.t)],
    'Net-Nostr-Client' => [qw(t/*.t)],
    'Net-Nostr-Relay'  => [qw(t/*.t t/nip/*.t)],
    'Net-Nostr'        => [qw(t/*.t t/nip/*.t)],
);

subtest 'dist Makefile.PL files run release tests and skip author tests' => sub {
    for my $dist (sort keys %expected_tests) {
        subtest $dist => sub {
            my $root = "dist/$dist";
            my $tmp = tempdir(CLEANUP => 1);

            _copy_file("$root/Makefile.PL", "$tmp/Makefile.PL");
            _copy_version_from_file($root, $tmp);
            make_path("$tmp/t/author");
            _write_test("$tmp/t/top.t");
            _write_test("$tmp/t/author/pod.t");

            if (grep { $_ eq 't/nip/*.t' } @{ $expected_tests{$dist} }) {
                make_path("$tmp/t/nip");
                _write_test("$tmp/t/nip/nested.t");
            }

            my ($output, $exit) = _run_in_dir($tmp, sub {
                my $output = `$^X Makefile.PL 2>&1`;
                return ($output, $? >> 8);
            });

            is($exit, 0, 'Makefile.PL exits cleanly') or diag $output;

            open my $fh, '<', "$tmp/Makefile" or die "open generated Makefile: $!";
            my $makefile = do { local $/; <$fh> };
            close $fh;

            my ($test_files) = $makefile =~ /^TEST_FILES\s*=\s*(.+)$/m;
            ok(defined $test_files, 'TEST_FILES is defined');

            for my $pattern (@{ $expected_tests{$dist} }) {
                my $quoted = quotemeta $pattern;
                like($test_files, qr/(?:^|\s)$quoted(?:\s|$)/, "$pattern included");
            }

            unlike(
                $test_files,
                qr/(?:^|\s)(?:t\/author\/\*\.t|t\/author\/pod\.t|t\/\*\/\*\.t)(?:\s|$)/,
                'author tests are excluded'
            );
        };
    }
};

subtest 'dist metadata does not list modules core in Perl 5.16' => sub {
    for my $dist (sort keys %expected_tests) {
        subtest $dist => sub {
            my $root = "dist/$dist";
            my $tmp = tempdir(CLEANUP => 1);

            _copy_file("$root/Makefile.PL", "$tmp/Makefile.PL");
            _copy_version_from_file($root, $tmp);

            my (
                $output, $exit, $manifest_output, $manifest_exit,
                $dist_output, $dist_exit, $tarball_count, @core_prereqs
            ) = _run_in_dir($tmp, sub {
                my $output = `$^X Makefile.PL 2>&1`;
                my $exit = $? >> 8;

                my $make = $Config{make} || 'make';
                my $manifest_output = `$make manifest 2>&1`;
                my $manifest_exit = $? >> 8;

                my $dist_output = `$make dist 2>&1`;
                my $dist_exit = $? >> 8;

                my @tarballs = glob('*.tar.gz');
                my @core_prereqs = @tarballs ? _core_prereqs_in_tarball($tarballs[0]) : ();
                return (
                    $output, $exit, $manifest_output, $manifest_exit,
                    $dist_output, $dist_exit, scalar @tarballs, @core_prereqs
                );
            });

            is($exit, 0, 'Makefile.PL exits cleanly') or diag $output;

            is($manifest_exit, 0, 'make manifest exits cleanly') or diag $manifest_output;

            is($dist_exit, 0, 'make dist exits cleanly') or diag $dist_output;

            is($tarball_count, 1, 'one tarball created');
            is(\@core_prereqs, [], 'META.json has no Perl 5.16 core module prereqs')
                or diag join "\n", @core_prereqs;
        };
    }
};

done_testing;

sub _copy_version_from_file {
    my ($root, $tmp) = @_;

    open my $fh, '<', "$root/Makefile.PL" or die "open $root/Makefile.PL: $!";
    my $source = do { local $/; <$fh> };
    close $fh;

    my ($version_from) = $source =~ /VERSION_FROM\s*=>\s*'([^']+)'/;
    die "$root/Makefile.PL missing VERSION_FROM" unless defined $version_from;

    my $src = "$root/$version_from";
    my $dst = "$tmp/$version_from";
    $dst =~ s{/[^/]+\z}{};
    make_path($dst);
    _copy_file($src, "$tmp/$version_from");
}

sub _copy_file {
    my ($src, $dst) = @_;
    my $dir = $dst;
    $dir =~ s{/[^/]+\z}{};
    make_path($dir) unless -d $dir;
    copy($src, $dst) or die "copy $src to $dst: $!";
}

sub _write_test {
    my ($path) = @_;
    open my $tfh, '>', $path or die "open $path: $!";
    print {$tfh} "use strictures 2;\nuse Test2::V0 -no_srand => 1;\nok 1;\ndone_testing;\n";
    close $tfh;
}

sub _run_in_dir {
    my ($dir, $code) = @_;
    my $cwd = getcwd();
    chdir $dir or die "chdir $dir: $!";

    my @result;
    my $ok = eval {
        @result = $code->();
        1;
    };
    my $error = $@;

    chdir $cwd or die "chdir $cwd: $!";
    die $error unless $ok;
    return @result;
}

sub _core_prereqs_in_tarball {
    my ($tarball) = @_;
    my $tar = Archive::Tar->new;
    $tar->read($tarball, 1) or die "read $tarball: " . $tar->error;
    my ($meta_file) = grep { m{^[^/]+/META\.json\z} } $tar->list_files;
    die "$tarball missing META.json" unless defined $meta_file;

    my $meta = JSON::PP::decode_json($tar->get_content($meta_file));
    my @core_prereqs;
    for my $phase (sort keys %{ $meta->{prereqs} || {} }) {
        for my $relationship (sort keys %{ $meta->{prereqs}{$phase} || {} }) {
            my $modules = $meta->{prereqs}{$phase}{$relationship};
            for my $module (sort keys %$modules) {
                next if $module eq 'perl';
                next unless _is_core_in_perl_516($module);
                push @core_prereqs, "$phase.$relationship:$module";
            }
        }
    }
    return @core_prereqs;
}

sub _is_core_in_perl_516 {
    my ($module) = @_;
    my $perl_516_core = $Module::CoreList::version{5.016}
        or die "Module::CoreList missing Perl 5.16 data";
    return exists $perl_516_core->{$module};
}
