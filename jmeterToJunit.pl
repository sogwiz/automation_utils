use Getopt::Long;
use Time::localtime;
use Time::Local;
use XML::Generator ':noimport';

#### vars

my @data;
my $lineNum = 0;
my @cols;
my @orderedcols;
my $buildTime;
my $buildTimestamp;
my $gateway;

my @files = ();

my $DEBUG = 1;

my %entire = ();
my %glabels = ();
my %gthreads = ();
my $atflag = 0; # if active threads found then according graphs will be created


my $collectinterval = 180;    # 60 seconds
#---
# cusps aggregate response times
#---
our @cusps = (200, 500, 1000, 2000, 5000, 10000, 60000);

#---
# labels determine the name of output charts
#---
our @labels = ();
our @threads = ();

#---
# intermediate values
#---
our %timestamps = ();
our $respcount = 0;
our $measures = 0;

my ($entireta,$entirecnt,$entireby);
my ($respcount,$sumresptimes,$sumSQresptimes); 

my $generator = XML::Generator->new(':pretty');

  my @test_cases     = ();
    my $total_tests    = 0;
    my $total_time     = 0;
    my $total_failures = 0;

####


$result = GetOptions ("file=s"   => \$file,      # string   
		"reportfile=s"	=> \$reportfile, #string
		"jtl" => \$jtl,	#flag
		"dashboard" => \$dashboard, #flag
		"buildurl=s" => \$buildUrl, #string
		"buildnumber=s" => \$buildNumber, #string
		"outdir=s" => \$outDir, #string
		"gateway=s" => \$gateway, #string
		"verbose"  => \$verbose);  # flag

usage("--file <FILE_NAME> must be specified\n")
   if !defined($file);


#if this is a jtl report file
if($jtl) {
	push(@files, $file);
	
	
		while(my $file = shift(@files)) {
	  print "Opening file $file\n" if $DEBUG;
	  open(IN, "<$file") || do  {
		print $file, " ", $!, "\n";
		next;
	  };

	  print "Parsing data from $file\n" if $DEBUG;
	  while(<IN>) {
		my ($time,$timestamp,$success,$label,$thread,$latency,$bytes,$DataEncoding,$DataType,$ErrorCount,$Hostname,$NumberOfActiveThreadsAll,$NumberOfActiveThreadsGroup,$ResponseCode,$ResponseMessage,$SampleCount);
		if(/^<(sample|httpSample)\s/) {


		  ($time) = (/\st="(\d+)"/o);
		  ($timestamp) = (/\sts="(\d+)"/o);
		  ($success) = (/\ss="(.+?)"/o);
		  ($label) = (/\slb="(.+?)"/o);
		  ($thread) = (/\stn="(.+?)"/o);
		  ($latency) = (/\slt="(\d+)"/o);
		  ($bytes) = (/\sby="(\d+)"/o);
		  ($DataEncoding) = (/\sde="(\d+)"/o);
		  ($DataType) = (/\sdt="(.+?)"/o);
		  ($ErrorCount) = (/\sec="(\d+)"/o);
		  ($Hostname) = (/\shn="(.+?)"/o);
		  ($NumberOfActiveThreadsAll) = (/\sna="(\d+)"/o);
		  ($NumberOfActiveThreadsGroup) = (/\sng="(\d+)"/o);
		  ($ResponseCode) = (/\src="(.+?)"/o);
		  ($ResponseMessage) = (/\srm="(.+?)"/o);
		  ($SampleCount) = (/\ssc="(\d+)"/o);
		  
		  
		  $total_tests++;
		  	$convertedTime = ($time/1000.0);
			$total_time += $convertedTime;
			
			
		  my $test_case;
		  
		  if($success eq "true"){
		  	$test_case = {
                classname => ($label),
                name      => ($label),
                'time'    => $convertedTime,
            };
            push @test_cases, $generator->testcase($test_case);
		  }
		  else { 
		  	$total_failures++;
		  	
		  	$failMessage = {
		  		message => ($ResponseMessage)
		  	};
		  	
		  	@failMessages = ();
		  	
		  	push @failMessages, $failMessage;
		  	
		  	$test_case = {
                classname => ($label),
                name      => ($label),
                'time'    => $convertedTime,
                
            };
            
            $element_failure = $generator->failure(
            {message => ($ResponseMessage),
            },
            );
            
            $element = $generator->testcase($test_case,$element_failure);
            
            #push @test_cases, $generator->testcase($test_case);
		  	push @test_cases, $element;
		  		
		  }

		  	
            

		} elsif(/^<sampleResult/) {
		  ($time) = (/\stime="(\d+)"/o);
		  ($timestamp) = (/timeStamp="(\d+)"/o);
		  ($success) = (/success="(.+?)"/o);
		  ($label) = (/label="(.+?)"/o);
		  ($thread) = (/threadName="(.+?)"/o);
		} else {
		  next;
		}

 $test_results = {
        total_time     => $total_time,
        test_cases     => \@test_cases,
        total_tests    => $total_tests,
        total_failures => $total_failures,
    };

		$label =~ s/\s+$//g;
		$label =~ s/^\s+//g;
		$label =~ s/[\W\s]+/_/g;

		next if($label =~ /^garbage/i); # don't count these labels into statistics

		#---
		# memorize labels
		#---
			  if(!grep(/^$label$/, @labels)) {
		  push(@labels, $label);
		  print "Found new label: $label\n" if $DEBUG;
		}
		$glabels{$label}{'respcount'} += 1;
		$glabels{$label}{'totalresptime'} += $time;
		push(@{$glabels{$label}{'line90'}}, $time);
	 
		$entire{'respcount'} += 1;

		#---
		# memorize timestamps
		#---

		my $tstmp = int($timestamp / (1000 * $collectinterval)) * $collectinterval;
		$timestamps{$tstmp} += 1;

		#---
		# cusps
		#---
		for(my $i = 0; $i <= $#cusps; $i++) {
		  if(($time <= $cusps[$i]) || (($i == $#cusps) && ($time > $cusps[$i]))) {
			$glabels{$label}{$cusps[$i]} += 1;
			$entire{$cusps[$i]} += 1;
			last;
		  }
		}
		#---
		# stddev
		#---
		$respcount += 1;
		$sumresptimes += $time;
		$sumSQresptimes += ($time ** 2);
		if($respcount > 1) {
		  my $stddev = sqrt(($respcount * $sumSQresptimes - $sumresptimes ** 2) /
			($respcount * ($respcount - 1)));

		  $entire{$tstmp, 'stddev'} = $glabels{$label}{$tstmp, 'stddev'} = $stddev;

		}

		#---
		# avg
		#---
		$entire{$tstmp, 'avg'} = $sumresptimes / $respcount;

		$glabels{$label}{$tstmp, 'responsetime'} += $time;
		$glabels{$label}{$tstmp, 'respcount'} += 1;
		$glabels{$label}{$tstmp, 'avg'} = int($glabels{$label}{$tstmp, 'responsetime'} / $glabels{$label}{$tstmp, 'respcount'});
		#print "{$label}: time is $glabels{$label}{$tstmp, 'responsetime'}\n";
		#print "{$label}: count is $glabels{$label}{$tstmp, 'respcount'}\n";
		#---
		# active threads
		#---

		if(!$entire{$tstmp, 'activethreads'}) {
		  $entireta = 0;
		  $entirecnt = 0;
		  $entireby = 0;
		}

		if($NumberOfActiveThreadsAll > 0) {
		  $atflag = 1;
		}

		$entirecnt += 1;

		if($atflag == 1) {
		  $entireta += $NumberOfActiveThreadsAll;
		  $entire{$tstmp, 'activethreads'} = int($entireta / $entirecnt);
  
		  if(!$glabels{$label}{$tstmp, 'activethreads'}) {
			$glabels{$label}{$tstmp, 'lbta'} = 0;
			$glabels{$label}{$tstmp, 'lbby'} = 0;
		  }
		  $glabels{$label}{$tstmp, 'lbta'} += $NumberOfActiveThreadsAll;
		  $glabels{$label}{$tstmp, 'activethreads'} = sprintf("%.0f", $glabels{$label}{$tstmp, 'lbta'} / $glabels{$label}{$tstmp, 'respcount'});

		} else {
		  #---
		  # if NumberOfActiveThreads is not available
		  # use threadname to extrapolate active threads later
		  #---
		  if($NumberOfActiveThreadsAll eq '') {
				  if(!$gthreads{$thread}{'first'}) {
			  $gthreads{$thread}{'first'} = $tstmp;
			  push(@threads, $thread);
			}
  
			$gthreads{$thread}{'last'} = $tstmp;
		  }
		}

		#---
		# throughput
		#---
		if($bytes > 0) {
		  $entireby += $bytes;
		  $entire{$tstmp, 'throughput'} = int($entireby / $entirecnt);
  
		  $glabels{$label}{$tstmp, 'lbby'} += $bytes;
		  $glabels{$label}{$tstmp, 'throughput'} = $glabels{$label}{$tstmp, 'lbby'}; # counts per $collectinterval
		}

	  }
	  print "Closing $file\n" if $DEBUG;
	  close(IN);
	}
	
	#print "Found $#labels labels\n" if $DEBUG;
	#$labelsArrSize = @labels;
	print "Found " . scalar @labels . " labels\n" if $DEBUG;

	# Sort the labels.
	print "Sorting labels\n" if $DEBUG;
	my @tmplabels = sort @labels;
	@labels = @tmplabels;	


	# if something could be parsed
	#---
	if($respcount > 0) {
	  #---
	  # number of time stamps
	  #---
	  $measures = scalar(keys(%timestamps));

	  print "Generating stats\n" if $DEBUG;
		&GenerateStats();  
	}
}

sub GenerateStats {
  if(scalar(@labels) == 0) {
    return undef;
  }
  
	foreach my $label (@labels) {
		 
		 my $avg =  int($glabels{$label}{'totalresptime'} / $glabels{$label}{'respcount'});
		 print "label $label has respcount : $glabels{$label}{'respcount'} and resp time  $glabels{$label}{'totalresptime'} with avg $avg\n";
		 #sort the array numerically, then grab the 90th percent value
		 my @sorted_responstimes = sort {$a <=> $b}( @{$glabels{$label}{'line90'}} );
		 my $arrsize = @sorted_responstimes;
		 
		 my $index90 = int($arrsize * 0.9); 
		 print "arrsize is $arrsize with index90 $index90\n";
		 print "value of 90percentline is @sorted_responstimes[$index90]\n";
	}
	
	  my $xml        = '';
  $xml .= "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n";
  $xml .= $generator->testsuite(
        {
            errors   => $test_results->{total_failures},
             failures => $test_results->{total_failures},
            name     => 'name of the test suite',
            tests    => $test_results->{total_tests},
            'time'   => $test_results->{total_time},
            
        },
        $generator->properties(@properties),
        @{ $test_results->{test_cases} },
        $generator->$system_out(),
        $generator->$system_err(), );
        
        print "$xml\n";
        open(my $fh, '>', $reportfile) or die "Could not open file '$reportfile' $!";
		print $fh "$xml\n";
		close $fh;

}

sub usage {
    print(STDERR $_[0]) if @_;
    print(STDERR "usage: perl jMetertToJunit.pl --file report.html\n");
    exit(1);
}