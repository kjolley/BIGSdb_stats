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
package BIGSdbRestClient;
use strict;
use warnings;
use 5.010;
use JSON;
use Data::Random qw(rand_chars);
use HTTP::Request::Common;
use LWP::UserAgent;
use Net::OAuth 0.20;
use Config::Tiny;
use Carp;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;
use constant KEY_FILE => '.api_key';

#Need any protected database in order to delegate authority
use constant PASSWORD_PROTECTED_DB => 'pubmlst_rmlst_seqdef';

sub new {
	my ( $class, $self ) = @_;
	bless( $self, $class );
	$self->{'user_agent'} = LWP::UserAgent->new;

	#	use Data::Dumper;
	#	say Dumper $self;
	return $self;
}

sub setup {
	my ($self)          = @_;
	my ($request_token) = "$ENV{'HOME'}/.request_token";
	unlink $request_token;
	$self->get_access_token();
	return;
}

sub _get_key {
	my ($self) = @_;
	my ($file) = "$ENV{'HOME'}/" . KEY_FILE;
	if ( !-e $file ) {
		die "$file does not exist.\n";
	}
	my $config = Config::Tiny->new();
	$config = Config::Tiny->read($file);
	return ( $config->{_}->{'key'}, $config->{_}->{'secret'} );
}

sub _retrieve_token {
	my ( $self, $token_name ) = @_;
	my ($full_path) = "$ENV{'HOME'}/.$token_name";
	return if !-e $full_path;
	my $config = Config::Tiny->new();
	$config = Config::Tiny->read($full_path);
	return ( $config->{_}->{'token'}, $config->{_}->{'secret'} );
}

sub _write_token {
	my ( $self, $token_name, $token, $secret ) = @_;
	my ($full_path) = "$ENV{'HOME'}/.$token_name";
	my $config = Config::Tiny->new();
	$config->{_}->{'token'}  = $token;
	$config->{_}->{'secret'} = $secret;
	$config->write($full_path);
	return;
}

sub _get_request_token {
	my ($self) = @_;
	my $protected_db = PASSWORD_PROTECTED_DB;
	my ( $key, $secret ) = $self->_get_key;
	my $request = Net::OAuth->request('request token')->new(
		consumer_key     => $key,
		consumer_secret  => $secret,
		request_url      => "$self->{'rest_url'}/db/$protected_db/oauth/get_request_token",
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
	my $res = $self->{'user_agent'}->request( GET $request->to_url, Content_Type => 'application/json', );
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
	my ( $self, $request_token, $request_secret ) = @_;
	my ( $key, $secret ) = $self->_get_key;
	my $protected_db = PASSWORD_PROTECTED_DB;
	unlink 'access_token';
	if ( !$request_token || $request_secret ) {
		my $session_response = $self->_get_request_token();
		( $request_token, $request_secret ) = ( $session_response->token, $session_response->token_secret );
	}
	say "\nNow log in at\n"
	  . "$self->{'bigsdb_url'}?db=$protected_db&page=authorizeClient&oauth_token=$request_token"
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
		request_url      => "$self->{'rest_url'}/db/$protected_db/oauth/get_access_token",
		request_method   => 'GET',
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
	);
	$request->sign;
	die "COULDN'T VERIFY! Check OAuth parameters.\n" unless $request->verify;
	say "\nGetting access token...";
	unlink 'request_token';    #Request tokens can only be redeemed once
	my $res = $self->{'user_agent'}->request( GET $request->to_url, Content_Type => 'application/json' );
	my $decoded_json = decode_json( $res->content );

	if ( $res->is_success ) {
		say 'Success.';
		my $access_response = Net::OAuth->response('access token')->from_hash($decoded_json);
		$self->_write_token( 'access_token', $access_response->token, $access_response->token_secret );
		return $access_response;
	} else {
		die "Failed to get access token.\n";
	}
}

sub _get_session_token {
	my ( $self, $access_token, $access_secret ) = @_;
	state $failed = 0;
	my ( $key, $secret ) = $self->_get_key;
	my $protected_db = PASSWORD_PROTECTED_DB;
	if ( !$access_token || $access_secret ) {
		( $access_token, $access_secret ) = $self->_retrieve_token('access_token');
		if ( !$access_token || !$access_secret ) {
			my $session_response = $self->get_access_token;
			( $access_token, $access_secret ) = ( $session_response->token, $session_response->token_secret );
		}
	}
	my $request = Net::OAuth->request('protected resource')->new(
		consumer_key     => $key,
		consumer_secret  => $secret,
		token            => $access_token,
		token_secret     => $access_secret,
		request_url      => "$self->{'rest_url'}/db/$protected_db/oauth/get_session_token",
		request_method   => 'GET',
		signature_method => 'HMAC-SHA1',
		timestamp        => time,
		nonce            => join( '', rand_chars( size => 16, set => 'alphanumeric' ) ),
	);
	$request->sign;
	die "COULDN'T VERIFY! Check OAuth parameters.\n" unless $request->verify;
	my $res = $self->{'user_agent'}->request( GET $request->to_url, Content_Type => 'application/json' );
	my $decoded_json = decode_json( $res->content );
	if ( $res->is_success ) {
		my $session_response = Net::OAuth->response('access token')->from_hash($decoded_json);
		$self->_write_token( 'session_token', $session_response->token, $session_response->token_secret );
		return $session_response;
	} else {
		say 'Failed:';
		if ( $res->{'_content'} =~ /401/ ) {
			$failed++;
			exit if $failed == 2;
			say 'Invalid access token, requesting new one...';
			my $access_response = $self->get_access_token();
			if ($access_response) {
				( $access_token, $access_secret ) = ( $access_response->token, $access_response->token_secret );
			}
			return $self->_get_session_token( $access_token, $access_secret );
		} else {
			return;
		}
	}
}

sub get_record {
	my ( $self, $uri ) = @_;
	my $response;
	my $requires_authorization;
	my $config = q();
	state %authenticated_dbs;
	if ( $uri =~ /$self->{'rest_url'}\/db\/([\w\d\-_]+)/x ) {
		$config = $1;
	}
	if ( !$authenticated_dbs{$config} ) {
		for my $attempt ( 1 .. 30 ) {
			$response = $self->{'user_agent'}->get($uri);
			last if $response->is_success || $response->code == 401 || $response->code == 404;
			my ( $code, $msg ) = ( $response->code, $response->message );
			say "Error retrieving $uri: Response $code: $msg. Will retry in 1s.";
			sleep 1;
		}
		if ( $response->is_success ) {
			my $data;
			eval { $data = decode_json( $response->decoded_content ); };
			die "Data is not JSON.\n" if $@;
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
		return $self->_get_protected_route($uri);
	}
	die "Cannot retrieve $uri.\n";
}

sub _get_protected_route {
	my ( $self,          $uri )            = @_;
	my ( $key,           $secret )         = $self->_get_key;
	my ( $session_token, $session_secret ) = $self->_retrieve_token('session_token');
	if ( !$session_token ) {
		$self->_get_session_token();
		( $session_token, $session_secret ) = $self->_retrieve_token('session_token');
	}
	state $failures = 0;
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
	my $res = $self->{'user_agent'}->get( $request->to_url );
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
			$failures++;
			croak "$uri: Failed too many times.\n" if $failures >= 10;
			$self->_get_session_token();
			return $self->_get_protected_route($uri);
		}
	}
	die "Invalid JSON.\n" if !ref $decoded_json;
	return $decoded_json;
}
1;
