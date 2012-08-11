package Net::Statsd;

# ABSTRACT: Sends statistics to the stats daemon over UDP
# Cosimo Streppone <cosimo@cpan.org>

use strict;
use warnings;
use Carp ();
use IO::Socket ();

our $HOST = 'localhost';
our $PORT = 8125;

my $SOCK;
my $SOCK_PEER;

=head1 NAME

Net::Statsd - Perl client for Etsy's statsd daemon

=head1 SYNOPSIS

    # Configure where to send events
    # That's where your statsd daemon is listening.
    $Net::Statsd::HOST = 'localhost';    # Default
    $Net::Statsd::PORT = 8125;           # Default

    #
    # Keep track of events as counters
    #
    Net::Statsd::increment('site.logins');
    Net::Statsd::increment('database.connects');

    #
    # Log timing of events, ex. db queries
    #
    use Time::HiRes;
    my $start_time = [ Time::HiRes::gettimeofday ];

    # do the complex database query
    # note: time value sent to timing should
    # be in milliseconds.
    Net::Statsd::timing(
        'database.complexquery',
        Time::HiRes::tv_interval($start_time) * 1000
    );

    #
    # Log metric values
    #
    Net::Statsd::gauge('core.temperature' => 55);

=head1 DESCRIPTION

This module implement a UDP client for the B<statsd> statistics
collector daemon in use at Etsy.com.

You want to use this module to track statistics in your Perl
application, such as how many times a certain event occurs
(user logins in a web application, or database queries issued),
or you want to time and then graph how long certain events take,
like database queries execution time or time to download a
certain file, etc...

If you're uncertain whether you'd want to use this module or
statsd, then you can read some background information here:

    http://codeascraft.etsy.com/2011/02/15/measure-anything-measure-everything/

The github repository for statsd is:

    http://github.com/etsy/statsd

By default the client will try to send statistic metrics to
C<localhost:8125>, but you can change the default hostname and port
with:

    $Net::Statsd::HOST = 'your.statsd.hostname.net';
    $Net::Statsd::PORT = 9999;

just after including the C<Net::Statsd> module.

=head1 ABOUT SAMPLING

A note about sample rate: A sample rate of < 1 instructs this
library to send only the specified percentage of the samples to
the server. As such, the application code should call this module
for every occurence of each metric and allow this library to
determine which specific measurements to deliver, based on the
sample_rate value. (e.g. a sample rate of 0.5 would indicate that
approximately only half of the metrics given to this module would
actually be sent to statsd).

=head1 FUNCTIONS

=cut

=head2 C<timing($name, $time, $sample_rate = 1)>

Log timing information.
B<Time is assumed to be in milliseconds (ms)>.

    Net::Statsd::timing('some.timer', 500);

=cut

sub timing {
    my ($name, $time, $sample_rate) = @_;

    if (! defined $sample_rate) {
        $sample_rate = 1;
    }

    my $stats = {
        $name => sprintf "%d|ms", $time
    };

    return Net::Statsd::send($stats, $sample_rate);
}

=head2 C<increment($counter, $sample_rate=1)>

=head2 C<increment(\@counter, $sample_rate=1)>

Increments one or more stats counters

    # +1 on 'some.int'
    Net::Statsd::increment('some.int');

    # 0.5 = 50% sampling
    Net::Statsd::increment('some.int', 0.5);

To increment more than one counter at a time,
you can B<pass an array reference>:

    Net::Statsd::increment(['grue.dinners', 'room.lamps'], 1);

B<You can also use "inc()" instead of "increment()" to type less>.


=cut

sub increment {
    my ($stats, $sample_rate) = @_;

    return Net::Statsd::update_stats($stats, 1, $sample_rate);
}

*inc = *increment;

=head2 C<decrement($counter, $sample_rate=1)>

Same as increment, but decrements. Yay.

    Net::Statsd::decrement('some.int')

B<You can also use "dec()" instead of "decrement()" to type less>.

=cut

sub decrement {
    my ($stats, $sample_rate) = @_;

    return Net::Statsd::update_stats($stats, -1, $sample_rate);
}

*dec = *decrement;

=head2 C<update_stats($stats, $delta=1, $sample_rate=1)>

Updates one or more stats counters by arbitrary amounts

    Net::Statsd::update_stats('some.int', 10)

equivalent to:

    Net::Statsd::update_stats('some.int', 10, 1)

A sampling rate less than 1 means only update the stats
every x number of times (0.1 = 10% of the times).

=cut

sub update_stats {
    my ($stats, $delta, $sample_rate) = @_;

    if (! defined $delta) {
        $delta = 1;
    }

    if (! defined $sample_rate) {
        $sample_rate = 1;
    }

    if (! ref $stats) {
        $stats = [ $stats ];
    }
    elsif (ref $stats eq 'HASH') {
        Carp::croak("Usage: update_stats(\$str, ...) or update_stats(\\\@list, ...)");
    }

    my %data = map { $_ => sprintf "%s|c", $delta } @{ $stats };

    return Net::Statsd::send(\%data, $sample_rate)
}

=head2 C<gauge($name, $value)>

Log arbitrary values, as a temperature, or server load.

    Net::Statsd::gauge('core.temperature', 55);

=cut

sub gauge {
    my ($name, $value) = @_;

    $value = 0 unless defined $value;

    # Didn't use '%d' because values might be floats
    my $stats = {
        $name => sprintf "%s|g", $value
    };

    return Net::Statsd::send($stats, 1);
}

=head2 C<send(\%data, $sample_rate = 1)>

Squirt the metrics over UDP.

    Net::Statsd::send({ 'some.int' => 1 });

=cut

sub send {
    my ($data, $sample_rate) = @_;

    my $sampled_data = _sample_data($data, $sample_rate);

    # No sampled_data can happen when:
    # 1) No $data came in
    # 2) Sample rate was low enough that we don't want to send events
    if (! $sampled_data) {
        return;
    }

    # cache the socket to avoid dns and socket creation overheads
    # (this boosts performance from ~6k to >60k sends/sec)
    if (!$SOCK || !$SOCK_PEER || "$HOST:$PORT" ne $SOCK_PEER) {

        $SOCK = IO::Socket::INET->new(
            Proto    => 'udp',
            PeerAddr => $HOST,
            PeerPort => $PORT,
        ) or do {
            Carp::carp("Net::Statsd can't create a socket to $HOST:$PORT: $!")
                unless our $_warn_once->{"$HOST:$PORT"}++;
            return
        };
        $SOCK_PEER = "$HOST:$PORT";

        # We don't want to die if Net::Statsd::send() doesn't work...
        # We could though:
        #
        # or die "Could not create UDP socket: $!\n";
    }

    my $all_sent = 1;

    keys %{ $sampled_data }; # reset iterator
    while ( my ($stat, $value) = each %{ $sampled_data } ) {
        my $packet = "$stat:$value";
        # send() returns the number of characters sent, or undef on error.
        my $r = send($SOCK, $packet, 0);
        if (!defined $r) {
            #warn "Net::Statsd send error: $!";
            $all_sent = 0;
        }
        elsif ($r != length($packet)) {
            #warn "Net::Statsd send truncated: $!";
            $all_sent = 0;
        }
    }

    return $all_sent;
}

=head2 C<_sample_data(\%data, $sample_rate = 1)>

B<This method is used internally, it's not part of the public interface.>

Takes care of transforming a hash of metrics data into
a B<sampled> hash of metrics data, according to the given
C<$sample_rate>.

If C<$sample_rate == 1>, then sampled data is exactly the
incoming data.

If C<$sample_rate = 0.2>, then every metric value will be I<marked>
with the given sample rate, so the Statsd server will automatically
scale it. For example, with a sample rate of 0.2, the metric values
will be multiplied by 5.

=cut

sub _sample_data {
    my ($data, $sample_rate) = @_;

    if (! $data || ref $data ne 'HASH') {
        Carp::croak("No data?");
    }

    if (! defined $sample_rate) {
        $sample_rate = 1;
    }

    # Sample rate > 1 doesn't make sense though
    if ($sample_rate >= 1) {
        return $data;
    }

    my $sampled_data;

    # Perform sampling here, so that clients using Net::Statsd
    # don't have to do it every time. This is the same
    # implementation criteria used in the other statsd client libs
    #
    # If rand() doesn't trigger, then no data will be sent
    # to the statsd server, which is what we want.

    if (rand() <= $sample_rate) {
        while (my ($stat, $value) = each %{ $data }) {
            # Uglier, but if there's no data to be sampled,
            # we get a clean undef as returned value
            $sampled_data ||= {};
            $sampled_data->{$stat} = sprintf "%s|@%s", $value, $sample_rate;
        }
    }

    return $sampled_data;
}

1;
