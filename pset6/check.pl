#! /usr/bin/perl -w

# check.pl
#    This program runs the tests in io61 and stdio versions.
#    It compares their outputs and measures time and memory usage.
#    It tries to prevent disaster: if your code looks like it's
#    generating an infinite-length file, or using too much memory,
#    check.pl will kill it.
#
#    To add tests of your own, scroll down to the bottom. It should
#    be relatively clear what to do.

use Time::HiRes qw(gettimeofday);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use POSIX;
use Scalar::Util qw(looks_like_number);
use List::Util qw(shuffle min max);
use Config;
sub first (@) { return $_[0]; }
my ($CHECKSUM) = first(grep {-x $_} ("/usr/bin/md5sum", "/sbin/md5", "/bin/false"));
my ($TTY) = (`tty` or "/dev/tty");
chomp($TTY);
my (@sig_name) = split(/ /, $Config{"sig_name"});
my ($SIGINT) = 0;
while ($sig_name[$SIGINT] ne "INT") {
    ++$SIGINT;
}

sub nonemptyenv ($) {
    my ($e) = @_;
    return exists($ENV{$e}) && $ENV{$e} ne "" && $ENV{$e} ne " ";
}

sub boolenv ($) {
    my ($e) = @_;
    return nonemptyenv($e) && $ENV{$e} ne "0" ? 1 : 0;
}

eval { require "syscall.ph" };

my ($Red, $Redctx, $Green, $Greenctx, $Cyan, $Ylo, $Yloctx, $Off) = ("\x1b[01;31m", "\x1b[0;31m", "\x1b[01;32m", "\x1b[0;32m", "\x1b[01;36m", "\x1b[01;33m", "\x1b[0;33m", "\x1b[0m");
my ($color) = -t STDERR && -t STDOUT;
if ($color) {
    $ENV{"ASAN_OPTIONS"} = "color=always" if !exists($ENV{"ASAN_OPTIONS"});
    $ENV{"TSAN_OPTIONS"} = "color=always" if !exists($ENV{"TSAN_OPTIONS"});
    $ENV{"UBSAN_OPTIONS"} = "color=always" if !exists($ENV{"UBSAN_OPTIONS"});
} else {
    $Red = $Redctx = $Green = $Greenctx = $Cyan = $Ylo = $Yloctx = $Off = "";
}


$SIG{"CHLD"} = sub {};
$SIG{"TSTP"} = "DEFAULT";
$SIG{"TTOU"} = "IGNORE";
my ($run61_pid);
open(TTY, "+<", $TTY) or die "can't open $TTY: $!";


my($ntest) = 0;
my($ntestfailed) = 0;

# check for a ton of existing ftx processes
$me = `id -un`;
chomp $me;
open(RUN61, "ps uxww | grep '^$me.*ftx' | grep -v grep |");
$nrun61 = 0;
$nrun61 += 1 while (defined($_ = <RUN61>));
close RUN61;
if ($nrun61 > 5) {
    print STDERR "\n";
    print STDERR "${Red}**** Looks like $nrun61 ftx* processes are already running.\n";
    print STDERR "**** Do you want all those processes?\n";
    print STDERR "**** Run `killall -9 ftxxfer` (or ftxrocket, etc.) to kill them.${Off}\n\n";
}

sub file_md5sum ($) {
    my ($x) = `$CHECKSUM $_[0]`;
    $x =~ s{\A(\S+).*\z}{$1}s;
    return $x;
}

sub unparse_signal ($) {
    my ($s) = @_;
    my (@sigs) = split(" ", $Config{sig_name});
    return "unknown signal $s" if $s >= @sigs;
    return "illegal instruction" if $sigs[$s] eq "ILL";
    return "abort signal" if $sigs[$s] eq "ABRT";
    return "floating point exception" if $sigs[$s] eq "FPE";
    return "segmentation fault" if $sigs[$s] eq "SEGV";
    return "broken pipe" if $sigs[$s] eq "PIPE";
    return "SIG" . $sigs[$s];
}

sub unparse_termination ($) {
    my ($info) = @_;
    if (exists($info->{"killed"})) {
        $info->{"killed"};
    } elsif ($info->{"status"} & 127) {
        "terminated by " . unparse_signal($info->{"status"} & 127);
    } else {
        "exit status " . ($info->{"status"} >> 8);
    }
}

sub run_sh61_pipe ($$;$) {
    my ($text, $fd, $size) = @_;
    my ($n, $buf) = (0, "");
    return $text if !defined($fd);
    while ((!defined($size) || length($text) <= $size)
           && defined(($n = POSIX::read($fd, $buf, 8192)))
           && $n > 0) {
        $text .= substr($buf, 0, $n);
    }
    return $text;
}

sub run_sh61 ($;%) {
    my($command, %opt) = @_;
    my($outfile) = exists($opt{"stdout"}) ? $opt{"stdout"} : undef;
    my($size_limit_file) = exists($opt{"size_limit_file"}) ? $opt{"size_limit_file"} : $outfile;
    $size_limit_file = [$size_limit_file] if $size_limit_file && !ref($size_limit_file);
    my($size_limit) = exists($opt{"size_limit"}) ? $opt{"size_limit"} : undef;
    my($dir) = exists($opt{"dir"}) ? $opt{"dir"} : undef;
    if (defined($dir) && $size_limit_file) {
        $dir =~ s{/+$}{};
        $size_limit_file = [map { m{\A/} ? $_ : "$dir/$_" } @$size_limit_file];
    }
    pipe(OR, OW) or die "pipe";
    fcntl(OR, F_SETFL, fcntl(OR, F_GETFL, 0) | O_NONBLOCK);
    1 while waitpid(-1, WNOHANG) > 0;

    my($preutime, $prestime, $precutime, $precstime) = times();

    $run61_pid = fork();
    if ($run61_pid == 0) {
        $SIG{"INT"} = "DEFAULT";
        POSIX::setpgid(0, 0) or die("child setpgid: $!\n");
        POSIX::tcsetpgrp(fileno(TTY), $$) or die("child tcsetpgrp: $!\n");
        defined($dir) && chdir($dir);
        close(TTY); # for explicitness: Perl will close by default

        my($fn) = defined($opt{"stdin"}) ? $opt{"stdin"} : "/dev/null";
        if (defined($fn) && $fn ne "/dev/stdin") {
            my($fd) = POSIX::open($fn, O_RDONLY);
            POSIX::dup2($fd, 0);
            POSIX::close($fd) if $fd != 0;
            fcntl(STDIN, F_SETFD, fcntl(STDIN, F_GETFD, 0) & ~FD_CLOEXEC);
        }

        close(OR);
        if (!defined($outfile) || $outfile ne "/dev/stdout") {
            open(OW, ">", $outfile) || die if defined($outfile) && $outfile ne "pipe";
            POSIX::dup2(fileno(OW), 1);
            POSIX::dup2(fileno(OW), 2);
            close(OW) if fileno(OW) != 1 && fileno(OW) != 2;
            fcntl(STDOUT, F_SETFD, fcntl(STDOUT, F_GETFD, 0) & ~FD_CLOEXEC);
            fcntl(STDERR, F_SETFD, fcntl(STDERR, F_GETFD, 0) & ~FD_CLOEXEC);
        }

        { exec($command) };
        print STDERR "error trying to run $command: $!\n";
        exit(1);
    }

    POSIX::setpgid($run61_pid, $run61_pid);    # might fail if child exits quickly
    POSIX::tcsetpgrp(fileno(TTY), $run61_pid); # might fail if child exits quickly

    my($before) = Time::HiRes::time();
    my($died) = 0;
    my($time_limit) = exists($opt{"time_limit"}) ? $opt{"time_limit"} : 0;
    my($out, $buf, $nb) = ("", "");
    my($answer) = exists($opt{"answer"}) ? $opt{"answer"} : {};
    $answer->{"command"} = $command;
    my($sigint_at) = defined($opt{"int_delay"}) ? $before + $opt{"int_delay"} : undef;
    my($sigint_state) = defined($sigint_at) ? 1 : 0;

    close(OW);

    eval {
        do {
            my $delta = 0.3;
            if ($sigint_at) {
                my $now = Time::HiRes::time();
                $delta = min($delta, $sigint_at < $now + 0.02 ? 0.1 : $sigint_at - $now);
            }
            Time::HiRes::usleep($delta * 1e6) if $delta > 0;

            if (waitpid($run61_pid, WNOHANG) > 0) {
                $answer->{"status"} = $?;
                die "!";
            }
            if ($sigint_state == 1 && Time::HiRes::time() >= $sigint_at) {
                my $pgrp = POSIX::tcgetpgrp(fileno(TTY));
                if ($pgrp != getpgrp()) {
                    kill(-$SIGINT, $pgrp);
                    $sigint_state = 2;
                }
            }
            if (defined($size_limit) && $size_limit_file && @$size_limit_file) {
                my $len = 0;
                $out = run_sh61_pipe($out, fileno(OR), $size_limit);
                foreach my $fname (@$size_limit_file) {
                    my $flen = $fname eq "pipe" ? length($out) : -s $fname;
                    $len += $flen if $flen;
                }
                if ($len > $size_limit) {
                    $died = "output file size $len, expected <= $size_limit";
                    die "!";
                }
            }
        } while (!$time_limit || Time::HiRes::time() < $before + $time_limit);
        if (waitpid($run61_pid, WNOHANG) > 0) {
            $answer->{"status"} = $?;
        } else {
            $died = sprintf("timeout after %.2fs", $time_limit);
        }
    };

    my($delta) = Time::HiRes::time() - $before;
    $answer->{"time"} = $delta;

    if (exists($answer->{"status"})
        && ($answer->{"status"} & 127) == $SIGINT
        && !defined($opt{"int_delay"})) {
        # assume user is trying to quit
        kill -9, $run61_pid;
        exit(1);
    }
    if (exists($answer->{"status"})
        && exists($opt{"delay"})
        && $opt{"delay"} > 0) {
        Time::HiRes::usleep($opt{"delay"} * 1e6);
    }
    if (exists($opt{"nokill"})) {
        $answer->{"pgrp"} = $run61_pid;
    } else {
        kill -9, $run61_pid;
        waitpid($run61_pid, 0);
        POSIX::tcsetpgrp(fileno(TTY), getpgrp());
    }
    $run61_pid = 0;

    my($postutime, $poststime, $postcutime, $postcstime) = times();
    $answer->{"utime"} = $postcutime - $precutime;
    $answer->{"stime"} = $postcstime - $precstime;

    if (defined($outfile) && $outfile ne "pipe") {
        $out = "";
        close(OR);
        open(OR, "<", (defined($dir) ? "$dir/$outfile" : $outfile));
    }
    $out = run_sh61_pipe($out, fileno(OR), $size_limit);
    close(OR);
    $answer->{"output"} = $out;

    if ($died) {
        $answer->{"killed"} = $died;
    }
    return $answer;
}


sub run_one_check ($$;$) {
    my ($ftxcmd, $diffcmd, $time_limit) = @_;
    $time_limit = 30 if !$time_limit;

    my ($info) = run_sh61($ftxcmd, "stdin" => "/dev/null", "stdout" => "pipe", "size_limit" => 100000, "time_limit" => $time_limit);
    if (exists($info->{"output"}) && $info->{"output"} ne "") {
        my $out = $info->{"output"};
        $out =~ s/\A((?:[^\n]*+\n){64}+).*\z/$1......./s;
        $out .= "\n" if $out =~ /[^\n]\z/;
        print OUT $out;
    }
    if (exists($info->{"killed"})
        || $info->{"status"} != 0) {
        print OUT "${Red}FAILURE${Redctx} (", unparse_termination($info), ")${Off}\n";
        return;
    }

    $diffcmd =~ s/diff-ftxdb\.pl/diff-ftxdb\.pl --color/ if $color;
    $info = run_sh61($diffcmd, "stdin" => "/dev/null", "stdout" => "pipe", "size_limit" => 100000, "time_limit" => 10);
    print OUT $info->{"output"};
}


open(OUT, ">&STDOUT");

print OUT "${Cyan}Building without sanitizers...${Off}\n";
system("make", "SAN=0", "ftxxfer");
my($tt, $info);

print OUT "\n${Cyan}./ftxxfer check...${Off}\n";
run_one_check("./ftxxfer", "./diff-ftxdb.pl");

print OUT "\n${Cyan}./ftxrocket check...${Off}\n";
system("make", "SAN=0", "ftxrocket");
run_one_check("./ftxrocket", "./diff-ftxdb.pl");

print OUT "\n${Cyan}./ftxrocket -J2 check...${Off}\n";
run_one_check("./ftxrocket -J2", "./diff-ftxdb.pl");

print OUT "\n${Cyan}./ftxblockchain check...${Off}\n";
system("make", "SAN=0", "ftxblockchain");
run_one_check("./ftxblockchain", "./diff-ftxdb.pl -l");

print OUT "\n${Cyan}./ftxxfer bigaccounts.fdb check...${Off}\n";
run_one_check("./ftxxfer bigaccounts.fdb", "./diff-ftxdb.pl bigaccounts.fdb");


print OUT "\n${Cyan}Building with sanitizers...${Off}\n";
system("make", "SAN=1", "ftxxfer");

print OUT "\n${Cyan}./ftxxfer check...${Off}\n";
run_one_check("./ftxxfer", "./diff-ftxdb.pl");

print OUT "\n${Cyan}./ftxblockchain check...${Off}\n";
system("make", "SAN=1", "ftxblockchain");
run_one_check("./ftxblockchain -n 10000", "./diff-ftxdb.pl -l");

print OUT "\n${Cyan}./ftxxfer bigaccounts.fdb check...${Off}\n";
run_one_check("./ftxxfer -n 10000 bigaccounts.fdb", "./diff-ftxdb.pl bigaccounts.fdb");

exit(0);
