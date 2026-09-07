use strict;
use warnings;
use Cwd qw(getcwd);
use File::Glob qw(bsd_glob);
use JSON::PP ();
use Net::SSLeay ();

$| = 1;
my $workspace = getcwd();
print "Perl=$] OS=$^O Net::SSLeay=$Net::SSLeay::VERSION ",
    Net::SSLeay::SSLeay_version(0), "\n";
system($^X, '-S', 'cpanm', '--local-lib', 'local', '--test-only',
    'https://www.cpan.org/authors/id/M/ML/MLEHMANN/AnyEvent-7.17.tar.gz');
my @results = ({name => 'original-full-suite', status => $?});

my @dirs = bsd_glob("$ENV{PERL_CPANM_HOME}/work/*/AnyEvent-7.17");
@dirs == 1 or die "Expected one AnyEvent directory, found @dirs\n";
chdir $dirs[0] or die "chdir: $!";
open my $input, '<', 't/80_ssltest.t' or die "open original: $!";
my $original = do { local $/; <$input> };
close $input or die "close original: $!";

my $drain = <<'DRAIN';
   if ($mode == 1) {
      $hd->push_write ("1\n");
      $hd->on_drain (sub {
         ok (1, "client_drain");
         $client_done->send; undef $hd;
      });
DRAIN

my @variants = (
    ['baseline', undef, 415],
    ['stoptls-drop', <<'CLOSE', 415],
         $_[0]->on_drain (undef);
         $_[0]->stoptls;
         $client_done->send; undef $hd;
CLOSE
    ['tcp-half-close', <<'CLOSE', 416],
         $_[0]->push_shutdown;
CLOSE
    ['stoptls-wait', <<'CLOSE', 416],
         $_[0]->on_drain (undef);
         $_[0]->stoptls;
CLOSE
    ['stoptls-half-close', <<'CLOSE', 416],
         $_[0]->on_drain (undef);
         $_[0]->stoptls;
         $_[0]->push_shutdown;
CLOSE
);

for my $variant (@variants) {
    my ($name, $close, $count) = @$variant;
    my $source = $original;
    if (defined $close) {
        my $replacement = $drain;
        $replacement =~ s/^         \$client_done->send; undef \$hd;\n/$close/m
            or die "Close sequence not found\n";
        $source =~ s/\Q$drain\E/$replacement/ or die "Drain callback not found\n";
        $source =~ s/use Test::More tests => 415;/use Test::More tests => $count;/
            or die "Test plan not found\n";
    }
    my $file = "t/investigation-$name.t";
    open my $output, '>', $file or die "write variant: $!";
    print {$output} $source;
    close $output or die "close variant: $!";
    for my $iteration (1..3) {
        print "TLS variant=$name iteration=$iteration\n";
        system($^X, '-S', 'prove', '-b', '-v', $file);
        my $status = $?;
        print "TLS result=$name iteration=$iteration status=$status\n";
        push @results, {name => $name, iteration => $iteration, status => $status};
    }
}

open my $results, '>', "$workspace/anyevent-tls-results.json" or die "write results: $!";
print {$results} JSON::PP->new->pretty->canonical->encode(\@results);
close $results or die "close results: $!";
