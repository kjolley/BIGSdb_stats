#!/usr/bin/env perl
#Written by Keith Jolley
#Copyright (c) 2020, University of Oxford
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
use Digest::MD5;
use Getopt::Long qw(:config no_ignore_case);
use constant DEFAULT_REST_URL => 'https://rest.pubmlst.org';
use constant IGNORE_GROUP     => 'test';
binmode( STDOUT, ':encoding(UTF-8)' );
my %opts;
GetOptions(
	'list_format'    => \$opts{'list_format'},
	'list_databases' => \$opts{'list_databases'}
) or die("Error in command line arguments\n");
my $client = BIGSdbRestClient->new( { rest_url => DEFAULT_REST_URL } );
main();

sub main {
	my $data   = $client->get_record(DEFAULT_REST_URL);
	my %ignore = map { $_ => 1 } split /,/x, IGNORE_GROUP;
	my $list   = {};
  SET: foreach my $dataset (@$data) {
		next if $ignore{ $dataset->{'name'} };
		if ( $dataset->{'databases'} ) {
			eval {
				DATABASE: foreach my $resource ( @{ $dataset->{'databases'} } )
				{
					my $database = $client->get_record( $resource->{'href'} );
					if ( $database->{'curators'} ) {
						my $curators = $client->get_record( $database->{'curators'} );
					  CURATOR: foreach my $curator_url (@{$curators->{'curators'}}) {
							my $curator = $client->get_record($curator_url);
							my $key =
							  Digest::MD5::md5_hex(
								"$curator->{'first_name'} $curator->{'surname'}, $curator->{'affiliation'}");
							if ( !defined $list->{$key} ) {
								$list->{$key} = {
									first_name  => $curator->{'first_name'},
									surname     => $curator->{'surname'},
									affiliation => $curator->{'affiliation'},
									databases   => [ $resource->{'description'} ]
								};
							} else {
								push @{ $list->{$key}->{'databases'} }, $resource->{'description'};
							}
						}
					}
				}
			};
		}
	}
	say q(<ul>) if $opts{'list_format'};
	foreach my $key (
		sort {
			     $list->{$a}->{'surname'} cmp $list->{$b}->{'surname'}
			  || $list->{$a}->{'first_name'} cmp $list->{$b}->{'first_name'}
		} keys %$list
	  )
	{
		local $" = q(, );
		my $value = qq($list->{$key}->{'first_name'} $list->{$key}->{'surname'}, $list->{$key}->{'affiliation'});
		$value .= qq( - @{$list->{$key}->{'databases'}}) if $opts{'list_databases'};
		say $opts{'list_format'} ? qq(<li>$value</li>) : $value;
	}
	say q(</ul>) if $opts{'list_format'};
	return;
}
