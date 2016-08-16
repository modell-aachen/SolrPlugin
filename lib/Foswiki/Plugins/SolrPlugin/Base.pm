# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2015 Michael Daum http://michaeldaumconsulting.com
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
use Foswiki::Plugins::SolrPlugin ();
use WebService::Solr ();
use Error qw( :try );
use Encode ();

our $STARTWW = qr/^|(?<=[\s\(])/m;
our $ENDWW = qr/$|(?=[\s,.;:!?)])/m;

##############################################################################
sub new {
  my $class = shift;
  my $session = shift;

  $session ||= $Foswiki::Plugins::SESSION;

  my $this = {
    session => $session,
    url => $Foswiki::cfg{SolrPlugin}{Url},    # || 'http://localhost:8983',
    wikiHost => $Foswiki::cfg{SolrPlugin}{WikiHost} || 'foswiki',
    wikiHostMap => $Foswiki::cfg{SolrPlugin}{WikiHostMap} || {},
    timeout => $Foswiki::cfg{SolrPlugin}{Timeout},
    optimizeTimeout => $Foswiki::cfg{SolrPlugin}{OptimizeTimeout},
    @_
  };
  bless($this, $class);

  $this->{timeout} = 180 unless defined $this->{timeout};
  $this->{optimizeTimeout} = 600 unless defined $this->{optimizeTimeout};

  return $this;
}

##############################################################################
sub connect {
  my ($this) = @_;

  my $maxConnectRetries = 1; # ... was 3 before;
  my $tries;

  for ($tries = 1; $tries <= $maxConnectRetries; $tries++) {
    eval {
      $this->{solr} = WebService::Solr->new($this->{url}, {
        agent => LWP::UserAgent->new(
          agent => "Foswiki-SolrPlugin/$Foswiki::Plugins::SolrPlugin::VERSION",
          timeout => $this->{timeout},
          keep_alive => 1
        ),
        autocommit => 0,
      });
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

  return "" unless defined $text;
  $text =~ s/&#(\d+);/chr($1)/ge;

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
  my ($this, $type, $size) = @_;

  $size ||= 16;

  my $pubUrlPath = $Foswiki::cfg{PubUrlPath}.'/'.$Foswiki::cfg{SystemWebName}.'/FamFamFamSilkIcons/';

  # some specific icons
  return $pubUrlPath.'page_white_edit.png' if $type =~ /topic/i;
  return $pubUrlPath.'comment.png' if $type =~ /comment/i;

  if (Foswiki::Func::getContext()->{MimeIconPluginEnabled}) {
    require Foswiki::Plugins::MimeIconPlugin;
    my ($iconName, $iconPath) = Foswiki::Plugins::MimeIconPlugin::getIcon($type, "oxygen", $size);
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

  if (!defined($topicTitle) || $topicTitle eq '') {
    if ($topic eq $Foswiki::cfg{HomeTopicName}) {
      $topicTitle = $web;
    } else {
      $topicTitle = $topic;
    }
  }

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

  return '' unless defined $summary;

  $summary = $this->plainify($summary, $web, $topic);
  $summary =~ s/\n/ /g;

  return $summary;
}

################################################################################
# wrapper around Foswiki::Func::getScriptUrlPath
# that really, _really_, __really__ returns a relative path even when
# called from the command line
sub getScriptUrlPath {
  my $this = shift;

  my $url = Foswiki::Func::getScriptUrlPath(@_);

  $url =~ s/^$this->{session}{urlHost}//;

  return $url;
}

################################################################################
sub plainify {
  my ($this, $text, $web, $topic) = @_;

  return '' unless defined $text;

  my $wtn = Foswiki::Func::getPreferencesValue('WIKITOOLNAME') || '';

  # from Foswiki:Extensions/GluePlugin
  $text =~ s/^#~~(.*?)$//gom;    # #~~
  $text =~ s/%~~\s+([A-Z]+[{%])/%$1/gos;    # %~~
  $text =~ s/\s*[\n\r]+~~~\s+/ /gos;        # ~~~
  $text =~ s/\s*[\n\r]+\*~~\s+//gos;        # *~~

  # from Fosiki::Render
  $text =~ s/\r//g;                         # SMELL, what about OS10?
  $text =~ s/%META:[A-Z].*?\}%//g;

  $text =~ s/%WEB%/$web/g;
  $text =~ s/%TOPIC%/$topic/g;
  $text =~ s/%WIKITOOLNAME%/$wtn/g;
  $text =~ s/%$Foswiki::regex{tagNameRegex}(\{.*?\})?%//g;  # remove

  # Format e-mail to add spam padding (HTML tags removed later)
  $text =~ s/$STARTWW((mailto\:)?[a-zA-Z0-9-_.+]+@[a-zA-Z0-9-_.]+\.[a-zA-Z0-9-_]+)$ENDWW//gm;
  $text =~ s/<!--.*?-->//gs;                                # remove all HTML comments
  $text =~ s/<(?!nop)[^>]*>/ /g;                            # remove all HTML tags except <nop>

  # SMELL: these should have been processed by entityDecode() before
  $text =~ s/&#\d+;/ /g;                                    # remove html entities
  $text =~ s/&[a-z]+;/ /g;                                  # remove entities

  # keep only link text of legacy [[prot://uri.tld/ link text]]
  $text =~ s/
          \[
              \[$Foswiki::regex{linkProtocolPattern}\:
                  ([^\s<>"\]]+[^\s*.,!?;:)<|\]])
                      \s+([^\[\]]*?)
              \]
          \]/$3/gx;

  # remove brackets from [[][]] links
  $text =~ s/\[\[([^\]]*\]\[)(.*?)\]\]/$1 $2/g;

  # remove "Web." prefix from "Web.TopicName" link
  $text =~ s/$STARTWW(($Foswiki::regex{webNameRegex})\.($Foswiki::regex{wikiWordRegex}|$Foswiki::regex{abbrevRegex}))/$3/g;
  $text =~ s/[\[\]\*\|=_\&\<\>]/ /g;    # remove Wiki formatting chars
  $text =~ s/^\-\-\-+\+*\s*\!*/ /gm;    # remove heading formatting and hbar
  $text =~ s/[\+\-]+/ /g;               # remove special chars
  $text =~ s/^\s+//;                    # remove leading whitespace
  $text =~ s/\s+$//;                    # remove trailing whitespace
  $text =~ s/!(\w+)/$1/gs;              # remove all nop exclamation marks before words
  $text =~ s/[\r\n]+/\n/gs;
  $text =~ s/[ \t]+/ /gs;

  # remove/escape special chars
  $text =~ s/\\//g;
  $text =~ s/"//g;
  $text =~ s/%\{//g;
  $text =~ s/\}%//g;
  $text =~ s/%//g;
  $text =~ s/\{\s*\}//g;
  $text =~ s/#+//g;
  $text =~ s/\$perce?nt//g;
  $text =~ s/\$dollar//g;
  $text =~ s/~~~/ /g;
  $text =~ s/^$//gs;

  return $this->discardIllegalChars($text);
}

################################################################################
sub escapeHtml {
  my ($this, $string) = @_;

  $string =~ s/<!--.*?-->//gs;
  $string =~ s/</&lt;/g;
  $string =~ s/>/&gt;/g;
  $string =~ s/"/&quot;/g;
  $string =~ s/'/&#39;/g;
  $string = $this->discardIllegalChars($string);

  return $string;
}

################################################################################
sub discardIllegalChars {
  my ($this, $string) = @_;

  # remove illegal characters
  $string =~ s/\p{C}/ /g;

  return $string;
}

##############################################################################
sub fromSiteCharSet {
  my $this = shift;
  return Encode::decode($Foswiki::cfg{Site}{CharSet}, $_[0]);
}

##############################################################################
sub toSiteCharSet {
  my $this = shift;
  return Encode::encode($Foswiki::cfg{Site}{CharSet}, $_[0]);
}

##############################################################################
sub fromUtf8 {
  my $this = shift;
  return Encode::decode_utf8($_[0]);
}

##############################################################################
sub toUtf8 {
  my ($this, $string) = @_;

#  my $charset = $Foswiki::cfg{Site}{CharSet};
#  $string = Encode::decode($charset, $string);
  return Encode::encode('utf-8', $string);
}

##############################################################################
sub buildHostFilter {
  my ($this, $skipMapping) = @_;
  my $host = $this->{wikiHost};
  return "host:$host" if $skipMapping;

  my $mapping = $this->{wikiHostMap};
  my @filters = "host:$host";
  while (my ($k, $v) = each %$mapping) {
    push @filters, "(web:$k host:$v)";
  }

  "(". join(" OR ", @filters) .")";
}

1;
