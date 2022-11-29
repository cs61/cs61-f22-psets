#! /usr/bin/perl -w

my ($dblinelen) = 16;
my ($baloffset) = 8;
my ($Red, $Redctx, $Green, $Greenctx, $Cyan, $Ylo, $Yloctx, $Off) = ("\x1b[01;31m", "\x1b[0;31m", "\x1b[01;32m", "\x1b[0;32m", "\x1b[01;36m", "\x1b[01;33m", "\x1b[0;33m", "\x1b[0m");

sub usage () {
    print STDERR "Usage: perl diff-ftxdb.pl INFILE OUTFILE [LEDGERFILE]\n";
    exit(1);
}

my ($need_ledger) = 0;
my ($color) = -t STDERR && -t STDOUT;
while (@ARGV > 0) {
    if ($ARGV[0] eq "-l") {
        $need_ledger = 1;
    } elsif ($ARGV[0] eq "--color") {
        $color = 1;
    } else {
        last;
    }
    shift @ARGV;
}

$Red = $Redctx = $Green = $Greenctx = $Cyan = $Ylo = $Yloctx = $Off = "" if !$color;
push @ARGV, "accounts.fdb" if @ARGV == 0;
push @ARGV, "/tmp/newaccounts.fdb" if @ARGV == 1;
push @ARGV, "/tmp/ledger.fdb" if $need_ledger && @ARGV == 2;
usage if @ARGV != 2 && @ARGV != 3;
usage if $ARGV[0] eq "-" && $ARGV[1] eq "-";
usage if @ARGV == 3 && $ARGV[2] eq "-";


sub checkline ($$$$) {
    my ($line, $lineno, $fname, $used) = @_;
    if ($line =~ /^([A-Za-z0-9]+)\s+([-+]?\d+)$/) {
        if (length($line) != $dblinelen) {
            push @err, "${Redctx}${fname}:${lineno}:${Red} Bad line length " . length($line) . "${Off}\n";
        } elsif (length($1) >= $baloffset) {
            push @err, "${Redctx}${fname}:${lineno}:${Red} Bad account name length " . length($1) . "${Off}\n";
        } elsif ($used) {
            if (exists($used->{$1})) {
                push @err, "${Redctx}${fname}:${lineno}:${Red} Account name `$1` reused${Off}\n";
            }
            $used->{$1} = 1;
        }
        return ($1, +$2);
    } else {
        push @err, "${Redctx}${fname}:${lineno}:${Red} Invalid account format${Off}\n";
        return (undef, undef);
    }
}

sub readfile ($\%) {
    my ($fname, $out) = @_;
    if ($fname eq "-") {
        open(F, "<&", STDIN);
        $fname = "<stdin>";
    } elsif (!open(F, "<", $fname)) {
        print STDERR $fname, ": ", $!, "\n";
        exit(1);
    }
    my $lineno = 1;
    my $total = 0;
    my $accts = {};
    my $lines = {};
    my $used = {};
    while (defined($_ = <F>)) {
        my ($acct, $amt) = checkline($_, $lineno, $fname, $used);
        if (defined($amt)) {
            $accts->{$acct} = $amt;
            $lines->{$acct} = $lineno;
            $total += $amt;
        }
        ++$lineno;
    }
    close F;
    $out->{"total"} = $total;
    $out->{"accts"} = $accts;
    $out->{"lines"} = $lines;
}

sub applyledger ($\%) {
    my ($fname, $out) = @_;
    if ($fname eq "-") {
        open(F, "<&", STDIN);
        $fname = "<stdin>";
    } elsif (!open(F, "<", $fname)) {
        print STDERR $fname, ": ", $!, "\n";
        exit(1);
    }
    my $lineno = 1;
    my $accts = $out->{"accts"};
    my $total = $out->{"total"};
    my %toolow;
    while (defined($_ = <F>)) {
        my ($acct, $amt) = checkline($_, $lineno, $fname, undef);
        if (defined($amt)) {
            if (exists($accts->{$acct})) {
                $accts->{$acct} += $amt;
                if ($accts->{$acct} < 0 && !exists($toolow{$acct})) {
                    push @err, "${Redctx}${fname}:${lineno}:${Red} Ledger takes `${acct}` balance below 0${Off}\n";
                    $toolow{$acct} = 1;
                }
            } else {
                push @err, "${Redctx}${fname}:${lineno}:${Red} Ledger account `${acct}` not in balance database${Off}\n";
            }
            $total += $amt;
        }
        ++$lineno;
    }
    close F;
    $out->{"ledger_total"} = $total;
    if ($out->{"total"} != $total) {
        push @err, "${Redctx}${fname}:${Red} Ledger does not preserve overall balance${Off}\n";
    }
}

my (%acct0, %acct1);
readfile($ARGV[0], %acct0);
readfile($ARGV[1], %acct1);
my $ledger = @ARGV == 3;
if ($ledger) {
    applyledger($ARGV[2], %acct0);
}
my $fname0 = $ARGV[0] eq "-" ? "<stdin>" : $ARGV[0];
my $fname1 = $ARGV[1] eq "-" ? "<stdin>" : $ARGV[1];
my $fname2 = $ledger ? $ARGV[2] : undef;

my ($k, $v);
while (($k, $v) = each %{$acct0{"accts"}}) {
    my $ln0 = $acct0{"lines"}->{$k};
    if (!exists($acct1{"accts"}->{$k})) {
        push @err, "${Redctx}${fname0}:${ln0}:${Red} Account `${k}` not in ${fname1}${Off}\n";
    } elsif ($ledger && $acct1{"accts"}->{$k} != $v) {
        push @err, "${Redctx}${fname1}:" . $acct1{"lines"}->{$k} . ":${Red} Account `${k}` has incorrect balance " . $acct1{"accts"}->{$k} . "${Off}\n${Redctx}${fname0}:${ln0}:${Red} Expected ${v}${Off}\n";
    }
}
while (($k, $v) = each %{$acct1{"accts"}}) {
    my $ln1 = $acct1{"lines"}->{$k};
    if (!exists($acct0{"accts"}->{$k})) {
        push @err, "${Redctx}${fname1}:${ln1}:${Red} Account `${k}` not in ${fname0}${Off}\n";
    }
}
if ($acct1{"total"} != $acct0{"total"}) {
    push @err, "${Redctx}${fname1}:${Red} Incorrect exchange total " . $acct1{"total"} . "${Off}\n${Redctx}${fname0}: Expected " . $acct0{"total"} . "${Off}\n";
}

if (@err) {
    my $nerr = @err > 20 ? 19 : scalar(@err);
    if (@err > 20) {
        print STDOUT join("", @err[0..19]);
        print STDOUT "${Redctx}There are other errors.${Off}\n" if @err > 20;
    } else {
        print STDOUT join("", @err);
    }
    exit(1);
} else {
    if ($ledger) {
        print STDOUT "${Green}${fname1} and ${fname2} OK${Off}\n";
    } else {
        print STDOUT "${Green}${fname1} OK${Off}\n";
    }
    exit(0);
}
