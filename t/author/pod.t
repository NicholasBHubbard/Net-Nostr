#!/usr/bin/perl

use strictures 2;

use lib glob('dist/*/lib');

use Test2::V0 -no_srand => 1;
use Test::Pod;
use Test::Pod::Coverage;
use File::Find qw(find);

subtest 'pod syntax' => sub {
    my @files = grep { !_is_internal_path($_) } _pod_files();
    all_pod_files_ok(@files);
};

subtest 'pod coverage' => sub {
    my @modules = grep { !_is_internal_module($_) } _modules();
    pod_coverage_ok($_) for sort @modules;
    done_testing;
};

sub _is_internal_path {
    my ($path) = @_;
    return $path =~ m{/(?:_[^/]+)\.pm\z};
}

sub _is_internal_module {
    my ($module) = @_;
    return $module =~ /::_/;
}

sub _pod_files {
    my @files;
    find(
        sub {
            return unless -f $_ && /\.p(?:m|od)\z/;
            push @files, $File::Find::name;
        },
        sort glob('dist/*/lib'),
    );
    return @files;
}

sub _modules {
    my @modules;
    for my $file (_pod_files()) {
        next unless $file =~ m{^dist/[^/]+/lib/(.+)\.pm\z};
        my $module = $1;
        $module =~ s{/}{::}g;
        push @modules, $module;
    }
    return @modules;
}

done_testing;
