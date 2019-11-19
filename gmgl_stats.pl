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
use constant LIB_DIR => '/usr/local/lib';
use lib (LIB_DIR);
use FindBin;
use lib "$FindBin::Bin/lib";
use BIGSdb::Constants qw(COUNTRIES);
use BIGSdbRestClient;
use JSON;
use constant REST_URL      => 'http://rest.pubmlst.org';
use constant BIGSDB_URL    => 'https://pubmlst.org/bigsdb';
use constant DBASE_CONFIGS => (
	{
		name           => 'Neisseria meningitidis',
		config         => 'pubmlst_neisseria_isolates',
		curated_config => 'pubmlst_neisseria_mrfgenomes'
	},
	{
		name           => 'Streptococcus pneumoniae',
		config         => 'pubmlst_spneumoniae_isolates',
		curated_config => 'pubmlst_spneumoniae_isolates_pgl'
	},
		{
		name           => 'Haemophilus influenzae',
		config         => 'pubmlst_hinfluenzae_isolates',
		curated_config => 'pubmlst_hinfluenzae_published_genomes'
	},
	{
		name           => 'Streptococcus agalactiae',
		config         => 'pubmlst_sagalactiae_isolates',
		curated_config => 'pubmlst_sagalactiae_published_genomes'
	},
);
my $client = BIGSdbRestClient->new(
	{
		rest_url   => REST_URL,
		bigsdb_url => BIGSDB_URL
	}
);
my $buffer = qq(set_name\tcountry\tiso3\tisolates\tgenomes\tcurated\n);
my $iso3   = COUNTRIES;
eval {
	foreach my $resource (DBASE_CONFIGS) {
		my $totals_uri   = REST_URL . qq(/db/$resource->{'config'}/fields/country/breakdown);
		my $totals_data  = $client->get_record($totals_uri);
		my $genomes_uri  = REST_URL . qq(/db/$resource->{'config'}/fields/country/breakdown?genomes=1);
		my $genomes_data = $client->get_record($genomes_uri);
		my $curated_uri  = REST_URL . qq(/db/$resource->{'curated_config'}/fields/country/breakdown);
		my $curated_data = $client->get_record($curated_uri);
		foreach my $country ( keys %$totals_data ) {
			$iso3->{$country}->{'iso3'} //= q();
			my $total   = $totals_data->{$country}  // 0;
			my $genomes = $genomes_data->{$country} // 0;
			my $curated = $curated_data->{$country} // 0;
			$buffer .= qq($resource->{'name'}\t$country\t$iso3->{$country}->{'iso3'}\t$total\t$genomes\t$curated\n);
		}
	}
};
if ($@) {
	die "$@\n";
}
say $buffer;
