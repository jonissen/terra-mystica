use strict;

package Server::Map;

use Digest::SHA1 qw(sha1_hex);
use Moose;
use Method::Signatures::Simple;

extends 'Server::Server';

use DB::Connection qw(get_db_connection);
use DB::Game;
use map;
use Server::Security;
use Server::Session;
use tracker;

has 'mode' => (is => 'ro', required => 1);

method handle($q, $id) {
    $self->no_cache();

    my $dbh = get_db_connection;
    my $username = username_from_session_token(
        $dbh,
        $q->cookie('session-token') // '');

    if (!defined $username) {
        $self->output_json({
            error => [ "Not logged in\n" ]
        });
        return;
    }

    my $base_map = $q->param('base_map');

    my $res = {
        error => [],
        bridges => [],
    };

    if ($self->mode() eq 'preview') {
        preview($dbh, $q->param('map-data'), $res);
    } elsif ($self->mode() eq 'save') {
        save($dbh, $q->param('map-data'), $res, $username);
    } elsif ($self->mode() eq 'view') {
        view($dbh, $id, $res);
    }

    $self->output_json($res);
};

func convert_to_lodev($base_map) {
    $base_map =~ s/\s+/ /g;
    $base_map =~ s/\s*E\s*/;\n/g; 
    $base_map =~ s/black/K/g;
    $base_map =~ s/blue/B/g;
    $base_map =~ s/brown/U/g;
    $base_map =~ s/green/G/g;
    $base_map =~ s/gray/S/g;
    $base_map =~ s/red/R/g;
    $base_map =~ s/yellow/Y/g;
    $base_map =~ s/x/I/g;
    $base_map =~ s/ /,/g;
    $base_map;
}

func convert_from_lodev($base_map) {
    if ($base_map =~ /^N/) {
        $base_map = ";$base_map";
    }    
    $base_map =~ s/N,?//g;

    $base_map =~ s/K/black/g;
    $base_map =~ s/B/blue/g;
    $base_map =~ s/U/brown/g;
    $base_map =~ s/G/green/g;
    $base_map =~ s/S/gray/g;
    $base_map =~ s/R/red/g;
    $base_map =~ s/Y/yellow/g;
    $base_map =~ s/I/x/g;
    $base_map =~ s/;\s*/ E /g;
    $base_map =~ s/^ +//g;
    $base_map =~ s/ +$//g;
    $base_map =~ s/,/ /g;
    $base_map =~ s/ +/ /g;
    $base_map;
}

func preview($dbh, $mapdata, $res) {
    my $map_str = convert_from_lodev($mapdata);
    my $base_map = [ split /\s+/, $map_str ];
    local %terra_mystica::game = (
        base_map => $base_map
    );
    local %terra_mystica::map = ();
    terra_mystica::setup_map;

    my $id = sha1_hex $map_str;

    $res->{'map'} = \%terra_mystica::map;
    $res->{'mapdata'} = $mapdata;
    $res->{'mapid'} = $id;
    $res->{'saved'} = map_exists($dbh, $id);
}

func map_exists($dbh, $id) {
    my ($count) = $dbh->selectrow_array("select count(*) from map_variant where id=?",
                                        {},
                                        $id);
    $count ? 1 : 0;
}

func save($dbh, $mapdata, $res) {
    my $map_str = convert_from_lodev($mapdata);
    my $id = sha1_hex $map_str;

    if (!map_exists($dbh, $id)) {
        $dbh->do("insert into map_variant (id, terrain) values (?, ?)",
                 {},
                 $id, $map_str);
    }

    $res->{'mapid'} = sha1_hex $map_str;
}

func view($dbh, $id, $res) {
    my ($map_str) = $dbh->selectrow_array("select terrain from map_variant where id=?", {}, $id);
    my $base_map = [ split /\s+/, $map_str ];
    local %terra_mystica::game = (
        base_map => $base_map
    );
    local %terra_mystica::map = ();
    terra_mystica::setup_map;

    $res->{'map'} = \%terra_mystica::map;
    $res->{'mapdata'} = convert_to_lodev($map_str);
    $res->{'mapid'} = $id;
}

1;
