# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Foswiki::Plugins::SolrPlugin::Base;

use strict;
use Foswiki::Func ();
use Foswiki::Plugins ();
use WebService::Solr ();
use Unicode::MapUTF8 ();
use Error qw( :try );

sub new {
  my $class = shift;
  my $session = shift;

  $session ||= $Foswiki::Plugins::SESSION;

  my $this = {
    session => $session,
    url => $Foswiki::cfg{SolrPlugin}{Url} || 'http://localhost:8983',
    @_
  };
  bless($this, $class);

  if (!$this->connect() && $Foswiki::cfg{SolrPlugin}{AutoStartDaemon}) {
    $this->startDaemon();
    $this->connect();
  }

  unless ($this->{solr}) {
    $this->log("ERROR: can't conect solr daemon");
  }

  return $this;
}

sub startDaemon {
  my ($this) = @_;

  my $maxStartRetries = 3;

  my $toolsDir = $Foswiki::cfg{ToolsDir} || $Foswiki::cfg{WorkingDir}."/../tools"; # try to cope with old foswikis w/o a ToolsDir setting
  my $autoStartCmd = $Foswiki::cfg{SolrPlugin}{SolrStartCmd} || $toolsDir.'/solrstart %SOLRHOME|F%';
  my $solrHome = $Foswiki::cfg{SolrPlugin}{SolrHome} || $Foswiki::cfg{WorkingDir}."/../solr";

  for (my $tries = 1; $tries <= $maxStartRetries; $tries++) {

    # trying to autostart
    $this->log("autostarting solr at $solrHome");

    unless (-f $solrHome."/start.jar") {
      $this->log("ERROR: start.jar not found ... aborting autostart");
      last;
    }

    my ($stdout, $exit, $stderr) = Foswiki::Sandbox::sysCommand(undef,
      $autoStartCmd,
      SOLRHOME => $solrHome
    );

    if ($exit) {
      $this->log("ERROR: $stderr");
      sleep 1;
    } else {
      $this->log("... waiting for solr to start up");
      sleep 5;
      last;
    }
  }
}

sub connect {
  my ($this) = @_;

  my $maxConnectRetries = 3;
  my $tries;

  for ($tries = 1; $tries <= $maxConnectRetries; $tries++) {
    eval {
      $this->{solr} = WebService::Solr->new($this->{url}, {
        autocommit=>0,
      }); 

      # SMELL: WebServices::Solr somehow does not degrade nicely
      if ($this->{solr}->ping()) {
        #$this->log("got ping reply");
      } else {
        $this->log("WARNING: can't ping solr");
        $this->{solr} = undef;
      }
    };

    if ($@) {
      $this->log("ERROR: can't contact solr server: $@");
      $this->{solr} = undef;
    };

    last if $this->{solr};
    sleep 2;
  }


  return $this->{solr};
}

sub log {
  my ($this, $logString, $noNewLine) = @_;

  print STDERR "$logString".($noNewLine?'':"\n");
  #Foswiki::Func::writeDebug($logString);
}

sub isSkippedWeb {
  my ($this, $web) = @_;

  my $skipwebs = $this->skipWebs;
  $web =~ s/\//\./g;

  # check all parent webs
  for (my @webName = split(/\./, $web); @webName; pop @webName) {
    return 1 if $skipwebs->{ join('.', @webName) };
  }

  return 0;
}

sub isSkippedTopic {
  my ($this, $web, $topic) = @_;

  my $skipTopics = $this->skipTopics;
  return 1 if $skipTopics->{"$web.$topic"} || $skipTopics->{$topic};

  return 0;
}

sub isSkippedAttachment {
  my ($this, $web, $topic, $attachment) = @_;
 
  return 1 if $web && $this->isSkippedWeb($web);
  return 1 if $topic && $this->isSkippedTopic($web, $topic);
 
  my $skipattachments = $this->skipAttachments;
 
  return 1 if $skipattachments->{"$attachment"};
  return 1 if $topic && $skipattachments->{"$topic.$attachment"};
  return 1 if $web && $topic && $skipattachments->{"$web.$topic.$attachment"};
 
  return 0;
}

# List of webs that shall not be indexed
sub skipWebs {
  my $this = shift;

  my $skipwebs = $this->{_skipwebs};

  unless (defined $skipwebs) {
    $skipwebs = {};
    my $to_skip = $Foswiki::cfg{SolrPlugin}{SkipWebs} || "Trash, Sandbox";
    foreach my $tmpweb (split(/\s*,\s*/, $to_skip)) {
      $skipwebs->{$tmpweb} = 1;
    }
    $this->{_skipwebs} = $skipwebs;
  }

  return $skipwebs;
}

# List of attachments to be skipped.
sub skipAttachments {
  my $this = shift;

  my $skipattachments = $this->{_skipattachments};

  unless (defined $skipattachments) {
    $skipattachments = {};
    my $to_skip = $Foswiki::cfg{SolrPlugin}{SkipAttachments} || '';
    foreach my $tmpattachment (split(/\s*,\s*/, $to_skip)) {
      $skipattachments->{$tmpattachment} = 1;
    }
    $this->{_skipattachments} = $skipattachments;
  }

  return $skipattachments;
}

# List of topics to be skipped.
sub skipTopics {
  my $this = shift;

  my $skiptopics = $this->{_skiptopics};

  unless (defined $skiptopics) {
    $skiptopics = {};
    my $to_skip = $Foswiki::cfg{SolrPlugin}{SkipTopics} || '';
    foreach my $t (split(/\s*,\s*/, $to_skip)) {
      $skiptopics->{$t} = 1;
    }
    $this->{_skiptopics} = $skiptopics;
  }

  return $skiptopics;
}

# List of file extensions to be stringified
sub indexExtensions {
  my $this = shift;

  my $indexextensions = $this->{_indexextensions};

  unless (defined $indexextensions) {
    $indexextensions = {};
    my $extensions = $Foswiki::cfg{SolrPlugin}{IndexExtensions} || 
      "txt, html, xml, doc, docx, xls, xlsx, ppt, pptx, pdf";
    foreach my $tmpextension (split(/\s*,\s*/, $extensions)) {
      $indexextensions->{$tmpextension} = 1;
    }

    $this->{_indexextensions} = $indexextensions;
  }

  return $indexextensions;
}

sub inlineError {
  my ($this, $text) = @_;
  return "<span class='foswikiAlert'>$text</span>";
}

sub toUtf8 {
  my ($this, $text) = @_;

  $text = Unicode::MapUTF8::to_utf8(-string=>$text, -charset=>$Foswiki::cfg{Site}{CharSet})
    if $Foswiki::cfg{Site}{CharSet} !~ /^utf-?8$/i;

  return $text;
}

sub fromUtf8 {
  my ($this, $text) = @_;

  $text = Unicode::MapUTF8::from_utf8(-string=>$text, -charset=>$Foswiki::cfg{Site}{CharSet})
    if $Foswiki::cfg{Site}{CharSet} !~ /^utf-?8$/i;

  return $text;
}

# sub fromUtf8 {
#   my ($this, $utf8string) = @_;
#
#   my $charset = $Foswiki::cfg{Site}{CharSet};
#   return $utf8string if $charset =~ /^utf-?8$/i;
#
#   if ($] < 5.008) {
#
#     # use Unicode::MapUTF8 for Perl older than 5.8
#     require Unicode::MapUTF8;
#     if (Unicode::MapUTF8::utf8_supported_charset($charset)) {
#       return Unicode::MapUTF8::from_utf8({ -string => $utf8string, -charset => $charset });
#     } else {
#       $this->log('Warning: Conversion from $encoding no supported, ' . 'or name not recognised - check perldoc Unicode::MapUTF8');
#       return $utf8string;
#     }
#   } else {
#
#     # good Perl version, just use Encode
#     require Encode;
#     import Encode;
#     my $encoding = Encode::resolve_alias($charset);
#     if (not $encoding) {
#       $this->log('Warning: Conversion to "' . $charset . '" not supported, or name not recognised - check ' . '"perldoc Encode::Supported"');
#       return $utf8string;
#     } else {
#
#       # converts to $charset, generating HTML NCR's when needed
#       my $octets = Encode::decode('utf-8', $utf8string);
#       return Encode::encode($encoding, $octets, &Encode::FB_HTMLCREF());
#     }
#   }
# }
#
# sub toUtf8 {
#   my ($this, $string) = @_;
#
#   my $charset = $Foswiki::cfg{Site}{CharSet};
#   return $string if $charset =~ /^utf-?8$/i;
#
#   if ($] < 5.008) {
#
#     # use Unicode::MapUTF8 for Perl older than 5.8
#     require Unicode::MapUTF8;
#     if (Unicode::MapUTF8::utf8_supported_charset($charset)) {
#       return Unicode::MapUTF8::to_utf8({ -string => $string, -charset => $charset });
#     } else {
#       $this->log('Warning: Conversion from $encoding no supported, ' . 'or name not recognised - check perldoc Unicode::MapUTF8');
#       return $string;
#     }
#   } else {
#
#     # good Perl version, just use Encode
#     require Encode;
#     import Encode;
#     my $encoding = Encode::resolve_alias($charset);
#     if (not $encoding) {
#       $this->log('Warning: Conversion to "' . $charset . '" not supported, or name not recognised - check ' . '"perldoc Encode::Supported"');
#       return undef;
#     } else {
#       my $octets = Encode::decode($encoding, $string, &Encode::FB_PERLQQ());
#       return Encode::encode('utf-8', $octets);
#     }
#   }
# }

1;
