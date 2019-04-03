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
	if (typeof url == 'undefined'){
		url = '/tmp/countries.tsv';
	}
	d3.tsv(url, function(d) {
		return d
	}, function(error, rows) {
		summary_data = embedMap.summarise(rows);
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
			'/d3-geomap/topojson/world/countries.json').colors(colours).column(
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
		red_purple: colorbrewer.RdPu[5],
		yellow_orange_brown: colorbrewer.YlOrBr[5]
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
		labels[this.iso3] = this.country + "\n" + embedMap.commify(this.isolates) + " isolate"
				+ plural + "\n" + this.label;
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
	var labels = [];
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
		if (typeof labels[this.iso3] == 'undefined') {
			labels[this.iso3] = [];
		}
		countries[this.iso3].isolates += +this.count;
		if (!set) {
			labels[this.iso3].push({
				set : this.set_name,
				isolates : this.count
			});
		}
		countries[this.iso3].name = this.country;
	});

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
				label += "\n" + sorted[i].set + ": " + embedMap.commify(sorted[i].isolates)
						+ " isolate" + plural;
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
