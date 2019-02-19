#!/usr/bin/env perl
#Written by Keith Jolley
#Copyright (c) 2019, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#This is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#BIGSdb is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
use strict;
use warnings;
use 5.010;
use FindBin;
use lib "$FindBin::Bin/lib";
use BIGSdbRestClient;
use Config::Tiny;
use DBI;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
use POSIX;
use constant STATS_DB           => 'bigsdb_stats';
use constant HOST               => 'zoo-aberlour';
use constant PORT               => 5432;
use constant USER               => 'apache';
use constant PASSWORD           => undef;                          #Better to set in .pgpass file or pass as option
use constant DEFAULT_REST_URL   => 'http://rest.pubmlst.org';
use constant DEFAULT_BIGSDB_URL => 'https://pubmlst.org/bigsdb';
use constant IGNORE_GROUP       => 'test';
my %opts;
GetOptions(
	'bigsdb_url=s'   => \$opts{'bigsdb_url'},
	'database=s'     => \$opts{'database'},
	'format=s'       => \$opts{'format'},
	'help'           => \$opts{'help'},
	'host=s'         => \$opts{'host'},
	'ignore_group=s' => \$opts{'ignore_group'},
	'password=s'     => \$opts{'password'},
	'port=i'         => \$opts{'port'},
	'setup_access'   => \$opts{'setup'},
	'stats=s'        => \$opts{'stats'},
	'update'         => \$opts{'update'},
	'url=s'          => \$opts{'url'},
	'user=s'         => \$opts{'user'},
) or die("Error in command line arguments\n");

if ( $opts{'help'} ) {
	show_help();
	exit;
}
$opts{'url'}        //= DEFAULT_REST_URL;
$opts{'bigsdb_url'} //= DEFAULT_BIGSDB_URL;
my $client = BIGSdbRestClient->new(
	{
		rest_url   => $opts{'url'},
		bigsdb_url => $opts{'bigsdb_url'}
	}
);
if ( $opts{'setup'} ) {
	$client->get_access_token;
	exit;
}
my %allowed_formats = map { $_ => 1 } qw(JSON TSV);
$opts{'format'} //= 'JSON';
if ( !$allowed_formats{ $opts{'format'} } ) {
	die "Invalid format.\n";
}
my $db = db_connect();
main();
exit;

sub main {
	if ( $opts{'update'} ) {
		update_resources();
		update_isolates();
		update_sequences();
	}
	if ( $opts{'stats'} ) {
		output_stats();
	}
	return;
}

sub output_stats {
	if ( $opts{'stats'} eq 'datestamp' ) {
		output_date_analysis( { type => 'datestamp' } );
		return;
	}
	if ( $opts{'stats'} eq 'date_entered' ) {
		output_date_analysis( { type => 'date_entered' } );
		return;
	}
	die "Invalid stats option.\n";
}

sub output_date_analysis {
	my ($options) = @_;
	my %table = (
		date_entered => 'date_entered',
		datestamp    => 'last_modified'
	);
	my $type = $options->{'type'} // 'datestamp';
	$db->do('CREATE TEMP TABLE date_output AS SELECT i.datestamp,r.set_name,i.count AS isolates,'
		  . "g.count AS genomes FROM set_resources r JOIN isolates_$table{$type} i ON r.dbase_config=i.dbase_config "
		  . "LEFT JOIN genomes_$table{$type} g ON i.datestamp=g.datestamp AND i.dbase_config=g.dbase_config LEFT JOIN "
		  . "sequences_$table{$type} s ON r.dbase_config=s.dbase_config" );
	$db->do('ALTER TABLE date_output ADD sequences int');
	$db->do('ALTER TABLE date_output ADD PRIMARY KEY(datestamp,set_name)');
	my $seq_data = run_query(
		"SELECT s.datestamp,r.set_name,s.count FROM sequences_$table{$type} s "
		  . 'JOIN set_resources r ON s.dbase_config=r.dbase_config',
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	foreach my $seq_record (@$seq_data) {
		$db->do(
			'INSERT INTO date_output (datestamp,set_name,sequences) VALUES (?,?,?) '
			  . 'ON CONFLICT (datestamp,set_name) DO UPDATE SET sequences=?',
			undef, @{$seq_record}{qw(datestamp set_name count count)}
		);
	}
	my $data =
	  run_query( 'SELECT * FROM date_output ORDER BY datestamp', undef, { fetch => 'all_arrayref', slice => {} } );
	if ( $opts{'format'} eq 'JSON' ) {
		say encode_json($data);
	} else {
		say qq(datestamp\tset_name\tisolates\tgenomes\tsequences);
		foreach my $record (@$data) {
			my @values = @{$record}{qw(datestamp set_name isolates genomes sequences)};
			$_ //= 0 foreach @values;
			local $" = qq(\t);
			say qq(@values);
		}
	}
	return;
}

sub update_resources {
	my $ignore_config_list = get_ignore_config_list();
	my %ignore             = map { $_ => 1 } @$ignore_config_list;
	my $data               = $client->get_record( $opts{'url'} );
	eval {
		foreach my $group (@$data) {
			foreach my $database ( @{ $group->{'databases'} } ) {
				next if $ignore{ $database->{'name'} };
				$db->do(
					' INSERT INTO resources( dbase_config, description ) VALUES(?,?) '
					  . ' ON CONFLICT(dbase_config) DO UPDATE SET description = ?',
					undef, @{$database}{qw(name description description)}
				);
				if ( $database->{'description'} =~ /(.+)\s(?:isolates|specimens|sequence\/profile\ definitions)$/x ) {
					$db->do( 'INSERT INTO sets (name) VALUES (?) ON CONFLICT DO NOTHING', undef, $1 );
					$db->do( 'INSERT INTO set_resources (set_name,dbase_config) VALUES (?,?) ON CONFLICT DO NOTHING',
						undef, $1, $database->{'name'} );
					update_totals($database);
				}
			}
		}
	};
	if ($@) {
		$db->rollback;
		die "$@\n";
	}
	$db->commit;
	return;
}

sub get_ignore_config_list {
	$opts{'ignore_group'} //= q();
	my @passed_list = split /,/x, $opts{'ignore_group'};
	my %ignore_group = map { $_ => 1 } ( IGNORE_GROUP, @passed_list );
	my $list         = [];
	my $data         = $client->get_record( $opts{'url'} );
	foreach my $group (@$data) {
		if ( $ignore_group{ $group->{'name'} } ) {
			foreach my $resource ( @{ $group->{'databases'} } ) {
				push @$list, $resource->{'name'};
			}
		}
	}
	return $list;
}

sub update_totals {
	my ($database) = @_;
	my $data = $client->get_record( $database->{'href'} );
	foreach my $type (qw(isolates genomes sequences)) {
		if ( $data->{$type} ) {
			my $type_record = $client->get_record( $data->{$type} );
			$db->do(
				"UPDATE sets SET $type=? WHERE name=(SELECT set_name FROM set_resources WHERE dbase_config=?)",
				undef, $type_record->{'records'},
				$database->{'name'}
			);
		}
	}
	return;
}

sub update_isolates {
	my ($options) = @_;
	my $ignore_config_list = get_ignore_config_list();
	my %ignore = map { $_ => 1 } @$ignore_config_list;
	my $resources = run_query( 'SELECT dbase_config FROM set_resources', undef, { fetch => 'col_arrayref' } );
	my %table = (
		date_entered => 'date_entered',
		datestamp    => 'last_modified'
	);
	eval {
		CONFIG: foreach my $config (@$resources)
		{
			next CONFIG if $ignore{$config};
			my $data = $client->get_record("$opts{'url'}/db/$config");
			next CONFIG if !$data->{'fields'};
			my $fields = $client->get_record( $data->{'fields'} );
		  FIELDNAME: foreach my $field_name (qw( date_entered datestamp)) {
			  FIELD: foreach my $field (@$fields) {
					next FIELD if $field->{'name'} ne $field_name || !$field->{'breakdown'};
				  TYPE: foreach my $type (qw(isolates genomes)) {
						my $clause = $type eq 'genomes' ? q(?genomes=1) : q();
						my $breakdown = $client->get_record( $field->{'breakdown'} . $clause );
						$db->do( "DELETE FROM ${type}_$table{$field_name} WHERE dbase_config=?", undef, $config );
						foreach my $date ( keys %$breakdown ) {
							$db->do(
								"INSERT INTO ${type}_$table{$field_name} (datestamp,dbase_config,count) VALUES (?,?,?)",
								undef, $date, $config, $breakdown->{$date}
							);
						}
					}
				}
			}
		}
	};
	if ($@) {
		$db->rollback;
		die "$@\n";
	}
	$db->commit;
	return;
}

sub update_sequences {
	my ($options) = @_;
	my $ignore_config_list = get_ignore_config_list();
	my %ignore = map { $_ => 1 } @$ignore_config_list;
	my %table = (
		date_entered => 'date_entered',
		datestamp    => 'last_modified'
	);
	my $resources = run_query( 'SELECT dbase_config FROM set_resources', undef, { fetch => 'col_arrayref' } );
	eval {
		CONFIG: foreach my $config (@$resources)
		{
			next CONFIG if $ignore{$config};
			my $data = $client->get_record("$opts{'url'}/db/$config");
			next CONFIG if !$data->{'sequences'};
			my $sequences = $client->get_record( $data->{'sequences'} );
			next CONFIG if !$sequences->{'fields'};
			my $fields = $client->get_record( $sequences->{'fields'} );
		  FIELDNAME: foreach my $field_name (qw( date_entered datestamp)) {
			  FIELD: foreach my $field (@$fields) {
					next FIELD if $field->{'name'} ne $field_name || !$field->{'breakdown'};
					my $breakdown = $client->get_record( $field->{'breakdown'} );
					$db->do( "DELETE FROM sequences_$table{$field_name} WHERE dbase_config=?", undef, $config );
					foreach my $date ( keys %$breakdown ) {
						$db->do(
							"INSERT INTO sequences_$table{$field_name} (datestamp,dbase_config,count) VALUES (?,?,?)",
							undef, $date, $config, $breakdown->{$date} );
					}
				}
			}
		}
	};
	if ($@) {
		$db->rollback;
		die "$@\n";
	}
	$db->commit;
	return;
}

sub db_connect {
	my $db_name  = $opts{'database'} // STATS_DB;
	my $host     = $opts{'host'}     // HOST;
	my $port     = $opts{'port'}     // PORT;
	my $user     = $opts{'user'}     // USER;
	my $password = $opts{'password'} // PASSWORD;
	my $dbh;
	eval {
		$dbh = DBI->connect( "DBI:Pg:host=$host;port=$port;dbname=$db_name",
			$user, $password, { AutoCommit => 0, RaiseError => 1, PrintError => 0, pg_enable_utf8 => 1 } );
	};
	die "$@\n" if $@;
	return $dbh;
}

sub run_query {

   #$options->{'fetch'}: row_arrayref, row_array, row_hashref, col_arrayref, all_arrayref, all_hashref
   #$options->{'key'}:   Key field(s) to use for returning all as hashrefs.  Should be an arrayref if more than one key.
   #$options->{'slice'}: Slice to return for all_arrayrefs.
	my ( $qry, $values, $options ) = @_;
	if ( defined $values ) {
		$values = [$values] if ref $values ne 'ARRAY';
	} else {
		$values = [];
	}
	my $sql = $db->prepare($qry);
	$options->{'fetch'} //= 'row_array';
	if ( $options->{'fetch'} eq 'col_arrayref' ) {
		my $data;
		eval { $data = $db->selectcol_arrayref( $sql, undef, @$values ) };
		die "$@ Query:$qry\n" if $@;
		return $data;
	}
	eval { $sql->execute(@$values) };
	die "$@ Query:$qry\n" if $@;
	if ( $options->{'fetch'} eq 'row_arrayref' ) {    #returns undef when no rows
		return $sql->fetchrow_arrayref;
	}
	if ( $options->{'fetch'} eq 'row_array' ) {       #returns () when no rows, (undef-scalar context)
		return $sql->fetchrow_array;
	}
	if ( $options->{'fetch'} eq 'row_hashref' ) {     #returns undef when no rows
		return $sql->fetchrow_hashref;
	}
	if ( $options->{'fetch'} eq 'all_hashref' ) {     #returns {} when no rows
		if ( !defined $options->{'key'} ) {
			die "Key field(s) needs to be passed.\n";
		}
		return $sql->fetchall_hashref( $options->{'key'} );
	}
	if ( $options->{'fetch'} eq 'all_arrayref' ) {    #returns [] when no rows
		return $sql->fetchall_arrayref( $options->{'slice'} );
	}
	die "Query failed - invalid fetch method specified.\n";
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw/me md us/;
	say << "HELP";
${bold}NAME$norm
  ${bold}collects_stats.pl$norm - Collect summary stat files for BIGSdb site
    
${bold}--bigsdb_url$norm [${under}URL$norm]
    URL to BIGSdb script on target site.

${bold}--database$norm [${under}DATABASE$norm]
    Name of the stats database.
    
${bold}--format$norm [${under}FORMAT$norm]
    Output format. Allowed values: JSON, TSV (default JSON).

${bold}--help$norm
    This help page.
    
${bold}--host$norm [${under}HOST$norm]
    Database host.
    
${bold}--ignore_group$norm [${under}GROUP$norm]
    Comma separated list of database configurations to ignore.
      
${bold}--password$norm [${under}PASSWORD$norm]
    Database user password.
    
${bold}--port$norm [${under}PORT$norm]
    Database port.

${bold}--setup_access$norm
    Authenticate and delegate access to retrieve an access token.
    
${bold}--stats$norm [${under}FUNCTION$norm]
    Output stats. Available option: date
    
${bold}--update$norm
	Update stats database.
    
${bold}--url$norm [${under}URL$norm]
    URL of the REST API.
    
${bold}--user$norm [${under}USER$norm]
    Database user.
    
HELP
	return;
}
