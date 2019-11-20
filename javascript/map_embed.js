var isolates;
var genomes;
var alleles;
var map;
var summary_data;
var max_label = 10;
var window_width = $("div#map").width();

var embedMap = {};

$(function() {
	embedMap.read_data_and_create_chart();
	$("#text_totals").show();
	$(window).resize(function() {
		delay(function() {
			var new_width = $("div#map").width();
			// Stop firing on scroll in Android
			if (new_width != window_width) {
				embedMap.draw_map();
				window_width = new_width;
			}
		}, 500);
	});
});

var delay = (function() {
	var timer = 0;
	return function(callback, ms) {
		clearTimeout(timer);
		timer = setTimeout(callback, ms);
	};
})();

embedMap.position_elements = function() {
	if ($("#mainpanel").width() < 600) {
		$("h2#map_title").css("font-size", "0.8em");
	} else {
		$("h2#map_title").css("font-size", "1em");
	}
	delay(function() {
		var totalHeight = $("#main_container")[0].scrollHeight;
		$("#mainpanel").css("height", totalHeight + 40 + "px");
	}, 500);
}

embedMap.read_data_and_create_chart = function() {
	var url = $("#url").val();
	if (typeof url == 'undefined') {
		url = '/tmp/countries.tsv';
	}
	d3.tsv(url).then(function(data) {
		summary_data = embedMap.summarise(data);
		embedMap.draw_map();
	});
}

embedMap.draw_map = function() {
	var max = $("#max").val();
	if (typeof max == 'undefined') {
		max = 5000;
	}
	var colours = embedMap.get_colours();
	$('#map').html('');
	map = d3.geomap.choropleth().geofile(
			'/javascript/topojson/countries.json').colors(colours).column(
			'isolates').format(d3.format(",d")).legend({
		width : 50,
		height : 120
	}).projection(d3.geoNaturalEarth).duration(1000).domain([ 0, max ])
			.valueScale(d3.scaleQuantize).unitId('iso3').postUpdate(
					embedMap.finishedDrawing);
	var selection = d3.select('#map').datum(summary_data);

	map.draw(selection);
}

embedMap.get_colours = function() {
	var colours = $("#colours").val();
	var range = {
		purple : colorbrewer.Purples[5],
		orange : colorbrewer.Oranges[5],
		green : colorbrewer.Greens[5],
		red_purple : colorbrewer.RdPu[5],
		yellow_orange_brown : colorbrewer.YlOrBr[5]
	};
	if (typeof colours == 'undefined') {
		return colorbrewer.Blues[5];
	}
	if (range[colours]) {
		return range[colours];
	}
	return colorbrewer.Blues[5];
}

embedMap.add_title = function() {
	var set = $("#set").val();
	var title = set ? "Source of isolates submitted to the " + set
			+ " database" : "Source of isolates submitted to PubMLST";
	$("h2#map_title").html(title);
}

embedMap.finishedDrawing = function() {
	var labels = [];
	$.each(summary_data, function() {
		var plural = this.isolates == 1 ? '' : 's';
		labels[this.iso3] = this.country + "\n"
				+ embedMap.commify(this.isolates) + " isolate" + plural + "\n"
				+ this.label;
	});

	var svg = d3.select("#map svg");
	svg.selectAll("path.unit").each(function(d, i) {
		var iso3 = this['__data__'].properties.iso3;
		d3.select(this).select('title').text(labels[iso3]);
	});
	embedMap.add_title();
	$("#map_link").show();
	embedMap.position_elements();
}

embedMap.summarise = function(data) {
	var countries = [];

	var set = $("#set").val();
	var counts = [];
	var iso3_countries = embedMap.getISO3();
	$.each(data, function() {
		if (set && this.set_name != set) {
			return true;
		}
		if (!this.iso3) {
			return true;
		}
		if (typeof countries[this.iso3] == 'undefined') {
			countries[this.iso3] = {
				isolates : 0,
				label : ''
			};
		}
		if (typeof counts[this.iso3] == 'undefined') {
			counts[this.iso3] = {};
		}
		countries[this.iso3].isolates += +this.count;
		if (!set) {
			if (typeof counts[this.iso3][this.set_name] == 'undefined') {
				counts[this.iso3][this.set_name] = 0;
			}
			counts[this.iso3][this.set_name] += parseInt(this.count);
		}
		countries[this.iso3].name = iso3_countries[this.iso3];
		if (typeof countries[this.iso3].name == 'undefined'){
			countries[this.iso3].name = this.country;
		}		
	});
	var labels = [];
	for (var country in counts){
		var sets = Object.keys(counts[country]);
		for (var i = 0; i < sets.length; i++){
			if (typeof labels[country] == 'undefined'){
				labels[country] = [];
			}
			
			labels[country].push({
				set : sets[i],
				isolates : counts[country][sets[i]]
			});
		}
	}

	var sorted_labels = [];
	for ( var country in labels) {
		var sorted = labels[country].sort(embedMap.sort_by_value);
		if (sorted.length > max_label) {
			sorted = sorted.slice(0, max_label);
			sorted.push({
				set : '...'
			});
		}
		var label = '';
		for (var i = 0; i < sorted.length; i++) {
			if (sorted[i].set == '...') {
				label += "\n" + "...";
			} else {
				var plural = sorted[i].isolates == 1 ? '' : 's';
				label += "\n" + sorted[i].set + ": "
						+ embedMap.commify(sorted[i].isolates) + " isolate"
						+ plural;
			}
		}
		sorted_labels[country] = label;
	}

	var list = [];
	for ( var country in countries) {
		list.push({
			country : countries[country].name,
			iso3 : country,
			isolates : countries[country].isolates,
			label : sorted_labels[country]
		});
	}
	return list;
}

embedMap.sort_by_value = function(a, b) {
	return ((+a.isolates < +b.isolates) ? 1 : ((+a.isolates > +b.isolates) ? -1
			: 0));
}

embedMap.commify = function(x) {
	return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

embedMap.getISO3 = function() {
	return {
		AFG: "Afghanistan",
		ALA: "Åland Islands",
		ALB: "Albania",
		DZA: "Algeria",
		ASM: "American Samoa",
		AND: "Andorra",
		AGO: "Angola",
		AIA: "Anguilla",
		ATG: "Antigua and Barbuda",
		ARG: "Argentina",
		ARM: "Armenia",
		ABW: "Aruba",
		AUS: "Australia",
		AUT: "Austria",
		AZE: "Azerbaijan",
		BHS: "Bahamas",
		BHR: "Bahrain",
		BGD: "Bangladesh",
		BRB: "Barbados",
		BLR: "Belarus",
		BEL: "Belgium",
		BLZ: "Belize",
		BEN: "Benin",
		BMU: "Bermuda",
		BTN: "Bhutan",
		BOL: "Bolivia",
		BIH: "Bosnia and Herzegovina",
		BWA: "Botswana",
		BRA: "Brazil",
		VGB: "British Virgin Islands",
		BRN: "Brunei Darussalam",
		BGR: "Bulgaria",
		BFA: "Burkina Faso",
		BDI: "Burundi",
		KHM: "Cambodia",
		CMR: "Cameroon",
		CAN: "Canada",
		CPV: "Cape Verde",
		CYM: "Cayman Islands",
		CAF: "Central African Republic",
		TCD: "Chad",
		CHL: "Chile",
		CHN: "China",
		HKG: "Hong Kong Special Administrative Region of China",
		MAC: "Macao Special Administrative Region of China",
		COL: "Colombia",
		COM: "Comoros",
		COG: "Congo",
		COK: "Cook Islands",
		CRI: "Costa Rica",
		CIV: "Côte d'Ivoire",
		HRV: "Croatia",
		CUB: "Cuba",
		CYP: "Cyprus",
		CZE: "Czech Republic",
		PRK: "Democratic People's Republic of Korea",
		COD: "Democratic Republic of the Congo",
		DNK: "Denmark",
		DJI: "Djibouti",
		DMA: "Dominica",
		DOM: "Dominican Republic",
		ECU: "Ecuador",
		EGY: "Egypt",
		SLV: "El Salvador",
		GNQ: "Equatorial Guinea",
		ERI: "Eritrea",
		EST: "Estonia",
		ETH: "Ethiopia",
		FRO: "Faeroe Islands",
		FLK: "Falkland Islands (Malvinas)",
		FJI: "Fiji",
		FIN: "Finland",
		FRA: "France",
		GUF: "French Guiana",
		PYF: "French Polynesia",
		GAB: "Gabon",
		GMB: "Gambia",
		GEO: "Georgia",
		DEU: "Germany",
		GHA: "Ghana",
		GIB: "Gibraltar",
		GRC: "Greece",
		GRL: "Greenland",
		GRD: "Grenada",
		GLP: "Guadeloupe",
		GUM: "Guam",
		GTM: "Guatemala",
		GGY: "Guernsey",
		GIN: "Guinea",
		GNB: "Guinea-Bissau",
		GUY: "Guyana",
		HTI: "Haiti",
		VAT: "Holy See",
		HND: "Honduras",
		HUN: "Hungary",
		ISL: "Iceland",
		IND: "India",
		IDN: "Indonesia",
		IRN: "Iran, Islamic Republic of",
		IRQ: "Iraq",
		IRL: "Ireland",
		IMN: "Isle of Man",
		ISR: "Israel",
		ITA: "Italy",
		JAM: "Jamaica",
		JPN: "Japan",
		JEY: "Jersey",
		JOR: "Jordan",
		KAZ: "Kazakhstan",
		KEN: "Kenya",
		KIR: "Kiribati",
		KWT: "Kuwait",
		KGZ: "Kyrgyzstan",
		LAO: "Lao People's Democratic Republic",
		LVA: "Latvia",
		LBN: "Lebanon",
		LSO: "Lesotho",
		LBR: "Liberia",
		LBY: "Libyan Arab Jamahiriya",
		LIE: "Liechtenstein",
		LTU: "Lithuania",
		LUX: "Luxembourg",
		MDG: "Madagascar",
		MWI: "Malawi",
		MYS: "Malaysia",
		MDV: "Maldives",
		MLI: "Mali",
		MLT: "Malta",
		MHL: "Marshall Islands",
		MTQ: "Martinique",
		MRT: "Mauritania",
		MUS: "Mauritius",
		MYT: "Mayotte",
		MEX: "Mexico",
		FSM: "Micronesia, Federated States of",
		MDA: "Moldova",
		MCO: "Monaco",
		MNG: "Mongolia",
		MNE: "Montenegro",
		MSR: "Montserrat",
		MAR: "Morocco",
		MOZ: "Mozambique",
		MMR: "Myanmar",
		NAM: "Namibia",
		NRU: "Nauru",
		NPL: "Nepal",
		NLD: "Netherlands",
		ANT: "Netherlands Antilles",
		NCL: "New Caledonia",
		NZL: "New Zealand",
		NIC: "Nicaragua",
		NER: "Niger",
		NGA: "Nigeria",
		NIU: "Niue",
		NFK: "Norfolk Island",
		MNP: "Northern Mariana Islands",
		NOR: "Norway",
		PSE: "Occupied Palestinian Territory",
		OMN: "Oman",
		PAK: "Pakistan",
		PLW: "Palau",
		PAN: "Panama",
		PNG: "Papua New Guinea",
		PRY: "Paraguay",
		PER: "Peru",
		PHL: "Philippines",
		PCN: "Pitcairn",
		POL: "Poland",
		PRT: "Portugal",
		PRI: "Puerto Rico",
		QAT: "Qatar",
		KOR: "Republic of Korea",
		REU: "R_union",
		ROU: "Romania",
		RUS: "Russian Federation",
		RWA: "Rwanda",
		BLM: "Saint-Barthélemy",
		SHN: "Saint Helena",
		KNA: "Saint Kitts and Nevis",
		LCA: "Saint Lucia",
		MAF: "Saint-Martin (French part)",
		SPM: "Saint Pierre and Miquelon",
		VCT: "Saint Vincent and the Grenadines",
		WSM: "Samoa",
		SMR: "San Marino",
		STP: "Sao Tome and Principe",
		SAU: "Saudi Arabia",
		SEN: "Senegal",
		SRB: "Serbia",
		SYC: "Seychelles",
		SLE: "Sierra Leone",
		SGP: "Singapore",
		SVK: "Slovakia",
		SVN: "Slovenia",
		SLB: "Solomon Islands",
		SOM: "Somalia",
		ZAF: "South Africa",
		ESP: "Spain",
		LKA: "Sri Lanka",
		SDN: "Sudan",
		SUR: "Suriname",
		SJM: "Svalbard and Jan Mayen Islands",
		SWZ: "Swaziland",
		SWE: "Sweden",
		CHE: "Switzerland",
		SYR: "Syrian Arab Republic",
		TJK: "Tajikistan",
		THA: "Thailand",
		MKD: "The former Yugoslav Republic of Macedonia",
		TLS: "Timor-Leste",
		TGO: "Togo",
		TKL: "Tokelau",
		TON: "Tonga",
		TTO: "Trinidad and Tobago",
		TUN: "Tunisia",
		TUR: "Turkey",
		TKM: "Turkmenistan",
		TCA: "Turks and Caicos Islands",
		TUV: "Tuvalu",
		UGA: "Uganda",
		UKR: "Ukraine",
		ARE: "United Arab Emirates",
		GBR: "UK",
		TZA: "United Republic of Tanzania",
		USA: "USA",
		VIR: "US Virgin Islands",
		URY: "Uruguay",
		UZB: "Uzbekistan",
		VUT: "Vanuatu",
		VEN: "Venezuela (Bolivarian Republic of)",
		VNM: "Viet Nam",
		WLF: "Wallis and Futuna Islands",
		ESH: "Western Sahara",
		YEM: "Yemen",
		ZMB: "Zambia",
		ZWE: "Zimbabwe",
	};
}
