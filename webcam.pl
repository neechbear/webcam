#!/usr/bin/perl -w

use strict;
use LWP::UserAgent ();

daemonize('/tmp/webcam/webcam.pid',1);
mkdir '/tmp/webcam';
chdir '/tmp/webcam' || die 'Unable to chdir to webcam archive directory';

my $host = get_ntl_host();
while (1) {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();

	my $file = sprintf('cam-%04d%02d%02d-%02d%02d%02d.jpg',
		$year+1900,$mon+1,$mday,$hour,$min,$sec);
	my $url = "http://$host/Jpeg/CamImg.jpg";

	my $ua = LWP::UserAgent->new;
	$ua->credentials($host, 'Camera Server', 'nicolaw', 'knickers');
	my $res = $ua->mirror($url,$file);
	
	unless ($res->is_success) {
		print LOG "Wrote $url to $file\n";
		open(LOG,'>>webcam.log') || die "Unable to open file handle LOG for file 'webcam.log': $!";
		print LOG "Failed to download $url: ".$res->status_line."\n";
		close(LOG) || warn "Unable to close file handle LOG for file 'webcam.log': $!\n";
		$host = get_ntl_host();
	}

	clean_directory(5);

	sleep 2;
}

exit;

sub clean_directory {
	my $keep = shift || 10;
	opendir(DH,'.') || die "Unable to open file handle DH for directory '.': $!";
	my @files = sort { $a cmp $b } grep(/^cam-\d{8}-\d{6}\.jpg$/,readdir(DH));
	closedir(DH) || warn "Unable to close file handle DH for directory '.': $!";
	for (1..$keep) { pop @files; }
	unlink $_ for @files;
}

sub get_ntl_host {
	my $host = `last -a | grep broadband.ntl.com | tac | awk '{ print \$10 }' | tail -n 1`;
	chomp $host;
	return "$host:8888";
}

# vim:ts=4:sw=4:tw=78
# Daemonize self
sub daemonize {
	# Pass in the PID filename to use
	my $pidfile = shift || undef;

	# Boolean true will supress "already running" messages if you want to
	# spawn a process out of cron every so often to ensure it's always
	# running, and to respawn it if it's died
	my $cron = shift || 0;

	# Set the fname to the filename minus path
	(my $SELF = $0) =~ s|.*/||;
	$0 = $SELF;

	# Lazy people have to have everything done for them!
	$pidfile = "/tmp/$SELF.pid" unless defined $pidfile;

	# Check that we're not already running, and quit if we are
	if (-f $pidfile) {
		unless (open(PID,$pidfile)) {
			warn "Unable to open file handle PID for file '$pidfile': $!\n";
			exit 1;
		}
		my $pid = <PID>; chomp $pid;
		close(PID) || warn "Unable to close file handle PID for file '$pidfile': $!\n";

		# This is a good method to check the process is still running for Linux
		# kernels since it checks that the fname of the process is the same as
		# the current process
		if (-f "/proc/$pid/stat") {
			open(FH,"/proc/$pid/stat") || warn "Unable to open file handle FH for file '/proc/$pid/stat': $!\n";
			my $line = <FH>;
			close(FH) || warn "Unable to close file handle FH for file '/proc/$pid/stat': $!\n";
			if ($line =~ /\d+[^(]*\((.*)\)\s*/) {
				my $process = $1;
				if ($process =~ /^$SELF$/) {
					warn "$SELF already running at PID $pid; exiting.\n" unless $cron;
					exit 0;
				}
			}

		# This will work on other UNIX flavors but doesn't gaurentee that the
		# PID you've just checked is the same process fname as reported in you
		# PID file
		} elsif (kill(0,$pid)) {
			warn "$SELF already running at PID $pid; exiting.\n" unless $cron;
			exit 0;

		# Otherwise the PID file is old and stale and it should be removed
		} else {
			warn "Removing stale PID file.\n";
			unlink($pidfile) || warn "Unable to unlink PID file '$pidfile': $!\n";
		}
	}

	# Daemon parent about to spawn
	if (my $pid = fork) {
		warn "Forking background daemon, process $pid.\n";
		exit 0;

	# Child daemon process that was spawned
	} else {
		# Fork a second time to get rid of any attached terminals
		if (my $pid = fork) {
			warn "Forking second background daemon, process $pid.\n";
			exit 0;
		} else {
			unless (defined $pid) {
				warn "Cannot fork: $!\n";
				exit 2;
			}
			unless (open(FH,">$pidfile")) {
				warn "Unable to open file handle FH for file '$pidfile': $!\n";
				exit 3;
			}
			print FH $$;
			close(FH) || warn "Unable to close file handle FH for file '$pidfile': $!\n";

			# Sort out file handles and current working directory
			chdir '/' || warn "Unable to change directory to '/': $!\n";
			close(STDOUT) || warn "Unable to close file handle STDOUT: $!\n";
			close(STDERR) || warn "Unable to close file handle STDERR: $!\n";
			open(STDOUT,'>>/dev/null'); open(STDERR,'>>/dev/null');

			return $$;
		}
	}
}

1;

