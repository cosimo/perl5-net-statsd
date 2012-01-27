use strict;
use warnings;
use Test::More tests => 13;
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

Net::Statsd::increment([qw(test.counter_1 test.counter_2)]);
$msgs = MockServer::get_and_reset_messages();
cmp_ok(scalar(@{$msgs}), '==', 2, 'test increment with array input');
map {delete $_->{_raw_data}} @{$msgs};
@{$msgs} = sort {$a->{key} cmp $b->{key}} @{$msgs};
is_deeply($msgs,
    [
        {
            key => 'test.counter_1',
            counters => [1]
        },
        {
            key => 'test.counter_2',
            counters => [1]
        },
    ]
);

note("the following test is similar to the direct _sample_data test in another file, but validates sent data"); 
my $tries = 10000;
my $sample_rate = 0.5;
my @messages;
for (1 .. $tries) {
    Net::Statsd::increment('test.counter', $sample_rate) ;
    # read messages from the udp queue to prevent from filling up...
    if ($_ % 50 == 0) {
        push (@messages, @{MockServer::get_and_reset_messages()});
    }
}

my $expected_seen = $tries * $sample_rate;
my $num_seen = scalar(@messages);
note("Got $num_seen samples out of $tries tries.");
cmp_ok(
    int(abs($num_seen - $expected_seen)),
    '<=',
    (int($expected_seen * 0.05) | 1),
    "5% delta or less");

