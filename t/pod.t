#!/usr/bin/perl

use strictures 2;

use Test::More;
use Test::Pod;
use Test::Pod::Coverage;

subtest 'pod syntax' => sub {
    all_pod_files_ok();
};

subtest 'pod coverage' => sub {
    all_pod_coverage_ok();
};

done_testing;
