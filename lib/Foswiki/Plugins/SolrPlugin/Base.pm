# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2012 Michael Daum http://michaeldaumconsulting.com
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
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use WebService::Solr ();
use Error qw( :try );
use Encode ();
use HTML::Entities ();

BEGIN {
  if ($Foswiki::cfg{Site}{CharSet} =~ /^utf-?8$/i) {
    $WebService::Solr::ENCODE = 0;    # don't encode to utf8 in WebService::Solr
  }
}

##############################################################################
sub new {
  my $class = shift;
  my $session = shift;

  $session ||= $Foswiki::Plugins::SESSION;

  my $this = {
    session => $session,
    url => $Foswiki::cfg{SolrPlugin}{Url},    # || 'http://localhost:8983',
    @_
  };
  bless($this, $class);

  return $this;
}

##############################################################################
sub startDaemon {
  my ($this) = @_;

  my $maxStartRetries = 3;

  my $toolsDir = $Foswiki::cfg{ToolsDir} || $Foswiki::cfg{WorkingDir} . "/../tools";    # try to cope with old foswikis w/o a ToolsDir setting
  my $autoStartCmd = $Foswiki::cfg{SolrPlugin}{SolrStartCmd} || $toolsDir . '/solrstart %SOLRHOME|F%';
  my $solrHome = $Foswiki::cfg{SolrPlugin}{SolrHome} || $Foswiki::cfg{WorkingDir} . "/../solr";

  for (my $tries = 1; $tries <= $maxStartRetries; $tries++) {

    # trying to autostart
    $this->log("autostarting solr at $solrHome");

    unless (-f $solrHome . "/start.jar") {
      $this->log("ERROR: start.jar not found ... aborting autostart");
      last;
    }

    my ($stdout, $exit, $stderr) = Foswiki::Sandbox::sysCommand(undef, $autoStartCmd, SOLRHOME => $solrHome);

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

##############################################################################
sub connect {
  my ($this) = @_;

  my $maxConnectRetries = 3;
  my $tries;

  for ($tries = 1; $tries <= $maxConnectRetries; $tries++) {
    eval {
      $this->{solr} = WebService::Solr->new($this->{url}, { autocommit => 0, });

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
    }

    last if $this->{solr};
    sleep 2;
  }

  return $this->{solr};
}

##############################################################################
sub log {
  my ($this, $logString, $noNewLine) = @_;

  print STDERR "$logString" . ($noNewLine ? '' : "\n");

  #Foswiki::Func::writeDebug($logString);
}

##############################################################################
sub isDateField {
  my ($this, $name) = @_;

  return ($name =~ /^((.*_dt)|createdate|date|timestamp)$/) ? 1 : 0;
}

##############################################################################
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

##############################################################################
sub isSkippedTopic {
  my ($this, $web, $topic) = @_;

  my $skipTopics = $this->skipTopics;
  return 1 if $skipTopics->{"$web.$topic"} || $skipTopics->{$topic};

  return 0;
}

##############################################################################
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

##############################################################################
sub isSkippedExtension {
  my ($this, $fileName) = @_;

  my $indexExtensions = $this->indexExtensions;

  my $extension = '';
  if ($fileName =~ /^(.+)\.(\w+?)$/) {
    $extension = lc($2);
  }
  $extension = 'jpg' if $extension =~ /jpe?g/i;

  return 0 if $indexExtensions->{$extension};
  return 1;
}

##############################################################################
# List of webs that shall not be indexed
sub skipWebs {
  my $this = shift;

  my $skipwebs = $this->{_skipwebs};

  unless (defined $skipwebs) {
    $skipwebs = {};

    my $to_skip = $Foswiki::cfg{SolrPlugin}{SkipWebs}
      || "Trash, TWiki, TestCases";

    foreach my $tmpweb (split(/\s*,\s*/, $to_skip)) {
      $skipwebs->{$tmpweb} = 1;
    }

    $this->{_skipwebs} = $skipwebs;
  }

  return $skipwebs;
}

##############################################################################
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

##############################################################################
# List of topics to be skipped.
sub skipTopics {
  my $this = shift;

  my $skiptopics = $this->{_skiptopics};

  unless (defined $skiptopics) {
    $skiptopics = {};
    my $to_skip = $Foswiki::cfg{SolrPlugin}{SkipTopics}
      || 'WebRss, WebSearch, WebStatistics, WebTopicList, WebLeftBar, WebPreferences, WebSearchAdvanced, WebIndex, WebAtom, WebChanges, WebCreateNewTopic, WebNotify';
    foreach my $t (split(/\s*,\s*/, $to_skip)) {
      $skiptopics->{$t} = 1;
    }
    $this->{_skiptopics} = $skiptopics;
  }

  return $skiptopics;
}

##############################################################################
# List of file extensions to be stringified
sub indexExtensions {
  my $this = shift;

  my $indexextensions = $this->{_indexextensions};

  unless (defined $indexextensions) {
    $indexextensions = {};
    my $extensions = $Foswiki::cfg{SolrPlugin}{IndexExtensions}
      || "txt, html, xml, doc, docx, xls, xlsx, ppt, pptx, pdf, odt";
    foreach my $tmpextension (split(/\s*,\s*/, $extensions)) {
      $indexextensions->{$tmpextension} = 1;
    }

    $this->{_indexextensions} = $indexextensions;
  }

  return $indexextensions;
}

##############################################################################
sub inlineError {
  my ($this, $text) = @_;
  return "<span class='foswikiAlert'>$text</span>";
}

##############################################################################
sub entityDecode {
  my ($this, $text) = @_;

  my $charset = $Foswiki::cfg{Site}{CharSet};
  $text = Encode::decode($charset, $text);
  $text = HTML::Entities::decode_entities($text);
  $text = Encode::encode($charset, $text);

  return $text;
}

##############################################################################
sub urlDecode {
  my ($this, $text) = @_;

  # SMELL: not utf8-safe
  $text =~ s/%([\da-f]{2})/chr(hex($1))/gei;

  return $text;
}

###############################################################################
sub normalizeWebTopicName {
  my ($this, $web, $topic) = @_;

  # better defaults
  $web ||= $this->{session}->{webName};
  $topic ||= $this->{session}->{topicName};

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  $web =~ s/\//\./g;    # normalize web using dots all the way

  return ($web, $topic);
}

###############################################################################
# compatibility wrapper
sub takeOutBlocks {
  my $this = shift;

  return Foswiki::takeOutBlocks(@_) if defined &Foswiki::takeOutBlocks;
  return $this->{session}->renderer->takeOutBlocks(@_);
}

###############################################################################
# compatibility wrapper
sub putBackBlocks {
  my $this = shift;

  return Foswiki::putBackBlocks(@_) if defined &Foswiki::putBackBlocks;
  return $this->{session}->renderer->putBackBlocks(@_);
}

##############################################################################
sub mapToIconFileName {
  my ($this, $type) = @_;

  my $pubUrlPath = $Foswiki::cfg{PubUrlPath}.'/'.$Foswiki::cfg{SystemWebName}.'/FamFamFamSilkIcons/';

  # some specific icons
  return $pubUrlPath.'page_white_edit.png' if $type =~ /topic/i;
  return $pubUrlPath.'comment.png' if $type =~ /comment/i;

  if (Foswiki::Func::getContext()->{MimeIconPluginEnabled}) {
    require Foswiki::Plugins::MimeIconPlugin;
    my ($iconName, $iconPath) = Foswiki::Plugins::MimeIconPlugin::getIcon($type, "oxygen", 16);
    return $iconPath;
  } 

  return $pubUrlPath.'picture.png' if $type =~ /(jpe?g)|gif|png/i;
  return $pubUrlPath.'compress.png' if $type =~ /zip|tar|tar|rar/i;
  return $pubUrlPath.'page_white_acrobat.png' if $type =~ /pdf/i;
  return $pubUrlPath.'page_excel.png' if $type =~ /xlsx?/i;
  return $pubUrlPath.'page_word.png' if $type =~ /docx?/i;
  return $pubUrlPath.'page_white_powerpoint.png' if $type =~ /pptx?/i;
  return $pubUrlPath.'page_white_flash.png' if $type =~ /flv|swf/i;

  return $pubUrlPath.'page_white.png';
}

##############################################################################
sub getTopicTitle {
  my ($this, $web, $topic, $meta) = @_;

  my $topicTitle = '';

  unless ($meta) {
    ($meta) = Foswiki::Func::readTopic($web, $topic);
  }

  my $field = $meta->get('FIELD', 'TopicTitle');
  $topicTitle = $field->{value} if $field && $field->{value};

  unless ($topicTitle) {
    $field = $meta->get('PREFERENCE', 'TOPICTITLE');
    $topicTitle = $field->{value} if $field && $field->{value};
  }

  $topicTitle ||= $topic;

  # bit of cleanup
  $topicTitle =~ s/<!--.*?-->//g;

  return $topicTitle;
}

##############################################################################
sub getTopicSummary {
  my ($this, $web, $topic, $meta, $text) = @_;

  my $summary = '';

  unless ($meta) {
    ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
  }
  
  my $field = $meta->get('FIELD', 'Summary');
  $summary = $field->{value} if $field && $field->{value};

  unless ($summary) {
    $field = $meta->get('FIELD', 'Teaser');
    $summary = $field->{value} if $field && $field->{value};
  }

  unless ($summary) {
    $field = $meta->get('PREFERENCE', 'SUMMARY');
    $summary = $field->{value} if $field && $field->{value};
  }

  $summary = $this->plainify($summary, $web, $topic);
  $summary = unicode_substr($text, 0, 300) unless $summary;

  return $summary;
}

################################################################################
sub unicode_substr {
  my ($string, $offset, $length) = @_;

  my $charset = $Foswiki::cfg{Site}{CharSet};

  $string = Encode::decode($charset, $string);
  $string = substr($string, $offset, $length);
  $string = Encode::encode($charset, $string);

  return $string;
}


1;
