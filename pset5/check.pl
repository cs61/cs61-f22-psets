#! /usr/bin/perl -w

# check.pl
#    This program runs tests on sh61 and analyzes the results for
#    errors.

use Time::HiRes qw(gettimeofday);
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);
use POSIX;
use Scalar::Util qw(looks_like_number);
use List::Util qw(shuffle min max);
use Config;

sub first (@) { return $_[0]; }
my($CHECKSUM) = first(grep {-x $_} ("/usr/bin/md5sum", "/sbin/md5", "/bin/false"));
my($TTY) = (`tty` or "/dev/tty");
chomp($TTY);
my(@sig_name) = split(/ /, $Config{"sig_name"});
my($SIGINT) = 0;
while ($sig_name[$SIGINT] ne "INT") {
    ++$SIGINT;
}

my($Red, $Redctx, $Green, $Greenctx, $Cyan, $Ylo, $Yloctx, $Off) = ("\x1b[01;31m", "\x1b[0;31m", "\x1b[01;32m", "\x1b[0;32m", "\x1b[01;36m", "\x1b[01;33m", "\x1b[0;33m", "\x1b[0m");
$Red = $Redctx = $Green = $Greenctx = $Cyan = $Ylo = $Yloctx = $Off = "" if !-t STDERR || !-t STDOUT;

my(@clean_pgrps);
sub remove_clean_pgrp ($) {
    my $i = 0;
    ++$i while ($i < @clean_pgrps && $clean_pgrps[$i] != $_[0]);
    splice(@clean_pgrps, $i, 1) if $i < @clean_pgrps;
}
sub kill_clean_pgrp () {
    foreach my $pgrp (@clean_pgrps) {
        kill -9, $pgrp;
    }
    @clean_pgrps = ();
}

$SIG{"CHLD"} = sub {};
$SIG{"TSTP"} = "DEFAULT";
$SIG{"TTOU"} = "IGNORE";
$SIG{"INT"} = sub {
    kill_clean_pgrp();
    $SIG{"INT"} = "DEFAULT";
    kill $SIGINT, $$;
};
my($ignore_sigint) = 0;
open(TTY, "+<", $TTY) or die "can't open $TTY: $!";

open(FOO, "sh61.cc") || die "Did you delete sh61.cc?";
$lines = 0;
$lines++ while defined($_ = <FOO>);
close FOO;

my $rev = 'rev';
my $ALLOW_OPEN = 1;
my $ALLOW_SECRET = 0;
my @ALLOW_TESTS = ();

sub CMD_INIT ()           { "CMD_INIT" }
sub CMD_CLEANUP ()        { "CMD_CLEANUP" }
sub CMD_CAREFUL_CLEANUP () { "CMD_CAREFUL_CLEANUP" }
sub CMD_SCRIPT_FILE ()    { "CMD_SCRIPT_FILE" }
sub CMD_OUTPUT_FILTER ()  { "CMD_OUTPUT_FILTER" }
sub CMD_INT_DELAY ()      { "CMD_INT_DELAY" }
sub CMD_SECRET ()         { "CMD_SECRET" }
sub CMD_CAT ()            { "CMD_CAT" }
sub CMD_MAX_TIME ()       { "CMD_MAX_TIME" }
sub CMD_TIME_LIMIT ()     { "CMD_TIME_LIMIT" }
sub CMD_FILE ()           { "CMD_FILE" }
sub CMD_SKIP ()           { "CMD_SKIP" }

@tests = (
# Execute
    [ # Each test is defined as an array with components:
      # 0. Test title
      # 1. Test description
      # 2. Command list
      # 3. Expected test output (with newlines changed to spaces)
      # Remaining parameters are optional.
      # CMD_INIT: Command list to set up the test environment, usually by
      #    creating input files. It's run by the normal shell.
      # CMD_CLEANUP: Command list to clean up, run by the normal shell after
      #    the main command has finished. Usually examines output files. Its
      #    output is appended to the main output file.
      # CMD_INT_DELAY: Send SIGINT to the command after this time passes.
      # CMD_SCRIPT_FILE: If set, store command in a file, not stdin.
      # CMD_MAX_TIME: Maximum time the command list should run; longer
      #    delay indicates an error.
      # CMD_TIME_LIMIT: Test aborts after this many seconds (default 10).
      # CMD_FILE: Argument is a list reference [FILENAME, CONTENT].
      # In the commands, the special syntax '%%' is replaced with the
      # test number.
      'Test SIMPLE1',
      'simple command',
      'echo Hooray',
      'Hooray' ],

    [ 'Test SIMPLE2',
      'simple command',
      'echo Double Hooray',
      'Double Hooray' ],

    [ 'Test SIMPLE3',
      'simple command',
      'cat f3.txt',
      'Triple Hooray',
      CMD_FILE => [ "f3.txt" => "Triple Hooray" ] ],

    [ 'Test SIMPLE4',
      'multiple simple commands',
      "echo Line 1\necho Line 2\necho Line 3",
      'Line 1 Line 2 Line 3' ],

    [ 'Test SIMPLE5',
      'foreground command is waited for',
      'sh -c "sleep 0.1; echo > f5.txt"',
      '',
      CMD_FILE => [ "f5.txt" => "no" ],
      CMD_CLEANUP => 'cat f5.txt' ],


# Command lists
    [ 'Test LIST1',
      'semicolon at end of list',
      'echo Semi ;',
      'Semi' ],

    [ 'Test LIST2',
      'semicolon between commands',
      'echo Semi ; echo Colon',
      'Semi Colon' ],

    [ 'Test LIST3',
      'semicolon between commands',
      'echo Semi ; echo Colon ; echo Rocks',
      'Semi Colon Rocks' ],

    [ 'Test LIST4',
      'semicolon between commands',
      'echo Hello ;   echo There ; echo Who ; echo Are ; echo You ; echo ?',
      'Hello There Who Are You ?' ],

    [ 'Test LIST5',
      'all commands in semicolon list run',
      'rm -f f%%.txt ; echo Removed',
      'Removed',
      CMD_FILE => [ "f%%.txt" => "no" ] ],


# Conditionals
    [ 'Test COND1',
      '&& respects failure status',
      'false && echo True',
      '' ],

    [ 'Test COND2',
      '&& respects success status',
      'true && echo True',
      'True' ],

    [ 'Test COND3',
      '|| respects success status',
      'echo True || echo False',
      'True' ],

    [ 'Test COND4',
      '|| respects failure status',
      'false || echo True',
      'True' ],

    [ 'Test COND5',
      '&& respects success status',
      'grep -cv NotThere ../sh61.cc && echo Wanted',
      "$lines Wanted" ],

    [ 'Test COND6',
      '&& respects failure status',
      'grep -c NotThere ../sh61.cc && echo Unwanted',
      '0' ],

    [ 'Test COND7',
      'conditional chains without output',
      'true && false || true && echo Good',
      'Good' ],

    [ 'Test COND8',
      'conditional chains with early output',
      'echo Start && false || false && echo Bad',
      'Start' ],

    [ 'Test COND9',
      'double-quoted arguments',
      'echo "&&" hello && echo "||" hello',
      '&& hello || hello'],

    [ 'Test COND10',
      'conditional chains with output',
      'echo Start && false || false && false || echo End',
      'Start End' ],

    [ 'Test COND11',
      '&& conditional chains with output',
      'false && echo no && echo no && echo no && echo no || echo yes',
      'yes' ],

    [ 'Test COND12',
      '|| conditional chains with output',
      'true || echo no || echo no || echo no || echo no && echo yes',
      'yes' ],

    [ 'Test COND13',
      'non-exit status and ||',
      '../build/timeout.sh 0.02 sleep 10 || echo yes',
      'yes' ],

    [ 'Test COND14',
      'non-exit status and &&',
      '../build/timeout.sh 0.02 sleep 10 && echo no',
      '' ],


# Pipelines
    [ 'Test PIPE1',
      'simple pipeline',
      'echo Pipe | wc -c',
      '5' ],

    [ 'Test PIPE2',
      'simple pipeline',
      'echo Ignored | echo Desired',
      'Desired' ],

    [ 'Test PIPE3',
      'simple pipeline',
      'echo Good | grep -n G',
      '1:Good' ],

    [ 'Test PIPE4',
      'simple pipeline',
      'echo Bad | grep -c G',
      '0' ],

    [ 'Test PIPE5',
      'pipeline running in parallel',
      'yes | head -n 5',
      'y y y y y' ],

    [ 'Test PIPE6',
      'three-command pipeline',
      'echo Line | cat | wc -l',
      '1' ],

    [ 'Test PIPE7',
      'rev in pipeline',
      "$rev f%%.txt | $rev",
      'goHangasaLAmIimalaSAgnaHoG',
      CMD_FILE => [ "f%%.txt" => "goHangasaLAmIimalaSAgnaHoG" ] ],

    [ 'Test PIPE8',
      'four-command pipeline',
      "echo GoHangASalamiImALasagnaHog | $rev | $rev | $rev",
      'goHangasaLAmIimalaSAgnaHoG' ],

    [ 'Test PIPE9',
      'multi-command pipeline',
      "cat f%%.txt | tr [A-Z] [a-z] | $CHECKSUM | tr -d -",
      '8e21d03f7955611616bcd2337fe9eac1',
      CMD_FILE => [ "f%%.txt" => "goHangasaLAmIimalaSAgnaHoG" ] ],

    [ 'Test PIPE10',
      'multi-command pipeline',
      "$rev f%%.txt | $CHECKSUM | tr [a-z] [A-Z] | tr -d -",
      '502B109B37EC769342948826736FA063',
      CMD_FILE => [ "f%%.txt" => "goHangasaLAmIimalaSAgnaHoG" ] ],

    [ 'Test PIPE11',
      'pipelines and semicolons',
      'echo Sedi | tr d m ; echo Calan | tr a o',
      'Semi Colon' ],

    # pipes and conditionals
    [ 'Test PIPE12',
      'pipeline status',
      'true | true && echo True',
      'True' ],

    [ 'Test PIPE13',
      'pipeline status',
      'true | echo True || echo False',
      'True' ],

    [ 'Test PIPE14',
      'pipeline status',
      'false | echo True || echo False',
      'True' ],

    [ 'Test PIPE15',
      'pipeline status',
      'echo Hello | grep -q X || echo NoXs',
      'NoXs' ],

    [ 'Test PIPE16',
      'pipeline status',
      'echo Yes | grep -q Y && echo Ys',
      'Ys' ],

    [ 'Test PIPE17',
      'pipelines and ||',
      'echo Hello | grep -q X || echo poqs | tr pq NX',
      'NoXs' ],

    [ 'Test PIPE18',
      'pipelines and &&',
      'echo Yes | grep -q Y && echo fs | tr f Y',
      'Ys' ],

    [ 'Test PIPE19',
      'pipeline precedence',
      'false && echo vnexpected | tr v u ; echo expected',
      'expected' ],

    [ 'Test PIPE20',
      'pipeline precedence',
      'false && echo unexpected && echo vnexpected | tr v u ; echo expected',
      'expected' ],

    # Some shells wait for all processes in a pipeline to exit, so this test
    # is not enabled.
    # [ 'Test PIPE25',
    #   'pipeline exit without wait',
    #   "false && sleep 2.061 | echo foo",
    #   '0',
    #   CMD_CLEANUP => "ps t $TTY | grep -cm1 \"slee*p 2.061\"" ],


# Background commands
    [ 'Test BG1',
      'background commands run',
      '/bin/sh -c "sleep 0.1; echo Replaced > f%%.txt" &',
      'Original Replaced',
      CMD_FILE => [ "f%%.txt" => "Original" ],
      CMD_CLEANUP => 'cat f%%.txt; sleep 0.15; cat f%%.txt' ],

    # Check that background commands are run in the background
    [ 'Test BG2',
      'background command is not waited for',
      'sleep 2 &',
      '1',
      CMD_FILE => [ "clean%%.sh" => "ps t $TTY | grep -cm1 \"slee*p\"" ],
      CMD_CLEANUP => "sh clean%%.sh" ],

    [ 'Test BG3',
      'background command is not waited for',
      'sh -c "sleep 0.2; test -r f%%b.txt && rm -f f%%a.txt" &',
      'Still here',
      CMD_FILE => [ "f%%a.txt" => "Still here", "f%%b.txt" => "" ],
      CMD_CLEANUP => 'rm f%%b.txt && sleep 0.3 && cat f%%a.txt' ],

    [ 'Test BG4',
      'background commands not creating extra shells',
      "echo &\nsleep 0.1\nps t $TTY",
      '1',
      CMD_OUTPUT_FILTER => 'grep sh61 | grep -v Z | wc -l' ],

    [ 'Test BG5',
      'all commands in semicolon list run',
      '../sh61 -q cmd%%a.sh &',
      'Hello 1',
      CMD_FILE => [ "cmd%%a.sh" => "echo Hello; sleep 0.4",
                    "clean%%.sh" => "sleep 0.2; ps t $TTY | grep -cm1 \"slee*p\"" ],
      CMD_CLEANUP => "sh clean%%.sh"],

    [ 'Test BG6',
      'semicolon/background precedence',
      '../sh61 -q cmd%%.sh',
      'Hello Bye 1',
      CMD_FILE => [ "cmd%%.sh" => "echo Hello; sleep 2& echo Bye" ],
      CMD_CLEANUP => "ps t $TTY | grep -cm1 \"slee*p\""],

    [ 'Test BG7',
      'background does not wait',
      'sh -c "sleep 0.1; echo Second" & sh -c "sleep 0.05; echo First" & sleep 0.15',
      'First Second' ],

    [ 'Test BG8',
      'second background does not wait',
      'sleep 0.2 & sleep 0.2 & echo OK',
      'OK',
      CMD_MAX_TIME => 0.1 ],

    [ 'Test BG9',
      'second background command not creating extra shells',
      "true & true &\nsleep 0.1\nps t $TTY\ntrue",
      '1',
      CMD_OUTPUT_FILTER => 'grep sh61 | grep -v Z | wc -l' ],

    [ 'Test BG10',
      'conditional chains and background',
      'sleep 0.2 && echo Second & sleep 0.1 && echo First',
      'First Second',
      CMD_CLEANUP => 'sleep 0.25'],

    [ 'Test BG11',
      'more conditionals with background',
      'echo first && sleep 0.1 && echo third & sleep 0.05 ; echo second ; sleep 0.1 ; echo fourth',
      'first second third fourth' ],

    [ 'Test BG12',
      'pipelines, background, semicolons',
      "../sh61 -q cmd%%.sh; ps t $TTY | grep -m1 \"slee*p\" | wc -l",
      'Hello Bye 1',
      CMD_INIT => 'echo "echo Hello; sleep 2 & echo Bye; sleep 0.1" > cmd%%.sh'],

    [ 'Test BG13',
      'pipelines, background',
      "sleep 2 & sleep 0.2; ps t $TTY | grep \"slee*p\" | cat | head -n 1 | wc -l",
      '1',
      CMD_SCRIPT_FILE => 1,
      CMD_TIME_LIMIT => 2 ],

    [ 'Test BG14',
      'pipelines, background',
      '../sh61 -q cmd%%.sh &',
      'Hello 1',
      CMD_FILE => [ "cmd%%.sh" => "echo Hello; sleep 0.4",
                    "clean%%.sh" => "sleep 0.2 ; ps t $TTY | grep -cm1 \"slee*p\"" ],
      CMD_CLEANUP => "../sh61 -q clean%%.sh",
      CMD_CAREFUL_CLEANUP => 1,
      CMD_SCRIPT_FILE => 1,
      CMD_TIME_LIMIT => 2 ],

    [ 'Test BG15', # actually a background test
      'pipeline and background',
      'sleep 0.2 | wc -c | sed s/0/Second/ & sleep 0.1 | wc -c | sed s/0/First/',
      'First Second',
      CMD_CLEANUP => 'sleep 0.25'],


# Zombies
    [ 'Test ZOMBIE1',
      'simple zombie cleanup',
      "sleep 0.05 &\nsleep 0.1\nps t $TTY",
      '',
      CMD_OUTPUT_FILTER => 'grep defunct | grep -v grep'],

    [ 'Test ZOMBIE2',
      'tougher zombie cleanup',
      "sleep 0.05 & sleep 0.05 & sleep 0.05 & sleep 0.05 &\nsleep 0.07\nsleep 0.07\nps t $TTY",
      '',
      CMD_OUTPUT_FILTER => 'grep defunct | grep -v grep'],


# Redirection
    [ 'Test REDIR1',
      'output redirection',
      'echo Start ; echo File > f%%.txt',
      'Start File',
      CMD_CLEANUP => 'cat f%%.txt'],

    [ 'Test REDIR2',
      'input redirection',
      'tr pq Fi < f%%.txt ; echo Done',
      'File Done',
      CMD_FILE => [ "f%%.txt" => "pqle" ] ],

    [ 'Test REDIR3',
      'redirection and pipeline',
      'cat unwanted.txt | cat < wanted.txt',
      'Wanted',
      CMD_FILE => [ "unwanted.txt" => "Unwanted", "wanted.txt" => "Wanted" ] ],

    [ 'Test REDIR4',
      'two redirections and pipeline',
      'cat < wanted.txt | cat > output.txt',
      'output.txt is Wanted',
      CMD_FILE => [ "wanted.txt" => "Wanted" ],
      CMD_CLEANUP => 'echo output.txt is; cat output.txt' ],

    [ 'Test REDIR5',
      'two redirections and long pipeline',
      'cat < xoqted.txt | tr xoq Wan | cat > output.txt',
      'output.txt is Wanted',
      CMD_FILE => [ "xoqted.txt" => "xoqted" ],
      CMD_CLEANUP => 'echo output.txt is; cat output.txt' ],

    [ 'Test REDIR6',
      'redirection overriding pipeline',
      'echo Ignored | cat < lower.txt | tr A-Z a-z',
      'lower',
      CMD_FILE => [ "lower.txt" => "LOWER" ] ],

    [ 'Test REDIR7',
      'redirection and pipeline',
      'tr hb HB < f%%.txt | sort | ../sh61 -q cmd%%.sh',
      'Bye Hello First Good',
      CMD_FILE => [ "cmd%%.sh" => "head -n 2 ; echo First && echo Good",
                    "f%%.txt" => "hello\nbye" ] ],

    [ 'Test REDIR8',
      'stderr redirection',
      "perl -e 'print STDERR $$' 2> f%%.txt ; grep '^[1-9]' f%%.txt | wc -l ; rm -f f%%.txt",
      '1',
      CMD_FILE => [ "f%%.txt" => "File" ] ],

    [ 'Test REDIR9',
      'multiple redirections',
      "perl -e 'print STDERR $$; print STDOUT \"X\"' > f%%a.txt 2> f%%b.txt ; grep '^[1-9]' f%%a.txt | wc -l ; grep '^[1-9]' f%%b.txt | wc -l ; cmp -s f%%a.txt f%%b.txt || echo Different",
      '0 1 Different',
      CMD_FILE => [ "f%%.txt" => "File" ] ],

    [ 'Test REDIR10',
      'multiple redirections',
      'sort < f%%a.txt > f%%b.txt ; tail -n 2 f%%b.txt ; rm -f f%%a.txt f%%b.txt',
      'Bye Hello',
      # (Remember, CMD_INIT is a normal shell command! For your shell,
      # parentheses are extra credit.)
      CMD_FILE => [ "f%%a.txt" => "Hello\nBye" ] ],

    [ 'Test REDIR11',
      'redirection error messages',
      'echo > /tmp/directorydoesnotexist/foo',
      'No such file or directory',
      CMD_CLEANUP => 'perl -pi -e "s,^.*:\s*,," out%%.txt' ],

    [ 'Test REDIR12',
      'redirection error command status',
      'echo notshown > /tmp/directorydoesnotexist/foo && echo Unwanted',
      'No such file or directory',
      CMD_CLEANUP => 'perl -pi -e "s,^.*:\s*,," out%%.txt' ],

    [ 'Test REDIR13',
      'redirection error command status',
      'echo notshown > /tmp/directorydoesnotexist/foo || echo Wanted',
      'No such file or directory Wanted',
      CMD_CLEANUP => 'perl -pi -e "s,^.*:\s*,," out%%.txt' ],

    [ 'Test REDIR14',
      'redirection error messages',
      'echo Hello < nonexistent%%.txt',
      'No such file or directory',
      CMD_CLEANUP => 'perl -pi -e "s,^.*:\s*,," out%%.txt' ],

    [ 'Test REDIR15',
      'redirection error command status',
      'echo Hello < nonexistent%%.txt && echo Unwanted',
      'No such file or directory',
      CMD_CLEANUP => 'perl -pi -e "s,^.*:\s*,," out%%.txt' ],

    [ 'Test REDIR16',
      'redirection error command status',
      'echo Hello < nonexistent%%.txt || echo Wanted',
      'No such file or directory Wanted',
      CMD_CLEANUP => 'perl -pi -e "s,^.*:\s*,," out%%.txt' ],

    [ 'Test REDIR17',
      'redirection placement',
      'echo > out.txt the redirection can occur anywhere && cat out.txt',
      'the redirection can occur anywhere' ],

    [ 'Test REDIR18',
      'redirection placement',
      'echo the redirection > out.txt can really occur anywhere && cat out.txt',
      'the redirection can really occur anywhere' ],


# cd
    [ 'Test CD1',
      'cd',
      'cd / ; pwd',
      '/' ],

    [ 'Test CD2',
      'multiple cd',
      'cd / ; cd /usr ; pwd',
      '/usr' ],

# cd without redirecting stdout
    [ 'Test CD3',
      'cd error',
      'cd / ; cd /doesnotexist 2> /dev/null ; pwd',
      '/' ],

    [ 'Test CD4',
      'cd error',
      'cd / ; cd /doesnotexist 2> /dev/null > /dev/null ; pwd',
      '/' ],

    [ 'Test CD5',
      'cd command status',
      'cd / && pwd',
      '/' ],

    [ 'Test CD6',
      'cd command status',
      'echo go ; cd /doesnotexist 2> /dev/null > /dev/null && pwd',
      'go' ],

    [ 'Test CD7',
      'cd command status',
      'cd /doesnotexist 2> /dev/null > /dev/null || echo does not exist',
      'does not exist' ],

    [ 'Test CD8',
      'multiple cd in conditional',
      'cd /tmp && cd / && pwd',
      '/' ],


# Interrupts
    [ 'Test INTR1',
      'interrupt stopping conditional',
      'echo a && sleep 0.2 && echo b',
      'a',
      CMD_INT_DELAY => 0.1,
      CMD_SKIP => 1 ],

    [ 'Test INTR2',
      'interrupt stopping command',
      'sleep 1',
      '',
      CMD_INT_DELAY => 0.1,
      CMD_MAX_TIME => 0.15,
      CMD_SKIP => 1 ],

    [ 'Test INTR3',
      'interrupt stopping shell',
      '../sh61 -q cmd%%.sh',
      '',
      CMD_INIT => 'echo "sleep 1 && echo undesired" > cmd%%.sh',
      CMD_INT_DELAY => 0.1,
      CMD_MAX_TIME => 0.15,
      CMD_SKIP => 1 ],

    [ 'Test INTR4',
      'interrupt continuing to next list',
      "echo start && sleep 0.2 && echo undesired \n echo end",
      'start end',
      CMD_SCRIPT_FILE => 1,
      CMD_INT_DELAY => 0.1,
      CMD_SKIP => 1 ],

    [ 'Test INTR5',
      'interrupt not stopping background',
      'sleep 0.2 && echo yes & sleep 0.1 && echo no',
      'yes',
      CMD_CLEANUP => 'sleep 0.15',
      CMD_INT_DELAY => 0.07,
      CMD_SKIP => 1 ]


    );

my($ntest) = 0;

my($sh) = "./sh61";
-d "out" || mkdir("out") || die "Cannot create 'out' directory\n";
my($ntestfailed) = 0;

# check for a ton of existing sh61 processes
$me = `id -un`;
chomp $me;
open(SH61, "ps uxww | grep '^$me.*sh61' | grep -v grep |");
$nsh61 = 0;
$nsh61 += 1 while (defined($_ = <SH61>));
close SH61;
if ($nsh61 > 5) {
    print STDERR "\n";
    print STDERR "${Red}**** Looks like $nsh61 ./sh61 processes are already running.\n";
    print STDERR "**** Do you want all those processes?\n";
    print STDERR "**** Run 'killall -9 sh61' to kill them.${Off}\n\n";
}

# remove output files
opendir(DIR, "out") || die "opendir: $!\n";
foreach my $f (grep {/\.(?:txt|sh)$/} readdir(DIR)) {
    unlink("out/$f");
}
closedir(DIR);

if (!-x $sh) {
    $editsh = $sh;
    $editsh =~ s,^\./,,;
    print STDERR "${Red}$sh does not exist, so I can't run any tests!${Off}\n(Try running \"make $editsh\" to create $sh.)\n";
    exit(1);
}

select STDOUT;
$| = 1;

my($testsrun) = 0;
my($testindex) = 0;

sub remove_files ($) {
    my($testnumber) = @_;
    opendir(DIR, "out");
    foreach my $f (grep {/$testnumber\.(?:sh|txt)$/} readdir(DIR)) {
        unlink("out/$f");
    }
    closedir(DIR);
}

sub unparse_signal ($) {
    my($s) = @_;
    my(@sigs) = split(" ", $Config{sig_name});
    return "unknown signal $s" if $s >= @sigs;
    return "illegal instruction" if $sigs[$s] eq "ILL";
    return "abort signal" if $sigs[$s] eq "ABRT";
    return "floating point exception" if $sigs[$s] eq "FPE";
    return "segmentation fault" if $sigs[$s] eq "SEGV";
    return "broken pipe" if $sigs[$s] eq "PIPE";
    return "SIG" . $sigs[$s];
}

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
        $size_limit_file = [map { m{^/} ? $_ : "$dir/$_" } @$size_limit_file];
    }
    pipe(OR, OW) or die "pipe";
    fcntl(OR, F_SETFL, fcntl(OR, F_GETFL, 0) | O_NONBLOCK);
    1 while waitpid(-1, WNOHANG) > 0;

    my($preutime, $prestime, $precutime, $precstime) = times();

    my($run61_pid) = fork();
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

    my($run61_pgrp) = $run61_pid;
    POSIX::setpgid($run61_pid, $run61_pgrp);    # might fail if child exits quickly
    POSIX::tcsetpgrp(fileno(TTY), $run61_pgrp); # might fail if child exits quickly
    push @clean_pgrps, $run61_pgrp;

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
            my($delta) = 0.3;
            if ($sigint_at) {
                my($now) = Time::HiRes::time();
                $delta = min($delta, $sigint_at < $now + 0.02 ? 0.1 : $sigint_at - $now);
            }
            Time::HiRes::usleep($delta * 1e6) if $delta > 0;

            if (waitpid($run61_pid, WNOHANG) > 0) {
                $answer->{"status"} = $?;
                die "!";
            }
            if ($sigint_state == 1 && Time::HiRes::time() >= $sigint_at) {
                my($pgrp) = POSIX::tcgetpgrp(fileno(TTY));
                if ($pgrp != getpgrp()) {
                    kill -$SIGINT, $pgrp;
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
            $answer->{"status"} = $?;
        } else {
            $died = sprintf("timeout after %.2fs", $time_limit);
        }
    };

    POSIX::tcsetpgrp(fileno(TTY), getpgrp()) or print STDERR "parent tcsetpgrp: $!\n";
    my($delta) = Time::HiRes::time() - $before;
    $answer->{"time"} = $delta;
    my($run61_status) = exists($answer->{"status"}) ? $answer->{"status"} : 0;

    if ($sigint_state < 2
        && ($run61_status & 127) == $SIGINT
        && !$ignore_sigint) {
        # assume user is trying to quit
        kill_clean_pgrp();
        exit(1);
    }
    if (exists($answer->{"status"})
        && exists($opt{"delay"})
        && $opt{"delay"} > 0) {
        Time::HiRes::usleep($opt{"delay"} * 1e6);
    }
    if (exists($opt{"nokill"})) {
        $answer->{"pgrp"} = $run61_pgrp;
    } else {
        kill -9, $run61_pgrp;
        waitpid($run61_pid, 0);
        remove_clean_pgrp($run61_pgrp);
    }

    my($postutime, $poststime, $postcutime, $postcstime) = times();
    $answer->{"utime"} = $postcutime - $precutime;
    $answer->{"stime"} = $postcstime - $precstime;

    if ($died) {
        $answer->{"killed"} = $died;
        close(OR);
        return $answer;
    }

    if (defined($outfile) && $outfile ne "pipe") {
        $out = "";
        close(OR);
        open(OR, "<", (defined($dir) ? "$dir/$outfile" : $outfile));
    }
    $out = run_sh61_pipe($out, fileno(OR), $size_limit);
    close(OR);

    $answer->{"output"} = $out;

    my(@stderr);
    if (0) {
        my($tx) = "";
        foreach my $l (split(/\n/, $out)) {
            $tx .= ($tx eq "" ? "" : "        : ") . $l . "\n" if $l ne "";
        }
        if ($tx ne "" && exists($answer->{"trial"})) {
            push @stderr, "    ${Redctx}STDERR (trial " . $answer->{"trial"} . "): $tx${Off}";
        } elsif ($tx ne "") {
            push @stderr, "    ${Redctx}STDERR: $tx${Off}";
        }
    }
    if (exists($answer->{"status"})
        && ($answer->{"status"} & 127)
        && (($answer->{"status"} & 127) != $SIGINT || $sigint_state != 2)) {
        my($signame) = unparse_signal($answer->{"status"} & 127);
        if (exists($answer->{"trial"})) {
            push @stderr, "    ${Redctx}KILLED by $signame (trial " . $answer->{"trial"} . ")${Off}";
        } else {
            push @stderr, "    ${Redctx}KILLED by $signame${Off}";
        }
        if (($answer->{"status"} & 127) == $SIGINT) {
            kill $SIGINT, 0;
        }
    }
    $answer->{"stderr"} = join("\n", @stderr) if @stderr;

    return $answer;
}

sub test_runnable ($$) {
    my($prefix, $number) = @_;
    $prefix = lc($prefix);
    return !@ALLOW_TESTS || grep {
        $prefix eq $_->[0]
            && ($_->[1] eq ""
                || ($number >= $_->[1]
                    && ($_->[2] eq "-" || $number <= ($_->[2] eq "" ? $_->[1] : -$_->[2]))));
    } @ALLOW_TESTS;
}

sub kill_sleeps () {
    open(PS, "ps t $TTY |");
    while (defined($_ = <PS>)) {
        $_ =~ s/^\s+//;
        my(@x) = split(/\s+/, $_);
        if (@x && $x[0] =~ /\A\d+\z/ && $x[4] eq "sleep") {
            kill $SIGINT, $x[0];
        }
    }
    close(PS);
}

sub system_intexit ($) {
    my($rv) = system($_[0]);
    if (($rv & 127) == $SIGINT) {
        kill $SIGINT, $$;
    }
    $rv;
}

sub run (@) {
    my($testnumber);
    if ($_[0] =~ /^Test (\w*?)(\d*)(\.\d+|[a-z]+|)(?=$|[.:\s])/i) {
        $testnumber = $1 . $2 . $3;
        return if !test_runnable($1, $2);
    } else {
        $testnumber = "x" . $testindex;
    }

    for (my $i = 0; $i < @_; ++$i) {
        $_[$i] =~ s/\%\%/$testnumber/g;
    }

    my ($desc, $longdesc, $in, $want) = @_;
    my (%opts);
    if ((@_ < 4 || substr($_[3], 0, 4) eq "CMD_")
        || (@_ > 4 && substr($_[4], 0, 4) ne "CMD_")) {
        print STDERR "Failure: old test format ", $desc, "\n";
        exit 1;
    } elsif (@_ > 4) {
        %opts = @_[4..(@_ - 1)];
    }
    return if $opts{CMD_SECRET} && !$ALLOW_SECRET;
    return if !$opts{CMD_SECRET} && !$ALLOW_OPEN;
    return if $opts{CMD_SKIP} && !@ALLOW_TESTS;
    $opts{CMD_FILE} = [] if !exists($opts{CMD_FILE});

    $ntest++;
    remove_files($testnumber);
    kill_sleeps();
    system_intexit("{ cd out; " . $opts{CMD_INIT} . "; } </dev/null >/dev/null 2>&1")
        if $opts{CMD_INIT};
    for (my $fi = 0; $fi != @{$opts{CMD_FILE}}; $fi += 2) {
        my $fn = $opts{CMD_FILE}->[$fi];
        $fn =~ s/\%\%/$testnumber/g;
        open(F, ">", "out/" . $fn) or die $fn;
        my $fd = $opts{CMD_FILE}->[$fi + 1];
        $fd =~ s/\%\%/$testnumber/g;
        print F $fd, "\n";
        close F;
    }

    print OUT "$desc: ";
    my($tempfile) = "main$testnumber.sh";
    my($outfile) = "out$testnumber.txt";
    open(F, ">out/$tempfile") || die;
    print F $in, "\n";
    close(F);

    my($start) = Time::HiRes::time();
    my($cmd) = "../$sh -q" . ($opts{CMD_SCRIPT_FILE} ? " $tempfile" : "");
    my($stdin) = $opts{CMD_SCRIPT_FILE} ? "/dev/stdin" : $tempfile;
    my($time_limit) = $opts{CMD_TIME_LIMIT} ? $opts{CMD_TIME_LIMIT} : 10;
    my($info) = run_sh61($cmd, "stdin" => $stdin, "stdout" => $outfile, "time_limit" => $time_limit, "size_limit" => 1000, "dir" => "out", "nokill" => 1, "delay" => 0.05, "int_delay" => $opts{CMD_INT_DELAY});

    if ($opts{CMD_CLEANUP}) {
        if ($opts{CMD_CAREFUL_CLEANUP}) {
            my($infox) = run_sh61("{ " . $opts{CMD_CLEANUP} . "; } >>$outfile 2>&1", "time_limit" => $time_limit, "dir" => "out", "stdin" => "/dev/stdin", "stdout" => "/dev/stdout");
            $info->{killed} = "cleanup command killed"
                if exists($infox->{killed}) && !exists($info->{killed});
        } else {
            system_intexit("cd out; { " . $opts{CMD_CLEANUP} . "; } </dev/null >>$outfile 2>&1");
        }
    }
    system_intexit("cd out; mv $outfile ${outfile}~; { " . $opts{CMD_OUTPUT_FILTER} . "; } <${outfile}~ >$outfile 2>&1")
        if $opts{CMD_OUTPUT_FILTER};

    if (exists($info->{"pgrp"})) {
        kill -9, $info->{"pgrp"};
        remove_clean_pgrp($info->{"pgrp"});
    }

    my($ok, $prefix, $sigdead) = (1, "");
    if (exists($info->{"status"})
        && ($info->{"status"} & 127)
        && exists($info->{"stderr"})) {  # died from signal
        my $t = $info->{"stderr"};
        $t =~ s/^\s+//;
        print OUT $t, "\n";
        $ntestfailed += 1 if $ok;
        $ok = 0;
        $prefix = "  ";
    }
    $result = `cat out/$outfile`;
    # sanitization errors
    my($sanitizera, $sanitizerb) = ("", "");
    if ($result =~ /\A([\s\S]*?)^(===+\s+==\d+==\s*ERROR[\s\S]*)\z/m) {
        $result = $1;
        $sanitizerb = $2;
    }
    while ($result =~ /\A([\s\S]*?)^(\S+\.cc:\d+:(?:\d+:)? runtime error.*(?:\n|\z)|=+\s+WARNING.*Sanitizer[\s\S]*?\n=+\n)([\s\S]*)\z/m) {
        $result = $1 . $3;
        $sanitizera .= $2;
    }
    my($sanitizer) = $sanitizera . $sanitizerb;
    $result =~ s%^sh61[\[\]\d]*\$ %%m;
    $result =~ s%sh61[\[\]\d]*\$ $%%m;
    $result =~ s%^\[\d+\]\s+\d+$%%mg;
    $result =~ s|\[\d+\]||g;
    $result =~ s|^\s+||g;
    $result =~ s|\s+| |g;
    $result =~ s|\s+$||;
    if (($result eq $want
         || ($want eq 'Syntax error [NULL]' && $result eq '[NULL]'))
        && !exists($info->{killed})
        && (!$opts{CMD_MAX_TIME} || $info->{time} <= $opts{CMD_MAX_TIME})) {
        # remove all files unless @ARGV was set
        print OUT "${Green}passed${Off}\n" if $ok;
        remove_files($testnumber) if !@ARGV && $ok;
    } else {
        printf OUT "$prefix${Red}FAILED${Redctx} in %.3f sec${Off}\n", $info->{time};
        $in =~ s/\n/ \\n /g;
        print OUT "    Checking $longdesc\n";
        print OUT "    Command  \`$in\`\n";
        if ($result eq $want) {
            print OUT "    Output   \`$want\`\n" if $want ne "";
        } else {
            print OUT "    Expected \`$want\`\n";
            $result = substr($result, 0, 76) . "..." if length($result) > 76;
            print OUT "    Got      \`$result\`\n";
        }
        if ($opts{CMD_MAX_TIME} && $info->{time} > $opts{CMD_MAX_TIME}) {
            printf OUT "    Should have completed in %.3f sec\n", $opts{CMD_MAX_TIME};
        }
        if (exists($info->{killed})) {
            print OUT "  ", $info->{killed}, "\n";
        }
        $ntestfailed += 1 if $ok;
    }
    if ($sanitizer ne "") {
        chomp $sanitizer;
        $sanitizer = substr($sanitizer, 0, 1200) . "..."
            if length($sanitizer) > 1200;
        $sanitizer =~ s/\n/\n      /g;
        print OUT "    ${Redctx}sanitizer reports errors:${Off}\n      $sanitizer\n";
    }

    if (exists($opts{CMD_CAT})) {
        print OUT "\n${Green}", $opts{CMD_CAT}, "\n==================${Off}\n";
        if (open(F, "<", "out/" . $opts{CMD_CAT})) {
            print OUT $_ while (defined($_ = <F>));
            close(F);
        } else {
            print OUT "${Red}out/", $opts{CMD_CAT}, ": $!${Off}\n";
        }
        print OUT "\n";
    }
}

open(OUT, ">&STDOUT");
my($leak_check) = 0;

while (@ARGV && $ARGV[0] =~ /^-/) {
    if ($ARGV[0] eq "--leak" || $ARGV[0] eq "--leak-check") {
        $leak_check = 1;
        shift @ARGV;
        next;
    } elsif ($ARGV[0] =~ /\A--leak=(.*)\z/) {
        $leak_check = ($1 eq "1" || $1 eq "yes");
        shift @ARGV;
        next;
    } elsif ($ARGV[0] eq "--ignore-sigint") {
        $ignore_sigint = 1;
        $SIG{"INT"} = "IGNORE";
        shift @ARGV;
        next;
    } elsif ($ARGV[0] eq "--only") {
        @ARGV = ($ARGV[1]);
        last;
    }

    print STDERR "Usage: check.pl TESTNUM...\n";
    exit(1);
}

if (!$leak_check && !$ENV{"ASAN_OPTIONS"}) {
    $ENV{"ASAN_OPTIONS"} = "detect_leaks=0";
}

foreach my $allowed_tests (@ARGV) {
    while ($allowed_tests =~ m{(?:^|[\s,])(\w+?)-?(\d*)((?:-\d*)?)(?=[\s,]|$)}g) {
        push(@ALLOW_TESTS, [lc($1), $2, $3]);
    }
}

my(%test_names);
foreach $test (@tests) {
    die "Test name " . $test->[0] . " reused" if exists $test_names{$test->[0]};
    $test_names{$test->[0]} = 1;
    ++$testindex;
    run(@$test);
}

my($ntestpassed) = $ntest - $ntestfailed;
print OUT "\r$ntestpassed of $ntest ", ($ntest == 1 ? "test" : "tests"), " passed\n" if $ntest > 1;
exit(0);
