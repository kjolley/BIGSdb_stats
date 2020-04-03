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
use constant REST_URL => 'https://rest.pubmlst.org';
my @dbases = @ARGV;
binmode( STDOUT, ':encoding(UTF-8)' );

if ( !@dbases ) {
	say 'Usage bigsdb_quickstats.pl <config name1> [<config name2>]';
	exit(1);
}
my $client = BIGSdbRestClient->new( { rest_url => REST_URL } );
my $buffer;
my $no_status;
foreach my $db (@dbases) {
	if ( $db eq 'nostatus' ) {
		$no_status = 1;
		next;
	}
	my $url          = REST_URL . "/db/$db";
	my $record       = $client->get_record($url);
	my $last_updated = q();
	if ( $record->{'sequences'} ) {
		$buffer .= qq(<p><b>Sequence database</b><br />\n);
		my $seq_record = $client->get_record( $record->{'sequences'} );
		my $nice_seqs  = commify( $seq_record->{'records'} );
		$buffer .= qq(Sequences: $nice_seqs<br />\n);
		if ( $seq_record->{'last_updated'} ) {
			$last_updated = $seq_record->{'last_updated'};
		}
		if ( $record->{'schemes'} ) {
			my $scheme_list = $client->get_record("$record->{'schemes'}?with_pk=1");
			if ( $scheme_list->{'records'} > 1 ) {
				$buffer .= qq(Profiles:<br />\n);
				foreach my $scheme_record ( @{ $scheme_list->{'schemes'} } ) {
					my $scheme_record = $client->get_record( $scheme_record->{'scheme'} );
					$scheme_record->{'records'} //= 0;
					$buffer .= qq($scheme_record->{'description'}: $scheme_record->{'records'}<br />\n);
					if ( $scheme_record->{'last_updated'} && $scheme_record->{'last_updated'} gt $last_updated ) {
						$last_updated = $scheme_record->{'last_updated'};
					}
				}
			} elsif ( $scheme_list->{'records'} == 1 ) {
				my $scheme_record = $client->get_record( $scheme_list->{'schemes'}->[0]->{'scheme'} );
				if ( $scheme_record && $scheme_record->{'records'} ) {
					$buffer .= qq(Profiles ($scheme_record->{'description'}): $scheme_record->{'records'}<br />\n);
					if ( $scheme_record->{'last_updated'} && $scheme_record->{'last_updated'} gt $last_updated ) {
						$last_updated = $scheme_record->{'last_updated'};
					}
				}
			}
		}
		if ($last_updated) {
			$buffer .= qq(Last updated: $last_updated);
		}
		$buffer .= qq(</p>\n);
	}
	if ( $record->{'isolates'} ) {
		$buffer .= qq(<p><b>Isolate database</b><br />\n);
		my $isolate_record = $client->get_record( $record->{'isolates'} );
		my $nice_records   = commify( $isolate_record->{'records'} );
		$buffer .= qq(Isolates: $nice_records);
		if ( $isolate_record->{'last_updated'} ) {
			$buffer .= qq(<br />\nLast updated: $isolate_record->{'last_updated'});
		}
		$buffer .= q(</p>);
	}
}
if ($buffer) {
	say q(<h2>Status</h2>) if !$no_status;
	say $buffer;
}

#Put commas in numbers
#Perl Cookbook 2.16
sub commify {
	my ($text) = @_;
	$text = reverse $text;
	$text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/gx;
	return scalar reverse $text;
}
