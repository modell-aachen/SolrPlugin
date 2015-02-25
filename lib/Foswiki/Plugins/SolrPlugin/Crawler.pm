# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2012-2014 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Foswiki::Plugins::SolrPlugin::Crawler;
use strict;
use warnings;

use Foswiki::Plugins::SolrPlugin::Base ();
our @ISA = qw( Foswiki::Plugins::SolrPlugin::Base );

################################################################################
sub crawl {
  die "not implemented";
}

################################################################################
sub getListOfUsers {
  die "not implemented";
}

################################################################################
sub getGrantedUsers {
  die "not implemented";
}

################################################################################
sub getAclFields {
  my $this = shift;

  my @aclFields = ();

  # permissions
  my @grantedUsers = $this->getGrantedUsers(@_);
  foreach my $wikiName (@grantedUsers) {
    push @aclFields, 'access_granted' => $wikiName;
  }

  return @aclFields;
}

################################################################################
sub isIndexableFile {
  my ($this, $fileName) = @_;

  my $extension = '';
  if ($fileName =~ /^(.+)\.(\w+?)$/) {
    $extension = lc($2);
  }
  $extension = 'jpg' if $extension =~ /jpe?g/i;
  
  my $indexFileTypes = $this->indexFileTypes();

  return $indexFileTypes->{$extension};
}

################################################################################
sub indexFileTypes {
  my $this = shift;

  my $indexFileType = $this->{_indexFileType};

  unless (defined $indexFileType) {
    $indexFileType = {};
    my $fileTypes = 
      $this->{fileTypes} ||
      $Foswiki::cfg{SolrPlugin}{IndexExtensions} || # backwards compatibility
      "txt, html, xml, doc, docx, xls, xlsx, ppt, pptx, pdf, odt";

    foreach my $tmpFileTypes (split(/\s*,\s*/, $fileTypes)) {
      $indexFileType->{$tmpFileTypes} = 1;
    }

    $this->{_indexFileType} = $indexFileType;
  }

  return $indexFileType;
}

################################################################################
sub getStringifiedVersion {
  my ($this, $fileName) = @_;

  # TODO: add caching similar to Foswiki::Plugins::SolrPlugin::Indexer
  my $body = '';

  my $extension = '';
  if ($fileName =~ /^(.+)\.(\w+?)$/) {
    $extension = lc($2);
  }
  $extension = 'jpg' if $extension =~ /jpe?g/i;
  
  my $indexFileTypes = $this->indexFileTypes();

  if ($indexFileTypes->{$extension}) {
    $body = Foswiki::Contrib::Stringifier->stringFor($fileName) || '';
  }

  return $body;
}

1;

