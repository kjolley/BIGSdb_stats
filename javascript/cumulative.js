$(function() {

	read_data_and_create_chart();
	position_elements();
	$(window).resize(function (){
		position_elements();
	});
	$("#export_image").off("click").click(function(){
		// fix back fill
		d3.select("#c3_chart").selectAll("path").attr("fill","none");
		// fix no axes
		d3.select("#c3_chart").selectAll("path.domain").attr("stroke","black");
		// fix no tick
		d3.select("#c3_chart").selectAll(".tick line").attr("stroke","black");
		d3.select("#c3_chart").selectAll(".c3-axis-y2").attr("display","none");
		// Annoying 2nd x-axis
		// Hide both, then selectively show the first one.
		d3.select("#c3_chart").selectAll(".c3-axis-x").attr("display","none");
		d3.select("#c3_chart").select(".c3-axis-x").attr("display","inline");
		var svg = d3.select("svg")
			.attr("xmlns","http://www.w3.org/2000/svg")
			.node().parentNode.innerHTML;
		svg = svg.replace(/<\/svg>.*$/,"</svg>");
		var blob = new Blob([svg],{type: "image/svg+xml"});		
		var filename = "cumulative.svg";
		saveAs(blob, filename);
	});
});

function read_data_and_create_chart() {$("#export").css
	var min_date = $.urlParam('min_date');
	Papa.parse('/tmp/date_entered.tsv', {
		download : true,
		skipEmptyLines : true,
		complete : function(parsed) {
			var period = get_date_period(parsed.data.slice(0));
			$('#date_slider').dateRangeSlider({
				bounds : {
					min : min_date ? new Date(min_date) : new Date(period.start),
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
		if (+this[2] > 0 || +this[3] > 0){
			taxa.push(this[1]);
			seen[this[1]]=1;
		}
	});
	var set = $.urlParam('set');
	taxa.sort();

	
	$("#taxa_list_div").append(
		"<select id='taxa_list' size='15' multiple='multiple' style='width:200px'></select>"
	);
	var container = $("#taxa_list");
	$.each(taxa, function() {
		var selection = (set && this != set) ? '' :  " selected='selected'";
	   container.append("<option" + selection + ">" + this + "</option>");
	});
	$("#taxa_list").SumoSelect({
		okCancelInMulti: true, 
		selectAll:true, 
		forceCustomRendering: true,
		captionFormatAllSelected:'{0} - All selected'
	});
	if (!set){
		$("#taxa").css({"display":"block"});
	}
	$("#export").show();
}

function position_elements(){
	var set = $.urlParam('set');
	if ($(window).width()>1000){
		if (set){
			$("#date_slider").css({width: ($(window).width()-120) + "px"});
			$("#c3_chart").css({float:"left",width: ($(window).width()-50) + "px"});
			$("#export").css({"float":"left"});
		} else {
			$("#date_slider").css({width: ($(window).width()-300) + "px"});
			$("#c3_chart").css({float:"left",width: ($(window).width()-280) + "px"});
			$("#export").css({"float":"right","margin-top":"1em", "margin-right":"0"});
		}
		$("#mainpanel").css({"min-height":"600px"});
	} else {
		$("#date_slider").css({width:"85%"});
		$("#taxa").css({float:"left"});
		$("#c3_chart").css({float:"none",width:"100%"});	
		if (!set){
			$("#export").css({float:"left", margin:"2em"});
			$("#mainpanel").css({"min-height":"950px"});
		}
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
	if (!taxa){
		taxa = [];
	}
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
	if (taxa && taxa.length == 1){
		title = taxa[0];
	}
	var range = $('#date_slider').dateRangeSlider("values");
	var cum_data = calc_cumulative(data, range);
	var chart = c3.generate({
		bindto : '#c3_chart',
		title: {
			text: title
		},
		data : {
			x : 'date',
			columns : [
					[ 'date' ].concat(cum_data.dates),
					[ 'isolates (no genome)' ]
							.concat(cum_data.isolates_no_genome),
					[ 'isolates (with genome)' ]
							.concat(cum_data.isolates_with_genome) ],
			type : 'area-step',
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
				type : 'timeseries',
				tick : {
					rotate : 0,
					multiline : false,
					count : 2,
					format: '%Y-%m-%d'
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

$.urlParam = function(name){
    var results = new RegExp('[\?&]' + name + '=([^&#]*)').exec(window.location.href);
    if (results==null) {
       return null;
    }
    return decodeURI(results[1]) || 0;
}
