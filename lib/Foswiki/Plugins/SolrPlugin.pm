# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2013 Michael Daum http://michaeldaumconsulting.com
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
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Error qw(:try);
  
our $VERSION = '2.00';
our $RELEASE = '2.00';
our $SHORTDESCRIPTION = 'Enterprise Search Engine for Foswiki based on [[http://lucene.apache.org/solr/][Solr]]';
our $NO_PREFS_IN_TOPIC = 1;
our %searcher;
our %indexer;
our %hierarchy;
our @knownIndexTopicHandler = ();
our @knownIndexAttachmentHandler = ();

sub initPlugin {

  Foswiki::Func::registerTagHandler('SOLRSEARCH', sub {
    my ($session, $params, $theTopic, $theWeb) = @_;

    return getSearcher($session)->handleSOLRSEARCH($params, $theWeb, $theTopic);
  });


  Foswiki::Func::registerTagHandler('SOLRFORMAT', sub {
    my ($session, $params, $theTopic, $theWeb) = @_;

    return getSearcher($session)->handleSOLRFORMAT($params, $theWeb, $theTopic);
  });


  Foswiki::Func::registerTagHandler('SOLRSIMILAR', sub {
    my ($session, $params, $theTopic, $theWeb) = @_;

    return getSearcher($session)->handleSOLRSIMILAR($params, $theWeb, $theTopic);
  });

  Foswiki::Func::registerTagHandler('SOLRSCRIPTURL', sub {
    my ($session, $params, $theTopic, $theWeb) = @_;

    return getSearcher($session)->handleSOLRSCRIPTURL($params, $theWeb, $theTopic);
  });


  Foswiki::Func::registerRESTHandler('search', sub {
    my $session = shift;

    my $web = $session->{webName};
    my $topic = $session->{topicName};
    return getSearcher($session)->restSOLRSEARCH($web, $topic);
  });

  Foswiki::Func::registerRESTHandler('proxy', sub {
    my $session = shift;

    my $web = $session->{webName};
    my $topic = $session->{topicName};
    return getSearcher($session)->restSOLRPROXY($web, $topic);
  });


  Foswiki::Func::registerRESTHandler('similar', sub {
    my $session = shift;

    my $web = $session->{webName};
    my $topic = $session->{topicName};
    return getSearcher($session)->restSOLRSIMILAR($web, $topic);
  });

  Foswiki::Func::registerRESTHandler('autocomplete', sub {
    my $session = shift;

    my $web = $session->{webName};
    my $topic = $session->{topicName};
    return getSearcher($session)->restSOLRAUTOCOMPLETE($web, $topic);
  });

  Foswiki::Func::registerRESTHandler('autosuggest', sub {
    my $session = shift;

    my $web = $session->{webName};
    my $topic = $session->{topicName};
    return getSearcher($session)->restSOLRAUTOSUGGEST($web, $topic);
  });

  Foswiki::Func::registerRESTHandler('webHierarchy', sub {
    my $session = shift;

    return getWebHierarchy($session)->restWebHierarchy(@_);
  });

  Foswiki::Func::registerRESTHandler('optimize', sub {
    my $session = shift;
    return getIndexer($session)->optimize();
  });

  Foswiki::Func::registerRESTHandler('crawl', sub {
    my $session = shift;

    my $query = Foswiki::Func::getCgiQuery();
    my $name = $query->param("name");
    my $path = $query->param("path");
    my $depth = $query->param("depth");

    return getCrawler($session, $name)->crawl($path, $depth);
  });

  if ($Foswiki::cfg{Plugins}{TaskDaemonPlugin}{Enabled}) {
    Foswiki::Func::registerRESTHandler('index', \&_restIndex);
  }

  Foswiki::Func::addToZone("script", "SOLRPLUGIN::SEARCHBOX", <<'HERE', "JQUERYPLUGIN");
<script src='%PUBURLPATH%/%SYSTEMWEB%/SolrPlugin/solr-searchbox.js'></script> 
HERE

  return 1;
}

sub registerIndexTopicHandler {
  push @knownIndexTopicHandler, shift;
}

sub registerIndexAttachmentHandler {
  push @knownIndexAttachmentHandler, shift;
}

sub getWebHierarchy {

  my $handler = $hierarchy{$Foswiki::cfg{DefaultUrlHost}};
  unless ($handler) {
    require Foswiki::Plugins::SolrPlugin::WebHierarchy;
    $handler = $hierarchy{$Foswiki::cfg{DefaultUrlHost}} = Foswiki::Plugins::SolrPlugin::WebHierarchy->new(@_);
  }

  return $handler;
}


sub getSearcher {

  my $searcher = $searcher{$Foswiki::cfg{DefaultUrlHost}};
  unless ($searcher) {
    require Foswiki::Plugins::SolrPlugin::Search;
    $searcher = $searcher{$Foswiki::cfg{DefaultUrlHost}} = Foswiki::Plugins::SolrPlugin::Search->new(@_);
  }

  return $searcher;
}

sub getIndexer {

  my $indexer = $indexer{$Foswiki::cfg{DefaultUrlHost}};
  unless ($indexer) {
    require Foswiki::Plugins::SolrPlugin::Index;
    $indexer = $indexer{$Foswiki::cfg{DefaultUrlHost}} = Foswiki::Plugins::SolrPlugin::Index->new(@_);
  }

  return $indexer;
}

sub getCrawler {
  my ($session , $name) = @_;

  throw Error::Simple("no crawler name") unless defined $name;
    
  my $params = $Foswiki::cfg{SolrPlugin}{Crawler}{$name};

  throw Error::Simple("unknown crawler $name") unless defined $params;

  my $module = $params->{module};
  eval "use $module";
  if ($@) {
    throw Error::Simple($@);
  }

  return $module->new($session, %$params);
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

sub _dispatchGrinderHandler {
  my $handler = [caller(1)]->[3]; # subroutine
  $handler =~ s/.*:://;
  return unless $Foswiki::cfg{Plugins}{TaskDaemonPlugin}{Enabled};
  require Foswiki::Plugins::SolrPlugin::GrinderDispatch;
  no strict 'refs';
  &{"Foswiki::Plugins::SolrPlugin::GrinderDispatch::$handler"}(@_);
}

sub beforeSaveHandler {
  &_dispatchGrinderHandler;
}

sub afterSaveHandler {
  &_dispatchGrinderHandler;
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
  &_dispatchGrinderHandler;
  return unless $Foswiki::cfg{SolrPlugin}{EnableOnRenameUpdates};
  getIndexer()->afterRenameHandler(@_);
}

sub completePageHandler {
    &_dispatchGrinderHandler;
}

sub _restIndex {
    &_dispatchGrinderHandler;
}

sub finishPlugin {

  my $indexer = $indexer{$Foswiki::cfg{DefaultUrlHost}};
  $indexer->finish() if $indexer;

  my $searcher = $searcher{$Foswiki::cfg{DefaultUrlHost}};
  if ($searcher) {
    #print STDERR "searcher keys=".join(", ", sort keys %$searcher)."\n";
    my $url = $searcher->{redirectUrl};
    if ($url) {
      #print STDERR "found redirect $url\n";
      Foswiki::Func::redirectCgiQuery(undef, $url);
    }
  }

  @knownIndexTopicHandler = ();
  @knownIndexAttachmentHandler = ();

  undef $indexer{$Foswiki::cfg{DefaultUrlHost}};
  undef $searcher{$Foswiki::cfg{DefaultUrlHost}};
  undef $hierarchy{$Foswiki::cfg{DefaultUrlHost}};
}

1;
