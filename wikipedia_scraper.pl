use LWP::Simple;                # From CPAN
use JSON qw( decode_json );     # From CPAN
use HTML::Restrict;				# From CPAN
use open qw/:std :utf8/;
use feature qw(say);
use Data::Dumper;               # Perl core module
use strict;                     # Good practice
use warnings;                   # Good practice
use utf8;
use threads;
use Thread::Queue;	
use Storable;
use List::MoreUtils qw(uniq);
use Term::ProgressBar;
use utf8;
 use HTML::Entities;

no warnings 'recursion';

$|=1;

my $limit = 10;
my $hr = HTML::Restrict->new();
my $thread_limit = 10;

sub decode_json_string {
	my ($url) = shift;
	return eval {
		#say $url;
		my $json = get($url);
		#say $json;
		decode_json($json);
	};
}

sub check_dissambiguation {
	my $decoded_json = shift;
	for my $prop (@{$decoded_json->{'parse'}->{'properties'}}) {
		if($prop->{'name'} eq "disambiguation") {
			return 1;
		}
	}
	return 0;
}

sub parse_text {
	my ($text, $content) = @_;	
	decode_entities($$text);
	utf8::decode($$text);
	my @body = ($$text =~ m/<p>(.*?)<\/p>|\<li>(.*?)<\/li>|<h[1-9]>(.*?)<\/h[1-9]>/g);
	$$content = join("\n", map { defined $_ ? $_ : '' } @body);
	$$content = $hr->process($$content);
	$$content =~ s/\[bewerken\]//g;
}

sub test {
	my $decoded_json = decode_json_string("https://nl.wikipedia.org/w/api.php?format=json&action=parse&pageid="."1"."&utf8=1");
	if(defined $decoded_json) {
		my $title = $decoded_json->{'parse'}->{'title'};
		my $text;
		my $content = $decoded_json->{'parse'}->{'text'}->{'*'};
		parse_text(\$content,\$text);
		say $title;
		say $text;
	}
}

sub get_page_ids {
	my ($top_cat,$sub_cat,$search,$level) = @_;	
	if($level>50) {	#protection for infinite recursion
		return;
	}
	my $pages_url = "https://nl.wikipedia.org/w/api.php?action=query&format=json&prop=&list=categorymembers&utf8=1&cmtitle=".$search."&cmprop=ids&cmtype=page&cmlimit=".$limit;
	my $decoded_json = decode_json_string($pages_url);
	if($decoded_json) {
		for my $page (@{$decoded_json->{'query'}->{'categorymembers'}}) {
			download_page($page->{'pageid'}, "output_direct", $top_cat, $sub_cat);
		}
	}
	undef $decoded_json;
	my $cat_url = "https://nl.wikipedia.org/w/api.php?action=query&format=json&prop=&list=categorymembers&utf8=1&cmtitle=".$search."&cmprop=ids%7Ctitle&cmtype=subcat&cmlimit=".$limit;		
	$decoded_json = decode_json_string($cat_url);
	if($decoded_json) {
		for my $cat (@{$decoded_json->{'query'}->{'categorymembers'}}) {
			if(defined $cat->{'title'}) {
				get_page_ids($top_cat,$sub_cat,$cat->{'title'},$level+1);
			}
		}
	}
}

sub download_page { 
	my ($page, $folder_name, $top_cat, $sub_cat) = @_;
	#say "$page\t$folder_name\t$top_cat\t$sub_cat";
	my $top_title = substr($top_cat,rindex($top_cat,':')+1);
	my $sub_title = substr($sub_cat,rindex($sub_cat,':')+1);
	mkdir($folder_name);
	mkdir($folder_name."/".$top_title);
	mkdir($folder_name."/".$top_title."/".$sub_title);
	my $decoded_json = decode_json_string("https://nl.wikipedia.org/w/api.php?format=json&action=parse&pageid=".$page."&utf8=1&prop=text%7Cproperties");
	if(defined $decoded_json && defined $decoded_json->{'parse'}->{'title'} && defined $decoded_json->{'parse'}->{'text'}->{'*'}) {
		if(!check_dissambiguation($decoded_json)) {
			my $title = $decoded_json->{'parse'}->{'title'};
			$title =~ s/[\/]//g;
			$title =~ tr/:/-/;
			$title =~ tr/.//;
			$title =~ tr/,/ /;
			decode_entities($title);
			utf8::decode($title);
			my $text;
			parse_text(\$decoded_json->{'parse'}->{'text'}->{'*'},\$text);
			my $path =  $folder_name."/".$top_title."/".$sub_title."/".$title.".txt";
			# say $path;
			open(my $fh, '>', $path);
			binmode($fh, ":utf8");
			print $fh $text;
			close $fh;
			say $path;
		}
		else {
			say $page."\tis a reference page";
		}
	}
	else {
		say $page."\thas an undefined title or text";
		say Dumper $decoded_json;
		say $decoded_json->{'parse'}->{'title'};
		say $decoded_json->{'parse'}->{'text'}->{'*'}
	}	
}

sub write_to_folder {
	my ($hash, $folder_name) = @_;
	my $q = Thread::Queue->new();
	my $thr = threads->create(
        sub {
            # Thread will loop until no more work
            while (defined(my $item = $q->dequeue())) {
                download_page(@{$item});
            }
        }
    );
	mkdir($folder_name);
	for my $key (keys %{$hash}) {
		say $key;
		my $top_cat = substr($key,rindex($key,':')+1);
		mkdir($folder_name."/".$top_cat);
		for my $sub_key (keys %{$hash->{$key}}) {
			say $sub_key;
			my $sub_cat = substr($sub_key,rindex($sub_key,':')+1);
			mkdir($folder_name."/".$top_cat."/".$sub_cat);
			for my $page (uniq @{$hash->{$key}->{$sub_key}}) {
				my @arr = ($page, $folder_name, $top_cat, $sub_cat);
				$q->enqueue(\@arr);
			}

		}
	}
	my @thr = map {
		threads->create(
			sub {
				while (defined(my $item = $q->dequeue_nb())) {
					download_page(@{$item});
			    }
		    }
		);
	} 1..10;
	$_->join() for @thr;
}

sub get_top_cats {
	my $top_cat_url = "https://nl.wikipedia.org/w/api.php?action=query&format=json&list=categorymembers&cmtitle=Categorie%3AAlles&cmtype=subcat&cmlimit=".$limit;
	my $json = get( $top_cat_url );
	my $decoded_json = decode_json( $json );
	return @{$decoded_json->{'query'}->{'categorymembers'}};
}

sub process_category {
	my ($top_title, $sub_cats) = @_;	
	my $q = Thread::Queue->new();
	for my $sub_cat (@{$sub_cats}) {
		my $sub_title = $sub_cat->{'title'};
		decode_entities($sub_title);
		utf8::decode($sub_title);
		my @arr = ($top_title, $sub_title,$sub_title,0);
		$q->enqueue(\@arr);
		# get_page_ids($top_title,$sub_title,$sub_title,0);	
	}
	my @thr = map {
		threads->create(
			sub {
				while (defined(my $item = $q->dequeue_nb())) {
					get_page_ids(@{$item});
			    }
		    }
		);
	} 1..10;
	$_->join() for @thr;
	# store $hash, "wiki-hash-$top_title";
	# write_to_folder($hash,"output");
}

sub main {
	my @top_cats = get_top_cats();
	my $q = Thread::Queue->new();
	for my $top_cat (@top_cats) {
		#say $top_cat->{'title'};
			if($top_cat->{title} eq "Categorie:Natuur" ||$top_cat->{title} eq "Categorie:Mens en maatschappij") {
			my $sub_cat_url = "https://nl.wikipedia.org/w/api.php?action=query&format=json&list=categorymembers&cmtitle=".$top_cat->{'title'}."&cmtype=subcat&cmlimit=500";#.$limit;
			my $decoded_json = decode_json_string($sub_cat_url);
			my $top_title = $top_cat->{'title'};
			if($top_title eq "Categorie:Wikipedia" | $top_title eq "Categorie:Lijsten") { next; }
			decode_entities($top_title);
			utf8::decode($top_title);
			my @sub_cats = @{$decoded_json->{'query'}->{'categorymembers'}};
			my @arr = ($top_title, \@sub_cats);
			$q->enqueue(\@arr);
		}
	}
	my @thr = map {
		threads->create(
			sub {
				while (defined(my $item = $q->dequeue_nb())) {
					process_category(@{$item});
			    }
		    }
		);
	} 1..10;
	$_->join() for @thr;
	#$hashref = retrieve('file');
	#write_to_folder($hash,"output");
	# sleep 1 while threads->list(threads::running) > 0;
}

sub read_and_write {
	my $hash = retrieve('my-hash-wiki');
	print Dumper %{$hash};
	write_to_folder($hash,"output");
	sleep 1 while threads->list(threads::running) > 0;
}

main();

# my $pages = ();

# for my $top_cat (keys %{$hash}) {
# 	for my $cat (keys %{$hash->{$top_cat}}) {
# 		say $cat;
# 		#push @{$hash->{$top_cat}->{$cat}}, "bjorn";
# 	}
# }


# my $hash;
# my $baseurl = "https://nl.wikipedia.org/w/api.php?format=json&action=parse&prop=text%7Ccategories%7Cdisplaytitle&pageid=";
# my $hr = HTML::Restrict->new();

# my @headcats = qw/ Cultuur Geschiedenis Heelal Lijsten Mens en maatschappij Natuur Persoon Religie Techniek Wetenschap Wikipedia/;

# for(my $i=1;$i<10;$i++) {
# 	my $json = get( $baseurl.$i );
# 	die "Could not get url: ".$baseurl.$i unless defined $json;

# 	my $decoded_json = decode_json( $json );
# 	if(defined $decoded_json->{'error'}) {
# 		next;
# 	}

# 	my $title = $decoded_json->{'parse'}->{'displaytitle'};
# 	my $html = $decoded_json->{'parse'}->{'text'}->{'*'};

# 	my @body = ($html =~ m/<p>(.*)<\/p>|<h[1-9]>(.*)<\/h[1-9]>|<ul>(.*)<\/ul>/g);
# 	#print join("\n",@body);
# 	my $content = join("\n", map { defined $_ ? $_ : '' } @body);
# 	utf8::decode($content);
# 	$content = $hr->process($content);
# 	$content =~ s/\[bewerken\]//g;
# 	#print $content;

# 	my $categories = $decoded_json->{'parse'}->{'categories'};
# 	for my $cat (@{$categories}) {
# 		if(!defined $cat->{'hidden'}) {
# 			#say $cat->{'*'};
# 			push @{$hash->{$cat->{'*'}}}, $title."\n".$content;
# 		}
		
# 	}
# }

# print Dumper $hash;

# print "Shares: ",join(",",
#       @{$decoded_json->{'query'}{'allcategories'}),
#       "\n