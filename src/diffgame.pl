#!/usr/bin/perl -wl

use strict;
use warnings;

use File::Basename qw(dirname);
use JSON;
use Text::Diff qw(diff);
use Time::HiRes qw(time);

BEGIN { push @INC, dirname $0 };

use db;

my $dir = dirname $0;
my $time = 0;

sub pretty_res {
    my $begin = time;
    my $res = qx(perl $dir/tracker.pl @_);
    my $json = decode_json $res;
    if ($time) {
        printf "  %s: %5.3f\n", $_[0], (time - $begin);
    }
    $json;
#    my $pretty = to_json($json, { pretty => 1 });
#    $pretty;
}

my ($dir1, $dir2) = (shift, shift);

sub convert_ledger {
    my $data = shift;
    return $data if !ref $data;

    # command / comment only
    return [ map { [ $_->{commands} || $_->{comment}, $_->{warning}] } @{$data} ];        
}

my $dbh = get_db_connection;

my $games = $dbh->selectall_arrayref("select id, write_id, extract(epoch from last_update) from game where id like ?",
                                     {},
                                     shift || '%');

for (@{$games}) {
    my $id = $_->[0];

    my $a = pretty_res $dir1, $id;
    my $b = pretty_res $dir2, $id;
    my $header_printed = 0;

    {
        local $| = 1; 
        printf "."; 
    }

    for my $key (keys %{$a}) {
        my $aa = $a->{$key};
        my $bb = $b->{$key};

        if (!ref $aa or !ref $bb) {
            next;
        }

        if ($key eq 'ledger') {
            $aa = convert_ledger $aa;
            $bb = convert_ledger $bb;
            my $aj = join "\n", map { to_json($_) } @{$aa};
            my $bj = join "\n", map { to_json($_) } @{$bb};
            if ($aj ne $bj) {
                print "\nDiff in $id" if !$header_printed++;
                # print "Ledger diffs";
                print diff \$aj, \$bj;
            }
        } else {
            my $aj = to_json($aa, { pretty => 1, canonical => 1 });
            my $bj = to_json($bb, { pretty => 1, canonical => 1 });
            if ($aj ne $bj) {
                print "\nDiff in $id" if !$header_printed++;
                print diff \$aj, \$bj;
            }
        }
    }
}
