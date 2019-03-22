var max_datapoints = 500;
$(function() {
	cumulativeApp.read_data_and_create_chart();
	$("#c3_link").show();
	$("#text_totals").show();
	cumulativeApp.position_elements();
	$(window).resize(function() {
		cumulativeApp.position_elements();
	});
});

var cumulativeApp = {};

cumulativeApp.position_elements = function() {
	if ($("#mainpanel").width() < 600) {
		$("div#c3_cumulative").css("width", "98%");
		$("h2#chart_title").css("font-size", "0.8em");
	} else {
		$("h2#chart_title").css("font-size", "1em");
	}
	var c3_width = $("div#c3_cumulative").width();
	$("div#c3_cumulative").css("height", parseInt(c3_width / 2) + "px");
	var totalHeight = $("#main_container")[0].scrollHeight;
	$("#mainpanel").css("height", totalHeight + 40 + "px");
}

cumulativeApp.commify = function(x) {
	return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

cumulativeApp.read_data_and_create_chart = function() {
	var url = $("#url").val();
	if (typeof url == 'undefined'){
		url = '/tmp/date_entered.tsv';
	}
	d3.tsv(url, function(d) {
		return d
	}, function(error, rows) {
		var cum_data = cumulativeApp.calc_cumulative(rows);
		cumulativeApp.create_chart(cum_data);
		
	});
}

cumulativeApp.get_datestamp = function(date_string) {
	var date = new Date(date_string);
	return date.getFullYear() + "-" + ("0" + (date.getMonth() + 1)).slice(-2)
			+ "-" + ("0" + date.getDate()).slice(-2);
}

cumulativeApp.get_date_period = function(data) {
	var today = new Date();
	var today_datestamp = cumulativeApp.get_datestamp(today);
	var max = today_datestamp;
	var min;
	if ($("#min_date").val()) {
		min = cumulativeApp.get_datestamp($("#min_date").val());
	} else {
		min = today_datestamp;
		$.each(data, function() {
			if (this.datestamp == 'datestamp') {
				return true;
			}
			if (this.datestamp < min) {
				min = this.datestamp;
			}
		});
	}
	return {
		min : min,
		max : max
	};
}

cumulativeApp.create_chart = function(cum_data) {
	var title = $("#set").val() ? 'Cumulative submissions to the '
			+ $("#set").val() + ' database'
			: 'Cumulative submissions to PubMLST';

	var c3_div = $("#c3_div") ? "#" + $("#c3_div").val() : "#c3_cumulative";

	var no_genomes = $("#no_genomes").val();
	var no_isolates = $("#no_isolates").val();
	var show_alleles = $("#alleles").val();
	var hide = [];
	if (no_genomes) {
		hide.push('isolates (no genome)', 'isolates (with genome)');
	} else if (no_isolates) {
		hide.push('isolates (no genome)', 'isolates (with genome)', 'isolates');
	} else {
		hide.push('isolates');
	}
	if (!show_alleles) {
		hide.push('alleles');
	}
	var columns = [ [ 'date' ].concat(cum_data.dates) ];
	if (!hide.includes('isolates (no genome)')) {
		columns.push([ 'isolates (no genome)' ]
				.concat(cum_data.isolates_no_genome));
	}
	if (!hide.includes('isolates (with genome)')) {
		columns.push([ 'isolates (with genome)' ]
				.concat(cum_data.isolates_with_genome))
	}
	if (!hide.includes('isolates')) {
		columns.push([ 'isolates' ].concat(cum_data.isolates))
	}
	if (!hide.includes('alleles')) {
		columns.push([ 'alleles' ].concat(cum_data.alleles))
	}

	var chart = c3.generate({
		bindto : c3_div,
		data : {
			x : 'date',
			columns : columns,
			type : 'area-step',
			groups : [ [ 'isolates (no genome)', 'isolates (with genome)',
					'isolates', 'alleles' ] ],
			colors : {
				'isolates (no genome)' : '#8fb3e3',
				'isolates (with genome)' : '#173753',
				'isolates' : '#8fb3e3',
				'alleles' : '#c4666d'
			},
			order : null
		},
		bar : {
			width : {
				ratio : 1
			}
		},
		axis : {
			x : {
				type : 'timeseries',
				tick : {
					rotate : 0,
					multiline : false,
					count : 2,
					format : '%Y-%m-%d'
				},
			},
		},
		legend : {
			show : true
		},
		padding : {
			right : 30
		},
		tooltip : {
			format : {
				value : function(value, ratio, id, index) {
					return value
				}
			}
		},
		onrendered : function() { // after chart is rendered
			cumulativeApp.position_elements();
		}
	});
	$("h2#chart_title").html(title);
	if ($("#hide").val()){
		chart.hide($("#hide").val());
	}
}

cumulativeApp.calc_cumulative = function(data) {
	var range = cumulativeApp.get_date_period(data);
	var date = [];
	var running_no_genome = 0;
	var running_with_genome = 0;
	var running_isolates = 0;
	var running_alleles = 0;
	var isolates_no_genome = [];
	var isolates_with_genome = [];
	var isolates = []
	var alleles = [];
	var last_date = cumulativeApp.get_datestamp(range.min);
	var min_date = last_date;
	var max_date = cumulativeApp.get_datestamp(range.max);
	var set = $("#set").val();
//	console.log(data);
	$.each(data, function() {
//		if (this[0] == 'datestamp') {
//			return true;
//		}
		if (set && this.set_name != set) {
			return true;
		}
		var this_date = this.datestamp;
		if (this_date < min_date) {
			running_no_genome += +this.isolates - +this.genomes;
			running_with_genome += +this.genomes;
			running_isolates += +this.isolates;
			running_alleles += +this.sequences
			return true;
		}
		if (this_date != last_date) {
			date.push(last_date);
			isolates_no_genome.push(running_no_genome);
			isolates_with_genome.push(running_with_genome);
			alleles.push(running_alleles);
			last_date = this_date;
		}
		if (this_date <= max_date) {
			running_no_genome += +this.isolates - +this.genomes;
			running_with_genome += +this.genomes;
			running_isolates += +this.isolates;
			running_alleles += +this.sequences
		} else {
			return false;
		}

	});

	if (last_date != date[date.length - 1]) {
		date.push(last_date);
		isolates_no_genome.push(running_no_genome);
		isolates_with_genome.push(running_with_genome);
		isolates.push(running_isolates);
		alleles.push(running_alleles);
	}
	return {
		dates : cumulativeApp.downsample(date, max_datapoints),
		isolates_no_genome : cumulativeApp.downsample(isolates_no_genome,
				max_datapoints),
		isolates_with_genome : cumulativeApp.downsample(isolates_with_genome,
				max_datapoints),
		isolates : cumulativeApp.downsample(isolates, max_datapoints),
		alleles : cumulativeApp.downsample(alleles, max_datapoints),
	};
}

cumulativeApp.downsample = function(data, max_points) {
	var total_points = data.length;
	var gap = total_points / max_points;
	if (gap <= 1) {
		return data;
	}
	var downsample = [];
	var j = 0;
	$.each(data, function(i, value) {
		if (i == 0 || i == (total_points - 1)) {
			downsample.push(value);
		} else {
			j++;
			if (j >= gap) {
				downsample.push(value);
				j = 0;
			}
		}
	});
	return downsample;
}
