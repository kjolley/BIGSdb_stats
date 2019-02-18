$(function() {
	var start_date = '2019-01-17';
	Papa.parse('/updates/date.tsv', {
		download : true,
		skipEmptyLines : true,
		complete : function(parsed) {
			var list = get_ranked_sets(parsed.data.slice(0), start_date, 5);

			var div = 0;
			$.each(list,
					function() {
						div++;
						var data = get_taxa_data(parsed.data.slice(0), this,
								start_date);
						console.log(data);
						load_chart_top_hit(this, div, data);

					});
		}
	})

});

function load_chart_top_hit(taxon, div, data) {
	console.log('#c3_chart' + div);
	var chart = c3.generate({
		bindto : '#c3_chart' + div,
		title : {
			text : taxon
		},
		data : {
			x : 'date',
			xFormat : '%Y-%m-%d',
			columns : [ [ 'date' ].concat(data.date),
					[ 'isolates' ].concat(data.isolates),
					[ 'genomes'].concat(data.genomes) ,
					[ 'alleles' ].concat(data.sequences)],
					
			type : 'bar',
			groups : [ [ 'isolates', 'genomes','alleles' ] ],
			colors: {
				isolates: '#4a4',
				genomes: '#a44',
				alleles: '#44a'
			}
		},

		axis : {
			x : {
				type : 'category',
				tick: {
					culling: true,
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
		onrendered: function(){
			d3.selectAll(".c3-axis.c3-axis-x .tick text").style("display","none");
		}
	});
	$(".c3-title").css("font-weight", "600");
	
}

function get_taxa_data(parsed_tsv, taxon, start_date) {
	var date = [];
	var last_date = new Date(start_date);
	var current_date = new Date();
	var isolates = [];
	var genomes = [];
	var sequences = [];
	$.each(parsed_tsv, function() {

		if (this[1] != taxon) {
			return true;
		}
		if (this[0] >= start_date) {
			var this_date = new Date(this[0]);
			last_date.setDate(last_date.getDate() + 1);
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
		}
	});
	while (last_date <= current_date) {
		last_date.setDate(last_date.getDate() + 1);
		date.push(last_date.getFullYear() + "-"
				+ ("0" + (last_date.getMonth() + 1)).slice(-2) + "-"
				+ ("0" + last_date.getDate()).slice(-2));

		isolates.push(0);
		genomes.push(0);
		sequences.push(0);
		
	}
	return {
		date : date,
		isolates : isolates,
		genomes: genomes,
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

//function load_chart_cumulative(url, start_date) {
//
//	Papa.parse(url, {
//		download : true,
//		skipEmptyLines : true,
//		complete : function(parsed) {
//			var date = [];
//			var isolates = [];
//			var current_date = '';
//			var date_isolates = 0;
//			$.each(parsed.data.slice(0), function() {
//				if (this[0] == 'datestamp') {
//					return false; // header row
//				}
//				if (this[0] >= start_date) {
//					if (this[0] != current_date) {
//						date.push(this[0]);
//						current_date = this[0];
//						if (date.length > 1) {
//							isolates.push(date_isolates);
//						}
//						date_isolates = +this[2];
//
//					} else {
//						date_isolates += +this[2];
//					}
//				}
//
//			});
//			isolates.push(date_isolates);
//			console.log(date);
//			console.log(isolates);
//		}
//	});
//}
