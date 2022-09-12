#! /usr/bin/perl -w

# check.pl
#    This program runs the tests in m61 versions and analyzes their
#    output for errors.

use Time::HiRes qw(gettimeofday);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use POSIX;
use Config;

my($TTY) = (`tty` or "/dev/tty");
chomp($TTY);
my(@sig_name) = split(/ /, $Config{"sig_name"});
my($SIGINT) = 0;
while ($sig_name[$SIGINT] ne "INT") {
    ++$SIGINT;
}

my($Red, $Redctx, $Green, $Greenctx, $Cyan, $Ylo, $Yloctx, $Off) = ("\x1b[01;31m", "\x1b[0;31m", "\x1b[01;32m", "\x1b[0;32m", "\x1b[01;36m", "\x1b[01;33m", "\x1b[0;33m", "\x1b[0m");
$Red = $Redctx = $Green = $Greenctx = $Cyan = $Ylo = $Yloctx = $Off = "" if !-t STDERR || !-t STDOUT;
my($ContextLines, $LeakCheck, $Make, $Test, $Exec) = (3, 0, 0, 0, 0);
my(@Restrict, @Makeargs);

$SIG{"CHLD"} = sub {};
$SIG{"TSTP"} = "DEFAULT";
$SIG{"TTOU"} = "IGNORE";
my($run61_pid);
open(TTY, "+<", $TTY) or die "can't open $TTY: $!";

sub run_sh61_pipe ($$;$) {
    my($text, $fd, $size) = @_;
    my($n, $buf) = (0, "");
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

        {
            if (ref $command) {
                exec { $command->[0] } @$command;
            } else {
                exec($command);
            }
        }
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
    $answer->{command} = $command;
    my($sigint_at) = defined($opt{"int_delay"}) ? $before + $opt{"int_delay"} : undef;
    my($sigint_state) = defined($sigint_at) ? 1 : 0;

    close(OW);

    eval {
        do {
            my($delta) = 0.3;
            if ($sigint_at) {
                my($now) = Time::HiRes::time();
                $delta = min($delta, $sigint_at < $now + 0.02 ? 0.1 : $sigint_at - $now);
            }
            Time::HiRes::usleep($delta * 1e6) if $delta > 0;

            if (waitpid($run61_pid, WNOHANG) > 0) {
                $answer->{status} = $?;
                die "!";
            }
            if ($sigint_state == 1 && Time::HiRes::time() >= $sigint_at) {
                my($pgrp) = POSIX::tcgetpgrp(fileno(TTY));
                if ($pgrp != getpgrp()) {
                    kill(-$SIGINT, $pgrp);
                    $sigint_state = 2;
                }
            }
            if (defined($size_limit) && $size_limit_file && @$size_limit_file) {
                my($len) = 0;
                $out = run_sh61_pipe($out, fileno(OR), $size_limit);
                foreach my $fname (@$size_limit_file) {
                    $len += ($fname eq "pipe" ? length($out) : -s $fname);
                }
                if ($len > $size_limit) {
                    $died = "output file size $len, expected <= $size_limit";
                    die "!";
                }
            }
        } while (Time::HiRes::time() < $before + $time_limit);
        if (waitpid($run61_pid, WNOHANG) > 0) {
            $answer->{status} = $?;
        } else {
            $died = "timeout";
        }
    };

    my($delta) = Time::HiRes::time() - $before;
    $answer->{time} = $delta;

    if (exists($answer->{status})
        && ($answer->{status} & 127) == $SIGINT
        && !defined($opt{"int_delay"})) {
        # assume user is trying to quit
        kill -9, $run61_pid;
        exit(2);
    }
    if (exists($answer->{status})
        && exists($opt{"delay"})
        && $opt{"delay"} > 0) {
        Time::HiRes::usleep($opt{"delay"} * 1e6);
    }
    if (exists($opt{"nokill"})) {
        $answer->{pgrp} = $run61_pid;
    } else {
        kill -9, $run61_pid;
        waitpid($run61_pid, 0);
        POSIX::tcsetpgrp(fileno(TTY), getpgrp());
    }
    $run61_pid = 0;

    my($postutime, $poststime, $postcutime, $postcstime) = times();
    $answer->{utime} = $postcutime - $precutime;
    $answer->{stime} = $postcstime - $precstime;

    if ($died) {
        $answer->{killed} = $died;
        close(OR);
        return $answer;
    }

    if (defined($outfile) && $outfile ne "pipe") {
        $out = "";
        close(OR);
        open(OR, "<", (defined($dir) ? "$dir/$outfile" : $outfile));
    }
    $answer->{output} = run_sh61_pipe($out, fileno(OR), $size_limit);
    close(OR);

    return $answer;
}

sub read_expected ($) {
    my($fname) = @_;
    open(EXPECTED, $fname) or die;

    my(@expected);
    my($line, $skippable, $unordered) = (0, 0, 0);
    my($allow_asan_warning, $time) = (0, 0, 0);
    while (defined($_ = <EXPECTED>)) {
        ++$line;
        if (m{^//! \?\?\?\s*$}) {
            $skippable = 1;
        } elsif (m{^//!!UNORDERED\s*$}) {
            $unordered = 1;
        } elsif (m{^//!!TIME\s*$}) {
            $time = 1;
        } elsif (m{^//!!(ALLOW_|DISALLOW_)ASAN_WARNING\s*$}) {
            $allow_asan_warning = $1 eq "ALLOW_";
        } elsif (m{^//! }) {
            s{^....(.*?)\s*$}{$1};
            $allow_asan_warning = 1 if /^alloc count:.*fail +[1-9]/;
            my($m) = {"t" => $_, "line" => $line, "skip" => $skippable,
                      "r" => "", "match" => []};
            foreach my $x (split(/(\?\?\?|\?\?\{.*?\}(?:=\w+)?\?\?|\?\?>=\d+\?\?)/)) {
                if ($x eq "???") {
                    $m->{r} =~ s{(?:\\ )+\z}{\\s+};
                    $m->{r} .= ".*";
                } elsif ($x =~ /\A\?\?\{(.*)\}=(\w+)\?\?\z/) {
                    $m->{r} .= "(" . $1 . ")";
                    push @{$m->{match}}, $2;
                } elsif ($x =~ /\A\?\?\{(.*)\}\?\?\z/) {
                    my($contents) = $1;
                    $m->{r} =~ s{(?:\\ )+\z}{\\s+};
                    $m->{r} .= "(?:" . $contents . ")";
                } elsif ($x =~ /\A\?\?>=(\d+)\?\?\z/) {
                    my($contents) = $1;
                    $contents =~ s/\A0+(?=[1-9]|0\z)//;
                    $m->{r} =~ s{(?:\\ )+\z}{\\s+};
                    my(@dig) = split(//, $contents);
                    my(@y) = ("0*[1-9]\\d{" . (@dig) . ",}");
                    for (my $i = 0; $i < @dig; ++$i) {
                        my(@xdig) = @dig;
                        if ($i == @dig - 1) {
                            $xdig[$i] = "[" . $dig[$i] . "-9]";
                        } else {
                            next if $dig[$i] eq "9";
                            $xdig[$i] = "[" . ($dig[$i] + 1) . "-9]";
                        }
                        for (my $j = $i + 1; $j < @dig; ++$j) {
                            $xdig[$j] = "\\d";
                        }
                        push @y, "0*" . join("", @xdig);
                    }
                    $m->{r} .= "(?:" . join("|", @y) . ")(?!\\d)";
                } else {
                    $m->{r} .= quotemeta($x);
                }
            }
            $m->{r} .= "\\s*";
            $m->{r} =~ s{\A(?:\\ )+}{\\s*};
            push @expected, $m;
            $skippable = 0;
        }
    }
    return {"l" => \@expected, "nl" => scalar(@expected),
            "skip" => $skippable, "unordered" => $unordered, "time" => $time,
            "allow_asan_warning" => $allow_asan_warning};
}

sub read_actual ($) {
    my($fname) = @_;
    open(ACTUAL, $fname) or die;
    my(@actual);
    while (defined($_ = <ACTUAL>)) {
        chomp;
        push @actual, $_;
    }
    close ACTUAL;
    \@actual;
}

sub compare_test_line ($$$) {
    my($line, $expline, $chunks) = @_;
    my($rex) = $expline->{r};
    while (my($k, $v) = each %$chunks) {
        $rex =~ s{\\\?\\\?$k\\\?\\\?}{$v}g;
    }
    if ($line =~ m{\A$rex\z}) {
        for (my $i = 0; $i < @{$expline->{match}}; ++$i) {
            $chunks->{$expline->{match}->[$i]} = ${$i + 1};
        }
        return 1;
    } else {
        return 0;
    }
}

sub print_actual ($$$$) {
    my ($actual, $a, $aname, $explen) = @_;
    my ($apfx) = "$aname:" . ($a + 1);
    my ($alen) = length($apfx) + 5;
    my ($amid) = "";
    if ($alen < $explen) {
        $amid = " " x ($explen - $alen);
        $alen = $explen;
    }
    my ($sep) = sprintf("$Off\n  $Redctx%${alen}s  ", "");
    my ($context) = $actual->[$a];
    my ($i);
    for ($i = 2; $i <= $ContextLines && $a + 1 != @$actual; ++$a, ++$i) {
        $context .= $sep . $actual->[$a + 1];
    }
    $context .= "..." if $i > $ContextLines && $a + 1 != @$actual;
    print STDERR "  ", $Redctx, $apfx, ":", $amid, " Got `", $context, "`", $Off, "\n";
}

sub print_killed ($$) {
    my($file, $out) = @_;
    printf STDERR "${Red}\r${file} FAIL: Killed after %.5fs: $out->{killed}$Off\n", $out->{time};
    if (exists($out->{output}) && $out->{output} =~ m/\A\s*(.+)/) {
        print STDERR "  ${Redctx}1st line of output: $1$Off\n";
    }
}

sub run_compare ($$$$$$) {
    my($actual, $exp, $aname, $ename, $outname, $out) = @_;
    my($unordered) = $exp->{unordered};

    my(%chunks);
    my($a) = 0;
    my(@explines) = @{$exp->{l}};
    for (; $a != @$actual; ++$a) {
        $_ = $actual->[$a];
        if (/^==\d+==\s*WARNING: AddressSanitizer failed to allocate/
            && $exp->{allow_asan_warning}) {
            next;
        }

        if (!@explines && !$exp->{skip}) {
            my($lines) = $exp->{nl} == 1 ? "line" : "lines";
            print STDERR "$Red${outname}FAIL: Too much output (expected ", $exp->{nl}, " output $lines)$Off\n";
            print_actual($actual, $a, $aname, 0);
            return 1;
        } elsif (!@explines) {
            next;
        }

        my($ok, $e) = (0, 0);
        while ($e != @explines) {
            $ok = compare_test_line($_, $explines[$e], \%chunks);
            last if $ok || !$unordered;
            ++$e;
        }
        if ($ok) {
            splice @explines, $e, 1;
        } elsif (!$explines[0]->{skip}) {
            print STDERR "$Red${outname}FAIL: Unexpected output starting on line ", $a + 1, "$Off\n";
            my ($pfx) = "$ename:" . $explines[0]->{line} . ": Expected";
            print STDERR "  ", $Redctx, $pfx, " `", $explines[0]->{t}, "`", $Off, "\n";
            print_actual($actual, $a, $aname, length($pfx));
            return 1;
        }
    }

    if (@explines) {
        print STDERR "$Red${outname}FAIL: Missing output starting on line ", scalar(@$actual), "$Off\n";
        my ($pfx) = "$ename:" . $explines[0]->{line} . ": Expected";
        print STDERR "  ", $Redctx, $pfx, " `", $explines[0]->{t}, "`", $Off, "\n";
        print_actual($actual, 0, $aname, length($pfx)) if @$actual;
        return 1;
    } else {
        my($ctx) = "";
        if ($exp->{time}) {
            $ctx .= " in " . sprintf("%.03f sec", $out->{time});
        }
        if (exists($chunks{"peak_memory"})) {
            $ctx .= " peak memory " . $chunks{"peak_memory"};
        }
        if ($ctx ne "") {
            print STDERR $Green, $outname, "OK", $Greenctx, $ctx, $Off, "\n";
        } else {
            print STDERR $Green, $outname, "OK", $Off, "\n";
        }
        return 0;
    }
}

sub push_expansion (\@$) {
    my ($a, $x) = @_;
    foreach my $t (split(/[\s,]+/, $x)) {
        push @$a, $t if $t ne "";
    }
}


my ($KeepGoing) = 0;

while (@ARGV > 0) {
    if ($ARGV[0] eq "-c" && @ARGV > 1 && $ARGV[1] =~ /^\d+$/) {
        $ContextLines = +$ARGV[1];
        shift @ARGV;
    } elsif ($ARGV[0] =~ /^-c(\d+)$/) {
        $ContextLines = +$1;
    } elsif ($ARGV[0] eq "-l") {
        $LeakCheck = 1;
    } elsif ($ARGV[0] eq "-k") {
        $KeepGoing = 1;
    } elsif ($ARGV[0] eq "-r" && @ARGV > 1) {
        push_expansion @Restrict, $ARGV[1];
        shift @ARGV;
    } elsif ($ARGV[0] =~ /^-r(.+)$/) {
        push_expansion @Restrict, $1;
    } elsif ($ARGV[0] eq "-m") {
        $Make = 1;
    } elsif ($ARGV[0] eq "-e") {
        $Test = 1;
    } elsif ($ARGV[0] eq "-x" && @ARGV > 1) {
        $Exec = $ARGV[1];
        shift @ARGV;
    } elsif ($ARGV[0] =~ /^-x(.+)$/) {
        $Exec = $1;
    } elsif ($ARGV[0] =~ /=/) {
        push @Makeargs, $ARGV[0];
    } elsif ($ARGV[0] =~ /\A-/) {
        print STDERR "Usage: ./check.pl [-c CONTEXT] [-l] [TESTS...]\n";
        print STDERR "       ./check.pl -x EXECFILE\n";
        print STDERR "       ./check.pl -e TESTS...\n";
        exit 1;
    } else {
        last;
    }
    shift @ARGV;
}

my (@testargs);
foreach my $arg (@ARGV) {
    if ($arg =~ /=/) {
        push @Makeargs, $arg;
    } else {
        $arg =~ s/test//g;
        push_expansion @testargs, $arg;
    }
}

sub test_class ($;@) {
    my($test) = shift @_;
    foreach my $x (@_) {
        if ($x eq $test
            || ($x =~ m/\A(\d+)-(\d+)\z/ && $test >= $1 && $test <= 2)
            || $x eq "san"
            || $x eq "leak"
            || ($x eq "phase1" && $test >= 1 && $test <= 19)
            || ($x eq "phase2" && $test >= 20 && $test <= 30)
            || ($x eq "phase3" && $test >= 31 && $test <= 45)
            || ($x eq "phase4" && $test >= 46 && $test <= 51)) {
            return 1;
        }
    }
    0;
}

sub asan_options ($) {
    my($test) = @_;
    $test = int($1) if $test =~ m{\A(?:\./)?test(\d+)\z};
    if ($LeakCheck && test_class($test, "leak")) {
        return "allocator_may_return_null=1 detect_leaks=1";
    } else {
        return "allocator_may_return_null=1 detect_leaks=0";
    }
}

sub test_runnable ($) {
    my($number) = @_;
    foreach my $r (@Restrict) {
        return 0 if !test_class($number, $r);
    }
    return !@testargs || test_class($number, @testargs);
}

sub run_make (@) {
    system("make", "--no-print-directory", @Makeargs, @_);
    exit(2) if $? != 0 && $? != 1;
}

if ($Exec) {
    die "bad -x option\n" if $Exec !~ m{\A(?![\./])[^/]+\z};
    run_make($Exec) if $Make;
    $ENV{"ASAN_OPTIONS"} = asan_options($Exec);
    $out = run_sh61("./" . $Exec, "stdout" => "pipe", "stdin" => "/dev/null",
                    "time_limit" => 10, "size_limit" => 80000);
    if (exists($out->{killed})) {
        print_killed($Exec, $out);
        exit(1);
    }
    my($ofile) = "out/" . $Exec . ".output";
    if (open(OUT, ">", $ofile)) {
        print OUT $out->{output};
        close OUT;
    }
    exit(run_compare([split("\n", $out->{output})],
                     read_expected($Exec . ".cc"),
                     $ofile, $Exec . ".cc", $Exec, $out));
} else {
    my(@tests) = ();
    foreach my $fn (sort(glob("test[0-9][0-9].cc"), glob("test[0-9][0-9][0-9].cc"))) {
        my($n) = +substr($fn, 4, -3);
        push @tests, $n if !grep { $_ == $n } @tests;
    }
    my($ntest, $ntestfailed) = (0, 0);

    if ($Test) {
        foreach my $i (@tests) {
            printf "test%02d\n", $i if test_runnable($i);
        }
        exit;
    }
    my(%need_make);
    if ($Make) {
        my(@makes);
        foreach my $i (@tests) {
            push @makes, sprintf("test%02d", $i) if test_runnable($i);
        }
        my($out) = run_sh61(["make", "-s", "-n", @makes], "stdout" => "pipe");
        if ($out && $out->{status} == 0 && exists($out->{output})) {
            foreach my $i (@tests) {
                my ($test) = sprintf("test%02d", $i);
                $need_make{$i} = 1 if index($out->{output}, $test) >= 0;
            }
        } else {
            foreach my $i (@tests) {
                $need_make{$i} = 1;
            }
        }
    }
    $ENV{"MALLOC_CHECK_"} = 0;
    foreach my $i (@tests) {
        next if !test_runnable($i);
        ++$ntest;
        $ENV{"ASAN_OPTIONS"} = asan_options($i);
        my($test) = sprintf("test%02d", $i);
        run_make($test) if exists($need_make{$i});
        printf STDERR "${test} ";
        $out = run_sh61("./${test}",
            "stdout" => "pipe", "stdin" => "/dev/null",
            "time_limit" => $i >= 27 && $i <= 30 ? 10 : 5,
            "size_limit" => 80000);
        my ($failed) = 0;
        if (exists($out->{killed})) {
            print_killed($test, $out);
            $failed = 1;
        } else {
            $failed = run_compare([split("\n", $out->{output})],
                    read_expected("${test}.cc"),
                    "output", "${test}.cc", "\r$test ", $out);
        }
        if ($failed) {
            ++$ntestfailed;
            exit(1) if !$KeepGoing;
        }
    }
    my($ntestpassed) = $ntest - $ntestfailed;
    if ($ntest == 0) {
        print STDERR "${Red}No tests match ", join(" ", @testargs), "$Off\n";
        exit(2);
    } if ($ntest == @tests && $ntestpassed == $ntest) {
        print STDERR "${Green}All tests passed!$Off\n";
        exit(0);
    } else {
        my($color) = ($ntestpassed == 0 ? $Red : ($ntestpassed == $ntest ? $Green : $Cyan));
        print STDERR "${color}$ntestpassed of $ntest ", ($ntest == 1 ? "test" : "tests"), " passed$Off\n";
        exit($ntestpassed == $ntest ? 0 : 1);
    }
}
