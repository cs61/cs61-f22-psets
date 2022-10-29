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
my (@Makeargs);

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
            $died = sprintf("timeout after %.2fs", $time_limit);
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


# test matching
my (@RESTRICT_TESTS, @ALLOW_TESTS);
my (%KNOWN_TESTS) = (
    "phase1" => "1-19", "phase2" => "20-30", "phase3" => "31-45", "phase4" => "46-51"
);

sub split_testid ($) {
    my ($testid) = @_;
    if ($_[0] =~ /\A([A-Za-z]*)(\d*)([A-Za-z]*)\z/) {
        return (uc($1), +$2, lc($3));
    } else {
        return ($_[0], "", "");
    }
}

sub split_testmatch ($) {
    my @t;
    while ($_[0] =~ m/(?:\A|[\s,])([A-Za-z]*|\*)-?(\*|\d*)(-\d*|[*.]|[A-Za-z][-A-Za-z]*|)(?=[\s,]|\z)/g) {
        my $full = $1 . $2 . $3;
        if (exists($KNOWN_TESTS{$full})) {
            push(@t, &split_testmatch($KNOWN_TESTS{$full}));
        } elsif (($2 ne "" || $3 eq "") && ($2 ne "*" || $3 ne "*")) {
            push(@t, [uc($1), $2 eq "" || $2 eq "*" ? "" : +$2, lc($3)]);
        }
    }
    @t;
}

sub match_testid ($$) {
    my ($id, $match) = @_;
    if (ref $match) {
        my ($pfx, $num, $sfx) = split_testid($id);
        my ($apfx, $anum, $asfx) = @$match;
        # check prefix
        return 0 if $apfx ne "" && $apfx ne "*" && $pfx ne $apfx;
        # check test number
        return 1 if $anum eq "";
        my $anum2 = $anum;
        if (substr($asfx, 0, 1) eq "-") {
            $anum2 = $asfx eq "-" ? $num : +substr($asfx, 1);
            $asfx = "";
        }
        return 0 if $num < $anum || $num > $anum2;
        # check test suffix
        return 1 if $asfx eq "" || $asfx eq "*";
        return ($sfx eq "") if $asfx eq ".";
        while ($asfx =~ /([a-z])(-\z|-[a-z]|(?!-))/g) {
            return 1 if $sfx eq $1;
            return 1 if $sfx gt $1 && $2 ne "" && ($2 eq "-" || $sfx le substr($2, 1));
        }
        return 0;
    } else {
        foreach my $m (split_testmatch($match)) {
            return 1 if &match_testid($id, $m);
        }
        return 0;
    }
}

sub testid_runnable ($) {
    my ($testid) = @_;
    return (!@RESTRICT_TESTS || !grep { match_testid($testid, $_) } @RESTRICT_TESTS)
        && (!@ALLOW_TESTS || grep { match_testid($testid, $_) } @ALLOW_TESTS);
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


my ($KeepGoing) = 0;
my ($Sanitizer) = 0;

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
        foreach my $t (split_testmatch($ARGV[1])) {
            push @RESTRICT_TESTS, $t;
        }
        shift @ARGV;
    } elsif ($ARGV[0] =~ /^-r(.+)$/) {
        foreach my $t (split_testmatch($1)) {
            push @RESTRICT_TESTS, $t;
        }
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
        $Sanitizer = 1 if $ARGV[0] =~ /\ASAN=(?!\z|0\z)/;
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

foreach my $arg (@ARGV) {
    if ($arg =~ /=/) {
        push @Makeargs, $arg;
    } else {
        $arg =~ s/test//g;
        foreach my $t (split_testmatch($arg)) {
            push @ALLOW_TESTS, $t;
        }
    }
}

sub test_class ($;@) {
    my($tn) = shift @_;
    my($tnum) = -1;
    if ($tn =~ /\A(?:test|)(\d*)(.*)\z/) {
        $tn = $1 . $2;
        $tnum = int($1);
    }
    foreach my $m (@_) {
        if ($m eq $tn
            || ($m =~ m/\A(\d+)([*a-z])\z/
                && int($1) == $tnum
                && ($2 eq "*" || substr($tn, -1) eq $2))
            || ($m =~ m/\A(\d+)-(\d+)\z/ && $tnum >= $1 && $tnum <= $2)
            || $m eq "san"
            || $m eq "leak"
            || ($m eq "phase1" && $tnum >= 1 && $tnum <= 19)
            || ($m eq "phase2" && $tnum >= 20 && $tnum <= 30)
            || ($m eq "phase3" && $tnum >= 31 && $tnum <= 45)
            || ($m eq "phase4" && $tnum >= 46 && $tnum <= 51)) {
            return 1;
        }
    }
    0;
}

sub asan_options ($) {
    my($tn) = @_;
    $tn =~ s/\A\.\///;
    if ($LeakCheck && test_class($tn, "leak")) {
        return "allocator_may_return_null=1 detect_leaks=1";
    } else {
        return "allocator_may_return_null=1 detect_leaks=0";
    }
}

sub time_limit ($) {
    my($tn) = @_;
    if ($tn =~ /test(\d+)/ && $1 >= 27 && $1 <= 30) {
        return $Sanitizer ? 20 : 10;
    } else {
        return 5;
    }
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
    foreach my $fn (glob("test[0-9][0-9].cc"), glob("test[0-9][0-9][0-9a-z].cc"), glob("test[0-9][0-9][0-9][a-z].cc")) {
        push @tests, substr($fn, 0, -3);
    }
    @tests = sort {
        my($a1, $b1) = ($a, $b);
        $a1 =~ s/\Atest(\d+)[a-z]?\z/$1/;
        $b1 =~ s/\Atest(\d+)[a-z]?\z/$1/;
        return (int($a1) <=> int($b1)) || ($a cmp $b);
    } @tests;

    my($ntest, $ntestfailed) = (0, 0);

    if ($Test) {
        foreach my $tn (@tests) {
            print $tn, "\n" if testid_runnable($tn);
        }
        exit;
    }
    my(%need_make);
    if ($Make) {
        my(@makes);
        foreach my $tn (@tests) {
            push @makes, $tn if testid_runnable($tn);
        }
        my($out) = run_sh61(["make", "-s", "-n", @makes], "stdout" => "pipe");
        if ($out && $out->{status} == 0 && exists($out->{output})) {
            foreach my $tn (@tests) {
                $need_make{$tn} = 1 if index($out->{output}, $tn . " ") >= 0;
            }
        } else {
            foreach my $tn (@tests) {
                $need_make{$tn} = 1;
            }
        }
    }
    $ENV{"MALLOC_CHECK_"} = 0;
    foreach my $tn (@tests) {
        next if !testid_runnable($tn);
        ++$ntest;
        $ENV{"ASAN_OPTIONS"} = asan_options($tn);
        run_make($tn) if exists($need_make{$tn});
        printf STDERR "${tn} ";
        $out = run_sh61("./${tn}",
            "stdout" => "pipe", "stdin" => "/dev/null",
            "time_limit" => time_limit($tn),
            "size_limit" => 80000);
        my ($failed) = 0;
        if (exists($out->{killed})) {
            print_killed($tn, $out);
            $failed = 1;
        } else {
            $failed = run_compare([split("\n", $out->{output})],
                    read_expected("${tn}.cc"),
                    "output", "${tn}.cc", "\r$tn ", $out);
        }
        if ($failed) {
            ++$ntestfailed;
            exit(1) if !$KeepGoing;
        }
    }
    my($ntestpassed) = $ntest - $ntestfailed;
    if ($ntest == 0) {
        print STDERR "${Red}No tests match$Off\n";
        exit(2);
    } if ($ntest == @tests && $ntestpassed == $ntest) {
        print STDERR "${Green}All tests passed!$Off\n";
        exit(0);
    } else {
        my($color) = ($ntestpassed == 0 ? $Red : ($ntestpassed == $ntest ? $Green : $Cyan));
        if ($ntest != 1) {
            print STDERR "${color}$ntestpassed of $ntest ", ($ntest == 1 ? "test" : "tests"), " passed$Off\n";
        }
        exit($ntestpassed == $ntest ? 0 : 1);
    }
}
