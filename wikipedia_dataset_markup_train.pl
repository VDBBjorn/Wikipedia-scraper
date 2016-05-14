use strict;
use warnings;
use feature qw(say);
use Data::Dumper;               # Perl core module
use List::Util 'shuffle';
use File::Copy;
$|=1;

my $folder = "./output-wiki-hoofd";
my $output = "./output-wiki-hoofd-train";
mkdir($output);

my $num_picks = 1000;

opendir(my $DIR, $folder) or die $!;
while (my $cat = readdir($DIR)) {
	next unless (-d "$folder/$cat");
	next if ($cat =~ m/^\./);
	mkdir("$output/$cat");
	say $cat;
	my @deck = ();
	opendir(my $CAT, "$folder/$cat");
	while(my $file = readdir($CAT)) {
		next unless(-f "$folder/$cat/$file");
		push @deck, "$file";
	}
	closedir($CAT);
	my @shuffled_indexes = shuffle(0..$#deck);
	if($#shuffled_indexes < $num_picks) {
		$num_picks = $#shuffled_indexes;
	}
	my @pick_indexes = @shuffled_indexes[ 0 .. $num_picks-1 ]; 
	my @picks = @deck[ @pick_indexes ];
	for my $pick (@picks) {	
		copy("$folder/$cat/$pick","$output/$cat/$pick") or die "Copy failed: $!";
	}
}	

closedir($DIR);


