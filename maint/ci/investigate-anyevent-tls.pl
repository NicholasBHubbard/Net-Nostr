use strict;
use warnings;
use Cwd qw(getcwd);
use File::Glob qw(bsd_glob);
use File::Copy qw(move);
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
);

my %sources;
my @files;
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
    $sources{$name} = $source;
    my $file = "t/investigation-$name.t";
    push @files, $file;
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

my $trace = <<'TRACE';
my $trace_mode;
my %tls_trace;
Net::SSLeay::CTX_set_min_proto_version($ctx->{ctx}, Net::SSLeay::TLS1_3_VERSION())
   or die "set TLS 1.3 minimum failed";
Net::SSLeay::CTX_set_max_proto_version($ctx->{ctx}, Net::SSLeay::TLS1_3_VERSION())
   or die "set TLS 1.3 maximum failed";
Net::SSLeay::CTX_set_num_tickets($ctx->{ctx}, 2) or die "set tickets failed";
Net::SSLeay::CTX_set_msg_callback($ctx->{ctx}, sub {
   my ($write, $version, $type, $buf, $len, $ssl) = @_;
   return unless $trace_mode == 1;
   if ($type == 22 && unpack('C', $buf) == 4) {
      ++$tls_trace{$write ? 'ticket_write' : 'ticket_read'};
      $tls_trace{protocol} = Net::SSLeay::get_version($ssl);
   }
   if ($type == 21 && (unpack('CC', $buf))[1] == 0) {
      ++$tls_trace{$write ? 'close_notify_write' : 'close_notify_read'};
   }
});
my $original_error = AnyEvent::Handle->can('_error');
{
   no warnings 'redefine';
   *AnyEvent::Handle::_error = sub {
      if ($trace_mode == 1) {
         my (undef, $file, $line) = caller;
         $tls_trace{error_origin} = "$file:$line";
         $tls_trace{error_number} = 0 + $_[1];
      }
      goto &$original_error;
   };
}
TRACE
my $assertions = <<'ASSERTIONS';
is($tls_trace{protocol}, 'TLSv1.3', 'mode 1 uses TLS 1.3');
cmp_ok($tls_trace{ticket_write} || 0, '>=', 2, 'mode 1 sends session tickets');
cmp_ok($tls_trace{close_notify_write} || 0, '>=', 1, 'mode 1 sends close_notify');
cmp_ok($tls_trace{close_notify_read} || 0, '>=', 1, 'mode 1 receives close_notify');
ASSERTIONS
for my $name (qw(baseline stoptls-drop)) {
    my $source = $sources{$name};
    $source =~ s/^(my \$ctx = new AnyEvent::TLS cert_file => \$0;)$/$1\n$trace/m
        or die "TLS context not found\n";
    $source =~ s/(for my \$mode \(1\.\.5\) \{)/$1\n   \$trace_mode = \$mode;/
        or die "Mode loop not found\n";
    my $after = 'diag(JSON::PP->new->canonical->encode(\%tls_trace));' . "\n";
    if ($name eq 'stoptls-drop') {
        $source =~ s/tests => 415/tests => 419/ or die "Trace plan not found\n";
        $after .= $assertions;
    }
    $source =~ s/^__END__$/use JSON::PP ();\n$after\n__END__/m
        or die "End marker not found\n";
    my $file = "t/investigation-trace-$name.t";
    push @files, $file;
    open my $output, '>', $file or die "write trace: $!";
    print {$output} $source;
    close $output or die "close trace: $!";
    system($^X, '-S', 'prove', '-b', '-v', $file);
    push @results, {name => "trace-$name", status => $?};
}

# Preserve variants outside t/ so the original full suite runs only once.
mkdir "$workspace/tls-variants" or die "mkdir variants: $!";
for my $file (@files) {
    (my $name = $file) =~ s{^t/}{};
    move($file, "$workspace/tls-variants/$name") or die "preserve variant: $!";
}
open my $patched, '>', 't/80_ssltest.t' or die "write patched test: $!";
print {$patched} $sources{'stoptls-drop'};
close $patched or die "close patched test: $!";
system($^X, '-S', 'cpanm', '--local-lib', "$workspace/local", '--reinstall', '.');
push @results, {name => 'patched-full-suite-and-install', status => $?};

open my $results, '>', "$workspace/anyevent-tls-results.json" or die "write results: $!";
print {$results} JSON::PP->new->pretty->canonical->encode(\@results);
close $results or die "close results: $!";
exit((grep { $_->{name} !~ /^(?:original-full-suite|baseline|trace-baseline)$/ && $_->{status} != 0 } @results) ? 1 : 0);
