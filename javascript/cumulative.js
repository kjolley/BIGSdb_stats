var max_datapoints = 500;
var export_text = '';
$(function() {

	read_data_and_create_chart();
	position_elements();
	$(window).resize(function() {
		position_elements();
	});
	$("#export_image")
			.off("click")
			.click(
					function() {
						// fix back fill
						d3.select("#c3_chart").selectAll("path").attr("fill",
								"none");
						// fix no axes
						d3.select("#c3_chart").selectAll("path.domain").attr(
								"stroke", "black");
						// fix no tick
						d3.select("#c3_chart").selectAll(".tick line").attr(
								"stroke", "black");
						d3.select("#c3_chart").selectAll(".c3-axis-y2").attr(
								"display", "none");
						// Annoying 2nd x-axis
						// Hide both, then selectively show the first one.
						d3.select("#c3_chart").selectAll(".c3-axis-x").attr(
								"display", "none");
						d3.select("#c3_chart").select(".c3-axis-x").attr(
								"display", "inline");
						var svg = d3.select("svg").attr("xmlns",
								"http://www.w3.org/2000/svg").node().parentNode.innerHTML;
						svg = svg.replace(/<\/svg>.*$/, "</svg>");
						var blob = new Blob([ svg ], {
							type : "image/svg+xml"
						});
						var filename = "cumulative.svg";
						saveAs(blob, filename);
					});
	$("#export_text").off("click").click(function() {

		var blob = new Blob([ export_text ], {
			type : "text/plain;charset=utf-8"
		})
		var filename = "cumulative.tsv";
		saveAs(blob, filename);
	});
});

function read_data_and_create_chart() {
	$("#export").css
	var min_date = $.urlParam('min_date');
	Papa.parse('/tmp/date_entered.tsv', {
		download : true,
		skipEmptyLines : true,
		complete : function(parsed) {
			var period = get_date_period(parsed.data.slice(0));
			$('#date_slider').dateRangeSlider(
					{
						bounds : {
							min : min_date ? new Date(min_date) : new Date(
									period.start),
							max : new Date()
						},
						defaultValues : {
							min : new Date(period.start),
							max : new Date()
						}
					});

			$("#date_slider").bind("valuesChanged", function(e, data) {
				create_chart(parsed.data.slice(0));
			});

			taxa_selector(parsed.data.slice(0));
			$("#taxa_list").off("change").change(function() {
				create_chart(parsed.data.slice(0));
			});
			create_chart(parsed.data.slice(0));
		}
	})
}

function taxa_selector(data) {
	var taxa = [];
	var seen = [];
	$.each(data, function() {
		if (seen[this[1]] || this[1] == 'set_name') {
			return true;
		}
		if (+this[2] > 0 || +this[3] > 0) {
			taxa.push(this[1]);
			seen[this[1]] = 1;
		}
	});
	var set = $.urlParam('set');
	taxa.sort();

	var container = $("#taxa_list");
	$.each(taxa, function() {
		var selection = (set && this != set) ? '' : " selected='selected'";
		container.append("<option" + selection + ">" + this + "</option>");
	});

	$("#taxa_list").multiselect().multiselectfilter();
	$(".ui-multiselect-menu.ui-widget.ui-widget-content").css({
		"display" : "none"
	});
	if (!set) {
		$("#taxa").css({
			"display" : "block"
		});
	}
	$("#export").show();
}

function position_elements() {
	$("#date_slider").css({
		width : $(window).width() - 120 + "px"
	});
	$("#c3_chart").css({
		width : "95%"
	});

}

function get_datestamp(date) {
	return date.getFullYear() + "-" + ("0" + (date.getMonth() + 1)).slice(-2)
			+ "-" + ("0" + date.getDate()).slice(-2);
}

function get_date_period(data) {
	var today = new Date();
	var today_datestamp = get_datestamp(today);
	var min = today_datestamp;
	var max = today_datestamp;
	$.each(data, function() {
		if (this[0] == 'datestamp') {
			return true;
		}
		if (this[0] < min) {
			min = this[0];
		}
		if (this[0] > max) {
			max = this[0];
		}
	});
	return {
		start : min,
		end : max
	};
}

function calc_cumulative(data, range) {
	export_text = "datestamp\tisolates\tisolates_no_genome\tisolates_with_genome\talleles\n";
	var taxa = $("#taxa_list").val();
	if (!taxa) {
		taxa = [];
	}
	var is_selected = [];
	$.each(taxa, function() {
		is_selected[this] = 1;
	});
	var date = [];
	var running_no_genome = 0;
	var running_with_genome = 0;
	var running_isolates = 0;
	var running_alleles = 0;
	var isolates = [];
	var isolates_no_genome = [];
	var isolates_with_genome = [];
	var alleles = []
	var last_date = get_datestamp(range.min);
	var min_date = last_date;
	var max_date = get_datestamp(range.max);
	$.each(data, function() {
		if (this[0] == 'datestamp' || !is_selected[this[1]]) {
			return true;
		}
		var this_date = this[0];
		if (this_date < min_date) {
			running_no_genome += +this[2] - +this[3];
			running_with_genome += +this[3];
			running_isolates += +this[2];
			running_alleles += +this[4];
			return true;
		}
		if (this_date != last_date) {
			date.push(last_date);
			isolates_no_genome.push(running_no_genome);
			isolates_with_genome.push(running_with_genome);
			isolates.push(running_isolates)
			alleles.push(running_alleles);
			export_text += last_date + "\t" + running_isolates + "\t"
					+ running_no_genome + "\t" + running_with_genome + "\t"
					+ running_alleles + "\n";
			last_date = this_date;
		}
		if (this_date <= max_date) {
			running_no_genome += +this[2] - +this[3];
			running_with_genome += +this[3];
			running_isolates += +this[2];
			running_alleles += +this[4];
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
		export_text += last_date + "\t" + running_isolates + "\t"
		+ running_no_genome + "\t" + running_with_genome + "\t"
		+ running_alleles + "\n";
	}

	return {
		dates : downsample(date, max_datapoints),
		isolates_no_genome : downsample(isolates_no_genome, max_datapoints),
		isolates_with_genome : downsample(isolates_with_genome, max_datapoints),
		isolates : downsample(isolates, max_datapoints),
		alleles : downsample(alleles, max_datapoints)
	};
}

function downsample(data, max_points) {
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

function create_chart(data) {

	var title;
	var taxa = $("#taxa_list").val();
	if (taxa && taxa.length == 1) {
		title = taxa[0];
	}
	var range = $('#date_slider').dateRangeSlider("values");
	var cum_data = calc_cumulative(data, range);
	var no_genomes = $.urlParam('no_genomes');
	var no_isolates = $.urlParam('no_isolates')
	var show_alleles = $.urlParam('alleles');
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
		bindto : '#c3_chart',
		title : {
			text : title
		},
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
			order : null,
			hide : hide,
		},
		legend : {
			show : true,
			hide : hide,
			item : {
				onclick : (hide.length == 3) ? function() {
				} : null
			}
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
			}
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
	});
}

$.urlParam = function(name) {
	var results = new RegExp('[\?&]' + name + '=([^&#]*)')
			.exec(window.location.href);
	if (results == null) {
		return null;
	}
	return decodeURI(results[1]) || 0;
}
