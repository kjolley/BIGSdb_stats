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
	// $("#text_totals").show();
	$(window).resize(function() {
		delay(function() {
			var new_width = $("div#map").width();
			// Stop firing on scroll in Android
			if (new_width != window_width) {
				embedMap.draw_map();
				window_width = new_width;
			}
			
		}, 500);
		embedMap.position_notes();
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
		$("h2#map_title").css("font-size", "1.2em");
	}

	delay(function() {
		var totalHeight = $("#main_container").scrollHeight;
		$("#mainpanel").css("height", (totalHeight + 40) + "px");
	}, 500);
}

embedMap.position_notes = function() {
	if ($("#mainpanel").width() < 760) {
		$("div.notes").css("width", ($("#mainpanel").width() - 20) + "px");
	} else if ($("#mainpanel").width() < 1030) {
		$("div.notes").css("width", "510px");
	} else {
		$("div.notes").css("width", ($("#mainpanel").width() - 20) + "px");	
	}
}

embedMap.read_data_and_create_chart = function() {
	var url = $("#url").val();
	if (typeof url == 'undefined') {
		url = '/tmp/gmgl_countries.tsv';
	}
	d3.tsv(url).then(function(data) {
		summary_data = embedMap.summarise(data);
		embedMap.draw_map();
		embedMap.update_totals(data);
	});
}

embedMap.draw_map = function() {
	var max = $("#max").val();
	if (typeof max == 'undefined') {
		max = 5000;
	}
	var colours = embedMap.get_colours();
	$('#map').html('');
	map = d3.geomap.choropleth().geofile('/javascript/topojson/countries.json')
			.colors(colours).column('isolates').format(d3.format(",d")).legend(
					{
						width : 50,
						height : 120
					}).projection(d3.geoNaturalEarth).duration(1000).domain(
					[ 0, max ]).valueScale(d3.scaleQuantize).unitId('iso3')
			.postUpdate(embedMap.finishedDrawing);
	var selection = d3.select('#map').datum(summary_data);

	map.draw(selection);
}

embedMap.get_colours = function() {
	var colours = $("#colours").val();
	var range = {
		purple : colorbrewer.Purples[5],
		orange : colorbrewer.Oranges[5],
		green : colorbrewer.Greens[5],
		red : colorbrewer.Reds[5],
		orange_red : colorbrewer.OrRd[5],
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
	var title = "Source of isolates";
	$("h2#map_title").html(title);
}

embedMap.finishedDrawing = function() {
	var labels = [];
	var country_name = [];
	var isolates = [];
	var set_map = {
		'Neisseria meningitidis' : 'neisseria',
		'Streptococcus pneumoniae' : 'spneumoniae',
		'Streptococcus agalactiae' : 'sagalactiae',
		'Haemophilus influenzae' : 'hinfluenzae'
	};
	var config = {
			'Neisseria meningitidis' : 'pubmlst_neisseria_mrfgenomes',
			'Streptococcus pneumoniae' : 'pubmlst_spneumoniae_isolates_pgl',
			'Streptococcus agalactiae' : 'pubmlst_sagalactiae_published_genomes',
			'Haemophilus influenzae' : 'pubmlst_hinfluenzae_published_genomes'
	};
	var sets = [];
	$.each(summary_data, function() {
		var plural = this.isolates == 1 ? '' : 's';
		labels[this.iso3] = this.country + "\n"
		country_name[this.iso3] = this.country;
		isolates[this.iso3] = this.isolates;
		sets[this.iso3] = this.sets;
	});

	var svg = d3.select("#map svg");
	svg.selectAll("path.unit").each(function(d, i) {
		var iso3 = this['__data__'].properties.iso3;
//		d3.select(this).select('title').text(labels[iso3]);
		d3.select(this).select('title').text("");
		if (isolates[iso3]) {
			d3.select(this).select('title').text(labels[iso3]);
			var mouse_monitor;
			d3.select(this).on("mouseover", function(d) {
				mouse_monitor = setTimeout(function() {
					$("div#link_panel").show();
					$("dd#country").html(country_name[iso3]);
					$("dd#total").html(embedMap.commify(isolates[iso3]));
					for (var key in set_map){
						if (typeof sets[iso3][key] == 'undefined'){
							sets[iso3][key] = 0;
							$("dd#" + set_map[key]).html("0");
						} else if (sets[iso3][key] == 0){
							$("dd#" + set_map[key]).html("0");
						} else {
							$("dd#" + set_map[key]).html('<a href="/bigsdb?db=' + config[key] + 
							'&page=query&prov_field1=f_country&prov_value1=' + country_name[iso3] + '&submit=1">' + 
							embedMap.commify(sets[iso3][key]) + '</a>');
						}
					}
					embedMap.position_elements();
				}, 200);
			});
			d3.select(this).on("mouseout", function(d) {
				clearTimeout(mouse_monitor);
			});
		}
	});
	embedMap.add_title();
	$("#map_link").show();
	embedMap.position_elements();
}

embedMap.summarise = function(data) {
	var countries = [];
	var sets = [];
	$.each(data, function() {
		if (!this.iso3) {
			return true;
		}
		if (this.curated == 0){
			return true;
		}
		if (typeof countries[this.iso3] == 'undefined') {
			countries[this.iso3] = {
				isolates : 0,
				label : ''
			};
		}
		countries[this.iso3].isolates += +this.curated;
		countries[this.iso3].name = this.country;
		if (typeof sets[this.iso3] == 'undefined') {
			sets[this.iso3] = [];
		}
		if (typeof this.curated != 'undefined'){
			if (typeof sets[this.iso3][this.set_name] == 'undefined'){
				sets[this.iso3][this.set_name] = 0;
			}
			sets[this.iso3][this.set_name] += parseInt(this.curated);
		}
	});

	var list = [];
	for ( var country in countries) {
		list.push({
			country : countries[country].name,
			iso3 : country,
			isolates : countries[country].isolates,
			sets: sets[country]
		});
	}
	console.log(list);
	return list;
}

embedMap.update_totals = function(data){
	var nm = {isolates:0, genomes:0, curated:0};
	var sp = {isolates:0, genomes:0, curated:0};
	var sa = {isolates:0, genomes:0, curated:0};
	var hi = {isolates:0, genomes:0, curated:0};
	$.each(data, function() {
		if (this.set_name == 'Neisseria meningitidis'){
			nm.isolates += parseInt(this.isolates);
			nm.genomes += parseInt(this.genomes);
			nm.curated += parseInt(this.curated);
		} else if (this.set_name == 'Streptococcus pneumoniae'){
			sp.isolates += parseInt(this.isolates);
			sp.genomes += parseInt(this.genomes);
			sp.curated += parseInt(this.curated);
		} else if (this.set_name == 'Streptococcus agalactiae'){
			sa.isolates += parseInt(this.isolates);
			sa.genomes += parseInt(this.genomes);
			sa.curated += parseInt(this.curated);
		} else if (this.set_name == 'Haemophilus influenzae'){
			hi.isolates += parseInt(this.isolates);
			hi.genomes += parseInt(this.genomes);
			hi.curated += parseInt(this.curated);
		}
	});
	$("#nm_isolates").html('<a href="/bigsdb?db=pubmlst_neisseria_isolates&page=query&submit=1">' 
			+ embedMap.commify(nm.isolates) + '</a>');
	$("#nm_genomes").html('<a href="/bigsdb?db=pubmlst_neisseria_isolates&page=query&linked_sequences_list=Any%20sequence%20data&submit=1">' 
			+ embedMap.commify(nm.genomes) + '</a>');
	$("#nm_curated").html('<a href="/bigsdb?db=pubmlst_neisseria_mrfgenomes&page=query&submit=1">' 
			+ embedMap.commify(nm.curated) + '</a>');
	$("#sp_isolates").html('<a href="/bigsdb?db=pubmlst_spneumoniae_isolates&page=query&submit=1">' 
			+ embedMap.commify(sp.isolates) + '</a>');
	$("#sp_genomes").html('<a href="/bigsdb?db=pubmlst_spneumoniae_isolates&page=query&linked_sequences_list=Any%20sequence%20data&submit=1">' 
			+ embedMap.commify(sp.genomes) + '</a>');
	$("#sp_curated").html('<a href="/bigsdb?db=pubmlst_spneumoniae_isolates_pgl&page=query&submit=1">' 
			+ embedMap.commify(sp.curated) + '</a>');	
	$("#hi_isolates").html('<a href="/bigsdb?db=pubmlst_hinfluenzae_isolates&page=query&submit=1">' 
			+ embedMap.commify(hi.isolates) + '</a>');
	$("#hi_genomes").html('<a href="/bigsdb?db=pubmlst_hinfluenzae_isolates&page=query&linked_sequences_list=Any%20sequence%20data&submit=1">' 
			+ embedMap.commify(hi.genomes) + '</a>');
	$("#hi_curated").html('<a href="/bigsdb?db=pubmlst_hinfluenzae_published_genomes&page=query&submit=1">' 
			+ embedMap.commify(hi.curated) + '</a>');
	$("#sa_isolates").html('<a href="/bigsdb?db=pubmlst_sagalactiae_isolates&page=query&submit=1">' 
			+ embedMap.commify(sa.isolates) + '</a>');
	$("#sa_genomes").html('<a href="/bigsdb?db=pubmlst_sagalactiae_isolates&page=query&linked_sequences_list=Any%20sequence%20data&submit=1">' 
			+ embedMap.commify(sa.genomes) + '</a>');
	$("#sa_curated").html('<a href="/bigsdb?db=pubmlst_sagalactiae_published_genomes&page=query&submit=1">' 
			+ embedMap.commify(sa.curated) + '</a>');
} 

embedMap.sort_by_value = function(a, b) {
	return ((+a.isolates < +b.isolates) ? 1 : ((+a.isolates > +b.isolates) ? -1
			: 0));
}

embedMap.commify = function(x) {
	return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

