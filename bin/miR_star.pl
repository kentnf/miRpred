#!/usr/bin/perl

=head1

  predict miRNA star sequence

  modified by Kentnf
  20140723 : fix several bugs, output more info, and output best miR according to expression

=cut

use strict;
use warnings;
use FindBin;
use IO::File;
use Getopt::Long;

my $usage = qq'
usage: $0 [-a miRNA_sql_output -b miRNA_hairpin_sql | -c hairpin ] -d sRNA_seq -e sRNA_expr -f output_file
 
	-a miRNA_sql		miRNA_sql_output file	
	-b miRNA_hairpin_sql 	miRNA_hairpin_sql file
	-c hairpin 		prase miRNA_sql_output and miRNA_hairpin_sql to generate hairpin file
	-d sRNA_seq 		input small RNA sequence [required]
	-e sRNA_expr 		expression of small RNA sequence [required]
	-f output_file		output file [required]
	-h 			print help info

';

my ($miRNA_sql, $hairpin_sql, $hairpin, $sRNA_seq, $sRNA_expr, $output, $help);

GetOptions(
        "h|?|help"		=> \$help,
        "a|miRNA-sql=s"		=> \$miRNA_sql,
        "b|hairpin-sql=s"	=> \$hairpin_sql,
        "c|hairpin=s"		=> \$hairpin,
        "d|small-RNA=s"		=> \$sRNA_seq,
        "e|sRNA-expr=s"		=> \$sRNA_expr,
        "f|output=s"		=> \$output
);

die $usage if $help;
die $usage unless $sRNA_seq;
die $usage unless $sRNA_expr;
die $usage unless $output;
if ($miRNA_sql && $hairpin_sql) {} 
elsif ($hairpin) { }
else { die $usage; }

#################################################################
# Configuration section                                         #
#################################################################

my $BOWTIE_PATH = ${FindBin::RealBin};
my $TEMP_PATH = ".";
my $gap = 2;				# distance from end position of hairpin

# set temp files base on system time	
my $star_candidate = $TEMP_PATH."/"."Star_candidate.";
my $temp_fas = $TEMP_PATH."/"."bowtie.tmp.fas.";
my $temp_db = $TEMP_PATH."/"."bowtie.tmp.db.";
unless ($hairpin) { $hairpin = $TEMP_PATH."/"."HAIRPINC"; }

my ($second, $minute, $hour);
($second, $minute, $hour) = localtime(); 
my $fid = $second.$minute.$hour;
   $temp_fas .= $fid; 
   $temp_db .= $fid;
   $star_candidate .= $fid;

#################################################################
# constructure temp hairpin sequence file 			#
#################################################################
my %ms;	# key: miRNA new ID; value: miRNA old ID from small RNA sequence;
my %sm;	# reverse of ms
if ($miRNA_sql && $hairpin_sql)
{
	my $in1 = IO::File->new($miRNA_sql) || die "Can not open miRNA sql file $miRNA_sql $!\n";
	while(<$in1>)
	{
		my @a = split(/\t/, $_);
		$ms{$a[0]} = $a[1];
		$sm{$a[1]} = $a[0];
	}
	$in1->close;

	# pre-miR miR       Ref   Start     End       miR start  Stand(?)
	# H000001 miR01029  Chr1  13252204  13252419  193        +         Hairpin_Sequence  -191.60
	my $out = IO::File->new(">".$temp_fas) || die "Can not open temp fasta file $temp_fas $!\n";	
	my $out2 = IO::File->new(">".$hairpin) || die "Can not open hairpin file $hairpin $!\n";
	my $in2 = IO::File->new($hairpin_sql) || die "Can not open miRNA hairpin sql file $hairpin_sql $!\n";
	while(<$in2>)
	{
        	my @b = split(/\t/, $_);
		die "[ERR]Undef miR ID for sRNA $b[1]\n" unless defined $ms{$b[1]};
        	$b[1] = $ms{$b[1]};
		print $out2 join("\t", @b);
		my $len_seq = length($b[7]);
                print $out ">$b[0]_$b[1]_$b[5]_$len_seq\n";
                my $seq = $b[7];
                $seq =~ tr/uU/tT/;
                print $out "$seq\n";
	}
	$in2->close;
	$out->close;
	$out2->close;

}
elsif ($hairpin)
{
	# H000001 Test01029       Chr1    13252204        13252419        193     +       Hairpin_Sequence        -191.60
	my $out = IO::File->new(">".$temp_fas) || die "Can not open temp fasta file $temp_fas $!\n";
	my $in = IO::File->new($hairpin) || die "Can not open converted hairpin file $hairpin $!\n";
	while(<$in>)
	{
		chomp;
		my $list = $_;
		my @a = split("\t", $list);
		my $len_seq = length($a[7]);
		print $out ">$a[0]_$a[1]_$a[5]_$len_seq\n";
		my $seq = $a[7];
  		$seq =~ tr/uU/tT/;
		print $out "$seq\n";
	}
	$in->close;
	$out->close;
}
else
{
	print $usage;
	exit(0);
}

#################################################################
# compare small RNA with hairpin fasta sequence			#
#################################################################
my $bowtie_db_out = `bowtie-build $temp_fas $temp_db`;
my $bowtie_run_out = `bowtie -v 0 -a -f $temp_db $sRNA_seq`;
chomp($bowtie_run_out);
if (length($bowtie_run_out) < 1) { 
	die "[ERR]no alignment\n";
}

#################################################################
# convert bowtie run output to star candidate 			#
#################################################################
open (OUTFILE, ">$star_candidate") || die "Cannot Open start candidate file $!\n";

my @list = split(/\n/, $bowtie_run_out);
foreach my $line (@list) 
{
	chomp $line;
	# read_id  strand  pre-miR  pos(0-base)  read_seq  qual  mismatch
	my ($sRNA, $strand, $miR, $loc, $seq, $sc, $mismatch) = split(/\t/, $line);
	if ($strand eq "+") 
	{
  		my $sRNA_s = $loc+1;
  		my $sRNA_e = $loc+length($seq);

  		#$miR = $L[0];
  		#$sRNA_b = $L[1];

  		#$sRNA_s = $L[2];
  		#$sRNA_e = $L[3];

  		my @miR_L = split("_", $miR); # pre-miR  miR  pos(miR on pre-miR)  pre-miR_len
  		my $miR_id = $miR_L[0];
  		my $sRNA_a = $miR_L[1];
  		my $miR_s = $miR_L[2];	# should be miR on pre-miR
  		my $miR_l = $miR_L[3];

  		my $miR_e = $miR_l - $gap;

        	if (int($miR_s) <=  $gap) 
		{      
                	if ($sRNA_e >= $miR_e) {
                        	print OUTFILE "$miR_id\t$sRNA_a\t$sRNA\t$miR_s\t$miR_l\t$sRNA_s\t$sRNA_e\n";
                	}
        	}       
        	else {
                	if ($sRNA_s <=  $gap) {
                        	print OUTFILE "$miR_id\t$sRNA_a\t$sRNA\t$miR_s\t$miR_l\t$sRNA_s\t$sRNA_e\n";
                	}
        	}
  	}
}
close(OUTFILE);

system "rm $TEMP_PATH/bowtie.tmp.*";

#################################################################
# Ratio between miR mature read and miR star read		#
# Minmum read abundence						#
# Difference between miR mature length and miR star length 	#
#################################################################

my $ratio_cutoff = 2.0;
my $min_freq_a_cutoff = 5;
my $min_freq_b_cutoff = 0;
my $len_diff_cutoff = 3;     

#################################################################

my %miRNA_seq = {};	# key: pre-miR ID, value: pre-miR seq
my %sRNA_seq = {};	# key: sRNA ID, value: sRNA seq
my %sRNA_freq = {};	# key: sRNA ID, value: expression(RPM)

#################################################################
# $hairpin sequence to hash					#
#################################################################
print "Loading miR hairpin....\n";
%miRNA_seq = load_hairpin($hairpin);

=head1 load_hairpin

 function: load miR hairpin sequence to hash

=cut
sub load_hairpin
{
	my $hairpin = shift;

	my %miRNA_seq;

	my $fh = IO::File->new($hairpin) || die "Can not open hairpin sequence file $hairpin $!\n";
	while(<$fh>)
	{
		chomp;
		my $line = $_;
		my @a = split("\t", $line);
		my $m_id = $a[0];
		my $seq = $a[7];
		$miRNA_seq{$m_id} = $seq;
	}
	$fh->close;

	return %miRNA_seq;
}

#################################################################
# small RNA sequence to hash					#
#################################################################
print "Loading sRNAs....\n";
%sRNA_seq = load_sRNA($sRNA_seq);

=head1 load_sRNA

 function: load small RNA sequence to hash

=cut
sub load_sRNA
{
	my $sRNA_seq = shift;

	my $s_id = "";
	my %sRNA_seq;

	my $fh = IO::File->new($sRNA_seq) || die "Can not open small RNA sequence $sRNA_seq $!\n";
	while(<$fh>)
	{
		chomp;
		my $line = $_;
		
		if ($line =~ m/^\>/) 
		{
			$s_id = $line;
     			$s_id =~ s/^\>//;
  		}
  		else
		{
     			$sRNA_seq{$s_id} = $line;
  		}
	}
	$fh->close;

	return %sRNA_seq;
}

#################################################################
# load small RNA expression number to hash			#
#################################################################
print "Loading read numbers....\n";
%sRNA_freq = load_read_number($sRNA_expr);

=head1 load_read_number

 function: load read expression number to hash

=cut

sub load_read_number
{
	my $sRNA_expr = shift;
	
	my %sRNA_freq;

	my $fh = IO::File->new($sRNA_expr) || die "Can not open small RNA expr file $sRNA_expr $!\n";
	# get title information
	my $title = <$fh>; chomp($title);
	my @t = split(/\t/, $title);
	shift @t; shift @t;
	$sRNA_freq{'title'} = join("\t", @t);

	while(<$fh>)
	{
		chomp;
  		my $line = $_;
  		my @a = split("\t", $line);
  		my $s_id = $a[1];
  		shift @a;
		shift @a;
  		$sRNA_freq{$s_id} = join("\t", @a);
	}
	$fh->close;

	return %sRNA_freq;
}

#################################################################
# checking miRNA start						#
#################################################################
print "Checking miRNA star....\n";

open(IN, $star_candidate) || die "can't open $star_candidate $!\n";
open(OUT, ">$output") || die "can't open $output $!\n";

my @exp = split(/\t/, $sRNA_freq{'title'});
my $exp_title = '';
foreach my $sample (@exp) { $exp_title.="\t$sample:A\t$sample:B\t$sample:ratio"; }

print OUT "#Pre-miR ID\tPre-miR seq\tmiR ID\tmiR Len\tmiR seq\tmiR start\tmiR end\tsRNA ID\tsRNA Len\tsRNA seq\tsRNA start\tsRNA end$exp_title\n";

my %miR_best;

while(<IN>)
{
  	chomp;
  	my $line = $_;
	my $exp_line = "";
  	my @a = split("\t", $line);
  	my $miR_id = $a[0];
  	my $sRNA_id_a = $a[1];
  	my $sRNA_id_b = $a[2];

	# check the hash
	unless(defined $miRNA_seq{$miR_id}) { die "Error in miRNA_seq"; }
	unless(defined $sRNA_seq{$sRNA_id_a}) { die "Error in sR_seq_a"; }
	unless(defined $sRNA_seq{$sRNA_id_b}) { die "Error in sR_seq_b"; }
	my $miR_seq = $miRNA_seq{$miR_id};
	my $sR_seq_a = $sRNA_seq{$sRNA_id_a};
	my $sR_seq_b = $sRNA_seq{$sRNA_id_b};

	die "[ERR]Undef miRNA ID $sRNA_id_a\n" unless defined $sm{$sRNA_id_a};
	my $mid = $sm{$sRNA_id_a};
	
	#"$sR_seq_a\n$sR_seq_b\n";
	
	unless(defined $sRNA_freq{$sR_seq_a}) { die "Error in sRNA_freq\n>$sRNA_id_a\n$sR_seq_a\n"; }
	unless(defined $sRNA_freq{$sR_seq_b}) { die "Error in sRNA_freq\n>$sRNA_id_b\n$sR_seq_b\n"; }
	#print "$sRNA_id_a\n$sRNA_freq{$sR_seq_a}\n$sRNA_id_b\n$sRNA_freq{$sR_seq_b}\n"; die;

	my @freq_a = split("\t", $sRNA_freq{$sR_seq_a});
	my @freq_b = split("\t", $sRNA_freq{$sR_seq_b});
	die "[ERR]exp num not equal for miR and sRNA\n" unless (scalar(@freq_a) == scalar(@freq_b));

  	my $ratio_avail = 0;
	my $ratio;
	my $high_exp_a = 0;
	# code for question
	for (my $i = 0; $i < @freq_a; $i++)
	{
		if ($freq_a[$i] > 0 && $freq_b[$i] > 0)
		{
			$ratio = sprintf("%.2f", ($freq_a[$i] / $freq_b[$i]));
			if ($ratio >= $ratio_cutoff && $freq_a[$i] >= $min_freq_a_cutoff && $freq_b[$i] >= $min_freq_a_cutoff)
			{ 
				$ratio_avail = 1; 
				$high_exp_a = $freq_a[$i] if $freq_a[$i] > $high_exp_a;
			}
		}
		else
		{
			$ratio = 'Inf';
			if ($freq_a[$i] > 0 && $freq_a[$i] >= $min_freq_a_cutoff)
			{
				$ratio_avail = 1;
				$high_exp_a = $freq_a[$i] if $freq_a[$i] > $high_exp_a;
			}
		}
		$exp_line.="\t".$freq_a[$i]."\t".$freq_b[$i]."\t".$ratio;
	}

  	my $len_diff = abs(length($sR_seq_a) - length($sR_seq_b));

	if ( $ratio_avail == 1 && $len_diff <= $len_diff_cutoff)
	{
		$a[4] = $a[3] + length($sR_seq_a) - 1;

		if ($a[4] > length($miR_seq)) {
			print "[WARN]$line\n";
		}

		my $outinfo = $miR_id."\t".$miR_seq."\t".$mid."\t".length($sR_seq_a)."\t".$sR_seq_a."\t$a[3]\t$a[4]".
                        	"\t".$sRNA_id_b."\t".length($sR_seq_b)."\t".$sR_seq_b."\t$a[5]\t$a[6]";
                $outinfo .= $exp_line."\n";
		# print OUT join("\t", @freq_a), "\t";
		# print OUT join("\t", @freq_b), "\n";

		if ( defined $miR_best{$mid}{'best'} ) 
		{
			if ($high_exp_a > $miR_best{$mid}{'best'}) 
			{
				$miR_best{$mid}{'best'} = $high_exp_a;
				$miR_best{$mid}{'out'} = $outinfo;
			}
		} 
		else 
		{
			$miR_best{$mid}{'best'} = $high_exp_a;
			$miR_best{$mid}{'out'} = $outinfo;
		}
  	}
}
close(IN);

foreach my $mid (sort keys %miR_best)
{
	print OUT $miR_best{$mid}{'out'};
}

close(OUT);

unlink($star_candidate);
