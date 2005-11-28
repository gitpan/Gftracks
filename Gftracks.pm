#!/usr/bin/perl
package Gftracks;
use warnings;
use strict;
use Data::Dumper;
use Exporter;
our @ISA=qw / Exporter /;
our @EXPORT = qw / instime init deltrack printtracks shell/;
# Normally sec should only be used internally, but just in case, 
# we make it possible to pull it in.
our @EXPORT_OK = qw /sec tidytime /;
our $VERSION="0.5";
# Returns number of secounds calculated from a grf timestamp
sub sec{
  my ($h,$m,$s)=split(':',$_[0]);
  $s+=$m*60;
  $s+=$h*3600;
  return $s;
}


#
# instime inserts a track at a given timestamp
#
# ins(\@tracks,$timestamp[,$duration]);
# If duration is not defined, the end of the track is set to the
# current end of the track in which the insertion is performed
sub instime{
  my @tracks=@{$_[0]};
  my $timestamp=$_[1];
  my $duration=$_[2] || undef; 
  return \@tracks if $duration; # $duration still does not work
  my $timesec=sec($timestamp);
  foreach (1..$#tracks){
    # Search until either, we find the track which the new is to be inserted 
    # into, or we are on the last track. (To avoid warning, the checks are done
    # the other way around
    next unless ($_ == $#tracks or(
		 sec($tracks[$_]{start})< $timesec) 
		 and (sec($tracks[$_+1]{start})> $timesec));
    if (sec($tracks[$_]{end})>$timesec){ # Unless the insert is between two tracks
      my $new={start=>$timestamp,
	       end=>$tracks[$_]{end}};
      splice(@tracks,$_+1,0,$new);    
      $tracks[$_]{end}=$timestamp;
    }else{
      if ($duration){
	my $new={start=>$timestamp,
		 end=>$tracks[$_+1]{end}};
	splice(@tracks,$_+1,0,$new);    
	$tracks[$_]{end}=$timestamp;
      }
    }
    last;
  }
  $tracks[0]{Number_of_tracks}=$#tracks;
  return \@tracks;
}

# _spliceback and _splicefwd splices the rest of the array when
# a track has been deleted. They should only be used internally. 
# In both cases the arguments are a pointer to the tracks array and 
# the index that is to be deleted

# _spliceback removes a track by combining it with the previous track
sub _spliceback{
  my $tracks=shift;
  my $delno =shift;
  $tracks->[$delno-1]{end}=$tracks->[$delno]{end};
  splice (@$tracks,$delno,1);
  return $tracks;
}

# _spliceback removes a track by combining it with the next track
sub _splicefwd{
  my $tracks=shift;
  my $delno =shift;
  $tracks->[$delno+1]{start}=$tracks->[$delno]{start};
  splice (@$tracks,$delno,1);
  return $tracks;
}


# Deltrack removes a track by default using spliceback (unless the last track 
# is deleted).
# deltrack (\@tracks,$index,$back)

sub deltrack{
  my $tracks=shift;
  my $delno =shift;
  my $back = $delno == $#{$tracks} || shift;
  # $tracks->[0] must not be deleted, as it holds the meta info
  return $tracks unless $delno*1; 
  return $tracks if $delno >$#{$tracks};
  $tracks = $back ?  _spliceback($tracks,$delno) : _splicefwd($tracks,$delno);
  $tracks->[0]{Number_of_tracks}=$#{$tracks};
  return $tracks;
}

sub _trackfile{
# Could add a function that returns a *.track file if that
# is the only one found in the active directory  
  my $file= $ENV{TRACKS};
  warn("Is $file a .tracks file?") unless $file=~/.tracks$/;
  return $file;

}

sub init{
  my (@lines,@tracks,$nooftracks, $comment, %data,$tracks);
  my $file=$_[0] || _trackfile;
  print "$file\n" if $ENV{GRFDEBUG};
  open (FILE,"<$file") || die ("Cannot open $file");
  my $i;
  while(<FILE>){
    if (!$nooftracks && /Number_of_tracks.(\d+)/)
      {
	$nooftracks=$1;
      }
    chomp;
    push @lines , $_;
    $tracks=$tracks || /Track ?\d/;
    unless($tracks){
      next if /^#/;
      my($key,$var)=split(/=/,$_);
      $data{$key}=$var if $var;
      next;
    }
    $comment=$_ if /^#/;
    if (/^Track(\d+)(start|end)=(.*)$/) {
      $tracks[$1]{$2}=$3;
      # The last comment is the one connected to the current track
      $tracks[$1]{comment}=$comment; 
      # If the {end} element is not defined for current track, then
      # we are at start and calculates the start timestamp
      $tracks[$1]{starttime}=sec($3) unless ($tracks[$1]{end});
    }
  }
  $tracks[0]=\%data;
  return \@tracks;
}

sub tidytime{
  # Does some sanitychecking of the time stamp and tidies up a bit
  my $zerotime="0:00:00.000";
  my $timestamp=shift;
  $timestamp.=' ';
  $timestamp=~m/(\d\D)?(\d{2})\D(\d{2}(\.\d{1,3})?)?/;
#  print "<$1|$2|$3|$4>\n";
  my $sec= ($3 || '0');
  $sec.='.' unless $4;
  $sec='0'.$sec if $sec < 10;
  $sec.='0'x(6-length($sec));
  my $hour= ($1 || '0 ');
  chop($hour);
  return "$hour:$2:$sec";

}



sub shellhelp{
  print <<ENDHELP
    h         : help
    a <t>     : add a track at given time
    d <n>     : delete the given track
    n         : print number of tracks
    p         : print start and end times for all tracks
    b <n> <t> : alter beginning of track
    e <n> <t> : alter end of track
    s         : save file
    q         : quit
    ---------------------------------------------------------
    <t> time,  must be given as h:mm:ss.ss 
    <n> tracknumber
    (c) Morten Sickel (cpan\@sickel.net) April 2005
    The last version should be available at http://sickel.net
    Licenced under the artistic licence

ENDHELP
}

sub shelladjusttime{
  # adjusts the time for start or end of a track
  my $tracks=shift;
  my $command=shift;
  my $end=shift;
  $command=~/\w+\s+(\d+)\s+(.*)/;
  my $time=tidytime($2);
  $$tracks[$1]{$end}=$time;
}


sub shelladd{
  # Adds  track at a given time
  my $tracks  = shift;
  my $command = shift;
  $command=~m/^\w+\s+(.*)/;
  $command=$1;
  $tracks=instime($tracks,$command);
  
}

sub shelldelete{
  my ($tracks,$command)=@_;
  $command=~m/^\w+\s+(.*)/;
  $command=$1;
  $tracks=deltrack($tracks,$command);
}

sub shellprint{
  my $tracks = shift;
  print $#$tracks," tracks\n";
}

sub shellsave{
  my($tracks,$file)=@_;
  open OUT,">$file.sav";
  print OUT printtracks($tracks);
  close OUT;
}

sub shellprinttracks{
  my $tracks=shift;
  my @tracks=@$tracks;
  my $i;
  print "track from"." "x10,"to\n";
  print "-"x(6+4+10+11),"\n";
  foreach $i (1..$#tracks){
    print "  $i"," "x(4-length($i)),$tracks[$i]->{start},
      " - ",$tracks[$i]->{end},"\n";
  }
  

}

sub shell{
  my $file = shift || _trackfile;
  $file=~tr/ //d;
  die("Use the environment variable TRACKS to set tracks file\n")
    unless $file;
  my $tracks=init($file);
  die('Cannot find tracks file, use the environment variable TRACKS')
    unless $tracks;
  print "press 'h' for help\n";
  while(1){
    print " > ";
    my $command = <>;
    last if $command=~/^q/i;
    shellhelp if $command =~/^h/i;
    $tracks=shelladd($tracks,$command) if $command =~/^a/;
    shellprint($tracks) if $command=~/^n/;
    $tracks=shelldelete($tracks,$command) if $command=~/^d/;
    shellsave($tracks,$file) if $command=~/^s/;
    shellprinttracks($tracks) if $command=~/^p/;
    shelladjusttime($tracks,$command,'start') if $command=~/^b/;
    shelladjusttime($tracks,$command,'end') if $command=~/^e/;
  }
}


sub printtracks{
  my $tracks=shift;
  my @tracks=@$tracks;
  my $not="Number_of_tracks";
  my $buffer="[Tracks]";
  foreach (keys %{$tracks[0]}){
    $buffer .= "$_=$$tracks[0]{$_}\n" if $_ ne $not;
  }
  $buffer.= "\n".$not."=".$$tracks[0]{$not}."\n\n";
  my $i;
  foreach $i (1..$#tracks){
    $i="0".$i if $i<10;
    no warnings;

    $buffer.= $tracks[$i]->{comment}."\n";
    $buffer.= "Track${i}start=".$tracks[$i]->{start}."\n";
    $buffer.= "Track${i}end=".$tracks[$i]->{end}."\n\n";
    use warnings;
  }
  return $buffer;
}

1;
