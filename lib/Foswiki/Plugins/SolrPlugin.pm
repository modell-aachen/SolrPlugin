# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2010 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Foswiki::Plugins::SolrPlugin;

use strict;
use Foswiki::Func ();
use Foswiki::Plugins ();
  
our $VERSION = '$Rev: 20091124 (2009-11-24) $';
our $RELEASE = '1.03';
our $SHORTDESCRIPTION = 'Enterprise Search Engine for Foswiki based on [[http://lucene.apache.org/solr/][Solr]]';
our $NO_PREFS_IN_TOPIC = 1;
our $baseWeb;
our $baseTopic;
our $searcher;
our $indexer;
our @knownIndexTopicHandler;
our @knownIndexAttachmentHandler;

sub initPlugin {
  ($baseTopic, $baseWeb) = @_;

  $searcher = undef;
  $indexer = undef;

  Foswiki::Func::registerTagHandler('SOLRSEARCH', \&SOLRSEARCH);
  Foswiki::Func::registerTagHandler('SOLRFORMAT', \&SOLRFORMAT);
  Foswiki::Func::registerTagHandler('SOLRSIMILAR', \&SOLRSIMILAR);
  Foswiki::Func::registerTagHandler('SOLRSCRIPTURL', \&SOLRSCRIPTURL);
  Foswiki::Func::registerRESTHandler('search', \&restSOLRSEARCH);
  Foswiki::Func::registerRESTHandler('terms', \&restSOLRTERMS);
  Foswiki::Func::registerRESTHandler('similar', \&restSOLRSIMILAR);
  Foswiki::Func::registerRESTHandler('autocomplete', \&restSOLRAUTOCOMPLETE);
  Foswiki::Func::registerRESTHandler('optimize', \&restOPTIMIZE);

  return 1;
}

sub registerIndexTopicHandler {
  push @knownIndexTopicHandler, shift;
}

sub registerIndexAttachmentHandler {
  push @knownIndexAttachmentHandler, shift;
}

sub getSearcher {

  unless ($searcher) {
    require Foswiki::Plugins::SolrPlugin::Search;
    $searcher = Foswiki::Plugins::SolrPlugin::Search->new(@_);
  }

  return $searcher;
}

sub getIndexer {

  unless ($indexer) {
    require Foswiki::Plugins::SolrPlugin::Index;
    $indexer = Foswiki::Plugins::SolrPlugin::Index->new(@_);
  }

  return $indexer;
}

sub SOLRSEARCH {
  my ($session, $params, $theTopic, $theWeb) = @_;

  return getSearcher($session)->handleSOLRSEARCH($params, $theWeb, $theTopic);
}

sub SOLRFORMAT {
  my ($session, $params, $theTopic, $theWeb) = @_;

  return getSearcher($session)->handleSOLRFORMAT($params, $theWeb, $theTopic);
}

sub SOLRSIMILAR {
  my ($session, $params, $theTopic, $theWeb) = @_;

  return getSearcher($session)->handleSOLRSIMILAR($params, $theWeb, $theTopic);
}

sub SOLRSCRIPTURL {
  my ($session, $params, $theTopic, $theWeb) = @_;

  return getSearcher($session)->handleSOLRSCRIPTURL($params, $theWeb, $theTopic);
}


sub restOPTIMIZE {
  my $session = shift;

  getIndexer($session)->optimize();
}


sub restSOLRSEARCH {
  my $session = shift;

  my $web = $session->{webName};
  my $topic = $session->{topicName};
  return getSearcher($session)->restSOLRSEARCH($web, $topic);
}

sub restSOLRTERMS {
  my $session = shift;

  my $web = $session->{webName};
  my $topic = $session->{topicName};
  return getSearcher($session)->restSOLRTERMS($web, $topic);
}

sub restSOLRSIMILAR {
  my $session = shift;

  my $web = $session->{webName};
  my $topic = $session->{topicName};
  return getSearcher($session)->restSOLRSIMILAR($web, $topic);
}

sub restSOLRAUTOCOMPLETE {
  my $session = shift;

  my $web = $session->{webName};
  my $topic = $session->{topicName};
  return getSearcher($session)->restSOLRAUTOCOMPLETE($web, $topic);
}

sub indexCgi {
  my $session = shift;

  return getIndexer($session)->index();
}

sub searchCgi {
  my $session = shift;

  my $request = $session->{cgiQuery} || $session->{request};
  my $template = $Foswiki::cfg{SolrPlugin}{SearchTemplate} || 'System.SolrSearchView';

  my $result = Foswiki::Func::readTemplate($template);
  $result = Foswiki::Func::expandCommonVariables($result);
  $result = Foswiki::Func::renderText($result);

  $session->writeCompletePage($result, 'view');
}

sub afterSaveHandler {
  return unless $Foswiki::cfg{SolrPlugin}{EnableOnSaveUpdates};

  my ($text, $topic, $web, $error, $meta) = @_;
  getIndexer()->afterSaveHandler($web, $topic, $meta, $text);
}

# Foswiki >= 1.1
sub afterUploadHandler {
  return unless $Foswiki::cfg{SolrPlugin}{EnableOnUploadUpdates};
  getIndexer()->afterUploadHandler(@_);
}

sub afterRenameHandler {
  return unless $Foswiki::cfg{SolrPlugin}{EnableOnRenameUpdates};
  getIndexer()->afterRenameHandler(@_);
}

sub finishPlugin {
  $indexer->finish() if $indexer;

  @knownIndexTopicHandler = ();

  if ($searcher) {
    my $url = $searcher->{redirectUrl};
    if ($url) {
      #print STDERR "found redirect $url\n";
      Foswiki::Func::redirectCgiQuery(undef, $url);
    }
  }
}

1;
