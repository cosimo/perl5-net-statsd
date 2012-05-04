use strict;
use warnings;
use Test::More tests => 2;
use Net::Statsd;

ok(1, "Net::Statsd module loaded");

my $version = Net::Statsd->VERSION();
ok($version, "Net::Statsd version is $version");
