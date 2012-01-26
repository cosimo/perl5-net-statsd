use strict;
use warnings;
use Test::More tests => 10;
use Net::Statsd;

my $dirname;
BEGIN {
    use File::Spec;
    use File::Basename;
    $dirname = dirname(File::Spec->rel2abs( __FILE__ ));
}
use lib $dirname;
use MockServer;

BEGIN {
    $Net::Statsd::HOST = 'localhost';
    $Net::Statsd::PORT = MockServer::PORT();
}

note <<"DESCRIPTION";
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
These test verify basic operation of the statsd client 
by validating the udp messages sent to a mock server
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
DESCRIPTION
;

MockServer::start();
my $msgs;

Net::Statsd::timing('test.timer', 345);
$msgs = MockServer::get_and_reset_messages();
is($msgs->[0]->{key}, 'test.timer', 'basic timer');
cmp_ok(scalar(@{$msgs->[0]->{timers}}), '==', 1);
cmp_ok($msgs->[0]->{timers}->[0], '==', 345);

Net::Statsd::increment('test.counter');
$msgs = MockServer::get_and_reset_messages();
is($msgs->[0]->{key}, 'test.counter', 'basic increment');
cmp_ok(scalar(@{$msgs->[0]->{counters}}), '==', 1);
cmp_ok($msgs->[0]->{counters}->[0], '==', 1);

Net::Statsd::increment('test.counter', 0.99);
$msgs = MockServer::get_and_reset_messages();
is($msgs->[0]->{key}, 'test.counter', 'increment with sample rate');
cmp_ok(scalar(@{$msgs->[0]->{counters}}), '==', 1);
cmp_ok($msgs->[0]->{counters}->[0], '==', 1);
is($msgs->[0]->{sample_rate}, '0.99');


