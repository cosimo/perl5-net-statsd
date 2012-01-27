#!/usr/bin/perl

=head1 NAME

t/rt-74172.t - Net::Statsd test suite

=head1 DESCRIPTION

C<$sample_rate> must default to 1, to avoid undefined value errors.

=cut

# Poor man's Test::NoWarnings
BEGIN {
    @main::__warnings = ();
    *CORE::GLOBAL::warn = sub { push @main::__warnings, [ @_ ]; CORE::warn(@_); };
}

use strict;
use warnings;
use Test::More tests => 5;
use Net::Statsd;

ok 1, "Net::Statsd module loaded";

my $data = {
    logins => "128|c",
    signups => "22|c",
};

my $sampled_data = Net::Statsd::_sample_data($data);
is_deeply $sampled_data => $data,
    'RT#74172 regression: no sample_rate makes sampled data same as input data';

$sampled_data = Net::Statsd::_sample_data($data, 1);
is_deeply $sampled_data => $data,
    'Sample rate of 1 is analogous to the no sample rate case';

my $samples = 0;
my $tries = 10000;
my $sample_rate = 0.5;
for (1 .. $tries) {
    if (keys(%{Net::Statsd::_sample_data($data, $sample_rate)})) {
        $samples++;
    }
}

# Probabilities... :-)
my $avg_result = $tries * $sample_rate;
ok abs($samples - $avg_result) < ($avg_result / 2),
    "Got $samples samples out of $tries tries. Sampling seems to work :)";

is_deeply \@main::__warnings, [],
    'No warnings should have been generated';
