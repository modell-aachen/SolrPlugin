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
package Foswiki::Plugins::SolrPlugin::Search;

use strict;
use warnings;

use Foswiki::Plugins::SolrPlugin::Base ();
our @ISA = qw( Foswiki::Plugins::SolrPlugin::Base );

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Plugins::JQueryPlugin ();
use POSIX ();
use Error qw(:try);
use JSON ();

use constant TRACE => 0; # toggle me

#use Data::Dump qw(dump);

##############################################################################
sub new {
  my ($class, $session) = @_;

  my $this = $class->SUPER::new($session);

  $this->{url} =
    $Foswiki::cfg{SolrPlugin}{SearchUrl} || $Foswiki::cfg{SolrPlugin}{Url};

  throw Error::Simple("no solr url defined") unless defined $this->{url};

  $this->log("ERROR: can't conect solr daemon") unless $this->connect;

  return $this;
}


##############################################################################
sub handleSOLRSEARCH {
  my ($this, $params, $theWeb, $theTopic) = @_;

  #$this->log("called handleSOLRSEARCH(".$params->stringify.")") if TRACE;
  return $this->inlineError("can't connect to solr server") unless defined $this->{solr};

  my $theId = $params->{id};
  return '' if defined $theId && defined $this->{cache}{$theId};

  my $theQuery = $params->{_DEFAULT} || $params->{search} || '';;
  $theQuery = $this->entityDecode($theQuery, 1);
  $params->{search} = $theQuery;

  my $theJump = Foswiki::Func::isTrue($params->{jump});

  if ($theJump && $theQuery) {
    # redirect to topic
    my ($web, $topic) = $this->normalizeWebTopicName($theWeb, $theQuery);

    if (Foswiki::Func::topicExists($web, $topic)) {
      my $url = Foswiki::Func::getScriptUrl($web, $topic, 'view');
      $this->{redirectUrl} = $url;
      return '';
    }
  }

  my $response = $this->doSearch($theQuery, $params);
  return '' unless defined $response;

  if (defined $theId) {
    $this->{cache}{$theId} = {
      response=>$response,
      params=>$params,
    };
  }

  # I feel lucky: redirect to first result
  my $theLucky = Foswiki::Func::isTrue($params->{'lucky'});
  if ($theLucky) {
    my $url = $this->getFirstUrl($response);
    if ($url) {
      # will redirect in finishPlugin handler
      $this->{redirectUrl} = $url;
      return "";
    }
  }

  return $this->formatResponse($params, $theWeb, $theTopic, $response);
}

##############################################################################
sub handleSOLRFORMAT {
  my ($this, $params, $theWeb, $theTopic) = @_;

  #$this->log("called handleSOLRFORMAT(".$params->stringify.")") if TRACE;
  return '' unless defined $this->{solr};

  my $theId = $params->{_DEFAULT} || $params->{id};
  return $this->inlineError("unknown query id") unless defined $theId;

  my $cacheEntry = $this->{cache}{$theId};
  return $this->inlineError("unknown query '$theId'") unless defined $cacheEntry;

  $params = {%{$cacheEntry->{params}}, %$params};

  return $this->formatResponse($params, $theWeb, $theTopic, $cacheEntry->{response});
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
    $this->log("Error parsing solr response") if TRACE;
    $error = $this->inlineError("Error parsing solr response");
  };
  return $error if $error;
  return '' unless $gotResponse;

  #$this->log("called formatResponse()") if TRACE;

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
  my $theHideSingle = $params->{hidesingle} || '';

  my %hideSingleFacets = map {$_ => 1} split(/\s*,\s*/, $theHideSingle);

  my $hilites;
  if ($theFormat =~ /\$hilite/ || $theHeader =~ /\$hilite/ || $theFooter =~ /\$hilite/) {
    my $hilitesEncoded = $this->getHighlights($response);
    if($hilitesEncoded) {
        foreach my $key (keys %$hilitesEncoded) {
            $hilites->{$key} = $hilitesEncoded->{$key};
        }
    }
  }

  my $moreLikeThis;
  if ($theFormat =~ /\$morelikethis/ || $theHeader =~ /\$morelikethis/ || $theFooter =~ /\$morelikethis/) {
    $moreLikeThis = $this->getMoreLikeThis($response);
    $moreLikeThis = $moreLikeThis;
  }

  my $spellcheck = '';
  if ($theFormat =~ /\$spellcheck/ || $theHeader =~ /\$spellcheck/ || $theFooter =~ /\$spellcheck/) {
    my $correction = $this->getCorrection($response);
    if ($correction) {
      $correction = $correction;
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

  #$this->log("page=$page, limit=$limit, index=$index, count=$count") if TRACE;

  if (defined $theFormat && $theFormat ne '') {
    for my $doc ($response->docs) {
      my $line = $theFormat;
      my $id = '';
      my $type = '';
      my $topic;
      my $web;
      my $summary = '';

      my $theValueSep = $params->{valueseparator} || ', ';
      foreach my $nameKey ($doc->field_names) {
        my $name = $nameKey;
        next unless $line =~ /\$$name/g;

        my @values = $doc->values_for($nameKey);
        my $value = join($theValueSep, @values);
        $value = $value;

        $web = $value if $name eq 'web';
        $topic = $value if $name eq 'topic';
        $id = $value if $name eq 'id';
        $type = $value if $name eq 'type';
        $summary = $value if $name eq 'summary';

        $value = sprintf('%.02f', $value)
          if $name eq 'score';

        if ($this->isDateField($name)) {
          $line =~ s/\$$name\((.*?)\)/Foswiki::Time::formatTime(Foswiki::Time::parseTime($value), $1)/ge;
          $line =~ s/\$$name\b/Foswiki::Time::formatTime(Foswiki::Time::parseTime($value), '$day $mon $year')/ge;
        } else {
          $value = sprintf("%.02f kb", ($value / 1024))
            if $name eq 'size' && $value =~ /^\d+$/;
          $line =~ s/\$$name\b/$value/g;
        }

      }
# DISABLED for performance reasons
#      next unless Foswiki::Func::topicExists($web, $topic);

      my $hilite = '';
      $hilite = ($hilites->{$id} || $summary) if $id && $hilites;

      my $mlt = '';
      $mlt = $moreLikeThis->{$id} if $id && $moreLikeThis;
      if ($mlt) {
        # TODO: this needs serious improvements
        #$line =~ s/\$morelikethis/$mlt->{id}/g;
      }

      my $itemFormat = 'attachment';
      $itemFormat = 'image' if $type =~ /^(gif|jpe?g|png|bmp|svg)$/i;
      $itemFormat = 'topic' if $type eq 'topic';
      $itemFormat = 'comment' if $type eq 'comment';
      $line =~ s/\$format/$itemFormat/g;
      $line =~ s/\$id/$id/g;
      $line =~ s/\$icon/$this->mapToIconFileName($type)/ge;
      $line =~ s/\$index/$index/g;
      $line =~ s/\$page/$page/g;
      $line =~ s/\$limit/$limit/g;
      $line =~ s/\$hilite/$hilite/g;
      $index++;
      push(@rows, $line);
    }
  }

  return '' if !@rows && !$theFacets && !$theInterestingFormat;

  my $facets = $this->getFacets($response);
  my $interestingTerms = $this->getInterestingTerms($response);

  # format facets
  my $facetResult = '';
  if ($facets) {

    foreach my $facetSpec (split(/\s*,\s*/, $theFacets)) {
      my ($facetLabel, $facetID) = parseFacetSpec($this->fromUtf8($facetSpec));
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

        # count rows
        my $len = 0;
        foreach my $querySpec (@facetQuery) {
          my ($key, $query) = parseFacetSpec($querySpec);
          my $count = $facets->{facet_queries}{$key};
          next unless $count;
          next if $theFacetExclude && $key =~ /$theFacetExclude/;
          next if $theFacetInclude && $key !~ /$theFacetInclude/;
          $len++;
        }

        unless ($hideSingleFacets{$facetID} && $len <= 1) {
          foreach my $querySpec (@facetQuery) {
            my ($key, $query) = parseFacetSpec($querySpec);
            my $count = $facets->{facet_queries}{$key};
            next unless $count;
            next if $theFacetExclude && $key =~ /$theFacetExclude/;
            next if $theFacetInclude && $key !~ /$theFacetInclude/;
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
      elsif ($this->isDateField($facetID)) {
        my $facet = $facets->{facet_ranges}{$facetLabel};
        next unless $facet;
        $facet = $facet->{counts};

        # count rows
        my $len = 0;
        for(my $i = 0; $i < scalar(@$facet); $i+=2) {
          my $key = $facet->[$i];
          my $count = $facet->[$i+1];
          next unless $count;
          next if $theFacetExclude && $key =~ /$theFacetExclude/;
          next if $theFacetInclude && $key !~ /$theFacetInclude/;
          $len++;
        }

        unless ($hideSingleFacets{$facetID} && $len <= 1) {
          for(my $i = 0; $i < scalar(@$facet); $i+=2) {
            my $key = $facet->[$i];
            my $count = $facet->[$i+1];
            next unless $count;
            next if $theFacetExclude && $key =~ /$theFacetExclude/;
            next if $theFacetInclude && $key !~ /$theFacetInclude/;
            $facetTotal += $count;
            my $line = $theFacetFormat;
            $line =~ s/\$key\b/$key/g;
            $line =~ s/\$date\((.*?)\)/Foswiki::Time::formatTime(Foswiki::Time::parseTime($key), $1)/ge;
            $line =~ s/\$date\b/Foswiki::Time::formatTime(Foswiki::Time::parseTime($key), '$day $mon $year')/ge;
            $line =~ s/\$count\b/$count/g;
            push(@facetRows, $line);
          }
        }
      }

      # field facet
      else {
        my $facet = $facets->{facet_fields}{$facetLabel};
        next unless defined $facet;

        # count rows
        my $len = 0;
        my $nrFacetValues = scalar(@$facet);
        for (my $i = 0; $i < $nrFacetValues; $i+=2) {
          my $key = $facet->[$i];
          next unless $key;
          $key = $key;
          next if $theFacetExclude && $key =~ /$theFacetExclude/;
          next if $theFacetInclude && $key !~ /$theFacetInclude/;
          $len++;
        }

        unless ($hideSingleFacets{$facetID} && $len <= 1) {
          for (my $i = 0; $i < $nrFacetValues; $i+=2) {
            my $key = $facet->[$i];
            next unless $key;

            my $count = $facet->[$i+1];

            next if $theFacetExclude && $key =~ /$theFacetExclude/;
            next if $theFacetInclude && $key !~ /$theFacetInclude/;
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
      next unless $termSpec =~ /^(.*):(.*)$/g;
      my $field = $1; 
      my $term = $2; 
      my $score = shift @$interestingTerms;

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
  $result =~ s/\$name//g; # cleanup
  $result =~ s/\$rows/0/g; # cleanup
  $result =~ s/\$morelikethis//g; # cleanup

  if ($params->{fields}) {
    my $cleanupPattern = '('.join('|', split(/\s*,\s*/, $params->{fields})).')';
    $cleanupPattern =~ s/\*/\\*/g;
    $result =~ s/\$$cleanupPattern//g;
  }

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
  $result =~ s/\$nop\b//go;
  $result =~ s/\$n/\n/go;
  $result =~ s/\$dollar/\$/go;

  #$this->log("result=$result");

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

  #$this->log("currentPage=$currentPage, lastPage=$lastPage, startPage=$startPage, endPage=$endPage") if TRACE;

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
sub restSOLRPROXY {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $query = Foswiki::Func::getCgiQuery();

  $theWeb ||= $this->{session}->{webName};
  $theTopic ||= $this->{session}->{topicName};
  my $theQuery = $query->param('q') || "*:*";

  my %params = map {$_ => [$query->multi_param($_)]} grep {!/^_$/} $query->param();

  my $wikiUser = Foswiki::Func::getWikiName();

  unless (Foswiki::Func::isAnAdmin($wikiUser)) { # add ACLs
    push @{$params{fq}}, " (access_granted:$wikiUser OR access_granted:all)"
  }

  #print STDERR "fq=$params{fq}\n";
  #print STDERR "params=".join(', ', keys %params)."\n";

  my $response = $this->solrSearch($theQuery, \%params);

  my $result = '';
  my $status = 200;
  my $contentType = "application/json; charset=utf8";

  try {
    $result = $response->raw_response->content();
  } catch Error::Simple with {
    $result = "Error parsing response";
    $status = 500;
    $contentType = "text/plain; charset=utf8";
  };

  # escape html-lish characters in title field (the title "grep<solr" will drive SafeWikiPlugin mad)
  $result =~ s#("title"\s*:\s*")((?:[^"\\]|\\"|\\\\)*")#(sub {my ($t,$s)=@_; $s=~s/</&lt;/g; $s=~s/>/&gt;/g; return "$t$s";})->($1,$2)#ge;

  $this->{session}->{response}->status($status);
  $this->{session}->{response}->header(-type=>$contentType);

  if (Foswiki::Func::getContext()->{"PiwikPluginEnabled"}) {
    my $count = 0;
    if ($result =~ /"numFound"\s*:\s*(\d+),/) {
      $count = $1;
    }
    require Foswiki::Plugins::PiwikPlugin;
    try {
      Foswiki::Plugins::PiwikPlugin::tracker->doTrackSiteSearch(
        $theQuery,
        $theWeb, # hm, there's no single category that makes sense here
        $count
      );
    } catch Error::Simple with {
      # report but ignore
      print STDERR "PiwikiPlugin::Tracker - ".shift()."\n";
    };
  }

  return Encode::decode_utf8($result);
}

##############################################################################
sub restSOLRSEARCH {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $query = Foswiki::Func::getCgiQuery();

  $theWeb ||= $this->{session}->{webName};
  $theTopic ||= $this->{session}->{topicName};

  my $theQuery = $query->param('q') || $query->param('search');
  my %params = map {$_ => join(" " , @{[$query->multi_param($_)]})} $query->multi_param();

  # SMELL: why doesn't this work out directly?
  my $jsonWrf = $params{"json.wrf"};
  delete $params{"json.wrf"};

  #print STDERR "params=".join(', ', keys %params)."\n";

  my $response = $this->doSearch($theQuery, \%params);

  # I feel lucky: redirect to first result
  my $theLucky = Foswiki::Func::isTrue($query->param('lucky'));
  if ($theLucky) {
    my $url = $this->getFirstUrl($response);
    if ($url) {
      # will redirect in finishPlugin handler
      $this->{redirectUrl} = $url;
      return "\n\n";
    }
  }

  my $result = '';
  my $status = 200;
  my $contentType = "application/json";

  try {
    $result = $response->raw_response->content();
  } catch Error::Simple with {
    $result = "Error parsing response";
    $status = 500;
    $contentType = "text/plain";
  };

  if ($jsonWrf) {
    $result = $jsonWrf."(".$result.")";
    $contentType = "text/javascript";
  }

  $this->{session}->{response}->status($status);
  $this->{session}->{response}->header(-type => $contentType);

  return $result;
}

##############################################################################
sub getFirstUrl {
  my ($this, $response) = @_;

  my $url;

  if ($this->totalEntries($response)) {
    for my $doc ($response->docs) {
      $url = $doc->value_for("url");
      last if $url;
    }
  }

  return $url;
}
##############################################################################
sub restSOLRAUTOSUGGEST {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $query = Foswiki::Func::getCgiQuery();

  my $theQuery = $query->param('term') || '*';
  $theQuery .= '*' if $theQuery !~ /\*$/ && $theQuery !~ /:/;

  my $theRaw = Foswiki::Func::isTrue(scalar $query->param('raw'));

  my $theLimit = $query->param('limit');
  $theLimit = 5 unless defined $theLimit;

  my $theOffset = $query->param('offset');
  $theOffset = 0 unless defined $theOffset;

  my $theFields = $query->param('fields');
  $theFields = "name,web,topic,container_title,title,thumbnail,url,score,type,field_Telephone_s,field_Phone_s,field_Mobile_s" unless defined $theFields;

  my $theGroups = $query->param('groups');
  $theGroups = 'persons, topics, attachments' unless defined $theGroups;

  my $userForm = $Foswiki::cfg{SolrPlugin}{PersonDataForm} || $Foswiki::cfg{PersonDataForm} || $Foswiki::cfg{Ldap}{PersonDataForm} || '*UserForm';
  my %filter = (
    persons => "form:$userForm",
    topics => "-form:$userForm type:topic",
    attachments => "-type:topic -type:comment",
  );

  my @groupQuery = ();
  foreach my $group (split(/\s*,\s*/, $theGroups)) {
    my $filter = $filter{$group};
    next unless defined $filter;
    push @groupQuery, $filter;
  }

  my $wikiUser = Foswiki::Func::getWikiName();

  my @filter = ();

  my $trashWeb = $Foswiki::cfg{TrashWebName} || 'Trash';
  push @filter, "-web:_* -web:$trashWeb"; # exclude some webs 

  my $solrExtraFilter = Foswiki::Func::getPreferencesValue("SOLR_EXTRAFILTER");
  $solrExtraFilter = Foswiki::Func::expandCommonVariables($solrExtraFilter) 
    if defined $solrExtraFilter && $solrExtraFilter ne '';
  push @filter, $solrExtraFilter 
    if defined $solrExtraFilter && $solrExtraFilter ne '';

  push(@filter, "(access_granted:$wikiUser OR access_granted:all)")
    unless Foswiki::Func::isAnAdmin($wikiUser);

  my %params = (
    q => $theQuery,
    qt => "edismax",
    indent => "true",
    group => "true",
    fl => $theFields,
    "group.sort" => "score desc",
    "group.offset" => $theOffset,
    "group.limit" => $theLimit,
    "group.query" => \@groupQuery,
     fq => \@filter,
  );

  my $theQueryFields = $query->param('queryfields');
  $params{qf} = [split(/\s*,\s*/, $theQueryFields)]
    if defined $theQueryFields;

  my $response = $this->solrSearch($theQuery, \%params);

  my $result = '';
  my $status = 200;
  my $contentType = "application/json; charset=$Foswiki::cfg{Site}{CharSet}";

  try {
    if ($theRaw) {
      $result = $response->raw_response->content();
    } else {
      $result = $response->content();
    }
  } catch Error::Simple with {
    $result = "Error parsing response: ".$response->raw_response->content();
    $status = 500;
    $contentType = "text/plain";
  };

  if ($status == 200 && !$theRaw) {
    my @autoSuggestions = ();
    my $group;

    if (Foswiki::Func::getContext()->{"PiwikPluginEnabled"}) {
      my $count = 0;
      foreach my $groupId (keys %{$result->{grouped}}) {
        $count += $result->{grouped}{$groupId}{doclist}{numFound};
      }
      require Foswiki::Plugins::PiwikPlugin;
      try {
        $theQuery =~ s/^\s+|\s+$//g;
        $theQuery =~ s/\s*\*//;
        Foswiki::Plugins::PiwikPlugin::tracker->doTrackSiteSearch(
          $theQuery,
          $theWeb, # hm, there's no single category that makes sense here
          $count
        );
      } catch Error::Simple with {
        # report but ignore
        print STDERR "PiwikiPlugin::Tracker - ".shift()."\n";
      };
    }

    # person topics
    $group = $result->{grouped}{$filter{persons}};
    if (defined $group) {
      my @docs = ();
      foreach my $doc (@{$group->{doclist}{docs}}) {
        my $phoneNumber = $doc->{field_Telephone_s} || $doc->{field_Phone_s} || $doc->{field_Mobile_s};
        $doc->{phoneNumber} = $phoneNumber if defined $phoneNumber;

        $doc->{thumbnail} = $Foswiki::cfg{PubUrlPath}."/".$Foswiki::cfg{SystemWebName}."/JQueryPlugin/images/nobody.gif"
          unless defined $doc->{thumbnail};

        $doc->{value} = $doc->{title};

        push @docs, $doc;
      }
      push @autoSuggestions, {
        "group" => "persons",
        "start" => $group->{doclist}{start},
        "numFound" => $group->{doclist}{numFound},
        "docs" => \@docs,
        "moreUrl" => $this->getAjaxScriptUrl($Foswiki::cfg{UsersWebName}, $Foswiki::cfg{UsersTopicName}, {
          topic => $Foswiki::cfg{UsersTopicName},
          #fq => $filter{persons},
          search => $theQuery #$this->fromSiteCharSet($theQuery)
        })
      } if @docs;
    }

    # normal topics
    $group = $result->{grouped}{$filter{topics}};
    if (defined $group) {
      my @docs = ();
      foreach my $doc (@{$group->{doclist}{docs}}) {
        $doc->{thumbnail} = $this->mapToIconFileName("unknown", 48)
          unless defined $doc->{thumbnail};
        $doc->{value} = $doc->{title};
        push @docs, $doc;
      }
      push @autoSuggestions, {
        "group" => "topics",
        "start" => $group->{doclist}{start},
        "numFound" => $group->{doclist}{numFound},
        "docs" => \@docs,
        "moreUrl" => $this->getAjaxScriptUrl($this->{session}{webName}, 'WebSearch', {
          topic => 'WebSearch',
          fq => $filter{topics},
          search => $theQuery #$this->fromSiteCharSet($theQuery)
        })
      } if @docs;
    }

    # attachments
    $group = $result->{grouped}{$filter{attachments}};
    if (defined $group) {
      my @docs = ();
      foreach my $doc (@{$group->{doclist}{docs}}) {
        unless (defined $doc->{thumbnail}) {
          if ($doc->{type} =~ /^(gif|jpe?g|png|bmp|svg)$/i) {
            $doc->{thumbnail} = $doc->{name};
          } else {
            my $ext = $doc->{name};
            $ext =~ s/^.*\.([^\.]+)$/$1/g;
            $doc->{thumbnail} = $this->mapToIconFileName($ext, 48);
          }
        }
        $doc->{value} = $doc->{title};
        push @docs, $doc;
      }
      push @autoSuggestions, {
        "group" => "attachments",
        "start" => $group->{doclist}{start},
        "numFound" => $group->{doclist}{numFound},
        "docs" => \@docs,
        "moreUrl" => $this->getAjaxScriptUrl($this->{session}{webName}, 'WebSearch', {
          topic => 'WebSearch',
          fq => $filter{attachments},
          search => $theQuery #$this->fromSiteCharSet($theQuery)
        })
      } if @docs;
    }

    $result = JSON::to_json(\@autoSuggestions);
  }

  $this->{session}->{response}->status($status);
  $this->{session}->{response}->header(-type=>$contentType);

  return $result;
}

##############################################################################
sub restSOLRAUTOCOMPLETE {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $query = Foswiki::Func::getCgiQuery();

  my $theRaw = Foswiki::Func::isTrue($query->param('raw'));
  my $theQuery = $query->param('term') || '';
  my $theFilter = $query->param('filter');
  my $theEllipsis = Foswiki::Func::isTrue($query->param('ellipsis'));
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

  # work around solr not doing case-insensitive facet queries
  $theQuery = lc($theQuery);

  if ($theQuery =~ /^(.+) (.+?)$/) {
    $theQuery = $1;
    $thePrefix = $2;
    $foundPrefix = 1;
  } else {
    $thePrefix = $theQuery;
    $theQuery = '*:*';
  }

  my $field = $query->param('field') || 'text';

  my $solrParams = {
    "facet.prefix" => $thePrefix,
    "facet" => 'true',
    "facet.mincount" => 1,
    "facet.limit" => ($query->param('limit') || 10),
    "facet.field" => $field,
    "indent" => 'true',
    "rows" => 0,
  };
  $solrParams->{"fq"} = \@filter if @filter;

  my $response = $this->solrSearch($theQuery, $solrParams);

  if ($theRaw) {
    my $result = $response->raw_response->content()."\n\n";
    return $result;
  }
  $this->log($response->raw_response->content()) if TRACE;

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
      if ($theEllipsis) {
        $title = $key;
        $title =~ s/$thePrefix $theQuery/.../;
      }
      my $line;

      $line = "{\"value\":\"$key\", \"label\":\"$title\", \"frequency\":$freq}";
      push(@result, $line);
    }
  }

  return "[\n".join(",\n ", @result)."\n]";
}

##############################################################################
sub restSOLRSIMILAR {
  my ($this, $theWeb, $theTopic) = @_;

  return '' unless defined $this->{solr};
  my $query = Foswiki::Func::getCgiQuery();
  my $theQuery = $query->param('q');
  $theQuery =  "id:".($this->{wikiHostMap}{$theWeb} || $this->{wikiHost})."#$theWeb.$theTopic" unless defined $theQuery;
  my %params = map {$_ => join(" " , @{[$query->param($_)]})} $query->param();
  delete $params{'q'};

  my $response = $this->doSimilar($theQuery, \%params);

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
  $theQuery =  "id:".($this->{wikiHostMap}{$theWeb} || $this->{wikiHost})."#$theWeb.$theTopic" unless defined $theQuery;

  my $response = $this->doSimilar($theQuery, $params);

  #$this->log($response->raw_response->content()) if TRACE;
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
  my $theInclude = Foswiki::Func::isTrue($params->{'include'});
  my $theStart = $params->{'start'} || 0;
  my $theRows = $params->{'rows'};
  my $theBoost = Foswiki::Func::isTrue($params->{'boost'}, 1);
  my $theMinTermFreq = $params->{'mintermfrequency'};
  my $theMinDocFreq = $params->{'mindocumentfrequency'};
  my $theMinWordLength = $params->{'mindwordlength'};
  my $theMaxWordLength = $params->{'maxdwordlength'};
  my $theMaxTerms = $params->{'maxterms'} || 25;

  $theLike = 'field_Category_flat_lst^5,tag' unless defined $theLike;
  $theFilter = 'type:topic' unless defined $theFilter;
  $theRows = 20 unless defined $theRows;

  $theFields = 'web,topic,title,score' unless defined $theFields;

  my $wikiUser = Foswiki::Func::getWikiName();
  my @filter = $this->parseFilter($theFilter);
  push(@filter, "(access_granted:$wikiUser OR access_granted:all)")
    unless Foswiki::Func::isAnAdmin($wikiUser);
  # this one doesn't use the solrSearch method, so add host filter here
  push @filter, $this->buildHostFilter;

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
  $solrParams->{"mlt.boost"} = $theBoost?'true':'false';
  $solrParams->{"mlt.qf"} = join(' ', @boosts) if @boosts;
  $solrParams->{"mlt.interestingTerms"} = 'details' if $params->{format_interesting};
  $solrParams->{"mlt.match.include"} = $theInclude?'true':'false';
  $solrParams->{"mlt.mintf"} = $theMinTermFreq if defined $theMinTermFreq;
  $solrParams->{"mlt.mindf"} = $theMinDocFreq if defined $theMinDocFreq;
  $solrParams->{"mlt.minwl"} = $theMinWordLength if defined $theMinWordLength;
  $solrParams->{"mlt.maxwl"} = $theMaxWordLength if defined $theMaxWordLength;

  $this->getFacetParams($params, $solrParams);

  return $this->solrRequest('mlt', $solrParams);
}

##############################################################################
sub doSearch {
  my ($this, $query, $params) = @_;

  my $theXslt = $params->{xslt} || '';
  my $theOutput = $params->{output} || $theXslt?'xslt':'json';
  my $theRows = $params->{rows};
  my $theFields = $params->{fields} || '*,score';
  my $theQueryType = $params->{type} || 'standard';
  my $theHighlight = Foswiki::Func::isTrue($params->{highlight});
  my $theSpellcheck = Foswiki::Func::isTrue($params->{spellcheck});
  my $theMoreLikeThis = Foswiki::Func::isTrue($params->{morelikethis});
  my $theWeb = $params->{web};
  my $theFilter = $params->{filter} || '';
  my $theExtraFilter = $params->{extrafilter};
  my $theRawFilterQuery = $params->{rawfilterquery};
  my $theRawFilterQuerySplit = $params->{rawfilterquerysplit} = '\\|';
  my $theDisjunktiveFacets = $params->{disjunctivefacets} || '';
  my $theCombinedFacets = $params->{combinedfacets} || '';
  my $theBoostQuery = $params->{boostquery};
  my $theQueryFields = $params->{queryfields};
  my $thePhraseFields = $params->{phrasefields};

  my %disjunctiveFacets = map {$_ => 1} split(/\s*,\s*/, $theDisjunktiveFacets);
  my %combinedFacets = map {$_ => 1} split(/\s*,\s*/, $theCombinedFacets);

  my $theStart = $params->{start} || 0;

  my $theReverse = Foswiki::Func::isTrue($params->{reverse});
  my $theSort = $params->{sort};
  $theSort = Foswiki::Func::expandTemplate("solr::defaultsort") unless defined $theSort;
  $theSort = "score desc" unless $theSort;

  my @sort = ();
  foreach my $sort (split(/\s*,\s*/, $theSort)) {
    if ($sort =~ /^(.+) (desc|asc)$/) {
      push @sort, $1.' '.$2;
    } else {
      push @sort, $sort.' '.($theReverse?'desc':'asc');
    }
  }
  $theSort = join(", ", @sort);

  $theRows =~ s/[^\d]//g if defined $theRows;
  $theRows = Foswiki::Func::expandTemplate('solr::defaultrows') if !defined($theRows) || $theRows eq '';
  $theRows = 20 if !defined($theRows) || $theRows eq '';

  my $solrParams = {
    "indent" =>'on',
    "start" => ($theStart*$theRows),
    "rows" => $theRows,
    "fl" => $theFields,
    "sort" => $theSort,
    "qt" => $theQueryType, # one of the requestHandlers defined in solrconfig.xml
    "wt" => $theOutput,
  };

  $solrParams->{tr} = $theXslt if $theXslt;
  $solrParams->{bq} = $theBoostQuery if $theBoostQuery;
  $solrParams->{qf} = $theQueryFields if $theQueryFields;
  $solrParams->{pf} = $thePhraseFields if $thePhraseFields;

  my $theGroup = $params->{'group'};
  my $theGroupLimit = $params->{'grouplimit'} || 1;
  if (defined $theGroup) {
    $solrParams->{"group"} = "true";
#    $solrParams->{"group.main"} = "true";
    $solrParams->{"group.ngroups"} = "true";
    $solrParams->{"group.limit"} = $theGroupLimit;
    $solrParams->{"group.field"} = $theGroup;
  }

  if ($theHighlight && $theRows > 0) {
    $solrParams->{"hl"} = 'true';
    $solrParams->{"hl.fl"} = 'text';
    $solrParams->{"hl.snippets"} = '2';
    $solrParams->{"hl.fragsize"} = '300';
    $solrParams->{"hl.mergeContignuous"} = 'true';
    $solrParams->{"hl.usePhraseHighlighter"} = 'true';
    $solrParams->{"hl.highlightMultiTerm"} = 'true';
    $solrParams->{"hl.alternateField"} = 'text';
    $solrParams->{"hl.maxAlternateFieldLength"} = '300';
    $solrParams->{"hl.useFastVectorHighlighter"} = 'true';
  }

  if ($theMoreLikeThis) {
    # TODO: add params to configure this
    $solrParams->{"mlt"} = 'true';
    $solrParams->{"mlt.mintf"} = '1';
    $solrParams->{"mlt.fl"} = 'web,topic,title,type,category,tag';
    $solrParams->{"mlt.qf"} = 'web^100 category^10 tag^10 type^200';
    $solrParams->{"mlt.boost"} = 'true';
    $solrParams->{"mlt.maxqt"} = '100';
  }

  if ($theSpellcheck) {
    $solrParams->{"spellcheck"} = 'true';
#    $solrParams->{"spellcheck.maxCollationTries"} = 1;
#    $solrParams->{"spellcheck.count"} = 1;
    $solrParams->{"spellcheck.maxCollations"} = 1;
#    $solrParams->{"spellcheck.extendedResults"} = 'true';
    $solrParams->{"spellcheck.collate"} = 'true';
  }

  # get all facet params
  $this->getFacetParams($params, $solrParams);

  my $wikiUser = Foswiki::Func::getWikiName();

  # create filter query
  my @filter;
  my @tmpFilter = $this->parseFilter($theFilter);
  my %seenDisjunctiveFilter = ();
  my %seenCombinedFilter = ();

  # gather different types of filters
  foreach my $item (@tmpFilter) {

    if ($item =~ /^(.*):(.*?)$/) {
      my $facetName = $1;
      my $facetValue = $2;

      # disjunctive
      if ($disjunctiveFacets{$facetName} || $this->isDateField($facetName)) {
        push(@{$seenDisjunctiveFilter{$facetName}}, $facetValue);
        next;
      }

      # combined
      if ($combinedFacets{$facetName}) {
        push(@{$seenCombinedFilter{$facetValue}}, $facetName);
        next;
      }
    }

    # normal
    push(@filter, $item);
  }

  # add filters for disjunctive filters
  @tmpFilter = ();
  foreach my $facetName (keys %seenDisjunctiveFilter) {
    # disjunctive facets that are also combined with each other, produce one big disjunction
    # gathered in tmpFilter before adding it to the overal @filter array
    if ($combinedFacets{$facetName}) {
      my $expr = join(" OR ", map("$facetName:$_", @{$seenDisjunctiveFilter{$facetName}}));
      push(@tmpFilter, $expr);
    } else {
      my $expr = "{!tag=$facetName}$facetName:(".join(" OR ", @{$seenDisjunctiveFilter{$facetName}}).")";
      push(@filter, $expr);
    }
  }
  push(@filter, "(".join(" OR ", @tmpFilter).")") if @tmpFilter;

  # add filters for combined filters
  foreach my $facetValue (keys %seenCombinedFilter) {
    my @expr = ();
    foreach my $facetName (@{$seenCombinedFilter{$facetValue}}) {
      push @expr, "$facetName:$facetValue";
    }
    push @filter, "(".join(" OR ", @expr).")";
  }

  if ($theWeb && $theWeb ne 'all') {
    $theWeb =~ s/\//\./g;
    push(@filter, "web:$theWeb");
  }

  if ($theRawFilterQuery) {
    push @filter, split(/$theRawFilterQuerySplit/, $theRawFilterQuery);
  }

  # extra filter
  push(@filter, $this->parseFilter($theExtraFilter));
  push(@filter, "(access_granted:$wikiUser OR access_granted:all)")
    unless Foswiki::Func::isAnAdmin($wikiUser); # add ACLs

  $solrParams->{"fq"} = \@filter if @filter;

  if (TRACE) {
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

  #$this->log("query=$query") if TRACE;
  my $response = $this->solrSearch($query, $solrParams);

  # TRACE raw response
  if (TRACE) {
    my $raw = $response->raw_response->content();
    #$raw =~ s/"response":.*$//s;
    $this->log("response: $raw");
  }


  return $response;
}

##############################################################################
sub solrSearch {
  my ($this, $query, $params) = @_;

  $params ||= {};
  $params->{'q'} = $query if $query;
  $params->{fq} ||= [];
  push @{$params->{fq}}, $this->buildHostFilter;

  while (my ($k, $v) = each %$params) {
    next unless $k =~ /^f\.[a-zA-Z_0-9]+\.facet\.mincount$/;
    my $val = shift @{$v};
    push @{$params->{$k}}, $val || 1;
  }

  #print STDERR "solrSearch($query), params=".dump($params)."\n";


  return $this->solrRequest("select", $params);
}

##############################################################################
sub solrRequest {
  my ($this, $path, $params) = @_;

  return $this->{solr}->generic_solr_request($path, $params);
}

##############################################################################
sub getFacetParams {
  my ($this, $params, $solrParams) = @_;

  $solrParams ||= {};

  my $theFacets = $params->{facets};
  my $theFacetQuery = $params->{facetquery} || '';

  return $solrParams unless $theFacets || $theFacetQuery;

  my $theFacetLimit = $params->{facetlimit};
  my $theFacetSort = $params->{facetsort} || '';
  my $theFacetOffset = $params->{facetoffset};
  my $theFacetMinCount = $params->{facetmincount} || 1;
  my $theFacetPrefix = $params->{facetprefix};
  my $theFacetMethod = $params->{facetmethod};

  $theFacetLimit = '' unless defined $theFacetLimit;

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
  $solrParams->{"facet.method"} = $theFacetMethod if defined $theFacetMethod;

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
    next if $facetID eq 'facetquery';
    if ($facetID =~ /^(tag|category)$/) {
      push(@$fieldFacets, "{!key=$facetLabel}$facetID");
    } elsif ($this->isDateField($facetID)) {
      push(@$dateFacets, "{!ex=$facetID, key=$facetLabel}$facetID");
    } else {
      push(@$fieldFacets, "{!ex=$facetID key=$facetLabel}$facetID");
    }
  }

  # date facets params
  # TODO: provide general interface to range facets
  if ($dateFacets) {
    $solrParams->{"facet.range"} = $dateFacets;
    $solrParams->{"facet.range.start"} = $params->{facetdatestart} || 'NOW/DAY-7DAYS';
    $solrParams->{"facet.range.end"} = $params->{facetdateend} || 'NOW/DAY+1DAYS';
    $solrParams->{"facet.range.gap"} = $params->{facetdategap} || '+1DAY';
    $solrParams->{"facet.range.other"} = $params->{facetdateother} || 'before';
    $solrParams->{"facet.range.hardend"} = 'true'; # TODO
  }

  $solrParams->{"facet.query"} = $queryFacets if $queryFacets;
  $solrParams->{"facet.field"} = $fieldFacets if $fieldFacets;

  return $solrParams;
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
      my $hilite = $struct->{$id}{text}; # TODO: use the actual highlight field
      next unless $hilite;
      $hilite = join(" ... ", @{$hilite});

      # bit of cleanup in case we only get half the comment
      $hilite =~ s/<!--//g;
      $hilite =~ s/-->//g;
      $hilites{$id} = $hilite;
    }
  }

  return \%hilites;
}

##############################################################################
sub getMoreLikeThis {
  my ($this, $response) = @_;

  my $moreLikeThis = [];

  try {
    $moreLikeThis = $response->content->{moreLikeThis};
  } catch Error::Simple with {
    #ignore
  };

  return $moreLikeThis;
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

  return $correction;
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
  my ($this, $params, $web, $topic) = @_;

  return '' unless defined $this->{solr};

  my $cacheEntry;
  my $theId = $params->{_DEFAULT} || $params->{id};
  my $theWeb = $params->{web} || $this->{session}->{webName};
  my $theTopic = $params->{topic} || $this->{session}->{topicName};

  $cacheEntry = $this->{cache}{$theId} if defined $theId;
  $params = {%{$cacheEntry->{params}}, %$params} if defined $cacheEntry;

  my $theAjax = Foswiki::Func::isTrue(delete $params->{ajax}, 1);

  my $result = '';
  if ($theAjax) {
    my ($web, $topic) = $this->normalizeWebTopicName($theWeb, $theTopic);
     $result = $this->getAjaxScriptUrl($web, $topic, $params);
  } else {
    my ($web, $topic) = $this->normalizeWebTopicName($theWeb, $theTopic);
    $result = $this->getScriptUrl($web, $topic, $params, $cacheEntry->{response});
  }

  return $result;
}

##############################################################################
sub getAjaxScriptUrl {
  my ($this, $web, $topic, $params) = @_;

  my @anchors = ();

  # TODO: add multivalue and union params
  my %isUnion = map {$_=>1} split(/\s*,\s*/, $params->{union} || '');
  my %isMultiValue = map {$_=>1} split(/\s*,\s*/, $params->{multivalue} || '');

  foreach my $key (sort keys %$params) {
    next if $key =~ /^(date|start|sort|_RAW|union|multivalue|separator|topic|_DEFAULT|search)$/;

    my $val  = $params->{$key};

    next if !defined($val) || $val eq '';

    if ($key eq 'fq') {
      push @anchors, 'fq='.$val;
      next;
    }

    my @locals = ();
    my $locals = '';
    push @locals, "tag=".$key if $isUnion{$key} || $isMultiValue{$key};
    push @locals, "q.op=OR" if $isUnion{$key};
    $locals = '{!'.join(' ', @locals).'}' if @locals;;

    # If the field value has a space or a colon in it, wrap it in quotes,
    # unless it is a range query or it is already wrapped in quotes.
    if ($val =~ /[ :]/  && $val !~ /[\[\{]\S+ TO \S+[\]\}]/ && $val !~ /^["\(].*["\)]$/) {
      $val = '%22' . $val . '%22'; # already escaped
    }

    push @anchors, 'fq='.$locals.$key.':'.($isUnion{$key}?"($val)":$val);
  }

  my $theStart = $params->{start};
  push @anchors, 'start='.$theStart if $theStart;

  my $theSort = $params->{sort};
  push @anchors, 'sort='.$theSort if $theSort;

  my $theSearch = $params->{_DEFAULT} || $params->{search};
  push @anchors, 'q='.$theSearch if defined $theSearch;

  my ($webSearchWeb, $webSearchTopic) = Foswiki::Func::normalizeWebTopicName($web, $params->{topic} || 'WebSearch');

  my $url = Foswiki::Func::getScriptUrlPath($webSearchWeb, $webSearchTopic, 'view');
  # not using getScriptUrl() for anchors due to encoding problems

  my $theSep = $params->{separator};
  $theSep = '&' unless defined $theSep;

  $url .= '#'.join($theSep, map {urlEncode($_)} @anchors) if @anchors;

  return $url;
}

##############################################################################
sub urlEncode {
  my $text = shift;

  # $text = Encode::encode_utf8($text) if $Foswiki::UNICODE; 
  #$text =~ s/([^0-9a-zA-Z-_.:~!*'\/])/'%'.sprintf('%02x',ord($1))/ge;

  # the small version
  $text =~ s/([':"])/'%'.sprintf('%02x',ord($1))/ge;
  $text =~ s/ /%20/g;

  return $text;
}

##############################################################################
sub getScriptUrl {
  my ($this, $web, $topic, $params, $response, $start) = @_;

  my $theRows = $params->{rows};
  $theRows = Foswiki::Func::expandTemplate('solr::defaultrows') unless defined $theRows;
  $theRows = 20 if !defined($theRows) || $theRows eq '';

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
  );
  push(@urlParams, search => $params->{search}) if $params->{search};
  push(@urlParams, display => $params->{display}) if $params->{display};
  push(@urlParams, type => $params->{type}) if $params->{type};
  push(@urlParams, web => $params->{web}) if $params->{web};
  push(@urlParams, autosubmit => $params->{autosubmit}) if defined $params->{autosubmit};


  # SMELL: duplicates parseFilter
  my $theFilter = $params->{filter} || '';
  $theFilter = $this->urlDecode($this->entityDecode($theFilter));
  while ($theFilter =~ /([^\s:]+?):((?:\[[^\]]+?\])|[^\s",]+|(?:"[^"]+?")),?/g) {
    my $field = $1;
    my $value = $2;
    if (defined $value) {
      $value =~ s/^"//;
      $value =~ s/"$//;
      $value =~ s/,$//;
      my $item;
      if ($value =~ /\s/ && $value !~ /^["\[].*["\]]$/) {
        $item = '$field:"$value"';
      } else {
        $item = '$field:$value';
      }

      $item =~ s/\$field/$field/g;
      $item =~ s/\$value/$value/g;
      push(@urlParams, filter=>$item);
    } else {
      push(@urlParams, filter=>$value); # SMELL what for?
    }
  }

  return Foswiki::Func::getScriptUrlPath($web, $topic, 'view', @urlParams);
}

##############################################################################
sub parseFilter {
  my ($this, $filter) = @_;

  my @filter = ();
  $filter ||= '';
  $filter = $this->toUtf8($this->urlDecode($this->entityDecode($filter)));

  while ($filter =~ /([^\s:]+?):((?:\[[^\]]+?\])|[^\s",\(]+|(?:"[^"]+?")|(?:\([^\)]+?\))),?/g) {
    my $field = $1;
    my $value = $2;
    $value =~ s/^"//;
    $value =~ s/"$//;
    $value =~ s/,$//;
    $value =~ s/\//\./g if $field eq 'web';
    #print STDERR "field=$field, value=$value\n";
    if ($value) {
      my $item;
      if ($value !~ /^\(/ && $value =~ /\s/ && $value !~ /^["\[].*["\]]$/) {
        $item = '$field:"$value"';
      } else {
        $item = '$field:$value';
      }
      $item =~ s/\$field/$field/g;
      $item =~ s/\$value/$value/g;
      push(@filter, $item);
    }
  }

  return @filter;
}

################################################################################
# params:
# - query
# - fields
# - process
# - sort
sub iterate {
  my ($this, $params) = @_;

  $params->{query} = "*" unless defined $params->{query};
  $params->{fields} ||= "topic";
  $params->{sort} ||= "webtopic_sort asc";

  my $len = 0;
  my $offset = 0;
  my $limit = 100;

  my @filter = ();
  my $wikiUser = Foswiki::Func::getWikiName();
  push @filter, " (access_granted:$wikiUser OR access_granted:all)"
    unless Foswiki::Func::isAnAdmin($wikiUser);

  do {
    my $response = $this->solrSearch(
      $params->{query},
      {
        fl => $params->{fields},
        start => $offset,
        rows => $limit,
        fq => \@filter,
      }
    );

    my @docs = $response->docs;
    $len = scalar(@docs);

    if ($params->{process}) {
      foreach my $doc (@docs) {
        &{$params->{process}}($doc);
      }
    }

    $offset += $len;
  } while ($len >= $limit);

  return $offset;
}

################################################################################
# params
# - field
# - process
sub iterateFacet {
  my ($this, $params) = @_;

  my @filter = ();

  my $wikiUser = Foswiki::Func::getWikiName();
  push @filter, " (access_granted:$wikiUser OR access_granted:all)"
    unless Foswiki::Func::isAnAdmin($wikiUser);

  my $len = 0;
  my $offset = 0;
  my $limit = 100;

  do {
    my $response = $this->solrSearch(
      "*",
      {
        "fl" => "none",
        "rows" => 0,
        "fq" => \@filter,
        "facet" => "true",
        "facet.field" => $params->{field},
        "facet.method" => "enum",
        "facet.limit" => $limit,
        "facet.offset" => $offset,
        "facet.sort" => "index",
      }
    );

    my $facets = $this->getFacets($response);
    return unless $facets;

    my %facet = @{$facets->{facet_fields}{$params->{field}}};

    if ($params->{process}) {
      while(my ($val, $count) = each %facet) {
        &{$params->{process}}($val, $count);
      }
    }

    $len = scalar(keys %facet);
    $offset += $len;

  } while ($len >= $limit);

  return $offset;
}

################################################################################
sub getListOfTopics {
  my ($this, $web) = @_;

  my @topics = ();

  $this->iterate({
    query => "web:$web type:topic", 
    fields => "webtopic,topic", 
    process => sub {
      my $doc = shift;
      my $topic = (defined $web) ? $doc->value_for("topic") : $doc->value_for("webtopic");
      push @topics, $topic;
    }
  });

  return @topics;
}

################################################################################
sub getListOfWebs {
  my $this = shift;

  my @webs = ();
  $this->iterateFacet({
    field => "web",
    process => sub {
      my ($val, $count) = @_;
      if ($count) {
        push @webs, $val if $count;
      } else {
        $this->log("WARNING: found web=$val with count=$count ... index needs optimization");
      }
    }
  });

  return @webs;
}


1;
