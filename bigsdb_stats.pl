#!/usr/bin/env perl
#Written by Keith Jolley
#Copyright (c) 2019-2020, University of Oxford
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
use JSON;
use POSIX;
use utf8;
use constant STATS_DB           => 'bigsdb_stats';
use constant HOST               => 'zoo-lagavulin';
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
	'days=i'         => \$opts{'days'},
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
$opts{'days'}       //= 3;
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
my %allowed_formats = map { $_ => 1 } qw(CSV JSON TSV flat_list);
$opts{'format'} //= 'JSON';
if ( !$allowed_formats{ $opts{'format'} } ) {
	die "Invalid format.\n";
}
my $db = db_connect();
main();
exit;

sub main {
	binmode STDOUT, ':encoding(utf8)';
	if ( $opts{'update'} ) {
		update_resources();
		update_isolates();
		update_sequences();
		update_profiles();
		update_countries();
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
	if ( $opts{'stats'} eq 'links' ) {
		output_recent_links();
		return;
	}
	if ( $opts{'stats'} eq 'totals' ) {
		output_totals();
		return;
	}
	if ( $opts{'stats'} eq 'countries' ) {
		output_countries();
		return;
	}
	if ( $opts{'stats'} eq 'summary' ) {
		output_summary();
		return;
	}
	die "Invalid stats option.\n";
}

sub output_totals() {
	my $isolates = run_query('SELECT SUM(count) FROM isolates_date_entered');
	my $genomes  = run_query('SELECT SUM(count) FROM genomes_date_entered');
	my $alleles  = run_query('SELECT SUM(count) FROM sequences_date_entered');
	my $profiles = run_query('SELECT SUM(count) FROM profiles_date_entered');
	if ( $opts{'format'} eq 'JSON' ) {
		say encode_json (
			{
				isolates => $isolates,
				genomes  => $genomes,
				alleles  => $alleles,
				profiles => $profiles
			}
		);
	} elsif ( $opts{'format'} eq 'TSV' ) {
		say qq(isolates\tgenomes\talleles\tprofiles);
		say qq($isolates\t$genomes\t$alleles\t$profiles);
	}
	return;
}

sub output_recent_links {
	my $date_list = get_list_of_dates();
	foreach my $date (@$date_list) {
		my $sets = get_dbase_set_updated_on($date);
		if ( ( $opts{'format'} // q() ) eq 'flat_list' ) {
			say qq(<b>$date:</b>);
			say q(<ul>);
			foreach my $set_name (@$sets) {
				say qq(<li>$set_name: );
				my $set_updates = get_set_updates( $set_name, $date );
				local $" = q(; );
				say qq(@$set_updates);
				say q(</li>);
			}
			say q(</ul>);
		} else {
			say qq(<b>$date</b>);
			say q(<ul>);
			foreach my $set_name (@$sets) {
				say qq(<li>$set_name:<ul>);
				my $set_updates = get_set_updates( $set_name, $date );
				say qq(<li>$_</li>) foreach @$set_updates;
				say q(</ul></li>);
			}
			say q(</ul>);
		}
	}
	return;
}

sub output_countries {
	my $iso3 = get_iso3();
	my $data = run_query(
		q(SELECT SUBSTRING(r.dbase_config,'pubmlst_(\D+)_isolates') AS id,r.set_name,c.country,c.count,c.genomes FROM )
		  . q(countries c JOIN set_resources r ON c.dbase_config=r.dbase_config ORDER BY c.country,r.set_name),
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	my $data_hash = {};
	foreach my $record (@$data) {
		next if !$iso3->{ $record->{'country'} };

		#Group all UK countries together.
		if ( $record->{'country'} =~ /^UK \[/x ) {
			$record->{'country'} = 'UK';
		}
		$record->{'iso3'} = $iso3->{ $record->{'country'} };
		if ( defined $data_hash->{ $record->{'id'} }->{ $record->{'iso3'} } ) {
			$data_hash->{ $record->{'id'} }->{ $record->{'iso3'} }->{'count'} += $record->{'count'};
		} else {
			$data_hash->{ $record->{'id'} }->{ $record->{'iso3'} } = {
				set_name => $record->{'set_name'},
				country  => $record->{'country'},
				count    => $record->{'count'},
				genomes  => $record->{'genomes'}
			};
		}
	}
	my $filtered;
	foreach my $id ( sort keys %$data_hash ) {
		foreach my $iso3 ( sort keys %{ $data_hash->{$id} } ) {
			my $record = $data_hash->{$id}->{$iso3};
			( my $url = qq($opts{'bigsdb_url'}?db=pubmlst_${id}_isolates&page=query&prov_field1=f_country&)
				  . qq(prov_value1=$record->{'country'}&submit=1) ) =~ s/\s/%20/gx;
			push @$filtered,
			  {
				id       => $id,
				set_name => $record->{'set_name'},
				iso3     => $iso3,
				country  => $record->{'country'},
				count    => $record->{'count'},
				genomes  => $record->{'genomes'},
				url      => $url
			  };
		}
	}
	if ( $opts{'format'} eq 'JSON' ) {
		say encode_json($filtered);
		return;
	}
	my $divider = $opts{'format'} eq 'TSV' ? qq(\t) : q(,);
	local $" = $divider;
	my @fields = qw(id set_name country iso3 count genomes url);
	say qq(@fields);
	foreach my $record (@$filtered) {
		my $code = $iso3->{ $record->{'country'} } // q();
		say qq(@{$record}{@fields});
	}
	return;
}

sub output_summary {
	$db->do('CREATE TEMP TABLE summaries AS SELECT * FROM sets ORDER BY name');
	$db->do('ALTER TABLE summaries ADD id text');
	$db->do('ALTER TABLE summaries ADD typing_url text');
	$db->do('ALTER TABLE summaries ADD isolates_url text');
	$db->do('ALTER TABLE summaries ADD isolates_updated date');
	$db->do('ALTER TABLE summaries ADD genomes_updated date');
	$db->do('ALTER TABLE summaries ADD sequences_updated date');
	$db->do('ALTER TABLE summaries ADD profiles int');
	my $configs = run_query( 'SELECT * FROM set_resources', undef, { fetch => 'all_arrayref', slice => {} } );

	foreach my $config (@$configs) {
		if ( $config->{'dbase_config'} =~ /pubmlst_(\D+)_seqdef$/x ) {
			$db->do(
				'UPDATE summaries SET (id,typing_url)=(?,?) WHERE name=?',
				undef, $1, "$opts{'bigsdb_url'}?db=$config->{'dbase_config'}",
				$config->{'set_name'}
			);
		}
		if ( $config->{'dbase_config'} =~ /pubmlst_(\D+)_isolates$/x ) {
			$db->do(
				'UPDATE summaries SET (id,isolates_url)=(?,?) WHERE name=?',
				undef, $1, "$opts{'bigsdb_url'}?db=$config->{'dbase_config'}",
				$config->{'set_name'}
			);
		}
		my $isolates_updated = run_query( 'SELECT MAX(datestamp) FROM isolates_last_modified WHERE dbase_config=?',
			$config->{'dbase_config'} );
		if ($isolates_updated) {
			$db->do( 'UPDATE summaries SET isolates_updated=? WHERE name=?',
				undef, $isolates_updated, $config->{'set_name'} );
		}
		my $genomes_updated = run_query( 'SELECT MAX(datestamp) FROM genomes_last_modified WHERE dbase_config=?',
			$config->{'dbase_config'} );
		if ($genomes_updated) {
			$db->do( 'UPDATE summaries SET genomes_updated=? WHERE name=?',
				undef, $genomes_updated, $config->{'set_name'} );
		}
		my $sequences_updated = run_query( 'SELECT MAX(datestamp) FROM sequences_last_modified WHERE dbase_config=?',
			$config->{'dbase_config'} );
		if ($sequences_updated) {
			$db->do( 'UPDATE summaries SET sequences_updated=? WHERE name=?',
				undef, $sequences_updated, $config->{'set_name'} );
		}
		if ( $config->{'set_name'} eq 'Ribosomal MLST' ) {
			my $profiles = run_query( 'SELECT SUM(count) FROM profiles_date_entered WHERE (dbase_config,scheme)=(?,?)',
				[ 'pubmlst_rmlst_seqdef', 'Ribosomal MLST' ] );
			$db->do( 'UPDATE summaries SET profiles=? WHERE name=?', undef, $profiles, 'Ribosomal MLST' );
		}
	}
	my $data = run_query( 'SELECT * FROM summaries ORDER BY name', undef, { fetch => 'all_arrayref', slice => {} } );
	$db->do('DROP TABLE summaries');
	if ( $opts{'format'} eq 'JSON' ) {
		say encode_json($data);
		return;
	} else {
		local $" = $opts{'format'} eq 'CSV' ? q(,) : qq(\t);
		my @fields = qw(id name formatted_name isolates genomes sequences profiles typing_url isolates_url
		  isolates_updated genomes_updated sequences_updated);
		say qq(@fields);
		my %exceptions = (
			'Lactococcus lactis 936-like bacteriophage'   => '<i>Lactococcus lactis</i> 936-like bacteriophage',
			'Plasmid MLST'                                => 'Plasmid MLST',
			'Oral Streptococcus spp.'                     => 'Oral <i>Streptococcus</i> spp.',
			'Ribosomal MLST'                              => 'Ribosomal MLST',
			'Sandbox'                                     => 'Sandbox',
			'Streptococcus bovis/equinus complex (SBSEC)' => '<i>Streptococcus bovis/equinus</i> complex (SBSEC)',
			'Treponema pallidum subsp. pallidum' => '<i>Treponema pallidum</i> subsp. <i>pallidum</i>'
		);
		my %ignore = map { $_ => 1 } qw(fish);
		foreach my $record (@$data) {

			if ( $record->{'name'} =~ /^(.+)\s(spp.|complex)$/x ) {
				$record->{'formatted_name'} = qq(<i>$1</i> $2);
			}
			if ( $record->{'name'} =~ /^Candidatus\s(.+)/x ) {
				$record->{'formatted_name'} = qq{&quot;<i>Candidatus</i> $1&quot;};
			}
			if ( $exceptions{ $record->{'name'} } ) {
				$record->{'formatted_name'} = $exceptions{ $record->{'name'} };
			}
			$record->{'formatted_name'} //= qq(<i>$record->{'name'}</i>);
			foreach my $field (@fields) {
				$record->{$field} = 'undef' if !defined $record->{$field};
			}
			next if $ignore{ $record->{'id'} };
			say qq(@{$record}{@fields});
		}
	}
	return;
}

sub get_set_updates {
	my ( $set_name, $date ) = @_;
	my @tables = qw(isolates_last_modified genomes_last_modified sequences_last_modified);
	my %name   = (
		isolates_last_modified  => 'isolate',
		genomes_last_modified   => 'genome',
		sequences_last_modified => 'allele'
	);
	my $set_resources   = run_query( 'SELECT * FROM set_resources', undef, { fetch => 'all_arrayref', slice => {} } );
	my $isolate_configs = {};
	my $seqdef_configs  = {};
	foreach my $set (@$set_resources) {
		$seqdef_configs->{ $set->{'set_name'} }  = $set->{'dbase_config'} if $set->{'dbase_config'} =~ /seqdef$/x;
		$isolate_configs->{ $set->{'set_name'} } = $set->{'dbase_config'} if $set->{'dbase_config'} =~ /isolates$/x;
	}
	my $list = [];
	foreach my $table (@tables) {
		my $count = run_query(
			"SELECT SUM(count) FROM $table t JOIN set_resources s ON "
			  . 't.dbase_config=s.dbase_config WHERE (s.set_name,t.datestamp)=(?,?)',
			[ $set_name, $date ]
		);
		if ($count) {
			my $plural = $count == 1 ? q() : q(s);
			my $url;
			if ( $table eq 'isolates_last_modified' && $isolate_configs->{$set_name} ) {
				$url = qq(/bigsdb?db=$isolate_configs->{$set_name}&amp;page=query&amp;)
				  . qq(prov_field1=f_datestamp&amp;prov_operator1==&amp;prov_value1=$date&amp;submit=1);
			} elsif ( $table eq 'sequences_last_modified' && $seqdef_configs->{$set_name} ) {
				$url = qq(/bigsdb?db=$seqdef_configs->{$set_name}&amp;page=tableQuery&amp;)
				  . qq(table=sequences&amp;s1=datestamp&amp;y1==&amp;t1=$date&amp;submit=1);
			}
			my $link;
			if ($url) {
				$link .= qq(<a href="$url">);
			}
			$link .= qq($count $name{$table}$plural);
			if ($url) {
				$link .= q(</a>);
			}
			push @$list, $link;
		}
	}
	my $profile_date = run_query(
		'SELECT SUM(count) AS count,scheme,scheme_id FROM profiles_last_modified t JOIN set_resources s ON '
		  . 't.dbase_config=s.dbase_config WHERE (s.set_name,t.datestamp)=(?,?) GROUP BY scheme,scheme_id ORDER BY scheme',
		[ $set_name, $date ],
		{ fetch => 'all_arrayref', slice => {} }
	);
	my %scheme_name = ( 'Ribosomal MLST' => 'rMLST' );
	foreach my $scheme (@$profile_date) {
		my $name = $scheme_name{ $scheme->{'scheme'} } // $scheme->{'scheme'};
		my $plural = $scheme->{'count'} == 1 ? q() : q(s);
		my $link;
		my $url;
		if ( $seqdef_configs->{$set_name} ) {
			$url = qq(/bigsdb?db=$seqdef_configs->{$set_name}&amp;page=query&amp;)
			  . qq(scheme_id=$scheme->{'scheme_id'}&amp;s1=datestamp&amp;y1==&amp;t1=$date&amp;submit=1);
		}
		if ($url) {
			$link .= qq(<a href="$url">);
		}
		$link .= qq($scheme->{'count'} $name profile$plural);
		if ($url) {
			$link .= q(</a>);
		}
		push @$list, $link;
	}
	return $list;
}

sub get_dbase_set_updated_on {
	my ($date) = @_;
	my @tables = qw(isolates_last_modified genomes_last_modified profiles_last_modified sequences_last_modified);
	my $list   = {};
	foreach my $table (@tables) {
		my $table_list = run_query(
			"SELECT DISTINCT(s.set_name) FROM $table t JOIN set_resources s ON "
			  . 't.dbase_config=s.dbase_config WHERE t.datestamp=?',
			$date,
			{ fetch => 'col_arrayref' }
		);
		$list->{$_} = 1 foreach @$table_list;
	}
	return [ sort keys %$list ];
}

sub get_list_of_dates {
	my @tables = qw(isolates_last_modified genomes_last_modified profiles_last_modified sequences_last_modified);
	my $list   = {};
	foreach my $table (@tables) {
		my $table_list =
		  run_query( "SELECT DISTINCT(datestamp) FROM $table ORDER BY datestamp desc LIMIT $opts{'days'}",
			undef, { fetch => 'col_arrayref' } );
		$list->{$_} = 1 foreach @$table_list;
	}
	my $limited_list = [];
	my $i            = 0;
	foreach my $date ( reverse sort keys %$list ) {
		push @$limited_list, $date;
		$i++;
		last if $i == $opts{'days'};
	}
	return $limited_list;
}

sub output_date_analysis {
	my ($options) = @_;
	my %table = (
		date_entered => 'date_entered',
		datestamp    => 'last_modified'
	);
	my $type = $options->{'type'} // 'datestamp';
	$db->do('CREATE TEMP TABLE date_output AS SELECT i.datestamp,r.set_name,i.count AS isolates '
		  . "FROM set_resources r JOIN isolates_$table{$type} i ON r.dbase_config=i.dbase_config " );
	$db->do('ALTER TABLE date_output ADD genomes int');
	$db->do('ALTER TABLE date_output ADD sequences int');
	$db->do('ALTER TABLE date_output ADD profiles int');
	$db->do('ALTER TABLE date_output ADD PRIMARY KEY(datestamp,set_name)');
	my $genome_data = run_query(
		"SELECT g.datestamp,r.set_name,g.count FROM genomes_$table{$type} g "
		  . 'JOIN set_resources r ON g.dbase_config=r.dbase_config',
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);

	foreach my $genome_record (@$genome_data) {
		$db->do(
			'INSERT INTO date_output (datestamp,set_name,genomes) VALUES (?,?,?) '
			  . 'ON CONFLICT (datestamp,set_name) DO UPDATE SET genomes=?',
			undef, @{$genome_record}{qw(datestamp set_name count count)}
		);
	}
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
	my $profile_data = run_query(
		"SELECT p.datestamp,r.set_name,SUM(p.count) AS count FROM profiles_$table{$type} p "
		  . 'JOIN set_resources r ON p.dbase_config=r.dbase_config GROUP BY r.set_name,p.datestamp',
		undef,
		{ fetch => 'all_arrayref', slice => {} }
	);
	foreach my $seq_record (@$profile_data) {
		$db->do(
			'INSERT INTO date_output (datestamp,set_name,profiles) VALUES (?,?,?) '
			  . 'ON CONFLICT (datestamp,set_name) DO UPDATE SET profiles=?',
			undef, @{$seq_record}{qw(datestamp set_name count count)}
		);
	}
	my $data =
	  run_query( 'SELECT * FROM date_output ORDER BY datestamp', undef, { fetch => 'all_arrayref', slice => {} } );
	if ( $opts{'format'} eq 'JSON' ) {
		say encode_json($data);
	} else {
		say qq(datestamp\tset_name\tisolates\tgenomes\tsequences\tprofiles);
		foreach my $record (@$data) {
			my @values = @{$record}{qw(datestamp set_name isolates genomes sequences profiles)};
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
	my $data               = $client->get_record("$opts{'url'}?show_all=1");
	eval {
		foreach my $group (@$data) {
			foreach my $database ( @{ $group->{'databases'} } ) {
				next if $ignore{ $database->{'name'} };
				$db->do(
					' INSERT INTO resources( dbase_config, description ) VALUES(?,?) '
					  . ' ON CONFLICT(dbase_config) DO UPDATE SET description = ?',
					undef, @{$database}{qw(name description description)}
				);
				if ( $database->{'description'} =~
					/(.+)\s(?:isolates|samples|records|sequence\/profile\ definitions|sequence\ definitions)$/x )
				{
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
	my $data         = $client->get_record("$opts{'url'}?show_all=1");
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
			eval {
				$db->do(
					"UPDATE sets SET $type=? WHERE name=(SELECT set_name FROM set_resources WHERE dbase_config=?)",
					undef, $type_record->{'records'},
					$database->{'name'}
				);
			};
			if ($@) {
				say "Problem with $database->{'name'}. $@.\n";
			}
		}
	}
	return;
}

sub update_isolates {
	my $ignore_config_list = get_ignore_config_list();
	my %ignore             = map { $_ => 1 } @$ignore_config_list;
	my $resources          = run_query( 'SELECT dbase_config FROM set_resources', undef, { fetch => 'col_arrayref' } );
	my %table              = (
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

sub update_profiles {
	my $ignore_config_list = get_ignore_config_list();
	my %ignore             = map { $_ => 1 } @$ignore_config_list;
	my $resources          = run_query( 'SELECT dbase_config FROM set_resources', undef, { fetch => 'col_arrayref' } );
	my %table              = (
		date_entered => 'date_entered',
		datestamp    => 'last_modified'
	);
	eval {
		CONFIG: foreach my $config (@$resources)
		{
			next CONFIG if $ignore{$config};
			my $data = $client->get_record("$opts{'url'}/db/$config");
			next CONFIG if !$data->{'sequences'};    #Not a profiles database
			next CONFIG if !$data->{'schemes'};      #Not a profiles database
		  FIELDNAME: foreach my $field_name (qw( date_entered datestamp)) {
				my $breakdown = $client->get_record( $data->{'schemes'} . "/breakdown/$field_name" );
				$db->do( "DELETE FROM profiles_$table{$field_name} WHERE dbase_config=?", undef, $config );
				foreach my $date (@$breakdown) {
					$db->do(
						"INSERT INTO profiles_$table{$field_name} (datestamp,dbase_config,scheme,scheme_id,count) "
						  . 'VALUES (?,?,?,?,?)',
						undef,
						$date->{$field_name},
						$config,
						$date->{'name'},
						$date->{'scheme_id'},
						$date->{'count'}
					);
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

sub update_countries {
	my $ignore_config_list = get_ignore_config_list();
	my %ignore             = map { $_ => 1 } @$ignore_config_list;
	my $resources          = run_query( 'SELECT dbase_config FROM set_resources', undef, { fetch => 'col_arrayref' } );
	eval {
		CONFIG: foreach my $config (@$resources)
		{
			next CONFIG if $ignore{$config};
			my $data = $client->get_record("$opts{'url'}/db/$config");
			next CONFIG if !$data->{'fields'};
			my $fields = $client->get_record( $data->{'fields'} );
		  FIELD: foreach my $field (@$fields) {
				next if $field->{'name'} ne 'country';
				next if !$field->{'allowed_values'};
				next if !$field->{'breakdown'};
				my $breakdown        = $client->get_record( $field->{'breakdown'} );
				my $genome_breakdown = $client->get_record("$field->{'breakdown'}?genomes=1");
				$db->do( 'DELETE FROM countries WHERE dbase_config=?', undef, $config );
				foreach my $country ( keys %$breakdown ) {
					$genome_breakdown->{$country} //= 0;
					$db->do(
						'INSERT INTO countries (dbase_config,country,count,genomes) VALUES (?,?,?,?)',
						undef, $config, $country,
						$breakdown->{$country},
						$genome_breakdown->{$country}
					);
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
	my $ignore_config_list = get_ignore_config_list();
	my %ignore             = map { $_ => 1 } @$ignore_config_list;
	my %table              = (
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
    
${bold}--days$norm [${under}DAYS$norm]
    Number of days to produce link for. Default:3.
    
${bold}--format$norm [${under}FORMAT$norm]
    Output format. Allowed values: CSV, JSON, TSV (default JSON), flat_list 
    (when used for outputting recent links).

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
    Output stats. Available options: countries, datestamp, date_entered, links, 
    summary, totals
    
${bold}--update$norm
	Update stats database.
    
${bold}--url$norm [${under}URL$norm]
    URL of the REST API.
    
${bold}--user$norm [${under}USER$norm]
    Database user.
    
HELP
	return;
}

sub get_iso3 {
	return {
		q(Afghanistan)                                       => q(AFG),
		q(Aland Islands)                                     => q(ALA),
		q(Albania)                                           => q(ALB),
		q(Algeria)                                           => q(DZA),
		q(American Samoa)                                    => q(ASM),
		q(Andorra)                                           => q(AND),
		q(Angola)                                            => q(AGO),
		q(Anguilla)                                          => q(AIA),
		q(Antarctica)                                        => q(ATA),
		q(Antigua and Barbuda)                               => q(ATG),
		q(Antigua & Barbuda)                                 => q(ATG),
		q(Argentina)                                         => q(ARG),
		q(Armenia)                                           => q(ARM),
		q(Aruba)                                             => q(ABW),
		q(Australia)                                         => q(AUS),
		q(Austria)                                           => q(AUT),
		q(Azerbaijan)                                        => q(AZE),
		q(Bahamas)                                           => q(BHS),
		q(Bahrain)                                           => q(BHR),
		q(Bangladesh)                                        => q(BGD),
		q(Barbados)                                          => q(BRB),
		q(Belarus)                                           => q(BLR),
		q(Belgium)                                           => q(BEL),
		q(Belize)                                            => q(BLZ),
		q(Benin)                                             => q(BEN),
		q(Bermuda)                                           => q(BMU),
		q(Bhutan)                                            => q(BTN),
		q(Bolivia)                                           => q(BOL),
		q(Bonaire, Sint Eustatius and Saba)                  => q(BES),
		q(Bosnia and Herzegovina)                            => q(BIH),
		q(Bosnia & Herzegovina)                              => q(BIH),
		q(Botswana)                                          => q(BWA),
		q(Bouvet Island)                                     => q(BVT),
		q(Brazil)                                            => q(BRA),
		q(British Virgin Islands)                            => q(VGB),
		q(British Indian Ocean Territory)                    => q(IOT),
		q(Brunei)                                            => q(BRN),
		q(Brunei Darussalam)                                 => q(BRN),
		q(Bulgaria)                                          => q(BGR),
		q(Burkina Faso)                                      => q(BFA),
		q(Burundi)                                           => q(BDI),
		q(Cambodia)                                          => q(KHM),
		q(Cameroon)                                          => q(CMR),
		q(Canada)                                            => q(CAN),
		q(Cape Verde)                                        => q(CPV),
		q(Cayman Islands)                                    => q(CYM),
		q(Central African Republic)                          => q(CAF),
		q(Chad)                                              => q(TCD),
		q(Chile)                                             => q(CHL),
		q(China)                                             => q(CHN),
		q(Hong Kong, Special Administrative Region of China) => q(HKG),
		q(Macao, Special Administrative Region of China)     => q(MAC),
		q(Christmas Island)                                  => q(CXR),
		q(Cocos (Keeling) Islands)                           => q(CCK),
		q(Colombia)                                          => q(COL),
		q(Comoros)                                           => q(COM),
		q(Congo (Brazzaville))                               => q(COG),
		q(Congo [Republic])                                  => q(COG),
		q(Congo, Democratic Republic of the)                 => q(COD),
		q(Congo [DRC])                                       => q(COD),
		q(Cook Islands)                                      => q(COK),
		q(Costa Rica)                                        => q(CRI),
		q(Côte d'Ivoire)                                    => q(CIV),
		q(Ivory Coast)                                       => q(CIV),
		q(Croatia)                                           => q(HRV),
		q(Cuba)                                              => q(CUB),
		q(Curaçao)                                          => q(CUW),
		q(Cyprus)                                            => q(CYP),
		q(Czech Republic)                                    => q(CZE),
		q(Czechoslovakia)                                    => q(CZE),
		q(Denmark)                                           => q(DNK),
		q(Djibouti)                                          => q(DJI),
		q(Dominica)                                          => q(DMA),
		q(Dominican Republic)                                => q(DOM),
		q(Ecuador)                                           => q(ECU),
		q(Egypt)                                             => q(EGY),
		q(El Salvador)                                       => q(SLV),
		q(Equatorial Guinea)                                 => q(GNQ),
		q(Eritrea)                                           => q(ERI),
		q(Estonia)                                           => q(EST),
		q(Ethiopia)                                          => q(ETH),
		q(Falkland Islands (Malvinas))                       => q(FLK),
		q(Faroe Islands)                                     => q(FRO),
		q(Fiji)                                              => q(FJI),
		q(Finland)                                           => q(FIN),
		q(France)                                            => q(FRA),
		q(French Guiana)                                     => q(GUF),
		q(French Polynesia)                                  => q(PYF),
		q(Polynesia)                                         => q(PYF),
		q(French Southern Territories)                       => q(ATF),
		q(Gabon)                                             => q(GAB),
		q(The Gambia)                                        => q(GMB),
		q(Georgia)                                           => q(GEO),
		q(Germany)                                           => q(DEU),
		q(Ghana)                                             => q(GHA),
		q(Gibraltar)                                         => q(GIB),
		q(Greece)                                            => q(GRC),
		q(Greenland)                                         => q(GRL),
		q(Grenada)                                           => q(GRD),
		q(Guadeloupe)                                        => q(GLP),
		q(Guam)                                              => q(GUM),
		q(Guatemala)                                         => q(GTM),
		q(Guernsey)                                          => q(GGY),
		q(Guinea)                                            => q(GIN),
		q(Guinea-Bissau)                                     => q(GNB),
		q(Guinea Bissau)                                     => q(GNB),
		q(Guyana)                                            => q(GUY),
		q(Haiti)                                             => q(HTI),
		q(Heard Island and Mcdonald Islands)                 => q(HMD),
		q(Holy See (Vatican City State))                     => q(VAT),
		q(Honduras)                                          => q(HND),
		q(Hungary)                                           => q(HUN),
		q(Iceland)                                           => q(ISL),
		q(India)                                             => q(IND),
		q(Indonesia)                                         => q(IDN),
		q(Iran)                                              => q(IRN),
		q(Iraq)                                              => q(IRQ),
		q(Ireland)                                           => q(IRL),
		q(Isle of Man)                                       => q(IMN),
		q(Israel)                                            => q(ISR),
		q(Italy)                                             => q(ITA),
		q(Jamaica)                                           => q(JAM),
		q(Japan)                                             => q(JPN),
		q(Jersey)                                            => q(JEY),
		q(Jordan)                                            => q(JOR),
		q(Kazakhstan)                                        => q(KAZ),
		q(Kenya)                                             => q(KEN),
		q(Kiribati)                                          => q(KIR),
		q(North Korea)                                       => q(PRK),
		q(South Korea)                                       => q(KOR),
		q(Korea)                                             => q(KOR),
		q(Kuwait)                                            => q(KWT),
		q(Kyrgyzstan)                                        => q(KGZ),
		q(Lao PDR)                                           => q(LAO),
		q(Laos)                                              => q(LAO),
		q(Latvia)                                            => q(LVA),
		q(Lebanon)                                           => q(LBN),
		q(Lesotho)                                           => q(LSO),
		q(Liberia)                                           => q(LBR),
		q(Libya)                                             => q(LBY),
		q(Liechtenstein)                                     => q(LIE),
		q(Lithuania)                                         => q(LTU),
		q(Luxembourg)                                        => q(LUX),
		q(Macedonia, Republic of)                            => q(MKD),
		q(Macedonia)                                         => q(MKD),
		q(Madagascar)                                        => q(MDG),
		q(Malawi)                                            => q(MWI),
		q(Malaysia)                                          => q(MYS),
		q(Maldives)                                          => q(MDV),
		q(Mali)                                              => q(MLI),
		q(Malta)                                             => q(MLT),
		q(Marshall Islands)                                  => q(MHL),
		q(Martinique)                                        => q(MTQ),
		q(Mauritania)                                        => q(MRT),
		q(Mauritius)                                         => q(MUS),
		q(Mayotte)                                           => q(MYT),
		q(Mexico)                                            => q(MEX),
		q(Micronesia, Federated States of)                   => q(FSM),
		q(Micronesia)                                        => q(FSM),
		q(Moldova)                                           => q(MDA),
		q(Moldavia)                                          => q(MDA),
		q(Monaco)                                            => q(MCO),
		q(Mongolia)                                          => q(MNG),
		q(Montenegro)                                        => q(MNE),
		q(Montserrat)                                        => q(MSR),
		q(Morocco)                                           => q(MAR),
		q(Mozambique)                                        => q(MOZ),
		q(Myanmar)                                           => q(MMR),
		q(Burma)                                             => q(MMR),
		q(Namibia)                                           => q(NAM),
		q(Nauru)                                             => q(NRU),
		q(Nepal)                                             => q(NPL),
		q(The Netherlands)                                   => q(NLD),
		q(Netherlands Antilles)                              => q(ANT),
		q(New Caledonia)                                     => q(NCL),
		q(New Zealand)                                       => q(NZL),
		q(Nicaragua)                                         => q(NIC),
		q(Niger)                                             => q(NER),
		q(Nigeria)                                           => q(NGA),
		q(Niue)                                              => q(NIU),
		q(Norfolk Island)                                    => q(NFK),
		q(Northern Mariana Islands)                          => q(MNP),
		q(Norway)                                            => q(NOR),
		q(Oman)                                              => q(OMN),
		q(Pakistan)                                          => q(PAK),
		q(Palau)                                             => q(PLW),
		q(Palestinian Territory, Occupied)                   => q(PSE),
		q(Palestinian territories)                           => q(PSE),
		q(Panama)                                            => q(PAN),
		q(Papua New Guinea)                                  => q(PNG),
		q(Paraguay)                                          => q(PRY),
		q(Peru)                                              => q(PER),
		q(Philippines)                                       => q(PHL),
		q(Pitcairn)                                          => q(PCN),
		q(Poland)                                            => q(POL),
		q(Portugal)                                          => q(PRT),
		q(Puerto Rico)                                       => q(PRI),
		q(Qatar)                                             => q(QAT),
		q(Réunion)                                          => q(REU),
		q(Reunion)                                           => q(REU),
		q(Romania)                                           => q(ROU),
		q(Russian Federation)                                => q(RUS),
		q(Russia)                                            => q(RUS),
		q(Rwanda)                                            => q(RWA),
		q(Saint-Barthélemy)                                 => q(BLM),
		q(Saint Helena)                                      => q(SHN),
		q(Saint Kitts and Nevis)                             => q(KNA),
		q(Saint Lucia)                                       => q(LCA),
		q(Saint-Martin (French part))                        => q(MAF),
		q(Saint Pierre and Miquelon)                         => q(SPM),
		q(Saint Vincent and Grenadines)                      => q(VCT),
		q(Samoa)                                             => q(WSM),
		q(San Marino)                                        => q(SMR),
		q(Sao Tome and Principe)                             => q(STP),
		q(São Tomé and Príncipe)                          => q(STP),
		q(Saudi Arabia)                                      => q(SAU),
		q(Senegal)                                           => q(SEN),
		q(Serbia)                                            => q(SRB),
		q(Seychelles)                                        => q(SYC),
		q(Sierra Leone)                                      => q(SLE),
		q(Singapore)                                         => q(SGP),
		q(Sint Maarten (Dutch part))                         => q(SXM),
		q(Slovakia)                                          => q(SVK),
		q(Slovak Republic)                                   => q(SVK),
		q(Slovenia)                                          => q(SVN),
		q(Solomon Islands)                                   => q(SLB),
		q(Somalia)                                           => q(SOM),
		q(South Africa)                                      => q(ZAF),
		q(South Georgia and the South Sandwich Islands)      => q(SGS),
		q(South Sudan)                                       => q(SSD),
		q(Spain)                                             => q(ESP),
		q(Sri Lanka)                                         => q(LKA),
		q(Sudan)                                             => q(SDN),
		q(Suriname)                                          => q(SUR),
		q(Svalbard and Jan Mayen Islands)                    => q(SJM),
		q(Swaziland)                                         => q(SWZ),
		q(Sweden)                                            => q(SWE),
		q(Switzerland)                                       => q(CHE),
		q(Syria)                                             => q(SYR),
		q(Taiwan)                                            => q(TWN),
		q(Tajikistan)                                        => q(TJK),
		q(Tanzania)                                          => q(TZA),
		q(Thailand)                                          => q(THA),
		q(Timor-Leste)                                       => q(TLS),
		q(East Timor)                                        => q(TLS),
		q(Togo)                                              => q(TGO),
		q(Tokelau)                                           => q(TKL),
		q(Tonga)                                             => q(TON),
		q(Trinidad & Tobago)                                 => q(TTO),
		q(Trinidad and Tobago)                               => q(TTO),
		q(Tunisia)                                           => q(TUN),
		q(Turkey)                                            => q(TUR),
		q(Turkmenistan)                                      => q(TKM),
		q(Turks and Caicos Islands)                          => q(TCA),
		q(Tuvalu)                                            => q(TUV),
		q(Uganda)                                            => q(UGA),
		q(Ukraine)                                           => q(UKR),
		q(United Arab Emirates)                              => q(ARE),
		q(UK)                                                => q(GBR),
		q(UK [England])                                      => q(GBR),
		q(UK [Northern Ireland])                             => q(GBR),
		q(UK [Scotland])                                     => q(GBR),
		q(UK [Wales])                                        => q(GBR),
		q(USA)                                               => q(USA),
		q(United States Minor Outlying Islands)              => q(UMI),
		q(Uruguay)                                           => q(URY),
		q(Uzbekistan)                                        => q(UZB),
		q(Vanuatu)                                           => q(VUT),
		q(Venezuela)                                         => q(VEN),
		q(Vietnam)                                           => q(VNM),
		q(Virgin Islands, US)                                => q(VIR),
		q(Wallis and Futuna Islands)                         => q(WLF),
		q(Wallis & Futuna Islands)                           => q(WLF),
		q(Western Sahara)                                    => q(ESH),
		q(Yemen)                                             => q(YEM),
		q(Yugoslavia)                                        => q(SCG),
		q(Zambia)                                            => q(ZMB),
		q(Zimbabwe)                                          => q(ZWE),
		q(USSR)                                              => q(SUN),
		q(Tahiti)                                            => q(PYF),
	};
}
