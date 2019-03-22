#!/usr/bin/env perl
#Extract country information for D3 rendering from a database config
#Written by Keith Jolley
#Copyright (c) 2019, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
#BIGSdb is free software: you can redistribute it and/or modify
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
#
#Version: 20190303
use strict;
use warnings;
use 5.010;
###########Local configuration#############################################
use constant {
	CONFIG_DIR       => '/etc/bigsdb',
	LIB_DIR          => '/usr/local/lib',
	DBASE_CONFIG_DIR => '/etc/bigsdb/dbases',
	HOST             => undef,                  #Use values in config.xml
	PORT             => undef,                  #But you can override here.
	USER             => undef,
	PASSWORD         => undef
};
#######End Local configuration#############################################
use lib (LIB_DIR);
use BIGSdb::Offline::Script;
use Getopt::Long qw(:config no_ignore_case);
use Term::Cap;
my %opts;
GetOptions(
	'database=s' => \$opts{'d'},
	'set_name=s' => \$opts{'set_name'},
	'help'       => \$opts{'h'},
) or die("Error in command line arguments\n");
if ( $opts{'h'} ) {
	show_help();
	exit;
}
if ( !$opts{'d'} ) {
	say "\nUsage: country_extract.pl --database <NAME>\n";
	say 'Help: country_extract.pl --help';
	exit;
}
my $script = BIGSdb::Offline::Script->new(
	{
		config_dir       => CONFIG_DIR,
		lib_dir          => LIB_DIR,
		dbase_config_dir => DBASE_CONFIG_DIR,
		host             => HOST,
		port             => PORT,
		user             => USER,
		password         => PASSWORD,
		options          => \%opts,
		instance         => $opts{'d'},
	}
);
die "Script initialization failed - check logs (authentication problems or server too busy?).\n"
  if !defined $script->{'db'};
die "This script can only be run against an isolate database.\n"
  if ( $script->{'system'}->{'dbtype'} // '' ) ne 'isolates';
main();
undef $script;

sub main {
	my $iso3 = get_iso3();
	my $data =
	  $script->{'datastore'}
	  ->run_query( "SELECT country,COUNT(*) AS count FROM $script->{'system'}->{'view'} GROUP BY country",
		undef, { fetch => 'all_arrayref', slice => {} } );
	if ( $opts{'set_name'} ) {
		print qq(set_name\t);
	}
	say qq(country\tiso3\tcount);
	foreach my $record (@$data) {
		if ( $opts{'set_name'} ) {
			print qq($opts{'set_name'}\t);
			my $code = $iso3->{ $record->{'country'} } // q();
			say qq($record->{'country'}\t$code\t$record->{'count'});
		}
	}
	return;
}

sub show_help {
	my $termios = POSIX::Termios->new;
	$termios->getattr;
	my $ospeed = $termios->getospeed;
	my $t = Tgetent Term::Cap { TERM => undef, OSPEED => $ospeed };
	my ( $norm, $bold, $under ) = map { $t->Tputs( $_, 1 ) } qw(me md us);
	say << "HELP";
${bold}NAME$norm
    ${bold}country_extract.pl$norm - Extract country information for D3 rendering from a database config

${bold}SYNOPSIS$norm
    ${bold}country_extract.pl --database ${under}NAME$norm${bold}$norm [${under}options$norm]

${bold}OPTIONS$norm

${bold}--database$norm ${under}NAME$norm
    Database configuration name.
    
${bold}--set_name$norm ${under}set_name$norm
    Comma-separated list of loci to exclude
    
${bold}--help$norm
    This help page.
    
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
		q(Tunisia)                                           => q(TUN),
		q(Turkey)                                            => q(TUR),
		q(Turkmenistan)                                      => q(TKM),
		q(Turks and Caicos Islands)                          => q(TCA),
		q(Tuvalu)                                            => q(TUV),
		q(Uganda)                                            => q(UGA),
		q(Ukraine)                                           => q(UKR),
		q(United Arab Emirates)                              => q(ARE),
		q(UK)                                                => q(GBR),
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
