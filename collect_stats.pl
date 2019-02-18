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
use Config::Tiny;
use DBI;
use Getopt::Long qw(:config no_ignore_case);
use Data::Random qw(rand_chars);
use HTTP::Request::Common;
use LWP::UserAgent;
use JSON;
use Term::Cap;
use POSIX;
use Net::OAuth 0.20;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;
use constant DEFAULT_REST_URL   => 'http://rest.pubmlst.org';
use constant DEFAULT_BIGSDB_URL => 'https://pubmlst.org/bigsdb';
use constant STATS_DB           => 'bigsdb_stats';
use constant HOST               => 'zoo-aberlour';
use constant PORT               => 5432;
use constant USER               => 'apache';
use constant PASSWORD           => undef;                          #Better to set in .pgpass file or pass as option
use constant KEY_FILE           => '~/.api_key';
use constant IGNORE_GROUP       => 'test';

#Need any protected database in order to delegate authority
use constant PASSWORD_PROTECTED_DB => 'pubmlst_rmlst_seqdef';
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
my $ua         = LWP::UserAgent->new;
my $rest_url   = $opts{'url'} // DEFAULT_REST_URL;
my $bigsdb_url = $opts{'bigsdb_db'} // DEFAULT_BIGSDB_URL;
if ( $opts{'setup'} ) {
	my ($request_token) = glob('~/.request_token');
	unlink $request_token;
	get_access_token();
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

sub get_ignore_config_list {
	$opts{' ignore_group '} //= q();
	my @passed_list = split /,/x, $opts{' ignore_group '};
	my %ignore_group = map { $_ => 1 } ( IGNORE_GROUP, @passed_list );
	my $list         = [];
	my $data         = get_record($rest_url);
	foreach my $group (@$data) {
		if ( $ignore_group{ $group->{'name'} } ) {
			foreach my $resource ( @{ $group->{'databases'} } ) {
				push @$list, $resource->{'name'};
			}
		}
	}
	return $list;
}

sub update_resources {
	my $ignore_config_list = get_ignore_config_list();
	my %ignore             = map { $_ => 1 } @$ignore_config_list;
	my $data               = get_record($rest_url);
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

sub update_totals {
	my ($database) = @_;
	my $data = get_record( $database->{'href'} );
	foreach my $type (qw(isolates genomes sequences)) {
		if ( $data->{$type} ) {
			my $type_record = get_record( $data->{$type} );
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
			my $data = get_record("$rest_url/db/$config");
			next CONFIG if !$data->{'fields'};
			my $fields = get_record( $data->{'fields'} );
		  FIELDNAME: foreach my $field_name (qw( date_entered datestamp)) {
			  FIELD: foreach my $field (@$fields) {
					next FIELD if $field->{'name'} ne $field_name || !$field->{'breakdown'};
				  TYPE: foreach my $type (qw(isolates genomes)) {
						my $clause = $type eq 'genomes' ? q(?genomes=1) : q();
						my $breakdown = get_record( $field->{'breakdown'} . $clause );
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
			my $data = get_record("$rest_url/db/$config");
			next CONFIG if !$data->{'sequences'};
			my $sequences = get_record( $data->{'sequences'} );
			next CONFIG if !$sequences->{'fields'};
			my $fields = get_record( $sequences->{'fields'} );
		  FIELDNAME: foreach my $field_name (qw( date_entered datestamp)) {
			  FIELD: foreach my $field (@$fields) {
					next FIELD if $field->{'name'} ne $field_name || !$field->{'breakdown'};
					my $breakdown = get_record( $field->{'breakdown'} );
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

sub get_key {
	my ($file) = glob(KEY_FILE);
	if ( !-e $file ) {
		die "$file does not exist.\n";
	}
	my $config = Config::Tiny->new();
	$config = Config::Tiny->read($file);
	return ( $config->{_}->{'key'}, $config->{_}->{'secret'} );
}

sub retrieve_token {
	my ($token_name) = @_;
	my ($full_path)  = glob("~/.$token_name");
	return if !-e $full_path;
	my $config = Config::Tiny->new();
	$config = Config::Tiny->read($full_path);
	return ( $config->{_}->{'token'}, $config->{_}->{'secret'} );
}

sub write_token {
	my ( $token_name, $token, $secret ) = @_;
	my ($full_path) = glob("~/.$token_name");
	my $config = Config::Tiny->new();
	$config->{_}->{'token'}  = $token;
	$config->{_}->{'secret'} = $secret;
	$config->write($full_path);
	return;
}

sub get_request_token {
	my $protected_db = PASSWORD_PROTECTED_DB;
	my ( $key, $secret ) = get_key();
	my $request = Net::OAuth->request('request token')->new(
		consumer_key     => $key,
		consumer_secret  => $secret,
		request_url      => "$rest_url/db/$protected_db/oauth/get_request_token",
		request_method   => 'GET',
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
		callback         => 'oob'
	);
	$request->sign;

	#say $request->signature_base_string;
	die "COULDN'T VERIFY! Check OAuth parameters.\n" unless $request->verify;
	say 'Getting request token...';
	my $res = $ua->request( GET $request->to_url, Content_Type => 'application/json', );
	my $decoded_json = decode_json( $res->content );
	my $request_response;
	if ( $res->is_success ) {
		say 'Success.';
		$request_response = Net::OAuth->response('request token')->from_hash($decoded_json);
		return $request_response;
	} else {
		die "Failed to get request token.\n";
	}
}

sub get_access_token {
	my ( $request_token, $request_secret ) = @_;
	my ( $key,           $secret )         = get_key();
	my $protected_db = PASSWORD_PROTECTED_DB;
	unlink 'access_token';
	if ( !$request_token || $request_secret ) {
		my $session_response = get_request_token();
		( $request_token, $request_secret ) = ( $session_response->token, $session_response->token_secret );
	}
	say "\nNow log in at\n"
	  . "$bigsdb_url?db=$protected_db&page=authorizeClient&oauth_token=$request_token"
	  . "\nto obtain a verification code.";
	print "\nPlease enter verification code:  ";
	my $verifier = <>;
	chomp $verifier;
	my $request = Net::OAuth->request('access token')->new(
		consumer_key     => $key,
		consumer_secret  => $secret,
		token            => $request_token,
		token_secret     => $request_secret,
		verifier         => $verifier,
		request_url      => "$rest_url/db/$protected_db/oauth/get_access_token",
		request_method   => 'GET',
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
	);
	$request->sign;
	die "COULDN'T VERIFY! Check OAuth parameters.\n" unless $request->verify;
	say "\nGetting access token...";
	unlink 'request_token';    #Request tokens can only be redeemed once
	my $res = $ua->request( GET $request->to_url, Content_Type => 'application/json' );
	my $decoded_json = decode_json( $res->content );

	if ( $res->is_success ) {
		say 'Success.';
		my $access_response = Net::OAuth->response('access token')->from_hash($decoded_json);
		write_token( 'access_token', $access_response->token, $access_response->token_secret );
		return $access_response;
	} else {
		die "Failed to get access token.\n";
	}
}

sub get_session_token {
	my ( $access_token, $access_secret ) = @_;
	state $failed = 0;
	my ( $key, $secret ) = get_key();
	my $protected_db = PASSWORD_PROTECTED_DB;
	if ( !$access_token || $access_secret ) {
		( $access_token, $access_secret ) = retrieve_token('access_token');
		if ( !$access_token || !$access_secret ) {
			my $session_response = get_access_token();
			( $access_token, $access_secret ) = ( $session_response->token, $session_response->token_secret );
		}
	}
	my $request = Net::OAuth->request('protected resource')->new(
		consumer_key     => $key,
		consumer_secret  => $secret,
		token            => $access_token,
		token_secret     => $access_secret,
		request_url      => "$rest_url/db/$protected_db/oauth/get_session_token",
		request_method   => 'GET',
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
	);
	$request->sign;
	die "COULDN'T VERIFY! Check OAuth parameters.\n" unless $request->verify;
	my $res = $ua->request( GET $request->to_url, Content_Type => 'application/json' );
	my $decoded_json = decode_json( $res->content );
	if ( $res->is_success ) {
		my $session_response = Net::OAuth->response('access token')->from_hash($decoded_json);
		write_token( 'session_token', $session_response->token, $session_response->token_secret );
		return $session_response;
	} else {
		say 'Failed:';
		if ( $res->{'_content'} =~ /401/ ) {
			$failed++;
			exit if $failed == 2;
			say 'Invalid access token, requesting new one...';
			my $access_response = get_access_token();
			if ($access_response) {
				( $access_token, $access_secret ) = ( $access_response->token, $access_response->token_secret );
			}
			return get_session_token( $access_token, $access_secret );
		} else {
			return;
		}
	}
}

sub get_record {
	my ($uri) = @_;
	my $response;
	my $requires_authorization;
	my $config = q();
	state %authenticated_dbs;
	if ( $uri =~ /$rest_url\/db\/([\w\d\-_]+)/x ) {
		$config = $1;
	}
	if ( !$authenticated_dbs{$config} ) {
		for my $attempt ( 1 .. 30 ) {
			$response = $ua->get($uri);
			last if $response->is_success || $response->code == 401 || $response->code == 404;
			my ( $code, $msg ) = ( $response->code, $response->message );
			say "Error retrieving $uri: Response $code: $msg. Will retry in 1s.";
			sleep 1;
		}
		if ( $response->is_success ) {
			my $data;
			eval { $data = decode_json( $response->decoded_content ); };
			BIGSdb::Exception::Data->throw('Data is not JSON') if $@;
			return $data;
		} else {
			if ( $response->code == 401 ) {
				$requires_authorization = 1;
			} else {
				my ( $code, $msg ) = ( $response->code, $response->message );
				die "Error retrieving $uri: Response $code: $msg\n";
			}
		}
	} else {
		$requires_authorization = 1;
	}
	if ($requires_authorization) {
		$authenticated_dbs{$config} = 1;
		return get_protected_route($uri);
	}
	die "Cannot retrieve $uri.\n";
}

sub get_protected_route {
	my ($uri) = @_;
	my ( $key,           $secret )         = get_key();
	my ( $session_token, $session_secret ) = retrieve_token('session_token');
	if ( !$session_token ) {
		get_session_token();
		( $session_token, $session_secret ) = retrieve_token('session_token');
	}
	my $request = Net::OAuth->request('protected resource')->new(
		consumer_key     => $key,
		consumer_secret  => $secret,
		token            => $session_token,
		token_secret     => $session_secret,
		request_url      => $uri,
		request_method   => 'GET',
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
	);
	$request->sign;
	die "Cannot verify signature.\n" unless $request->verify;
	my $res = $ua->get( $request->to_url );
	my $decoded_json;
	eval { $decoded_json = decode_json( $res->content ) };
	if ($@) {
		die $res->content . "\n";
	}
	if ( ref $decoded_json eq 'HASH' ) {
		if ( ( $decoded_json->{'message'} // q() ) =~ /Client\ is\ unauthorized/x ) {
			die "Access denied - client is unauthorized.\n";
		}
		if ( ( $decoded_json->{'status'} // q() ) eq '401' ) {

			#			say 'Invalid session token, requesting new one.';
			get_session_token();
			return get_protected_route($uri);
		}
	}
	die "Invalid JSON.\n" if !ref $decoded_json;
	return $decoded_json;
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
