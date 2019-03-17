$(function() {
	Papa.parse('/tmp/date_entered.tsv', {
		download : true,
		skipEmptyLines : true,
		complete : function(parsed) {
			var summary = summarise(parsed.data.slice(0));
			console.log(summary);
			$("dd#isolates").html(commify(summary.isolates));
			$("dd#genomes").html(commify(summary.genomes));
			$("dd#alleles").html(commify(summary.alleles));
			$("dl#overview_stats").show();
		}
	})
});

function summarise(data){
	var set = $("#set").val();
	var isolates = 0;
	var genomes = 0;
	var alleles = 0;
	$.each(data, function() {
		if (this[0] == 'datestamp' || (set && this[1] != set)) {
			return true;
		}
		isolates += +this[2];
		genomes += +this[3];
		alleles += +this[4];
	});
	return {
		isolates: isolates,
		genomes: genomes,
		alleles: alleles
	};
}

function commify(x) {
    return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}