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

package Foswiki::Plugins::SolrPlugin::Search;
use strict;

use Foswiki::Plugins::SolrPlugin::Base ();
our @ISA = qw( Foswiki::Plugins::SolrPlugin::Base );

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Plugins::JQueryPlugin ();
use POSIX ();
use Error qw(:try);

use constant DEBUG => 0; # toggle me
use constant CONVERT_TOUTF8 => 1; # SMELL: I don't grok it

##############################################################################
sub handleSOLRSEARCH {
  my ($this, $params, $theWeb, $theTopic) = @_;

  #$this->log("called handleSOLRSEARCH(".$params->stringify.")") if DEBUG;
  return $this->inlineError("can't connect to solr server") unless defined $this->{solr};

  my $theId = $params->{id};
  return '' if defined $theId && defined $this->{cache}{$theId};

  my $theQuery = $params->{_DEFAULT} || $params->{search} || '';;
  $theQuery = entityDecode($theQuery);
  $params->{search} = $theQuery;
  
  my $theJump = $params->{jump} || 'off';

  if ($theJump eq 'on' && $theQuery) {
    # redirect to single-hit 
    my ($web, $topic) = Foswiki::Func::normalizeWebTopicName($theWeb, $theQuery);
    if (Foswiki::Func::topicExists($web, $topic)) {
      my $url = Foswiki::Func::getScriptUrl($web, $topic, 'view');
      $this->{redirectUrl} = $url;
      return '';
    }
  }

  my $response = $this->doSearch($theQuery, $params);
  my $result = '';

  if ($response) {
    if (defined $theId) {
      $this->{cache}{$theId} = {
          response=>$response,
          params=>$params,
      };
    } else {
      $result = $this->formatResponse($params, $theWeb, $theTopic, $response);
    }
  }

  return $result;
}

##############################################################################
sub handleSOLRFORMAT {
  my ($this, $params, $theWeb, $theTopic) = @_;

  #$this->log("called handleSOLRFORMAT(".$params->stringify.")") if DEBUG;
  return '' unless defined $this->{solr};

  my $theId = $params->{_DEFAULT} || $params->{id};
  return $this->inlineError("unknown query id") unless defined $theId;

  my $cacheEntry = $this->{cache}{$theId};
  return $this->inlineError("unknown query '$theId'") unless defined $cacheEntry;

  $params = {%{$cacheEntry->{params}}, %$params};

  my $topic = $params->{topic} || $theTopic;
  my $web = $params->{web};
  $web = $theWeb if !defined($web) || $web eq 'all';

  return $this->formatResponse($params, $web, $topic, $cacheEntry->{response});
}


##############################################################################
sub formatResponse {
  my ($this, $params, $theWeb, $theTopic, $response) = @_;

  return '' unless $response;

  my $error;
  my $gotResponse = 0;
  try {
    $gotResponse = 1 if $response->content->{response};
  } catch Error::Simple with {
    $this->log("Error parsing solr response") if DEBUG;
    $error = $this->inlineError("Error parsing solr response");
  };
  return $error if $error;
  return '' unless $gotResponse;


  #$this->log("called formatResponse()") if DEBUG;

  Foswiki::Plugins::JQueryPlugin::createPlugin("metadata");
  Foswiki::Plugins::JQueryPlugin::createPlugin("focus");
  Foswiki::Plugins::JQueryPlugin::createPlugin("autocomplete");

  Foswiki::Func::addToZone('head', "SOLRPLUGIN", <<'HERE', "JQUERYPLUGIN::AUTOCOMPLETE, JQUERYPLUGIN::FOCUS, JQUERYPLUGIN::METADATA");
<link rel='stylesheet' href='%PUBURLPATH%/%SYSTEMWEB%/SolrPlugin/solrplugin.css' type='text/css' media='all' />
HERE
  Foswiki::Func::addToZone('script', "SOLRPLUGIN", <<'HERE', "JQUERYPLUGIN::AUTOCOMPLETE, JQUERYPLUGIN::FOCUS, JQUERYPLUGIN::METADATA");
<script type='text/javascript' src='%PUBURLPATH%/%SYSTEMWEB%/SolrPlugin/solrplugin.js'></script>
HERE

  my $theFormat = $params->{format} || '';
  my $theSeparator = $params->{separator} || '';
  my $theHeader = $params->{header} || '';
  my $theFooter = $params->{footer} || '';
  my $theCorrection = $params->{correction} || 
    'Did you mean <a href=\'$url\' class=\'solrCorrection\'>%ENCODE{"$correction" type="quote"}%</a>';
  my $theInterestingHeader = $params->{header_interesting} || '';
  my $theInterestingFormat = $params->{format_interesting} || '';
  my $theInterestingSeparator = $params->{separator_interesting} || '';
  my $theInterestingFooter = $params->{footer_interesting} || '';
  my $theInterestingExclude = $params->{exclude_interesting} || '';
  my $theInterestingInclude = $params->{include_interesting} || '';
  my $theFacets = $params->{facets};
  my $theHideSingle = $params->{hidesingle} || 'off';

  my $hilites;
  if ($theFormat =~ /\$hilite/ || $theHeader =~ /\$hilite/ || $theFooter =~ /\$hilite/) {
    $hilites = $this->getHighlights($response);
  }

  my $spellcheck = '';
  if ($theFormat =~ /\$spellcheck/ || $theHeader =~ /\$spellcheck/ || $theFooter =~ /\$spellcheck/) {
    my $correction = $this->getCorrection($response);
    if ($correction) {
      my $tmp = $params->{search};
      $params->{search} = $correction;
      my $scriptUrl = $this->getScriptUrl($theWeb, $theTopic, $params, $response);
      $spellcheck = $theCorrection;
      $spellcheck =~ s/\$correction/$correction/g;
      $spellcheck =~ s/\$url/$scriptUrl/g;
    }
  }

  my $page = $this->currentPage($response);
  my $limit = $this->entriesPerPage($response);
  my @rows = ();
  my $index = $page * $limit + 1;
  my $from = $index;
  my $to = $index + $limit - 1;
  my $count = $this->totalEntries($response);
  $to = $count if $to > $count;

  #$this->log("page=$page, limit=$limit, index=$index, count=$count") if DEBUG;
  
  if ($theFormat) {
    for my $doc ($response->docs) {
      my $line = $theFormat;
      my $id = '';
      my $type = '';
      my $topic;
      my $web;
      my $summary = '';
      foreach my $field ($doc->fields) {
        my $name = $field->{name};
        my $value = $field->{value};

	$name = $this->fromUtf8($name);
	$value = $this->fromUtf8($value);

        $id = $value if $name eq 'id';
        $type = $value if $name eq 'type';
        $web = $value if $name eq 'web';
        $topic = $value if $name eq 'topic';
        $summary = $value if $name eq 'summary';

        next unless $line =~ /\$$name/g;

        $value = sprintf('%.02f', $value)
          if $name eq 'score';

        $value = Foswiki::Time::formatTime(Foswiki::Time::parseTime($value))
          if $name eq 'date' || $name =~ /_d$/;

        $value = sprintf("%.02f kb", ($value / 1024))
          if $name eq 'size' && $value =~ /^\d+$/;


        $line =~ s/\$$name\b/$value/g;
      }
      next unless Foswiki::Func::topicExists($web, $topic); # just to make sure
      my $hilite = '';
      $hilite = ($hilites->{$id} || $summary) if $id && $hilites;
      my $icon = $this->mapToIconFileName($type);
      my $itemFormat = 'attachment';
      $itemFormat = 'image' if $type =~ /^(gif|jpe?g|png|bmp)$/i;
      $itemFormat = 'topic' if $type eq 'topic';
      $itemFormat = 'comment' if $type eq 'comment';
      $line =~ s/\$format/$itemFormat/g;
      $line =~ s/\$id/$id/g;
      $line =~ s/\$icon/$icon/g;
      $line =~ s/\$index/$index/g;
      $line =~ s/\$page/$page/g;
      $line =~ s/\$limit/$limit/g;
      $line =~ s/\$hilite/$hilite/g;
      $index++;
      push(@rows, $line);
    }
  }

  my $facets = $this->getFacets($response);
  my $interestingTerms = $this->getInterestingTerms($response);

  return '' if !@rows && !$theFacets && !$theInterestingFormat;

  # format facets
  my $facetResult = '';
  if ($facets) {

    foreach my $facetSpec (split(/\s*,\s*/, $theFacets)) {
      my ($facetLabel, $facetID) = parseFacetSpec($facetSpec);
      my $theFacetHeader = $params->{"header_$facetID"} || '';
      my $theFacetFormat = $params->{"format_$facetID"} || '';
      my $theFacetFooter = $params->{"footer_$facetID"} || '';
      my $theFacetSeparator = $params->{"separator_$facetID"} || '';
      my $theFacetExclude = $params->{"exclude_$facetID"};
      my $theFacetInclude = $params->{"include_$facetID"};

      next unless defined $theFacetFormat;

      my $shownFacetLabel = $facetLabel;
      $shownFacetLabel =~ s/_/ /g; #revert whitespace workaround

      my @facetRows = ();
      my $facetTotal = 0;

      # query facets
      if ($facetID eq 'facetquery') {
        my $theFacetQuery = $params->{facetquery} || '';
        my @facetQuery = split(/\s*,\s*/, $theFacetQuery);
        if ($theHideSingle ne 'on' || @facetQuery > 1) {
          foreach my $querySpec (@facetQuery) {
            my ($key, $query) = parseFacetSpec($querySpec);
            my $count = $facets->{facet_queries}{$key};
            next if $theFacetExclude && $key =~ /$theFacetExclude/;
            next if $theFacetInclude && $key !~ /$theFacetExclude/;
            next unless $count;
            $facetTotal += $count;
            my $line = $theFacetFormat;
            $key =~ s/_/ /g; #revert whitespace workaround
            $line =~ s/\$key\b/$key/g;
            $line =~ s/\$query\b/$query/g;
            $line =~ s/\$count\b/$count/g;
            push(@facetRows, $line);
          }
        }
      }

      # date facets
      elsif ($facetID =~ /^((.*_d)|date|timestamp)$/) {
        my $facet = $facets->{facet_dates}{$facetLabel};
        next unless $facet;
        if ($theHideSingle ne 'on' || scalar(keys %$facet) > 1) {
          foreach my $key (keys %$facet) {
            $key = $this->fromUtf8($key);
            next if $key =~ /^(gap|end|before)$/;
            my $count = $facet->{$key};
            next if $theFacetExclude && $key =~ /$theFacetExclude/;
            next if $theFacetInclude && $key !~ /$theFacetExclude/;
            next unless $count;
            $facetTotal += $count;
            my $line = $theFacetFormat;
            $line =~ s/\$key\b/$key/g;
            $line =~ s/\$date(?:\((.*?)\))?\b/Foswiki::Time::formatTime(Foswiki::Time::parseTime($key), ($1 || '$day $mon $year'))/ge;
            $line =~ s/\$count\b/$count/g;
            push(@facetRows, $line);
          }
        }
      } 
      
      # field facet
      else {
        my $facet = $facets->{facet_fields}{$facetLabel};
        next unless defined $facet;
        my $len = scalar(@$facet);
        if ($theHideSingle ne 'on' || $len > 2) {
          for (my $i = 0; $i < $len; $i+=2) {
            my $key = $facet->[$i];
            next unless $key;
            my $count = $facet->[$i+1];
            $key = $this->fromUtf8($key);
            next if $theFacetExclude && $key =~ /$theFacetExclude/;
            next if $theFacetInclude && $key !~ /$theFacetExclude/;
            my $line = $theFacetFormat;
            $facetTotal += $count;
            $line =~ s/\$key\b/$key/g;
            $line =~ s/\$count\b/$count/g;
            push(@facetRows, $line);
          }
        }
      }
      my $nrRows = scalar(@facetRows);
      if ($nrRows > 0) {
        my $line = $theFacetHeader.join($theFacetSeparator, @facetRows).$theFacetFooter;
        $line =~ s/\$label\b/$shownFacetLabel/g;
        $line =~ s/\$id\b/$facetID/g;
        $line =~ s/\$total\b/$facetTotal/g;
        $line =~ s/\$rows\b/$nrRows/g;
        $facetResult .= $line;
      }
    }
  }

  # format interesting terms
  my $interestingResult = '';
  if ($interestingTerms) {
    my @interestingRows = ();
    while (my $termSpec = shift @$interestingTerms) {
      my $field = '';
      my $term = '';
      my $score = 0;
      next unless $termSpec =~ /^(.*):(.*)$/g;
      $field = $1;
      $term = $2;
      $score = shift @$interestingTerms;
      next if $theInterestingExclude && $term =~ /$theInterestingExclude/;
      next if $theInterestingInclude && $term =~ /$theInterestingInclude/;
      my $line = $theInterestingFormat;
      $line =~ s/\$term/$term/g;
      $line =~ s/\$score/$score/g;
      $line =~ s/\$field/$field/g;
      push(@interestingRows, $line);
    }
    if (@interestingRows) {
      $interestingResult = $theInterestingHeader.join($theInterestingSeparator, @interestingRows).$theInterestingFooter;
    }
  }

  my $result = $theHeader.join($theSeparator, @rows).$facetResult.$interestingResult.$theFooter;
  $result =~ s/\$spellcheck/$spellcheck/g;
  $result =~ s/\$count/$count/g;
  $result =~ s/\$from/$from/g;
  $result =~ s/\$to/$to/g;
  $result =~ s/\$name//g; # clearnup
  $result =~ s/\$rows/0/g; # clearnup
  if ($result =~ /\$pager/) {
    my $pager = $this->renderPager($theWeb, $theTopic, $params, $response);
    $result =~ s/\$pager/$pager/g;
  }

  if ($result =~ /\$seconds/) {
    my $seconds = sprintf("%0.3f", ($this->getQueryTime($response) / 1000));
    $result =~ s/\$seconds/$seconds/g;
  }

  # standard escapes
  $result =~ s/\$perce?nt/\%/go;
  $result =~ s/\$nop//go;
  $result =~ s/\$n/\n/go;
  $result =~ s/\$dollar/\$/go;

  return $result;
}

##############################################################################
sub renderPager {
  my ($this, $web, $topic, $params, $response) = @_;

  return '' unless $response;

  my $lastPage = $this->lastPage($response);
  return '' unless $lastPage > 0;

  my $currentPage = $this->currentPage($response);
  my $result = '';
  if ($currentPage > 0) {
    my $scriptUrl = $this->getScriptUrl($web, $topic, $params, $response, $currentPage-1);
    $result .= "<a href='$scriptUrl' class='solrPagerPrev'>%MAKETEXT{\"Previous\"}%</a>";
  } else {
    $result .= "<span class='solrPagerPrev foswikiGrayText'>%MAKETEXT{\"Previous\"}%</span>";
  }

  my $startPage = $currentPage - 4;
  my $endPage = $currentPage + 4;
  if ($endPage >= $lastPage) {
    $startPage -= ($endPage-$lastPage+1);
    $endPage = $lastPage;
  }
  if ($startPage < 0) {
    $endPage -= $startPage;
    $startPage = 0;
  }
  $endPage = $lastPage if $endPage > $lastPage;

  if ($startPage > 0) {
    my $scriptUrl = $this->getScriptUrl($web, $topic, $params, $response, 0);
    $result .= "<a href='$scriptUrl'>1</a>";
  }

  if ($startPage > 1) {
    $result .= "<span class='solrPagerEllipsis'>&hellip;</span>";
  }

  #$this->log("currentPage=$currentPage, lastPage=$lastPage, startPage=$startPage, endPage=$endPage") if DEBUG;

  my $count = 1;
  my $marker = '';
  for (my $i = $startPage; $i <= $endPage; $i++) {
    my $scriptUrl = $this->getScriptUrl($web, $topic, $params, $response, $i);
    $marker = $i == $currentPage?'current':'';
    $result .= "<a href='$scriptUrl' class='$marker'>".($i+1)."</a>";
    $count++;
  }

  if ($endPage < $lastPage-1) {
    $result .= "<span class='solrPagerEllipsis'>&hellip;</span>"
  }

  if ($endPage < $lastPage) {
    my $scriptUrl = $this->getScriptUrl($web, $topic, $params, $response, $lastPage);
    $marker = $currentPage == $lastPage?'current':'';
    $result .= "<a href='$scriptUrl' class='$marker'>".($lastPage+1)."</a>";
  }

  if ($currentPage < $lastPage) {
    my $scriptUrl = $this->getScriptUrl($web, $topic, $params, $response, $currentPage+1);
    $result .= "<a href='$scriptUrl' class='solrPagerNext'>%MAKETEXT{\"Next\"}%</a>";
  } else {
    $result .= "<span class='solrPagerNext foswikiGrayText'>%MAKETEXT{\"Next\"}%</span>";
  }

  if ($result) {
    $result = "<div class='solrPager'>$result</div>"
  }

  return $result;
}

##############################################################################
sub restSOLRSEARCH {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $query = Foswiki::Func::getCgiQuery();

  $theWeb ||= $this->{session}->{webName};
  $theTopic ||= $this->{session}->{topicName};

  my $theQuery = $query->param('q') || $query->param('search');

  my %params = map {$_ => $query->param($_)} $query->param();

  my $response = $this->doSearch($theQuery, \%params);

  my $result = '';
  try {
    $result = $response->raw_response->content();
  } catch Error::Simple with {
    $result = "Error parsing response";
  };

  return $result."\n\n";
}

##############################################################################
sub restSOLRAUTOCOMPLETE {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $query = Foswiki::Func::getCgiQuery();

  my $theRaw = $query->param('raw') || 'off';
  my $theQuery = $query->param('q') || '';
  my $theFilter = $query->param('filter');
  my $theEllipsis = $query->param('ellipsis') || 'off';
  my $thePrefix;
  my $foundPrefix = 0;

  my $wikiUser = Foswiki::Func::getWikiName();
  my @filter = $this->parseFilter($theFilter);
  push(@filter, "(access_granted:$wikiUser OR access_granted:all)") 
    unless Foswiki::Func::isAnAdmin($wikiUser);

  # tokenize here as well to separate query and prefix
  $theQuery =~ s/[\!"§\$%&\/\(\)=\?{}\[\]\*\+~#',\.;:\-_]/ /g;
  $theQuery =~ s/([$Foswiki::regex{lowerAlpha}])([$Foswiki::regex{upperAlpha}$Foswiki::regex{numeric}]+)/$1 $2/go;
  $theQuery =~ s/([$Foswiki::regex{numeric}])([$Foswiki::regex{upperAlpha}])/$1 $2/go;

  if ($theQuery =~ /^(.+) (.*?)$/) {
    $theQuery = $1;
    $thePrefix = $2;
    $foundPrefix = 1;
  } else {
    $thePrefix = $theQuery;
    $theQuery = '*:*';
  }

  my $field = $query->param('field') || 'catchall';

  my $solrParams = {
    "q" => $theQuery,
    "facet.prefix" => $thePrefix,
    "facet" => 'true',
    "facet.mincount" => 1,
    "facet.limit" => ($query->param('limit') || 10),
    "facet.field" => $field,
    "indent" => 'true',
    "rows" => 0,
  };
  $solrParams->{"fq"} = \@filter if @filter;

  my $response = $this->{solr}->generic_solr_request('select', $solrParams);

  if ($theRaw eq 'on') {
    my $result = '';
    try {
      $result = $response->raw_response->content()."\n\n"
    } catch Error::Simple with {
      $result = "Error parsing response\n\n";
    }
    return $result;
  }

  my $facets = $this->getFacets($response);
  return '' unless $facets;

  # format autocompletion
  my @result = ();
  foreach my $facet (keys %{$facets->{facet_fields}}) {
    my @facetRows = ();
    my @list = @{$facets->{facet_fields}{$facet}};
    while (my $key = shift @list) {
      my $freq = shift @list;
      $key = "$theQuery $key" if $foundPrefix;
      my $title = $key;
      if ($theEllipsis eq 'on') {
        $title = $key;
        $title =~ s/$theQuery $thePrefix/.../;
      }
      my $line = $this->fromUtf8("$key|$title|$freq");
      push(@result, $line);
    }
  }
  return join("\n", @result)."\n\n";
}

##############################################################################
sub restSOLRSIMILAR {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $query = Foswiki::Func::getCgiQuery();
  my $theQuery = $query->param('q');
  $theQuery =  "id:$theWeb.$theTopic" unless defined $theQuery;
  my %params = map {$_ => $query->param($_)} $query->param();
  delete $params{'q'};

  my $response = $this->doSimilar($theQuery, \%params);

  #my $theRaw = $params->('raw') || 'off';

  my $result = '';
  try {
    $result = $response->raw_response->content();
  } catch Error::Simple with {
    $result = "Error parsing result";
  };

  return $result."\n\n";
}

##############################################################################
sub handleSOLRSIMILAR {
  my ($this, $params, $theWeb, $theTopic) = @_;

  return $this->inlineError("can't connect to solr server") unless defined $this->{solr};

  my $theQuery = $params->{_DEFAULT};
  $theQuery = "id:$theWeb.$theTopic" unless defined $theQuery;

  my $response = $this->doSimilar($theQuery, $params);

  #$this->log($response->raw_response->content()) if DEBUG;
  return $this->formatResponse($params, $theWeb, $theTopic, $response);
}


#############################################################################
sub doSimilar {
  my ($this, $query, $params) = @_;

  #$this->log("doSimilar($query)");

  my $theQuery = $query || $params->{'q'} || '*:*';
  my $theLike = $params->{'like'};
  my $theFields = $params->{'fields'};
  my $theFilter = $params->{'filter'};
  my $theInclude = $params->{'include'} || 'false';
  my $theStart = $params->{'start'} || 0;
  my $theRows = $params->{'rows'};
  my $theMaxTerms = $params->{'maxterms'};
  my $theBoost = $params->{'boost'} || 'true';
  my $theMinTermFreq = $params->{'mintermfrequency'};
  my $theMinDocFreq = $params->{'mindocumentfrequency'};
  my $theMinWordLength = $params->{'mindwordlength'};
  my $theMaxWordLength = $params->{'maxdwordlength'};

  $theLike = 'category,tag' unless defined $theLike;
  $theFilter = 'type:topic' unless defined $theFilter;
  $theRows = 10 unless defined $theRows;
  $theMaxTerms = 100 unless defined $theMaxTerms;

  $theFields = 'web,topic,title,score' unless defined $theFields;
  $theInclude = undef unless $theInclude =~ /^(true|false)$/;
  $theBoost = undef unless $theBoost =~ /^(true|false)$/;

  my $wikiUser = Foswiki::Func::getWikiName();
  my @filter = $this->parseFilter($theFilter);
  push(@filter, "(access_granted:$wikiUser OR access_granted:all)") 
    unless Foswiki::Func::isAnAdmin($wikiUser);

  if (CONVERT_TOUTF8) {
    $theQuery = $this->toUtf8($theQuery);
  }

  my $solrParams = {
    "q" => $theQuery, 
    "fq" => \@filter,
    "fl" => $theFields,
    "rows" => $theRows,
    "start" => $theStart,
    "indent" => 'true',
    "mlt.maxqt" => $theMaxTerms,
  };
  
  my @fields = ();
  my @boosts = ();
  foreach my $like (split(/\s*,\s*/, $theLike)) {
    if ($like =~ /^(.*)\^(.*)$/) {
      push(@fields, $1);
      push(@boosts, $like);
    } else {
      push(@fields, $like);
    }
  }

  $solrParams->{"mlt.fl"} = join(',', @fields) if @fields;
  $solrParams->{"mlt.boost"} = $theBoost if defined $theBoost;
  $solrParams->{"mlt.qf"} = join(' ', @boosts) if @boosts;
  $solrParams->{"mlt.interestingTerms"} = 'details' if $params->{format_interesting};
  $solrParams->{"mlt.match.include"} = $theInclude if defined $theInclude;
  $solrParams->{"mlt.mintf"} = $theMinTermFreq if defined $theMinTermFreq;
  $solrParams->{"mlt.mindf"} = $theMinDocFreq if defined $theMinDocFreq;
  $solrParams->{"mlt.minwl"} = $theMinWordLength if defined $theMinWordLength;
  $solrParams->{"mlt.maxwl"} = $theMaxWordLength if defined $theMaxWordLength;

  $this->getFacetParams($params, $solrParams);

  return $this->{solr}->generic_solr_request('mlt', $solrParams);
}

##############################################################################
sub restSOLRTERMS {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $query = Foswiki::Func::getCgiQuery();

  my $theRaw = $query->param('raw') || 'off';
  my $theQuery = ($query->param('q') || '*:*');
  my $theFields = $query->param('fields') || '';
  my $theField = $query->param('field');
  my $theEllipsis = $query->param('ellipsis') || 'off';
  my $theLength = $query->param('length') || 0;

  if (defined $theLength) {
    $theLength =~ s/[^\d]//g;
  }
  $theLength ||= 0;

  my @fields = split(/\s*,\s*/, $theFields);
  push(@fields, $theField) if defined $theField;
  push(@fields, 'webtopic') unless @fields;

  my $wikiUser = Foswiki::Func::getWikiName();
  my $solrParams = {
    "terms" => 'true',
    "terms.fl" => \@fields,
    "terms.mincount" => 1,
    "terms.lower" => $theQuery,
    "terms.prefix" => $theQuery,
    "terms.lower.incl" => 'false',
    "indent" => 'true',
  };

  $solrParams->{"fq"} = "(access_granted:$wikiUser OR access_granted:all)" 
    unless Foswiki::Func::isAnAdmin($wikiUser);

  my $response = $this->{solr}->generic_solr_request('terms', $solrParams);

  my %struct = ();
  try {
    %struct = @{$response->content->{terms}};
  } catch Error::Simple with {
    # ignore
  };
  my @result = ();
  foreach my $field (keys %struct) {
    while (my $term = shift @{$struct{$field}}) {
      my $freq = shift @{$struct{$field}};
      my $title = $term;

      my $strip = $theQuery;
      my $hilite = $theQuery;
      if ($theLength) {
        $strip = substr($theQuery, 0, -$theLength);
        $hilite = substr($theQuery, -$theLength);
      }
      $title =~ s/$strip/.../ if $theEllipsis eq 'on';

      my $line = "$term|$title|$hilite|$freq";
      push(@result, $line);
    }
  }
  if ($theRaw eq 'on') {
    my $result = '';
    try {
      $result = $response->raw_response->content();
    } catch Error::Simple with {
      #
    };
    return $result."\n\n";
  }

  return join("\n", @result)."\n\n";
}


##############################################################################
sub doSearch {
  my ($this, $query, $params) = @_;

  my $theOutput = $params->{output} || '';
  my $theRows = $params->{rows};
  my $theFields = $params->{fields} || '*,score';
  my $theQueryType = $params->{type} || 'standard';
  my $theHighlight = $params->{highlight} || 'off';
  my $theSpellcheck = $params->{spellcheck} || 'off';
  my $theWeb = $params->{web};
  my $theContributor = $params->{contributor};
  my $theFilter = $params->{filter} || '';
  my $theExtraFilter = $params->{extrafilter};
  my $theFacet = $params->{facet};

  $theQueryType = Foswiki::Func::expandTemplate("solr::defaultquerytype") unless $theQueryType =~ /^(standard|dismax)$/;
  $theQueryType = 'standard' unless defined $theQueryType;

  if ($theWeb) {
    $theWeb =~ s/\//\./g;
    $params->{web} = $theWeb;
  }

  my $theStart = $params->{start} || 0;

  my $theReverse = $params->{reverse};
  my $theSort = $params->{sort};
  $theSort = Foswiki::Func::expandTemplate("solr::defaultsort") unless defined $theSort;
  $theSort = "score desc" unless $theSort;

  if ($theSort =~ /^(.*) (.*)$/) {
    $theSort = $1;
    $theReverse = ($2 eq 'desc'?'on':'off');
  }
  unless (defined $theReverse) {
    if ($theSort eq 'score') {
      $theReverse = 'on'; # score desc is default
    } else {
      $theReverse = 'off';
    }
  }
  $theSort .= " ".($theReverse eq 'on'?'desc':'asc');

  $theRows =~ s/[^\d]//g if defined $theRows;
  $theRows = Foswiki::Func::expandTemplate('solr::defaultrows') if !defined($theRows) || $theRows eq '';
  $theRows = 10 if !defined($theRows) || $theRows eq '';

  my $solrParams = {
    "indent" =>'on',
    "start" => ($theStart*$theRows),
    "rows" => $theRows,
    "fl" => $theFields,
    "sort" => $theSort,
    "qt" => $theQueryType, # or is it defType?
    "wt" => ($theOutput eq 'xml'?'xml':'json'),
  };

  if ($theHighlight eq 'on' && $theRows > 0) {
    $solrParams->{"hl"} = 'true';
    $solrParams->{"hl.fl"} = 'catchall';
    $solrParams->{"hl.requireFieldMatch"} = 'true';
    $solrParams->{"hl.usePraseHighlighter"} = 'true';
    $solrParams->{"hl.highligtMultiTerm"} = 'true';
    $solrParams->{"hl.mergeContignuous"} = 'true';
    $solrParams->{"hl.fragsize"} = '150';
    $solrParams->{"hl.snippets"} = '2';
    $solrParams->{"hl.alternateField"} = 'summary';
    $solrParams->{"hl.maxAlternateFieldLength"} = '300';
    # TODO: some more hl params?
  }

  if ($theSpellcheck eq 'on') {
    $solrParams->{"spellcheck"} = 'true';
  }

  # get all facet params
  $this->getFacetParams($params, $solrParams);

  my $wikiUser = Foswiki::Func::getWikiName();

  # create filter query
  my @filter;
  my %seenFilter;
  my @tmpfilter = $this->parseFilter($theFilter);

  # add disjunctive filters
  foreach my $item (@tmpfilter) {
    if ($item =~ /^date:"?(.*?)"?$/) {
      push(@{$seenFilter{'date'}}, $1);
    } else {
      push(@filter, $item);
    }
  }
  foreach my $field (keys %seenFilter) {
    my $expr = "{!tag=$field}$field:(".join(" OR ", @{$seenFilter{$field}}).")";
    push(@filter, $expr);
  }

  # extra filter 
  push(@filter, $this->parseFilter($theExtraFilter));
  push(@filter, "(access_granted:$wikiUser OR access_granted:all)") 
    unless Foswiki::Func::isAnAdmin($wikiUser); # add ACLs

  # SMELL: do we really need these special filters
  push(@filter, "contributor:".$theContributor) if $theContributor; # add contributor

  $solrParams->{"fq"} = \@filter if @filter;

  if (DEBUG) {
    foreach my $key (sort keys %$solrParams) {
      my $val = $solrParams->{$key};
      if (ref($val)) {
        $val = join(', ', @$val);
      }
      $this->log("solrParams key=$key val=$val");
    }
  }

  # default query for standard request handler
  if (!$query) {
    if (!$theQueryType || $theQueryType eq 'standard' || $theQueryType eq 'lucene') {
      $query = '*:*';
    }
  }

  if (CONVERT_TOUTF8) {
    $query = $this->toUtf8($query);
  }
  $this->log("query=$query") if DEBUG;
  my $response = $this->{solr}->search($query, $solrParams);

  #$this->log("response:\n".$response->raw_response->content()) if DEBUG;

  return $response;
}

##############################################################################
sub getFacetParams {
  my ($this, $params, $solrParams) = @_;

  $solrParams ||= {};

  my $theFacets = $params->{facets};
  my $theFacetQuery = $params->{facetquery} || '';

  return $solrParams unless $theFacets || $theFacetQuery;

  my $theFacetLimit = $params->{facetlimit} || '';
  my $theFacetSort = $params->{facetsort} || '';
  my $theFacetOffset = $params->{facetoffset};
  my $theFacetMinCount = $params->{facetmincount};
  my $theFacetPrefix = $params->{facetprefix};
  my $theContributor = $params->{contributor};

  # parse facet limit
  my %facetLimit;
  my $globalLimit;
  foreach my $limitSpec (split(/\s*,\s*/, $theFacetLimit)) {
    if ($limitSpec =~ /^(.*)=(.*)$/) {
      $facetLimit{$1} = $2;
    } else {
      $globalLimit = $limitSpec; 
    }
  }
  $solrParams->{"facet.limit"} = $globalLimit if defined $globalLimit;
  foreach my $facetName (keys %facetLimit) {
    $solrParams->{"f.".$facetName.".facet.limit"} = $facetLimit{$facetName};
  }

  # parse facet sort
  my %facetSort;
  my $globalSort;
  foreach my $sortSpec (split(/\s*,\s*/, $theFacetSort)) {
    if ($sortSpec =~ /^(.*)=(.*)$/) {
      my ($key, $val) = ($1, $2);
      if ($val =~ /^(count|index)$/) { 
        $facetSort{$key} = $val;
      } else {
        $this->log("Error: invalid sortSpec '$sortSpec' ... ignoring");
      }
    } else {
      if ($sortSpec =~ /^(count|index)$/) { 
        $globalSort = $sortSpec; 
      } else {
        $this->log("Error: invalid sortSpec '$sortSpec' ... ignoring");
      }
    }
  }
  $solrParams->{"facet.sort"} = $globalSort if defined $globalSort;
  foreach my $facetName (keys %facetSort) {
    $solrParams->{"f.".$facetName.".facet.sort"} = $facetSort{$facetName};
  }

  # general params
  # TODO: make them per-facet like sort and limit
  $solrParams->{"facet"} = 'true';
  $solrParams->{"facet.mincount"} = (defined $theFacetMinCount)?$theFacetMinCount:1;
  $solrParams->{"facet.offset"} = $theFacetOffset if defined $theFacetOffset;
  $solrParams->{"facet.prefix"} = $theFacetPrefix if defined $theFacetPrefix;
  
  # gather all facets
  my $fieldFacets;
  my $dateFacets;
  my $queryFacets;
  
  foreach my $querySpec (split(/\s*,\s*/, $theFacetQuery)) {
    my ($facetLabel, $facetQuery) = parseFacetSpec($querySpec);
    if ($facetQuery =~ /^(.*?):(.*)$/) {
      push(@$queryFacets, "{!ex=$1 key=$facetLabel}$facetQuery");
    } else {
      push(@$queryFacets, "{!key=$facetLabel}$facetQuery");
    }
  }

  foreach my $facetSpec (split(/\s*,\s*/, $theFacets)) {
    my ($facetLabel, $facetID) = parseFacetSpec($facetSpec);
    #next if $facetID eq 'web' && $params->{web} && $params->{web} ne 'all';
    next if $facetID eq 'contributor' && $theContributor;
    next if $facetID eq 'facetquery';
    if ($facetID =~ /^(tag|category)$/) {
      push(@$fieldFacets, "{!key=$facetLabel}$facetID");
    } elsif ($facetID =~ /^((.*_d)|date|timestamp)$/) {
      push(@$dateFacets, "{!ex=$facetID, key=$facetLabel}$facetID");
    } else {
      push(@$fieldFacets, "{!ex=$facetID key=$facetLabel}$facetID");
    }
  }

  # date facets params
  if ($dateFacets) {
    $solrParams->{"facet.date"} = $dateFacets;
    $solrParams->{"facet.date.start"} = $params->{facetdatestart} || 'NOW/DAY-7DAYS';
    $solrParams->{"facet.date.end"} = $params->{facetdateend} || 'NOW/DAY+1DAYS';
    $solrParams->{"facet.date.gap"} = $params->{facetdategap} || '+1DAY';
    $solrParams->{"facet.date.other"} = $params->{facetdateother} || 'before';
  }

  $solrParams->{"facet.query"} = $queryFacets if $queryFacets;
  $solrParams->{"facet.field"} = $fieldFacets if $fieldFacets;

  return $solrParams;
}


##############################################################################
sub mapToIconFileName {
  my ($this, $type) = @_;

  return 'picture.png' if $type =~ /(jpe?g)|gif|png/i;
  return 'compress.png' if $type =~ /zip|tar|tar|rar/i;
  return 'page_white_acrobat.png' if $type =~ /pdf/i;
  return 'page_excel.png' if $type =~ /xlsx?/i;
  return 'page_word.png' if $type =~ /docx?/i;
  return 'page_white_powerpoint.png' if $type =~ /pptx?/i;
  return 'page_white_flash.png' if $type =~ /flv|swf/i;
  return 'page_white_text.png' if $type =~ /topic/i;
  return 'comment.png' if $type =~ /comment/i;

  return 'page_white.png';
}

##############################################################################
# replaces buggy Data::Page interface
sub currentPage {
  my ($this, $response) = @_;

  my $rows = 0;
  my $start = 0;
  
  try {
    $rows = $this->entriesPerPage($response);
    $start = $response->content->{response}->{start};
  } catch Error::Simple with {
    # ignore
  };

  return POSIX::floor($start / $rows) if $rows;
  return 0;
}

##############################################################################
sub lastPage {
  my ($this, $response) = @_;
  
  my $rows = 0;
  my $total = 0;
  try {
    $rows = $this->entriesPerPage($response);
    $total = $this->totalEntries($response);
  } catch Error::Simple with {
    # ignore
  };

  return POSIX::ceil($total/$rows)-1 if $rows;
  return 0;
}

##############################################################################
sub entriesPerPage {
  my ($this, $response) = @_;

  my $result = 0;
  try {
    $result = $response->content->{responseHeader}->{params}->{rows} || 0;
  } catch Error::Simple with {
    # ignore
  };

  return $result;
}

##############################################################################
sub totalEntries {
  my ($this, $response) = @_;

  my $result = 0;

  try {
   $result = $response->content->{response}->{numFound};
  } catch Error::Simple with {
    # ignore
  };

  return $result;
}

##############################################################################
sub getQueryTime {
  my ($this, $response) = @_;

  my $result = 0;
  try {
    $result = $response->content->{responseHeader}->{QTime} || 0;
  } catch Error::Simple with {
    # ignore
  };

  return $result;
}


##############################################################################
sub getHighlights {
  my ($this, $response) = @_;

  my %hilites = ();

  my $struct;
  try {
    $struct = $response->content->{highlighting};
  } catch Error::Simple with {
    #ignore
  };

  if ($struct) {
    foreach my $id (keys %$struct) {
      my $hilite = $struct->{$id}{catchall};
      next unless $hilite;
      $hilite = join(" ... ", @{$hilite});
      $hilites{$id} = $this->fromUtf8($hilite);
    }
  }

  return \%hilites;
}

##############################################################################
sub getCorrection {
  my ($this, $response) = @_;

  my $struct;

  try {
    $struct = $response->content->{spellcheck};
  } catch Error::Simple with {
    # ignore
  };

  return '' unless $struct;

  $struct = {@{$struct->{suggestions}}};
  return '' unless $struct;
  return '' if $struct->{correctlySpelled};

  my $correction = $struct->{collation};
  return '' unless $correction;

  return $this->fromUtf8($correction);
}

##############################################################################
sub getFacets {
  my ($this, $response) = @_;

  my $struct = '';

  try {
    $struct = $response->content->{facet_counts};
  } catch Error::Simple with {
    # ignore
  };

  return $struct;
}

##############################################################################
sub getInterestingTerms {
  my ($this, $response) = @_;

  my $struct = '';
  
  try {
    $struct = $response->content->{interestingTerms};
  } catch Error::Simple with {
    # ignore
  };

  return $struct;
}


##############################################################################
sub parseFacetSpec {
  my ($spec) = @_;

  $spec =~ s/^\s+//g;
  $spec =~ s/\s+$//g;
  my $key = $spec;
  my $val = $spec;

  if ($spec =~ /^(.+)=(.+)$/) {
    $key = $1;
    $val = $2;
  }
  $key =~ s/ /_/g;

  return ($key, $val);
}

##############################################################################
sub handleSOLRSCRIPTURL {
  my ($this, $params, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};

  my $theId = $params->{_DEFAULT} || $params->{id};
  return $this->inlineError("unknown query id") unless defined $theId;

  my $cacheEntry = $this->{cache}{$theId};
  return $this->inlineError("unknown query '$theId'") unless defined $cacheEntry;

  $params = {%{$cacheEntry->{params}}, %$params};

  my $web = $params->{web} || $theWeb;
  my $topic = $params->{topic} || $theTopic;

  return $this->getScriptUrl($web, $topic, $params, $cacheEntry->{response});
}

##############################################################################
sub getScriptUrl {
  my ($this, $web, $topic, $params, $response, $start) = @_;

  my $theRows = $params->{rows};
  my $theFilter = $params->{filter} || '';
  
  my $theQueryType = $params->{type} || 'standard';
  $theQueryType = Foswiki::Func::expandTemplate("solr::defaultquerytype") unless $theQueryType =~ /^(standard|dismax)$/;
  $theQueryType = 'standard' unless defined $theQueryType;

  $theRows = Foswiki::Func::expandTemplate('solr::defaultrows') unless defined $theRows;
  $theRows = 10 if !defined($theRows) || $theRows eq '';

  my $theSort = $params->{sort};
  $theSort = Foswiki::Func::expandTemplate("solr::defaultsort") unless defined $theSort;
  $theSort = "score desc" unless defined $theSort;
  $theSort =~ s/^\s+//;
  $theSort =~ s/\s+$//;

  $start = $this->currentPage($response)
    unless defined $start;
  $start = 0 unless $start;

  my @urlParams = (
    start=>$start,
    rows=>$theRows,
    sort=>$theSort,
    search=>$params->{search},
    display=>$params->{display}, # list, grid
    type=>$params->{type}, # standard, dismax
    web=>$params->{web},
    origtopic=>$params->{origtopic},
  );

  $theFilter = urlDecode(entityDecode($theFilter));
  while ($theFilter =~ /([^\s]+):([^\s"]+|(?:"[^"]+"))/g) {
    my $field = $1;
    my $value = $2;
    if (defined $value) {
      $value =~ s/^"//;
      $value =~ s/"$//;
      $value =~ s/,$//;
      push(@urlParams, filter=>"$field:\"$value\"");
    } else {
      push(@urlParams, filter=>$value);
    }
  }

  return Foswiki::Func::getScriptUrl($web, $topic, 'view', @urlParams);
}

##############################################################################
sub parseFilter {
  my ($this, $filter, $format) = @_; 

  if (CONVERT_TOUTF8) {
    $filter = $this->toUtf8($filter);
  }

  $format ||= '$field:"$value"';

  my @filter = ();
  $filter ||= '';
  $filter = urlDecode(entityDecode($filter));
  #print STDERR "filter=$filter\n";
  while ($filter =~ /([^\s:]+?):([^\s",]+|(?:"[^"]+?")),?/g) {
    my $field = $1;
    my $value = $2;
    $value =~ s/^"//;
    $value =~ s/"$//;
    $value =~ s/,$//;
    $value =~ s/\//\./g if $field eq 'web';
    if ($value) {
      my $item = $format;
      $item =~ s/\$field/$field/g;
      $item =~ s/\$value/$value/g;
      #print STDERR "...adding=$item\n";
      push(@filter, $item);
    }
  }

  return @filter;
}

##############################################################################
sub entityDecode {
  my $text = shift;

  $text =~ s/&#(\d+);/chr($1)/ge;
  return $text;
}

##############################################################################
sub urlDecode {
  my $text = shift;

  $text =~ s/%([\da-f]{2})/chr(hex($1))/gei;

  return $text;
}

1;
