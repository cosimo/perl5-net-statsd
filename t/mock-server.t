#!/usr/bin/perl

=head1 NAME

t/mock-server.t - Net::Statsd test suite

=head1 DESCRIPTION

These test verify basic operation of the statsd client
by validating the udp messages sent to a mock server

=cut

# Poor man's Test::NoWarnings
BEGIN {
    @main::__warnings = ();
    *CORE::GLOBAL::warn = sub { push @main::__warnings, [ @_ ]; CORE::warn(@_); };
}

use strict;
use warnings;
use Test::More tests => 10;
use Net::Statsd;

my $dirname;
BEGIN {
    use File::Spec;
    use File::Basename;
    $dirname = dirname(File::Spec->rel2abs(__FILE__));
}

use lib $dirname;
use MockServer;

note <<"DESCRIPTION";
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
These test verify basic operation of the statsd client
by validating the udp messages sent to a mock server
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
DESCRIPTION

$Net::Statsd::PORT = MockServer::start();
my $msgs;

Net::Statsd::timing('test.timer', 345);
$msgs = MockServer::get_and_reset_messages();
is_deeply($msgs, [ {
    key => 'test.timer',
    timers => [ 345 ],
    _raw_data => 'test.timer:345|ms'
} ], "Sent 1 timing event. Received correctly.");

Net::Statsd::increment('test.counter');
$msgs = MockServer::get_and_reset_messages();
is_deeply($msgs, [ {
    key => 'test.counter',
    counters => [ 1 ],
    _raw_data => 'test.counter:1|c'
} ], "Sent 1 counter event. Received correctly.");

Net::Statsd::increment('test.counter', 0.999999);
$msgs = MockServer::get_and_reset_messages();
is_deeply($msgs, [ {
    key => 'test.counter',
    counters => [ 1 ],
    sample_rate => 0.999999,
    _raw_data => 'test.counter:1|c|@0.999999'
} ], "Sent 1 counter even with sample_rate. Received it correctly.");

Net::Statsd::increment([qw(test.counter_1 test.counter_2)]);
$msgs = MockServer::get_and_reset_messages();

ok(ref $msgs eq 'ARRAY', 'Got back an array of messages');
is(scalar @{ $msgs } => 2, 'And the array holds 2 messages');

# Ignore those for is_deeply() comparison
delete $_->{_raw_data} for @{ $msgs };

# Prevent failures due to order of messages
$msgs = [ sort {$a->{key} cmp $b->{key}} @{$msgs} ];
is_deeply($msgs, [
    { key => 'test.counter_1', counters => [1] },
    { key => 'test.counter_2', counters => [1] },
], "Received back the two events");

Net::Statsd::gauge('oxygen.level', 0.98);
$msgs = MockServer::get_and_reset_messages();
ok(ref $msgs eq 'ARRAY');
is(scalar @{ $msgs } => 1);
is_deeply($msgs, [ {
    key => 'oxygen.level',
    gauges => [0.98],
    _raw_data => 'oxygen.level:0.98|g',
} ], "Gauge message was stored correctly");

note("The following test validates sent data");

my $tries = 10000;
my $sample_rate = 0.5;
my @messages;

for (1 .. $tries) {
    Net::Statsd::increment('test.counter', $sample_rate) ;
    # read messages from the udp queue to prevent from filling up...
    if ($_ % 50 == 0) {
        push @messages, @{MockServer::get_and_reset_messages()};
    }
}

my $expected_seen = $tries * $sample_rate;
my $num_seen = scalar @messages;
diag("Got $num_seen samples out of $tries tries");
cmp_ok(
    int(abs($num_seen - $expected_seen)), '<=', (int($expected_seen * 0.05) | 1),
    "5% delta or less"
);
