#!/usr/bin/perl
# Perl JSON benchmark: perl bench.pl <cpanel|jsonxs|jsonpp> <input> <min-samples>
#   cpanel - Cpanel::JSON::XS->new->utf8->decode (what decode_json does) into Perl hashes, arrays and
#            scalars; built by ../build.sh perl into perl/local.
#   jsonxs - JSON::XS->new->utf8->decode, likewise.
#   jsonpp - JSON::PP->new->utf8->decode, the pure-Perl module that comes with Perl.
# All three decode UTF-8 bytes. A .ndjson input is a batch: its lines are split before timing and each
# is parsed as its own document; one operation parses every line once. Prints the check line (see
# ../reference.py) first; exits 1 on a parse error. Timings follow the shared rule (see measure and
# ../run.sh), timed with Time::HiRes's CLOCK_MONOTONIC.
use strict;
use warnings;
no warnings 'recursion';
use B ();
use FindBin ();
use lib "$FindBin::Bin/local/lib/perl5";
use Time::HiRes qw(clock_gettime CLOCK_MONOTONIC);

sub now_ns { return clock_gettime(CLOCK_MONOTONIC) * 1e9 }

sub measure {
	my ($min_samples, $op) = @_;
	my $warm = now_ns();
	do { $op->() } while (now_ns() - $warm < 1e9);
	my $start = now_ns();
	my @samples;
	while (1) {
		my $t0 = now_ns();
		$op->();
		push @samples, now_ns() - $t0;
		my @sorted = sort { $a <=> $b } @samples;
		my $n = @sorted;
		my $median = $n % 2 ? $sorted[$n >> 1] : ($sorted[$n / 2 - 1] + $sorted[$n / 2]) / 2;
		if ($n >= $min_samples) {
			my $within = grep { $_ >= $median * 0.9 && $_ <= $median * 1.1 } @samples;
			return ($median, $n, 1) if $within >= 0.6 * $n;
		}
		return ($median, $n, 0) if $n >= 1000 || now_ns() - $start >= 10e9;
	}
}

# objects arrays keys strings numbers true false null chars, then the numsum as two 32-bit halves
# (summed separately so nothing overflows; combined modulo 2^64 when printed)
my @c = (0) x 11;

sub add_number {
	my $u = unpack('Q<', pack('d<', $_[0] + 0.0));
	$c[9] += $u & 0xFFFFFFFF;
	$c[10] += $u >> 32;
}

sub walk {
	my ($v) = @_;
	if (!defined $v) {
		$c[7]++;
	} elsif (ref $v eq 'HASH') {
		$c[0]++;
		while (my ($k, $x) = each %$v) {
			$c[2]++;
			$c[8] += length $k;
			walk($x);
		}
	} elsif (ref $v eq 'ARRAY') {
		$c[1]++;
		walk($_) for @$v;
	} elsif (ref $v) { # a boolean object (JSON::PP::Boolean, Types::Serialiser)
		$v ? $c[5]++ : $c[6]++;
	} elsif (B::svref_2object(\$v)->FLAGS & (B::SVf_IOK | B::SVf_NOK)) {
		$c[4]++;
		add_number($v);
	} else {
		$c[3]++;
		$c[8] += length $v;
	}
}

my ($variant, $path, $min) = @ARGV;
my %modules = (cpanel => 'Cpanel::JSON::XS', jsonxs => 'JSON::XS', jsonpp => 'JSON::PP');
if (!defined $min || !$modules{$variant}) {
	print STDERR "usage: bench.pl <cpanel|jsonxs|jsonpp> <input> <min-samples>\n";
	exit 2;
}
my $module = $modules{$variant};
eval "require $module" or die $@;
my $json = $module->new->utf8;

open my $fh, '<:raw', $path or die "cannot open $path\n";
my $data = do { local $/; <$fh> };
close $fh;
my $total = length $data;
my @docs = $path =~ /\.ndjson$/ ? grep { /\S/ } split /\n/, $data : ($data);

for my $d (@docs) {
	my $v = eval { $json->decode($d) };
	if ($@) {
		print STDERR "parse error: $@";
		exit 1;
	}
	walk($v);
}
my $lo = $c[9] & 0xFFFFFFFF;
my $hi = ($c[10] + ($c[9] >> 32)) & 0xFFFFFFFF;
printf "check: %s %08x%08x\n", join(' ', @c[0 .. 8]), $hi, $lo;
$| = 1;

my ($median, $n, $converged) = measure($min, sub { $json->decode($_) for @docs });
my $ms = $median / 1e6;
printf "%.3f ms/op %.1f MB/s (n=%d, %s)\n", $ms, $total / 1048576 / ($ms / 1000), $n, $converged ? 'converged' : 'capped';
