$(function() {
	read_data_and_create_charts();
	$('#state').on("change", function(){
		read_data_and_create_charts();
	});
});

function read_data_and_create_charts(){
	var period = $('#period').val();
	var state = $('#state').val();
	
	Papa.parse('/updates/' + state + '.tsv', {
		download : true,
		skipEmptyLines : true,
		complete : function(parsed) {
			create_charts(parsed.data.slice(0));
			$('#period').off("change").on("change", function() {
				create_charts(parsed.data.slice(0));
			});
		}
	})
}

function create_charts(data){
	var period = $('#period').val();
	var start_date = get_start_date();
	var list = get_ranked_sets(data, start_date, 5);

	var div = 0;
	$.each(list, function() {
		div++;

		var chart_data;
		if (period == 'past_month') {
			chart_data = get_daily_taxa_data(data, this,
					start_date);
		} else if (period == 'past_year') {
			chart_data = get_weekly_taxa_data(data, this,
					start_date);
		} else if (period == 'past_5_years') {
			chart_data = get_monthly_taxa_data(data, this,
					start_date);
		}
		load_chart_top_hit(this, div, chart_data);
	});
}

function get_start_date() {
	var period = $('#period').val();
	var start_time = new Date();
	if (period == 'past_month') {
		start_time.setDate(start_time.getDate() - 30);
	} else if (period == 'past_year') {
		start_time.setDate(start_time.getDate() - 365);
	} else if (period == 'past_5_years'){
		start_time.setDate(start_time.getDate() - 365*5);
	}
	return start_time.getFullYear() + "-"
			+ ("0" + (start_time.getMonth() + 1)).slice(-2) + "-"
			+ ("0" + start_time.getDate()).slice(-2);
}

function load_chart_top_hit(taxon, div, data) {
	var chart = c3.generate({
		bindto : '#c3_chart' + div,
		title : {
			text : taxon
		},
		data : {
			x : 'date',
			columns : [ [ 'date' ].concat(data.date),
					[ 'isolates' ].concat(data.isolates),
					[ 'genomes' ].concat(data.genomes),
					[ 'alleles' ].concat(data.sequences) ],
			type : 'bar',
			groups : [ [ 'isolates', 'genomes', 'alleles' ] ],
			colors : {
				isolates : '#4a4',
				genomes : '#a44',
				alleles : '#44a'
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
			right : 20
		},
		tooltip : {
			format : {
				value : function(value, ratio, id, index) {
					return value
				}
			}
		},
	});
	$("#c3_chart" + div + " .c3-title").css("font-weight", "600");
}

function get_daily_taxa_data(parsed_tsv, taxon, start_date) {
	var date = [];
	var last_date = new Date(start_date);
	var current_date = new Date();
	current_date.setHours(0, 0, 0, 0);
	var isolates = [];
	var genomes = [];
	var sequences = [];
	$.each(parsed_tsv, function() {

		if (this[1] != taxon) {
			return true;
		}
		if (this[0] >= start_date) {
			var this_date = new Date(this[0]);
			while (last_date < this_date) {
				date.push(last_date.getFullYear() + "-"
						+ ("0" + (last_date.getMonth() + 1)).slice(-2) + "-"
						+ ("0" + last_date.getDate()).slice(-2));
				isolates.push(0);
				genomes.push(0);
				sequences.push(0);
				last_date.setDate(last_date.getDate() + 1);
			}
			date.push(this[0]);
			isolates.push(+this[2]);
			genomes.push(+this[3]);
			sequences.push(+this[4]);
			last_date = new Date(this[0]);
			last_date.setDate(last_date.getDate() + 1);
		}
	});
	while (last_date <= current_date) {		
		date.push(last_date.getFullYear() + "-"
				+ ("0" + (last_date.getMonth() + 1)).slice(-2) + "-"
				+ ("0" + last_date.getDate()).slice(-2));
		isolates.push(0);
		genomes.push(0);
		sequences.push(0);
		last_date.setDate(last_date.getDate() + 1);
	}
	return {
		date : date,
		isolates : isolates,
		genomes : genomes,
		sequences : sequences
	};
}

function get_weekly_taxa_data(parsed_tsv, taxon, start_date) {
	var date = [];
	var last_date = new Date(start_date);
	var last_week = last_date.getWeek();
	var current_date = new Date();
	var current_week = current_date.getWeek();
	current_date.setHours(0, 0, 0, 0);
	var isolates = [];
	var genomes = [];
	var sequences = [];
	var this_week_genomes = 0;
	var this_week_isolates = 0;
	var this_week_sequences = 0;
	var this_week;
	$.each(parsed_tsv, function() {
		if (this[1] != taxon) {
			return true;
		}
		if (this[0] >= start_date) {
			var this_date = new Date(this[0]);
			this_week = this_date.getWeek();
			if (this_week > last_week) {
				date.push(last_week);
				isolates.push(this_week_isolates);
				genomes.push(this_week_genomes);
				sequences.push(this_week_sequences);
				this_week_isolates = 0;
				this_week_genomes = 0;
				this_week_sequences = 0;
				last_date.setDate(last_date.getDate() + 7);
				last_week = last_date.getWeek();
				while (this_week > last_week) {
					date.push(last_week);
					isolates.push(0);
					genomes.push(0);
					sequences.push(0);
					last_date.setDate(last_date.getDate() + 7);
					last_week = last_date.getWeek();
				}
			}
			if (this_week == last_week) {
				this_week_isolates += +this[2];
				this_week_genomes += +this[3];
				this_week_sequences += +this[4];
			}
		}
	});
	while (last_week <= current_week ) {
		date.push(last_week);
		isolates.push(this_week_isolates);
		genomes.push(this_week_genomes);
		sequences.push(this_week_sequences);
		this_week_isolates = 0;
		this_week_genomes = 0;
		this_week_sequences = 0;
		last_week = last_date.getWeek();
		last_date.setDate(last_date.getDate() + 7);
	}

	return {
		date : date,
		isolates : isolates,
		genomes : genomes,
		sequences : sequences
	};
}

function get_monthly_taxa_data(parsed_tsv, taxon, start_date) {
	var date = [];
	var last_date = new Date(start_date);
	var last_month = last_date.getMonthYear();
	var current_date = new Date();
	var current_month = current_date.getMonthYear();
	current_date.setHours(0, 0, 0, 0);
	var isolates = [];
	var genomes = [];
	var sequences = [];
	var this_month_genomes = 0;
	var this_month_isolates = 0;
	var this_month_sequences = 0;
	var this_month;
	$.each(parsed_tsv, function() {
		if (this[1] != taxon) {
			return true;
		}
		if (this[0] >= start_date) {
			var this_date = new Date(this[0]);
			this_month = this_date.getMonthYear();
			if (this_month > last_month) {
				date.push(last_month);
				isolates.push(this_month_isolates);
				genomes.push(this_month_genomes);
				sequences.push(this_month_sequences);
				this_month_isolates = 0;
				this_month_genomes = 0;
				this_month_sequences = 0;
				last_date.setMonth(last_date.getMonth() + 1);
				last_month = last_date.getMonthYear();
				while (this_month > last_month) {
					date.push(last_month);
					isolates.push(0);
					genomes.push(0);
					sequences.push(0);
					last_date.setMonth(last_date.getMonth() + 1);
					last_month = last_date.getMonthYear();
				}
			}
			if (this_month == last_month) {
				this_month_isolates += +this[2];
				this_month_genomes += +this[3];
				this_month_sequences += +this[4];
			}
		}
	});
	while (last_month <= current_month) {
		date.push(last_month);
		isolates.push(this_month_isolates);
		genomes.push(this_month_genomes);
		sequences.push(this_month_sequences);
		this_month_isolates = 0;
		this_month_genomes = 0;
		this_month_sequences = 0;
		last_date.setMonth(last_date.getMonth() + 1);
		last_month = last_date.getMonthYear();

	}

	return {
		date : date,
		isolates : isolates,
		genomes : genomes,
		sequences : sequences
	};
}

function get_ranked_sets(parsed_tsv, start_date, number) {
	var taxa = {};
	$.each(parsed_tsv, function() {

		if (this[0] == 'datestamp') {
			return true; // header row
		}
		if (this[0] >= start_date) {
			var row_total = +this[2] + +this[4];
			if (typeof taxa[this[1]] == 'undefined') {
				taxa[this[1]] = 0;
			}
			taxa[this[1]] += row_total;
		}
	});
	var i = 0;
	var list = [];
	$.each(sortPropertiesDesc(taxa), function() {
		i++;
		list.push(this[0]);
		if (i == number) {
			return false;
		}
	});
	return list;
}

function sortPropertiesDesc(obj) {
	var sortable = [];
	for ( var key in obj) {
		if (obj.hasOwnProperty(key)) {
			sortable.push([ key, obj[key] ]);
		}
	}
	sortable.sort(function(a, b) {
		return b[1] - a[1];
	});
	return sortable;
}

// function load_chart_cumulative(url, start_date) {
//
// Papa.parse(url, {
// download : true,
// skipEmptyLines : true,
// complete : function(parsed) {
// var date = [];
// var isolates = [];
// var current_date = '';
// var date_isolates = 0;
// $.each(parsed.data.slice(0), function() {
// if (this[0] == 'datestamp') {
// return false; // header row
// }
// if (this[0] >= start_date) {
// if (this[0] != current_date) {
// date.push(this[0]);
// current_date = this[0];
// if (date.length > 1) {
// isolates.push(date_isolates);
// }
// date_isolates = +this[2];
//
// } else {
// date_isolates += +this[2];
// }
// }
//
// });
// isolates.push(date_isolates);
// console.log(date);
// console.log(isolates);
// }
// });
// }

// Source: https://weeknumber.net/how-to/javascript
Date.prototype.getWeek = function() {
	var date = new Date(this.getTime());
	date.setHours(0, 0, 0, 0);
	// Thursday in current week decides the year.
	date.setDate(date.getDate() + 3 - (date.getDay() + 6) % 7);
	// January 4 is always in week 1.
	var week1 = new Date(date.getFullYear(), 0, 4);
	// Adjust to Thursday in week 1 and count number of weeks from date to
	// week1.
	return date.getWeekYear()
			+ "/w"
			+ ("0" + (1 + Math
					.round(((date.getTime() - week1.getTime()) / 86400000 - 3 + (week1
							.getDay() + 6) % 7) / 7))).slice(-2);
}

// Returns the four-digit year corresponding to the ISO week of the date.
Date.prototype.getWeekYear = function() {
	var date = new Date(this.getTime());
	date.setDate(date.getDate() + 3 - (date.getDay() + 6) % 7);
	return date.getFullYear();
}

Date.prototype.getMonthYear = function() {
	var date = new Date(this.getTime());
	return date.getFullYear() + "-" + ("0" + (date.getMonth() + 1)).slice(-2);
}
