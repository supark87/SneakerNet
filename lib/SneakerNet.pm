package SneakerNet;
use strict;
use warnings;
use Exporter qw(import);
use File::Basename qw/fileparse basename dirname/;
use Config::Simple;
use Data::Dumper;

use FindBin qw/$Bin $Script $RealBin $RealScript/;

our @EXPORT_OK = qw(
  readConfig samplesheetInfo 
  command logmsg
);


my $thisdir=dirname($INC{'SneakerNet.pm'});

sub logmsg{print STDERR "$0: @_\n";}

sub readConfig{
  my $settings={};

  my @file=glob("$thisdir/../config/*.conf");
  for my $file(@file){
    my $cfg = new Config::Simple();
    if(!$cfg->read($file)){
      logmsg "WARNING: could not read $file: ".$cfg->error;
      next;
    }
    my %vars= $cfg->vars();
    $$settings{$_}=$vars{$_} for(keys(%vars));
    $$settings{obj}{basename($file)}=$cfg; # save the obj too
  }
  return $settings;
}

sub samplesheetInfo{
  my($samplesheet,$settings)=@_;

  my $config=readConfig();

  my $section="";
  my @header=();
  my %sample;
  open(SAMPLE,$samplesheet) or die "ERROR: could not open sample spreadsheet $samplesheet: $!";
  while(<SAMPLE>){
    s/^\s+|\s+$//g; # trim whitespace

    if(/^\[(\w+)\]/){  # [sectionname]
      $section=lc($1);
      my $header=<SAMPLE>;
      $header=~s/^\s+|\s+$//g; # trim whitespace
      @header=split(/,/,lc($header));
      next;
    }
    if($section eq "data"){
      my %F;
      @F{@header}=split(/,/,$_);
      $F{route}||=[]; # force route to be an array
      for my $keyvalue(split(/;/,lc($F{description}))){
        my($key,$value)=split(/=/,$keyvalue);
        $key=~s/^\s+|\s+$//g;      #whitespace trim
        $value=~s/^\s+|\s+$//g;    #whitespace trim
        #$F{$key}={} if(!$F{$key});
        #$F{$key}{$value}++;
        if($F{$key}){
          if(ref($F{$key}) ne 'ARRAY'){
            $F{$key}=[$F{$key}];
          }
          push(@{ $F{$key} }, $value);
        } else {
          $F{$key}=$value;
        }
      }
      delete($F{description});

      # What taxon is this if not listed?
      if(!$F{species}){
        for my $taxonArr(@{ $$config{genomeSizes} }){
          my($regex,$size,$possibleTaxon)=@$taxonArr;
          if($F{sample_id}=~/$regex/){
            $F{species}=$possibleTaxon;
            last;
          }
        }
      }

      # What rules under taxonProperties.conf does this
      # genome mostly align with?
      my $alignedWith="";
      my %taxonProperties=%{ $$settings{obj}{"taxonProperties.conf"}->vars };
      #die Dumper $$settings{obj}{"taxonProperties.conf"}->param(-block=>'Salmonella');
      while(my($key,$value)=each(%taxonProperties)){
        my($taxon,$property)=split(/\./,$key);

        # Guess the taxon based on some rules
        if( 
          ($property eq 'regex' && $F{sample_id}=~/$value/i) || 
          $F{species}=~/$taxon/i
        ){
          $F{taxonRules}=$$settings{obj}{"taxonProperties.conf"}->param(-block=>$taxon);
          $F{taxonRules}{taxon}=$taxon;
          last;
        }
          
      }

      $sample{$F{sample_id}}=\%F;
    }
  }
  close SAMPLE;

  # Try to associate samples to files
  # Warning: this adds a mix of strings into a set of hashes and so
  # the variable type (ref) needs to be checked sometimes.
  my %fastqToName;
  while(my($samplename,$sampleinfo)=each(%sample)){
    my @possibleFastq=glob(dirname($samplesheet)."/$samplename*.fastq.gz");
    $sample{$samplename}{fastq}=\@possibleFastq;
    
    # Make some links from file to sample
    for my $fastq(@possibleFastq){
      $fastqToName{$fastq}=$samplename;
    }
  }
  %sample=(%sample,%fastqToName);

  return \%sample;
}

sub command{
  my($command,$settings)=@_;
  logmsg "COMMAND\n  $command" if($$settings{debug});
  system($command);
  if($?){
    my $msg="ERROR running command\n  $command";
    die $msg;
  }
}


