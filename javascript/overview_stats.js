$(function() {
	$.ajax({
		url : '/tmp/date_entered.tsv',
		success : function(data) {
			var summary = overviewApp.summarise(data);
			$("dd#isolates").html(overviewApp.commify(summary.isolates));
			$("dd#genomes").html(overviewApp.commify(summary.genomes));
			$("dd#alleles").html(overviewApp.commify(summary.alleles));
			$("dd#profiles").html(overviewApp.commify(summary.profiles));
			$("dl#overview_stats").show();
		}
	})
});

var overviewApp = {};

overviewApp.summarise = function(data) {
	var set = $("#set").val();
	var isolates = 0;
	var genomes = 0;
	var alleles = 0;
	var profiles = 0;
	var lines = data.split(/\n/);
	$.each(lines, function() {
		if (this == ''){
			return true;
		}
		var cols = this.split(/\t/);
		if (cols[0] == 'datestamp' || (set && cols[1] != set)) {
			return true;
		}
		isolates += +cols[2];
		genomes += +cols[3];
		alleles += +cols[4];
		profiles += +cols[5];
	});
	return {
		isolates : isolates,
		genomes : genomes,
		alleles : alleles,
		profiles : profiles
	};
}

overviewApp.commify = function(x) {
	return x.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}
