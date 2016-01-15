#!perl

# PODNAME: benchmark.pl
# ABSTRACT: Report max send rate for Net::Statsd client

=head1 DESCRIPTION

A basic test of the time is takes to send stats through Net::Statsd.

=cut

use strict;
use warnings;

use Net::Statsd;
use Benchmark;
use Getopt::Long;

GetOptions(
    'host|h=s' => \($Net::Statsd::HOST = 'localhost'),
    'port|p=i' => \($Net::Statsd::PORT = 9), # port 9 is the standard discard service
) or exit 1;

my $count = shift || 10_000;

print "Using $INC{'Net/Statsd.pm'} sending to $Net::Statsd::HOST:$Net::Statsd::PORT\n";

timethese($count, {
    increment  => sub { Net::Statsd::increment('foo.bar.i') },
    decrement  => sub { Net::Statsd::increment('foo.bar.d') },
    timing_100 => sub { Net::Statsd::timing('foo.bar.t',   1) },
    timing_001 => sub { Net::Statsd::timing('foo.bar.t', 0.1) },
    gauge      => sub { Net::Statsd::gauge('foo.bar.g', 42) },
});
