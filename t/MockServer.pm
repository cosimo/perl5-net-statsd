package MockServer;
use strict;
use IO::Socket::INET;
use IO::Select;

$| = 1;

use vars qw ($socket @messages $select);

sub start {

    # No LocalPort means use any available unprivileged port
    $socket = new IO::Socket::INET(
        LocalAddr => '127.0.0.1',
        Proto     => 'udp',
    ) or die "unable to create socket: $!\n";

    $select = IO::Select->new($socket);
    reset_messages();
    return $socket->sockport(); 
}

my $_data = "";
sub run {
    my $timeout = shift || 3;
    while (1) {
        my @ready = $select->can_read($timeout);
        last unless @ready;
        
        my $msg = {};
        $socket->recv($_data, 1024);
        $_data =~ s/^\s+//;
        $_data =~ s/\s+$//;
        $msg->{_raw_data} = $_data;
        last if $_data =~ /^quit/i;
        
        my @bits = split(':', $_data);

        my $key = shift @bits;
        $key =~ s/\s+/_/g;
        $key =~ s/\//-/g;
        $key =~ s/[^a-zA-Z_\-0-9\.]//g;
        $msg->{key} = $key;

        if (@bits == 0 || ! defined $bits[0]) {
            push @bits, 1;
        }

        for (@bits) {
            my @fields = split m{\|};

            if (@fields == 1 || ! defined $fields[1]) {
                $msg->{error} = "bad line";
                next;
            }

            # Timer
            if ($fields[1] eq 'ms') {
                push @{$msg->{timers}}, $fields[0];
            }

            # Gauge (FIXME I'll just pretend this is correct)
            elsif ($fields[1] eq 'g') {
                push @{$msg->{gauges}}, $fields[0];
            }

            # Counter, evt. sampled
            else {
                if ($fields[2] && $fields[2] =~ /^\s*@([\d\.]+)/) {
                    $msg->{sample_rate} = $1;
                }
                push @{$msg->{counters}}, $fields[0];
            }
        }
        push @messages, $msg;
    }
}

sub get_messages {
    process();
    my @to_return = @messages;
    return \@to_return;
};

sub get_and_reset_messages {
    my $ret = get_messages();
    reset_messages();
    return $ret
}

sub reset_messages { @messages = () }

sub stop {
    my $s_send = IO::Socket::INET->new(
        PeerAddr  => '127.0.0.1:'. $socket->sockport(),
        Proto     => 'udp',
    ) or die "failed to create client socket: $!\n";
    $s_send->send("quit");
    $s_send->close();
}

sub process {
    stop();
    run();
}

1;
