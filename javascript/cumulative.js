$(function() {

	read_data_and_create_chart();
	position_elements();
	$(window).resize(function (){
		position_elements();
		
	
	});
});

function read_data_and_create_chart() {

	Papa.parse('/tmp/date_entered.tsv', {
		download : true,
		skipEmptyLines : true,
		complete : function(parsed) {
			var period = get_date_period(parsed.data.slice(0));
			$('#date_slider').dateRangeSlider({
				bounds : {
					min : new Date(period.start),
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
			$("#taxa_list").off("change").change(function(){
				create_chart(parsed.data.slice(0));
			});
			create_chart(parsed.data.slice(0));

		}
	})
}

function taxa_selector(data){
	var taxa = [];
	var seen = [];
	$.each(data, function() {
		if (seen[this[1]] || this[1] == 'set_name'){
			return true;
		}
		taxa.push(this[1]);
		seen[this[1]]=1;
	});
	taxa.sort();
	$("#taxa_list_div").append("<select id='taxa_list' size='15' multiple='multiple' style='width:200px'></select>");
	var container = $("#taxa_list");
	$.each(taxa, function() {
		   container.append("<option selected='selected'>" + this + "</option>");
	});
}

function position_elements(){
	if ($(window).width()>1000){
		$("#date_slider").css({width: ($(window).width()-300) + "px"});
		$("#taxa").css({float:"right"});
		$("#taxa_list").css({width:"200px"});
		$("#c3_chart").css({float:"left",width: ($(window).width()-280) + "px"});
	} else {
		$("#date_slider").css({width:"90%"});
		$("#taxa").css({float:"none"});
		$("#taxa_list").css({width:"auto"});
		$("#c3_chart").css({float:"none",width:"100%"});		
	}	
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
	var taxa = $("#taxa_list").val();
	var is_selected=[];
	$.each(taxa, function() {
		is_selected[this] = 1;
	});
	var date = [];
	var i_no_genome = 0;
	var i_with_genome = 0;
	var isolates_no_genome = [];
	var isolates_with_genome = [];
	var last_date = get_datestamp(range.min);
	var min_date = last_date;
	var max_date = get_datestamp(range.max);
	$.each(data, function() {
		if (this[0] == 'datestamp' || !is_selected[this[1]]) {
			return true;
		}
		var this_date = this[0];
		if (this_date < min_date) {
			i_no_genome += +this[2] - +this[3];
			i_with_genome += +this[3];
			return true;
		}
		if (this_date != last_date) {
			date.push(last_date);
			isolates_no_genome.push(i_no_genome);
			isolates_with_genome.push(i_with_genome);
			last_date = this_date;
		}
		if (this_date <= max_date) {
			i_no_genome += +this[2] - +this[3];
			i_with_genome += +this[3];
		} else {
			return false;
		}

	});
	if (last_date != date[date.length - 1]) {
		date.push(last_date);
		isolates_no_genome.push(i_no_genome);
		isolates_with_genome.push(i_with_genome);
	}
	// console.log("Isolates with no genome:" + i_no_genome);
	// console.log("Isolates with genome:" + i_with_genome);
	//
	// console.log(date);
	// console.log(isolates_no_genome);
	// console.log(isolates_with_genome);

	return {
		dates : downsample(date, 500),
		isolates_no_genome : downsample(isolates_no_genome, 500),
		isolates_with_genome : downsample(isolates_with_genome, 500)
	};
}

function downsample(data, max_points) {
	var total_points = data.length;
	var gap = total_points / max_points;
	if (gap <= 1) {
		return data;
	}
	var downsample = [];
	var i = 0;
	var j = 0;
	$.each(data, function() {
		if (i == 0 || i == (total_points - 1)) {
			downsample.push(this);
		} else {

			j++;
			if (j >= gap) {
				downsample.push(this);
				j = 0;
			}

		}
		i++;
	});
	return downsample;
}

function create_chart(data) {
	var range = $('#date_slider').dateRangeSlider("values");
	var cum_data = calc_cumulative(data, range);
	var chart = c3.generate({
		bindto : '#c3_chart',
		data : {
			x : 'date',
			columns : [
					[ 'date' ].concat(cum_data.dates),
					[ 'isolates (no genome)' ]
							.concat(cum_data.isolates_no_genome),
					[ 'isolates (with genome)' ]
							.concat(cum_data.isolates_with_genome), ],
			type : 'bar',
			groups : [ [ 'isolates (no genome)', 'isolates (with genome)' ] ],
			colors : {
				'isolates (no genome)' : '#8fb3e3',
				'isolates (with genome)' : '#173753',
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
				type : 'category',
				tick : {
					culling : true,
					rotate : 0,
					multiline : false,
					count : 2
				},
			}
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
	});
}