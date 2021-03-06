#!/usr/bin/env perl
# Runs nullarbor

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;
use File::Copy qw/move copy/;
use File::Basename qw/fileparse basename dirname/;
use File::Temp;
use FindBin;
use Email::Stuffer;
use List::MoreUtils qw/uniq/;

use lib "$FindBin::RealBin/../lib/perl5";
use SneakerNet qw/readConfig logmsg samplesheetInfo command/;

$ENV{PATH}="/opt/Roary-3.2.7/bin:/opt/ruby-2.2.3/bin:/opt/kramdown/bin:/opt/samtools-1.2/htslib-1.2.1:/opt/bwa-0.7.12:/opt/mlst-1.2/bin:/opt/nullarbor/bin:/opt/abricate/bin:/opt/bcftools-1.2:/opt/samtools-1.2:/opt/megahit-1.0.2/bin:/opt/prokka-1.11/bin:/opt/snippy-2.6/bin:/opt/kraken:$ENV{PATH}";
$ENV{RUBYLIB}||="";
$ENV{RUBYLIB}="$ENV{RUBYLIB}:/opt/kramdown/lib";
$ENV{KRAKEN_DEFAULT_DB}="/opt/kraken/minikraken_20141208";
$ENV{PERL5LIB}="$ENV{PERL5LIB}:/opt/Roary-3.2.7/lib";

local $0=fileparse $0;
exit(main());

sub main{
  my $settings=readConfig();
  GetOptions($settings,qw(help inbox=s debug test numcpus=i)) or die $!;
  die usage() if($$settings{help} || !@ARGV);
  $$settings{numcpus}||=1;
  
  my $dir=$ARGV[0];

  nullarbor($dir,$settings);

  return 0;
}

sub nullarbor{
  my($dir,$settings)=@_;
  my $allsamples=samplesheetInfo("$dir/SampleSheet.csv",$settings);

  # Run nullarbor by species, and so we need species names
  my %species;
  while(my($samplename,$info)=each(%$allsamples)){
    next if(ref($info) ne 'HASH');
    $species{$$info{species}}=1;
  }
  my @species=keys(%species);

  for my $species(@species){
    nullarborBySpecies($dir,$species,$settings);
  }
}

sub nullarborBySpecies{
  my($dir,$species,$settings)=@_;
  
  my $tsv=makeTabFile($dir,$species,$settings);
  my $mlstScheme=chooseMlstScheme($species,$settings);
  my $ref=chooseRef($dir,$species,$settings);

  my $outdir="$species.nullarbor";
     $outdir=~s/\s+|\/+|:/_/g;      # remove special characters
     $outdir="$dir/$outdir";        # add on the parent directory
  
  system("mkdir -pv $outdir");
  command("cp -nv $ref $outdir/ref.fa");
  command("nullarbor.pl --name $species --mlst $mlstScheme --ref $ref --input $tsv --outdir $outdir --force --cpus 1 2>&1 | tee $outdir.log") if(!-e "$outdir/Makefile");
  command("nice make --environment-overrides -j $$settings{numcpus} -C $outdir 2>&1 | tee --append $outdir.log");

  return $outdir;
}

sub makeTabFile{
  my($dir,$species,$settings)=@_;
  $species||="all";

  my $allsamples=samplesheetInfo("$dir/SampleSheet.csv",$settings);
  my $tsv="$dir/samples.$species.tsv";
  open(TAB,">",$tsv) or die "ERROR: could not open $tsv for writing: $!";
  while(my($samplename,$info)=each(%$allsamples)){
    next if(ref($info) ne 'HASH');
    if($species eq 'all' || $$info{species} eq $species){
      print TAB join("\t",$samplename,@{$$info{fastq}})."\n";
    }
  }
  close TAB;
  return $tsv;
}

sub chooseMlstScheme{
  my($species,$settings)=@_;
  
  # TODO put this logic into a config file
  my $internalError="WARNING: I have no idea what scheme to attach to $species. Please edit the logic found in $0 after line ".__LINE__;
  my $scheme="";
  if($species=~/listeria|monocytogenes/i){
    $scheme="lmonocytogenes";
  } elsif($species=~/Escherichia|E\.coli/i){
    $scheme="ecoli";
  } elsif($species=~/Campy/i){
    $scheme="campylobacter";
  } elsif($species=~/cholerae/i){
    $scheme="vcholerae";
  } elsif($species=~/vibrio/i){
    $scheme="vibrio";
  } elsif($species=~/salmonella/i){
    $scheme="senterica";
  }

  # Catch any weird things and return a warning if so
  elsif($species=~/^undetermined/i){
    logmsg $internalError;
  }else{
    logmsg $internalError;
  }

    
  return $scheme;
}

sub chooseRef{
  my($dir,$species,$settings)=@_;
  system("mkdir -pv $dir");
  my $ref="$dir/ref.fa";
  return $ref if(-e $ref);

  # Find largest fastq file and assemble it quickly.
  my $maxSize=0;
  my($R1,$R2);
  my $allsamples=samplesheetInfo("$dir/SampleSheet.csv",$settings);
  while(my($samplename,$info)=each(%$allsamples)){
    next if(ref($info) ne 'HASH');
    my $size=(-s $$info{fastq}[0]) + (-s $$info{fastq}[1]);
    if($species eq 'all' || $$info{species} eq $species){
      if($size > $maxSize){
        $maxSize=$size;
        ($R1,$R2)=@{ $$info{fastq} };
      }
    }
  }
  
  my $megahit_cpus=$$settings{numcpus};
     $megahit_cpus=2 if($megahit_cpus < 2);
  command("rm -rf $dir/referenceAssembly.tmp");
  command("megahit -1 $R1 -2 $R2 -o $dir/referenceAssembly.tmp -t $megahit_cpus --k-min 61 --k-max 91 --k-step 20 --min-count 3 --min-contig-len 500 --no-mercy");
  command("cp $dir/referenceAssembly.tmp/final.contigs.fa $ref");
  command("fa $ref");
  command("rm -rf $dir/referenceAssembly.tmp");
  return $ref;
}
################
# Utility subs #
################

sub usage{
  "Runs nullarbor for the read set
  Usage: $0 runDir
  --numcpus 1
  "
}

