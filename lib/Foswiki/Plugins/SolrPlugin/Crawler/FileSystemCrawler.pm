# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2012-2015 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
package Foswiki::Plugins::SolrPlugin::Crawler::FileSystemCrawler;

use strict;
use warnings;

use Foswiki::Plugins::SolrPlugin::Crawler ();
use Foswiki::Contrib::Stringifier ();

use File::Spec ();
use Error qw(:try);
use User::grent;

our @ISA = qw( Foswiki::Plugins::SolrPlugin::Crawler );

use constant TRACE => 0;

################################################################################
sub new {
  my $class = shift;
  my $session = shift;

  my $this = $class->SUPER::new($session, @_);

  $this->init;

  return $this;
}

################################################################################
sub init {
  my $this = shift;

  $this->{_currentDepth} = 0;
  $this->{depth} ||= 0;

  # TODO: have a history db to continue where we got interupted last
  $this->{_seen} = {};
}

################################################################################
sub crawl {
  my ($this, $path) = @_;

  $path ||= $this->{path}; 

  #$this->log("crawl($path)");

  # protect against infinite recursion 
  return if $this->{_seen}{$path};
  $this->{_seen}{$path} = 1;

  #print STDERR "here1\n";

  return if $this->{excludePath} && $path =~ /$this->{excludePath}/;
  return if $this->{includePath} && $path !~ /$this->{includePath}/;
  return if $this->{depth} && $this->{_currentDepth} > $this->{depth};

  if (-d $path) {
    #print STDERR "here2\n";

    if (opendir(my $dirh, $path)) {

      my @dirContents = readdir $dirh;
      @dirContents = File::Spec->no_upwards(@dirContents);

      my @dirs = File::Spec->splitdir($path);

      $this->{_currentDepth}++;

      foreach my $entry (@dirContents) {
        my $thisPath = File::Spec->catfile(@dirs, $entry);
        $this->crawl($thisPath);
      }

      closedir $dirh;
    }
  } elsif($this->{followSymLinks} && -l $path) {
    #print STDERR "here3\n";

    $this->indexFile($path);

  } elsif(-f $path) {
    #print STDERR "here4\n";

    $this->indexFile($path);

  } else {
    return; # not a file type we are interested in
  }

  sleep($this->{throttle}) if $this->{throttle};
}

################################################################################
sub getGrantedUsers {
  my $this = shift;
  my $fileName = shift;

  my @stat = stat($fileName);

  my $user = getpwuid($stat[4]);

  my $group = getgrgid($stat[5]);
  my $groupName = $group->name;
  my %members = map {$_ => 1} @{$group->members};
  $members{$user} = 1;

  $this->log("... owned by $user/$groupName, members=".join(", ", keys %members));

  return keys %members;
}

################################################################################
sub indexFile {
  my ($this, $fileName) = @_;

  $this->log("Indexing file $fileName") if TRACE;

  my @aclFields = $this->getAclFields($fileName);


  my $body = '';
  if (-r $fileName) {
    if ($this->isIndexableFile($fileName)) {
      $this->log("... reading $fileName");
      #$body = $this->getStringifiedVersion($fileName);
    }
    #print STDERR "body=$body\n";
  } else {
    $this->log("... can't read $fileName");
  } 
}

1;
