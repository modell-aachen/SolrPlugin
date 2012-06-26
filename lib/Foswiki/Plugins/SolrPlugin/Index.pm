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

package Foswiki::Plugins::SolrPlugin::Index;
use strict;
use warnings;

use Foswiki::Plugins::SolrPlugin::Base ();
our @ISA = qw( Foswiki::Plugins::SolrPlugin::Base );

use Error qw( :try );
use Fcntl qw( :flock );
use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Plugins::SolrPlugin ();
use Foswiki::Form ();
use Foswiki::OopsException ();
use Foswiki::Time ();
use Foswiki::Contrib::Stringifier ();

use constant DEBUG => 0;    # toggle me
use constant VERBOSE => 1;  # toggle me
use constant PROFILE => 0;  # toggle me

#use Time::HiRes (); # enable this too when profiling

use constant COMMIT_THRESHOLD => 200;    # commit every x topics on a bulk index job
use constant WAIT_SEARCHER => "true";
use constant SOFTCOMMIT => "true";

##############################################################################
sub new {
  my ($class, $session) = @_;

  my $this = $class->SUPER::new($session);

  $this->{url} = $Foswiki::cfg{SolrPlugin}{UpdateUrl} || $Foswiki::cfg{SolrPlugin}{Url};

  $this->{_groupCache} = {};
  $this->{_webACLCache} = {};

  throw Error::Simple("no solr url defined") unless defined $this->{url};

  # Compared to the Search constructor there's no autostarting here
  # to prevent any indexer to accidentally create a solrindex lock and further
  # java inheriting it. So we simply test for connectivity and barf if that fails.
  $this->connect();

  unless ($this->{solr}) {
    $this->log("ERROR: can't conect solr daemon");
  }

  # trap SIGINT
  $SIG{INT} = sub {
    $this->log("got interrupted ... finishing work");
    $this->{_trappedSignal} = 1; # will be detected by loops further down
  };

  # TODO: trap SIGALARM
  # let the indexer run for a maximum timespan, then flag a signal for it
  # to bail out from work done so far

  return $this;
}

################################################################################
sub finish {
  my $this = shift;

  $this->commit(1)
    if $Foswiki::cfg{SolrPlugin}{EnableOnSaveUpdates}
      || $Foswiki::cfg{SolrPlugin}{EnableOnUploadUpdates}
      || $Foswiki::cfg{SolrPlugin}{EnableOnRenameUpdates};

  undef $this->{_knownUsers};
  undef $this->{_groupCache};
  undef $this->{_webACLCache};
}

################################################################################
# entry point to either update one topic or a complete web
sub index {
  my $this = shift;

  # exclusively lock the indexer to prevent a delta and a full index
  # mode to run in parallel

  try {

    #    $this->lock();

    my $query = Foswiki::Func::getCgiQuery();
    my $web = $query->param('web') || 'all';
    my $topic = $query->param('topic');
    my $mode = $query->param('mode') || 'delta';
    my $optimize = Foswiki::Func::isTrue($query->param('optimize'));

    if ($topic) {
      $web = $this->{session}->{webName} if !$web || $web eq 'all';

      #$this->log("doing a topic index $web.$topic");
      $this->updateTopic($web, $topic);
    } else {

      #$this->log("doing a web index in $mode mode");
      $this->update($web, $mode);
    }

    $this->commit(1) if $this->{commitCounter};
    $this->optimize() if $optimize;
  }

  catch Error::Simple with {
    my $error = shift;
    print STDERR "Error: " . $error->{-text} . "\n";
  }

  finally {

    #    $this->unlock();
  };
}

################################################################################
sub afterSaveHandler {
  my $this = shift;

  return unless $this->{solr};

  $this->updateTopic(@_);
}

################################################################################
sub afterRenameHandler {
  my ($this, $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment) = @_;

  return unless $this->{solr};

  $this->updateTopic($oldWeb, $oldTopic);
  $this->updateTopic($newWeb, $newTopic);
}

################################################################################
sub afterUploadHandler {
  my ($this, $attachment, $meta) = @_;

  return unless $this->{solr};

  my $web = $meta->web;
  my $topic = $meta->topic;

  # SMELL: make sure meta is loaded
  $meta = $meta->load() unless $meta->latestIsLoaded();

  my @aclFields = $this->getAclFields($web, $topic, $meta);

  $this->indexAttachment($web, $topic, $attachment, \@aclFields);
}

################################################################################
# update documents of a web - either in fully or incremental
# on a full update, the complete web is removed from the index prior to updating it;
# this calls updateTopic for each topic to be updated
sub update {
  my ($this, $web, $mode) = @_;

  $mode ||= 'full';

  # check if old webs still exist
  my $searcher = Foswiki::Plugins::SolrPlugin::getSearcher();
  my @webs = $searcher->getListOfWebs();

  #print STDERR "webs=".join(", ", @webs)."\n";
  foreach my $thisWeb (@webs) {
    next if Foswiki::Func::webExists($thisWeb);
    $this->log("$thisWeb doesn't exist anymore ... deleting");
    $this->deleteWeb($thisWeb);
  }

  if (!defined($web) || $web eq 'all') {
    @webs = Foswiki::Func::getListOfWebs("user");
  } else {
    @webs = ();
    foreach my $item (split(/\s*,\s*/, $web)) {
      push @webs, $item;
      push @webs, Foswiki::Func::getListOfWebs("user", $item);
    }
  }

  # TODO: check the list of webs we had the last time we did a full index
  # of all webs; then possibly delete them

  foreach my $web (@webs) {
    if ($this->isSkippedWeb($web)) {

      #$this->log("Skipping web $web");
      next;
    } else {

      #$this->log("Indexing web $web");
    }

    my $start_time = time();

    my $found = 0;
    if ($mode eq 'full') {

      # full
      $this->deleteWeb($web);
      foreach my $topic (Foswiki::Func::getTopicList($web)) {
        next if $this->isSkippedTopic($web, $topic);
        $this->indexTopic($web, $topic);
        $found = 1;
        last if $this->{_trappedSignal};
      }
    } else {

      # delta
      my $since = $this->getTimestamp($web);

      my @topics = Foswiki::Func::getTopicList($web);
      foreach my $topic (@topics) {
        next if $this->isSkippedTopic($web, $topic);

        my $topicIndexTime = $this->getTimestamp($web, $topic);
        next if $topicIndexTime > $since;

        my $time;
        if ($Foswiki::Plugins::SESSION->can('getApproxRevTime')) {
          $time = $Foswiki::Plugins::SESSION->getApproxRevTime($web, $topic);
        } else {

          # This is here for old engines
          $time = $Foswiki::Plugins::SESSION->{store}->getTopicLatestRevTime($web, $topic);
        }
        next if $time < $since;

        $this->deleteTopic($web, $topic);
        $this->indexTopic($web, $topic);

        $this->setTimestamp($web, $topic);
        $found = 1;
        last if $this->{_trappedSignal};
      }
    }
    last if $this->{_trappedSignal};
    $this->setTimestamp($web) if $found;
  }
}

################################################################################
# update one specific topic; deletes the topic from the index before updating it again
sub updateTopic {
  my ($this, $web, $topic, $meta, $text) = @_;

  ($web, $topic) = $this->normalizeWebTopicName($web, $topic);

  return if $this->isSkippedWeb($web);
  return if $this->isSkippedTopic($web, $topic);

  $this->deleteTopic($web, $topic, $meta);
  if (Foswiki::Func::topicExists($web, $topic)) {
    $this->indexTopic($web, $topic, $meta, $text);
  }

  $this->commit();
}

################################################################################
# work horse: index one topic and all attachments
sub indexTopic {
  my ($this, $web, $topic, $meta, $text) = @_;

  my %outgoingLinks = ();

  my $t0 = [Time::HiRes::gettimeofday] if PROFILE;

  # normalize web name
  $web =~ s/\//\./g;

  if (VERBOSE) {
    $this->log("Indexing topic $web.$topic");
  } else {

    #$this->log(".", 1);
  }

  # new solr document for the current topic
  my $doc = $this->newDocument();

  unless (defined $meta && defined $text) {
    ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
  }

  $text = $this->entityDecode($text);

  # Eliminate Topic Makup Language elements and newlines.
  my $origText = $text;
  $text = $this->plainify($text, $web, $topic);

  # parent data
  my $parent = $meta->getParent();
  my $parentWeb;
  my $parentTopic;
  if ($parent) {
    ($parentWeb, $parentTopic) = $this->normalizeWebTopicName($web, $parent);
    $this->_addLink(\%outgoingLinks, $web, $topic, $parentWeb, $parentTopic);
  }

  # get all outgoing links from topic text
  $this->extractOutgoingLinks($web, $topic, $origText, \%outgoingLinks);

  # all webs

  # get date
  my ($date) = $this->getRevisionInfo($web, $topic);
  $date ||= 0;    # prevent formatTime to crap out
  $date = Foswiki::Func::formatTime($date, 'iso', 'gmtime');

  # get create date
  my ($createDate) = $this->getRevisionInfo($web, $topic, 1);
  $createDate ||= 0;    # prevent formatTime to crap out
  $createDate = Foswiki::Func::formatTime($createDate, 'iso', 'gmtime');

  # get contributor and most recent author
  my @contributors = $this->getContributors($web, $topic);
  my %contributors = map {$_ => 1} @contributors;
  $doc->add_fields(contributor => [keys %contributors]);

  my $author = $contributors[0];
  my $createAuthor = $contributors[ scalar(@contributors) - 1 ];

  # get TopicTitle
  my $topicTitle = $this->getTopicTitle($web, $topic, $meta);

  # get summary
  my $summary = $this->getTopicSummary($web, $topic, $meta, $text);

  # url to topic
  my $url = $this->getScriptUrlPath($web, $topic, "view");

  my $collection = $Foswiki::cfg{SolrPlugin}{DefaultCollection} || "wiki";

  my $containerTitle = $this->getTopicTitle($web, $Foswiki::cfg{HomeTopicName});
  $containerTitle = $web if $containerTitle eq $Foswiki::cfg{HomeTopicName};

  # gather all webs and parent webs
  my @webCats = ();
  my @prefix = ();
  foreach my $component (split(/\./, $web)) {
    push @prefix, $component;
    push @webCats, join(".", @prefix);
  }

  $doc->add_fields(

    # common fields
    id => "$web.$topic",
    collection => $collection,
    url => $url,
    topic => $topic,
    web => $web,
    webcat => [@webCats],
    webtopic => "$web.$topic",
    title => $topicTitle,
    text => $text,
    summary => $summary,
    author => $author,
    date => $date,
    createauthor => $createAuthor,
    createdate => $createDate,
    type => 'topic',
    container_id => $web,
    container_url => $this->getScriptUrlPath($web, $Foswiki::cfg{HomeTopicName}, "view"),
    container_title => $containerTitle,
    icon => $this->mapToIconFileName('topic'),

    # topic specific
  );

  $doc->add_fields(parent => "$parentWeb.$parentTopic") if $parent;

  # tag and analyze language
  my $contentLanguage = $this->getContentLanguage($web, $topic);
  if (defined $contentLanguage && $contentLanguage ne 'detect') {
    $doc->add_fields(
      language => $contentLanguage,
      'text_' . $contentLanguage => $text,
    );
  }

  # process form
  my $formName = $meta->getFormName();
  if ($formName) {

    # read form definition to add field type hints
    my $formDef;
    try {
      $formDef = new Foswiki::Form($this->{session}, $web, $formName);
    }
    catch Foswiki::OopsException with {

      # Form definition not found, ignore
      my $e = shift;
      $this->log("ERROR: can't read form definition for $formName");
    } catch Foswiki::AccessControlException with {
      # Form definition not accessible, ignore
      my $e = shift;
      $this->log("ERROR: can't access form definition for $formName");
    };

    $formName =~ s/\//\./g;
    $doc->add_fields(form => $formName);

    if ($formDef) {    # form definition found, if not the formfields aren't indexed

      my %seenFields = ();
      my $formFields = $formDef->getFields();
      if ($formFields) {
        foreach my $fieldDef (@{$formFields}) {
          my $attrs = $fieldDef->{attributes};    # TODO: check for Facet
          my $name = $fieldDef->{name};
          my $type = $fieldDef->{type};
          my $isMultiValued = $fieldDef->isMultiValued;
          my $isValueMapped = $fieldDef->can("isValueMapped") && $fieldDef->isValueMapped;
          my $field = $meta->get('FIELD', $name);
          next unless $field;

          # prevent from mall-formed formDefinitions
          if ($seenFields{$name}) {
            $this->log("WARNING: malformed form definition for $web.$formName - field $name appear twice must be unique");
            next;
          }
          $seenFields{$name} = 1;

          my $value = $field->{value};
          if ($isValueMapped) {
            $fieldDef->getOptions(); # load value map
            # SMELL: there's no api to get the mapped display value
            $value = $fieldDef->{valueMap}{$value} if defined $fieldDef->{valueMap} && defined $fieldDef->{valueMap}{$value};
          } 

          # extract outgoing links for formfield values
          $this->extractOutgoingLinks($web, $topic, $value, \%outgoingLinks);

          # bit of cleanup
          $value =~ s/<!--.*?-->//gs;

          # create a dynamic field indicating the field type to solr

          # date
          if ($type eq 'date') {
            try {
              my $epoch = $value;
              $epoch = Foswiki::Time::parseTime($value) unless $epoch =~ /^\d+$/;
              $epoch ||= 0;    # prevent formatTime to crap out
              $value = Foswiki::Time::formatTime($epoch, 'iso', 'gmtime');
              $doc->add_fields('field_' . $name . '_dt' => $value,);
            } catch Error::Simple with {
              $this->log("WARNING: malformed date value '$value'");
            };
          }

          # multi-valued types
          elsif ($isMultiValued || $name =~ /TopicType/) {    # TODO: make this configurable

            $doc->add_fields('field_' . $name . '_lst' => [ split(/\s*,\s*/, $value) ]);
          }

          # make it a text field unless its name does not indicate otherwise
          else {
            my $fieldName = 'field_' . $name;
            my $fieldType = '_s';
            if ($fieldName =~ s/(_(?:i|s|l|t|b|f|dt|lst))$//) {
              $fieldType = $1;
            }
            if ($fieldType eq '_f') {
              if ($value =~ /^\s*([\-\+]?\d+(\.\d+)?)\s*$/) {
                $doc->add_fields($fieldName . '_f' => $1,);
              } else {
                $this->log("WARNING: malformed float value '$value'");
              }
            } elsif ($fieldType eq '_s') {

              # applying a full plainify might alter the content too much in some cases. so
              # we try to remove only those characters that break the json parser
              #$value = $this->plainify($value, $web, $topic);
              $value =~ s/<!--.*?-->//gs;    # remove all HTML comments
              $value =~ s/<[^>]*>/ /g;       # remove all HTML tags
              $value = $this->discardIllegalChars($value);       # remove illegal characters

              $doc->add_fields(
                $fieldName . '_s' => $value,
                $fieldName . '_search' => $value,
              ) if defined $value && $value ne '';
            } else {
              $doc->add_fields($fieldName . $fieldType => $value,) if defined $value && $value ne '';
            }
          }
        }
      }
    }
  }

  # store all outgoing links collected so far
  foreach my $link (keys %outgoingLinks) {
    next if $link eq "$web.$topic";    # self link is not an outgoing link
    $doc->add_fields(outgoing => $link);
  }

  # all prefs are of type _t
  # TODO it may pay off to detect floats and ints
  my @prefs = $meta->find('PREFERENCE');
  if (@prefs) {
    foreach my $pref (@prefs) {
      my $name = $pref->{name};
      my $value = $pref->{value};
      $doc->add_fields(
        'preference_' . $name . '_t' => $value,
        'preference' => $name,
      );
    }
  }

  # call index topic handlers
  my %seen;
  foreach my $sub (@Foswiki::Plugins::SolrPlugin::knownIndexTopicHandler) {
    next if $seen{$sub};
    try {
      &$sub($this, $doc, $web, $topic, $meta, $text);
      $seen{$sub} = 1;
    }
    catch Foswiki::OopsException with {
      my $e = shift;
      $this->log("ERROR: while calling indexTopicHandler: " . $e->stringify());
    };
  }

  # get extra fields like acls and other properties

  my $t1 = [Time::HiRes::gettimeofday] if PROFILE;
  my @aclFields = $this->getAclFields($web, $topic, $meta);
  $doc->add_fields(@aclFields) if @aclFields;

  if (PROFILE) {
    my $elapsed = int(Time::HiRes::tv_interval($t1) * 1000);
    $this->log("took $elapsed ms to get the extra fields from $web.$topic");
    $t1 = [Time::HiRes::gettimeofday];
  }

  # attachments
  my @attachments = $meta->find('FILEATTACHMENT');
  if (@attachments) {
    my $thumbnail;
    my $firstImage;
    my %sorting = map { $_ => lc($_->{comment} || $_->{name}) } @attachments;
    foreach my $attachment (sort { $sorting{$a} cmp $sorting{$b} } @attachments) {

      # is the attachment is the skip list?
      my $name = $attachment->{'name'} || '';
      if ($this->isSkippedAttachment($web, $topic, $name)) {
        $this->log("Skipping attachment $web.$topic.$name");
        next;
      }

      # add attachment names to the topic doc
      $doc->add_fields('attachment' => $name);

      # decide on thumbnail
      if (!defined $thumbnail && $attachment->{attr} && $attachment->{attr} =~ /t/) {
        $thumbnail = $name;
      }
      if (!defined $firstImage && $name =~ /\.(png|jpe?g|gif|bmp|svg)$/i) {
        $firstImage = $name;
      }

      # then index each of them
      $this->indexAttachment($web, $topic, $attachment, \@aclFields);
    }

    # take the first image attachment when no thumbnail was specified explicitly
    $thumbnail = $firstImage if !defined($thumbnail) && defined($firstImage);
    $doc->add_fields('thumbnail' => $thumbnail) if defined $thumbnail;
  }

  if (PROFILE) {
    my $elapsed = int(Time::HiRes::tv_interval($t1) * 1000);
    $this->log("took $elapsed ms to index all attachments at $web.$topic");
    $t1 = [Time::HiRes::gettimeofday];
  }

  # add the document to the index
  try {
    $this->add($doc);
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };

  $this->commit();

  if (PROFILE) {
    my $elapsed = int(Time::HiRes::tv_interval($t0) * 1000);
    $this->log("took $elapsed ms to index topic $web.$topic");
    $t0 = [Time::HiRes::gettimeofday];
  }

}

################################################################################
# returns one of the SupportedLanguages or undef if not found
sub getContentLanguage {
  my ($this, $web, $topic) = @_;

  unless (defined $Foswiki::cfg{SolrPlugin}{SupportedLanguages}) {
    Foswiki::Func::writeWarning("{SolrPlugin}{SupportedLanguages} not defined. Please run configure.");
    return;
  }

  my $donePush = 0;
  if ($web ne $this->{session}{webName} || $topic ne $this->{session}{topicName}) {
    Foswiki::Func::pushTopicContext($web, $topic);
    $donePush = 1;
  }

  my $prefsLanguage = Foswiki::Func::getPreferencesValue('CONTENT_LANGUAGE') || '';
  my $contentLanguage = $Foswiki::cfg{SolrPlugin}{SupportedLanguages}{$prefsLanguage} || 'detect';

  #$this->log("contentLanguage=$contentLanguage") if DEBUG;

  Foswiki::Func::popTopicContext() if $donePush;

  return $contentLanguage;
}

################################################################################
sub extractOutgoingLinks {
  my ($this, $web, $topic, $text, $outgoingLinks) = @_;

  my $removed = {};

  # normal wikiwords
  $text = $this->takeOutBlocks($text, 'noautolink', $removed);
  $text =~ s#(?:($Foswiki::regex{webNameRegex})\.)?($Foswiki::regex{wikiWordRegex}|$Foswiki::regex{abbrevRegex})#$this->_addLink($outgoingLinks, $web, $topic, $1, $2)#gexom;
  $this->putBackBlocks(\$text, $removed, 'noautolink');

  # square brackets
  $text =~ s#\[\[([^\]\[\n]+)\]\]#$this->_addLink($outgoingLinks, $web, $topic, undef, $1)#ge;
  $text =~ s#\[\[([^\]\[\n]+)\]\[([^\]\n]+)\]\]#$this->_addLink($outgoingLinks, $web, $topic, undef, $1)#ge;

}

sub _addLink {
  my ($this, $links, $baseWeb, $baseTopic, $web, $topic) = @_;

  $web ||= $baseWeb;
  ($web, $topic) = $this->normalizeWebTopicName($web, $topic);

  my $link = $web . "." . $topic;
  return '' if $link =~ /^http|ftp/;    # don't index external links
  return '' unless Foswiki::Func::topicExists($web, $topic);

  $link =~ s/\%SCRIPTURL(PATH)?{.*?}\%\///g;
  $link =~ s/%WEB%/$baseWeb/g;
  $link =~ s/%TOPIC%/$baseTopic/g;

  #print STDERR "link=$link\n" unless defined $links->{$link};

  $links->{$link} = 1;

  return $link;
}

################################################################################
# add the given attachment to the index.
sub indexAttachment {
  my ($this, $web, $topic, $attachment, $commonFields) = @_;

  #my $t0 = [Time::HiRes::gettimeofday] if PROFILE;

  my $name = $attachment->{'name'} || '';
  if (VERBOSE) {
    #$this->log("Indexing attachment $web.$topic.$name");
  } else {

    #$this->log("a", 1);
  }

  # SMELL: while the below test weeds out attachments that somehow where gone physically it is too expensive for the
  # average case to open all attachments
  #unless (defined(Foswiki::Func::readAttachment($web, $topic, $name))) {
  #  $this->log("... attachment $web.$topic.$name not found") if DEBUG;
  #  return;
  #}

  # the attachment extension has to be checked

  my $extension = '';
  my $title = $name;
  if ($name =~ /^(.+)\.(\w+?)$/) {
    $title = $1;
    $extension = lc($2);
  }
  $title =~ s/_+/ /g;
  $extension = 'jpg' if $extension =~ /jpe?g/i;

  # check extension
  my $indexextensions = $this->indexExtensions();
  my $attText = '';
  if ($indexextensions->{$extension}) {
    $attText = $this->getStringifiedVersion($web, $topic, $name);
    $attText = $this->plainify($attText, $web, $topic);
  } else {

    #$this->log("not reading attachment $web.$topic.$name");
  }

  my $doc = $this->newDocument();

  my $comment = $attachment->{'comment'} || '';
  my $size = $attachment->{'size'} || 0;
  my $date = $attachment->{'date'} || 0;
  $date = Foswiki::Func::formatTime($date, 'iso', 'gmtime');
  my $author = getWikiName($attachment->{user});

  # get summary
  my $summary = $this->substr($attText, 0, 300);

  #  my $author = $attachment->{'user'} || $attachment->{'author'} || '';
  #  $author = Foswiki::Func::getWikiName($author) || 'UnknownUser';
  #  # weed out some strangers
  #  $author = 'UnknownUser' unless Foswiki::Func::isValidWikiWord($author);

  # get contributor and most recent author
  my @contributors = $this->getContributors($web, $topic, $attachment);
  my %contributors = map {$_ => 1} @contributors;
  $doc->add_fields(contributor => [keys %contributors]);

  # normalize web name
  $web =~ s/\//\./g;
  my $id = "$web.$topic.$name";

  # view url
  #my $url = $this->getScriptUrlPath($web, $topic, 'viewfile', filename => $name);
  my $webDir = $web;
  $webDir =~ s/\./\//g;
  my $url = $Foswiki::cfg{PubUrlPath}.'/'.$webDir.'/'.$topic.'/'.$name;

  my $collection = $Foswiki::cfg{SolrPlugin}{DefaultCollection} || "wiki";
  my $icon = $this->mapToIconFileName($extension);

  # gather all webs and parent webs
  my @webCats = ();
  my @prefix = ();
  foreach my $component (split(/\./, $web)) {
    push @prefix, $component;
    push @webCats, join(".", @prefix);
  }

  # TODO: what about createdate and createauthor for attachments
  $doc->add_fields(

    # common fields
    id => $id,
    collection => $collection,
    url => $url,
    web => $web,
    webcat => [@webCats],
    topic => $topic,
    webtopic => "$web.$topic",
    title => $title,
    type => $extension,
    text => $attText,
    summary => $summary,
    author => $author,
    date => $date,

    # attachment fields
    name => $name,
    comment => $comment,
    size => $size,
    icon => $icon,
    container_id => $web . '.' . $topic,
    container_url => $this->getScriptUrlPath($web, $topic, "view"),
    container_title => $this->getTopicTitle($web, $topic),
  );

  # tag and analyze language
  # SMELL: silently assumes all attachments to a topic are the same langauge
  my $contentLanguage = $this->getContentLanguage($web, $topic);
  if (defined $contentLanguage && $contentLanguage ne 'detect') {
    $doc->add_fields(
      language => $contentLanguage,
      'text_' . $contentLanguage => $attText,
    );
  }

  # add extra fields, i.e. ACLs
  $doc->add_fields(@$commonFields) if $commonFields;

  # call index attachment handlers
  my %seen;
  foreach my $sub (@Foswiki::Plugins::SolrPlugin::knownIndexAttachmentHandler) {
    next if $seen{$sub};
    &$sub($this, $doc, $web, $topic, $attachment);
    $seen{$sub} = 1;
  }

  # add the document to the index
  try {
    $this->add($doc);
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };

  $this->commit();

  #if (PROFILE) {
  #  my $elapsed = int(Time::HiRes::tv_interval($t0) * 1000);
  #  $this->log("took $elapsed ms to index attachment $web.$topic.$name");
  #}
}

################################################################################
# add a document to the index
sub add {
  my ($this, $doc) = @_;

  #my ($package, $file, $line) = caller;
  #print STDERR "called add from $package:$line\n";

  return unless $this->{solr};
  return $this->{solr}->add($doc);
}

################################################################################
# optimize index
sub optimize {
  my $this = shift;

  return unless $this->{solr};

  # temporarily set a different timeout for this operation
  my $agent = $this->{solr}->agent();
  my $oldTimeout = $agent->timeout();

  $agent->timeout($this->{optimizeTimeout});  

  $this->{solr}->commit();
  $this->log("Optimizing index");
  $this->{solr}->optimize({
    waitSearcher => WAIT_SEARCHER,
    softCommit => SOFTCOMMIT,
  });

  $agent->timeout($oldTimeout);
}

################################################################################
# commit every COMMIT_THRESHOLD times
sub commit {
  my ($this, $force) = @_;

  return unless $this->{solr};

  $this->{commitCounter}++;

  if ($this->{commitCounter} > 1 && ($this->{commitCounter} >= COMMIT_THRESHOLD || $force)) {
    $this->log("Committing index") if VERBOSE;
    $this->{solr}->commit({
        waitSearcher => WAIT_SEARCHER,
        softCommit => SOFTCOMMIT,
    });
    $this->{commitCounter} = 0;

    # invalidate page cache for all search interfaces
    if ($Foswiki::cfg{Cache}{Enabled} && $this->{session}{cache}) {
      my @webs = Foswiki::Func::getListOfWebs("user, public");
      foreach my $web (@webs) {
        next if $web eq $Foswiki::cfg{TrashWebName};

        #$this->log("firing dependencies in $web");
        $this->{session}->{cache}->fireDependency($web, "WebSearch");

        # SMELL: should record all topics a SOLRSEARCH is on, outside of a dirtyarea
      }
    }
  }
}

################################################################################
sub newDocument {

  #my $this = shift;

  return WebService::Solr::Document->new;
}

################################################################################
sub deleteTopic {
  my ($this, $web, $topic, $meta) = @_;

  $this->deleteDocument($web, $topic);

  if ($meta) {
    my @attachments = $meta->find('FILEATTACHMENT');
    if (@attachments) {
      foreach my $attachment (@attachments) {
        $this->deleteDocument($web, $topic, $attachment);
      }
    }
  } else {
    $this->deleteByQuery("web:\"$web\" topic:\"$topic\"");
  }
}

################################################################################
sub deleteWeb {
  my ($this, $web) = @_;

  $web =~ s/\//./g;
  $this->deleteByQuery("web:\"$web\"");
}

################################################################################
sub deleteByQuery {
  my ($this, $query) = @_;

  return unless $query;

  #$this->log("Deleting documents by query $query") if VERBOSE;

  my $success;
  try {
    $success = $this->{solr}->delete_by_query($query);
    $this->commit();
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };

  return $success;
}

################################################################################
sub deleteDocument {
  my ($this, $web, $topic, $attachment) = @_;

  $web =~ s/\//\./g;
  my $id = "$web.$topic";
  $id .= ".$attachment" if $attachment;

  #$this->log("Deleting document $id");

  try {
    $this->{solr}->delete_by_id($id);
    $this->commit();
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };

}

################################################################################
sub lock {
  my $this = shift;

  my $lockfile = Foswiki::Func::getWorkArea('SolrPlugin') . "/indexer.lock";
  open($this->{lock}, ">$lockfile")
    or die "can't create lockfile $lockfile";

  flock($this->{lock}, LOCK_EX)
    or die "can't lock indexer: $!";
}

################################################################################
sub unlock {
  my $this = shift;

  flock($this->{lock}, LOCK_UN)
    or die "unable to unlock: $!";
}

################################################################################
sub getStringifiedVersion {
  my ($this, $web, $topic, $attachment) = @_;

  my $pubpath = Foswiki::Func::getPubDir();
  my $dirWeb = $web;
  $dirWeb =~ s/\./\//g;
  $web =~ s/\//\./g;

  my $filename = "$pubpath/$dirWeb/$topic/$attachment";

  # untaint..
  $filename =~ /(.*)/;
  $filename = $1;

  my $mime = $this->mmagic->checktype_filename($filename);
  my $skipCaching = ($mime =~ /^(text\/plain)$/)?1:0;

  #print STDERR "filename=$filename, mime=$mime\n";

  my $workArea = Foswiki::Func::getWorkArea('SolrPlugin');
  my $cachedFilename = "$workArea/$web/$topic/$attachment.txt";

  # untaint..
  $cachedFilename =~ /(.*)/;
  $cachedFilename = $1;

  my $attText = '';

  if ($skipCaching) {
    #print STDERR "skipping caching attachment $filename as it is a $mime\n";
    $attText = Foswiki::Contrib::Stringifier->stringFor($filename) || '';
  } else {

    mkdir "$workArea/$web" unless -d "$workArea/$web";
    mkdir "$workArea/$web/$topic" unless -d "$workArea/$web/$topic";

    my $origModified = modificationTime($filename);
    my $cachedModified = modificationTime($cachedFilename);

    if ($origModified > $cachedModified) {

      #$this->log("caching stringified version of $attachment in $cachedFilename");
      $attText = Foswiki::Contrib::Stringifier->stringFor($filename) || '';
      Foswiki::Func::saveFile($cachedFilename, $attText);
    } else {

      #$this->log("found stringified version of $attachment in cache");
      $attText = Foswiki::Func::readFile($cachedFilename);
    }
  }

  $attText = Encode::decode('Windows-1252', $attText);
  $attText = Encode::encode($Foswiki::cfg{Site}{CharSet}, $attText);
  return $attText;
}

################################################################################
sub mmagic {
  my $this = shift;

  unless (defined $this->{mmagic}) {
    require File::MMagic;
    $this->{mmagic} = File::MMagic->new();
  }

  return $this->{mmagic};
}

################################################################################
sub modificationTime {
  my $filename = shift;

  my @stat = stat($filename);
  return $stat[9] || $stat[10] || 0;
}

################################################################################
sub nrKnownUsers {
  my ($this, $id) = @_;

  $this->getListOfUsers();
  return $this->{_nrKnownUsers};
}

################################################################################
sub isKnownUser {
  my ($this, $id) = @_;

  $this->getListOfUsers();
  return (exists $this->{_knownUsers}{$id}?1:0);
}

################################################################################
# Get a list of all registered users
sub getListOfUsers {
  my $this = shift;

  unless (defined $this->{_knownUsers}) {

    my $it = Foswiki::Func::eachUser();
    while ($it->hasNext()) {
      my $user = $it->next();
      $this->{_knownUsers}{$user} = 1;# if Foswiki::Func::topicExists($Foswiki::cfg{UsersWebName}, $user);
    }

    #$this->log("known users=".join(", ", sort keys %{$this->{_knownUsers}})) if DEBUG;
    $this->{_nrKnownUsers} = scalar(keys %{ $this->{_knownUsers} });

    #$this->log("found ".$this->{_nrKnownUsers}." users");
  }

  return $this->{_knownUsers};
}

################################################################################
sub getContributors {
  my ($this, $web, $topic, $attachment) = @_;

  #my $t0 = [Time::HiRes::gettimeofday] if PROFILE;

  my $maxRev;
  try {
    (undef, undef, $maxRev) = $this->getRevisionInfo($web, $topic, undef, $attachment);
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };
  return () unless defined $maxRev;

  $maxRev =~ s/r?1\.//go;    # cut 'r' and major

  my %contributors = ();

  # get most recent
  my (undef, $user, $rev) = $this->getRevisionInfo($web, $topic, $maxRev, $attachment, $maxRev);
  my $mostRecent = getWikiName($user);
  $contributors{$mostRecent} = 1;

  # get creator
  (undef, $user, $rev) = $this->getRevisionInfo($web, $topic, 1, $attachment, $maxRev);
  my $creator = getWikiName($user);
  $contributors{$creator} = 1;

  # only take the top 10; extracting revinfo takes too long otherwise :(
  $maxRev = 10 if $maxRev > 10;

  for (my $i = $maxRev; $i > 0; $i--) {
    my (undef, $user, $rev) = $this->getRevisionInfo($web, $topic, $i, $attachment, $maxRev);
    my $wikiName = getWikiName($user);
    $contributors{$wikiName} = 1;
  }

  #if (PROFILE) {
  #  my $elapsed = int(Time::HiRes::tv_interval($t0) * 1000);
  #  $this->log("took $elapsed ms to get contributors of $web.$topic".($attachment?'.'.$attachment->{name}:''));
  #}
  delete $contributors{$mostRecent};
  delete $contributors{$creator};

  my @contributors = ($mostRecent, keys %contributors, $creator);
  return @contributors;
}

################################################################################
sub getWikiName {
  my $user = shift;

  my $wikiName = Foswiki::Func::getWikiName($user) || 'UnknownUser';
  $wikiName = 'UnknownUser' unless Foswiki::Func::isValidWikiWord($wikiName);    # weed out some strangers

  return $wikiName;
}

################################################################################
# wrapper around original getRevisionInfo which
# can't deal with dots in the webname
sub getRevisionInfo {
  my ($this, $web, $topic, $rev, $attachment, $maxRev) = @_;

  ($web, $topic) = $this->normalizeWebTopicName($web, $topic);

  if ($attachment && (!defined($rev) || $rev == $maxRev)) {

    # short cut for attachments
    my $info = {};
    $info->{version} = $attachment->{version} || $maxRev;
    $info->{date} = $attachment->{date};
    $info->{author} = $attachment->{author} || $attachment->{user};

    #$info->{date} = $this->getTimestamp() unless defined $info->{date};
    #$info->{author} = $Foswiki::Users::BaseUserMapping::DEFAULT_USER_CUID unless defined $info->{author};
    return $info;
  } else {
    return Foswiki::Func::getRevisionInfo($web, $topic, $rev, $attachment);
  }
}

################################################################################
# returns the list of users granted view access, or "all" if all users have got view access
sub getGrantedUsers {
  my ($this, $web, $topic, $meta, $text) = @_;

  my %grantedUsers;
  my $forbiddenUsers;

  my $allow = $this->getACL($meta, 'ALLOWTOPICVIEW');
  my $deny = $this->getACL($meta, 'DENYTOPICVIEW');

  if (DEBUG) {
    $this->log("topicAllow=@$allow") if defined $allow;
    $this->log("topicDeny=@$deny") if defined $deny;
  }

  # Check DENYTOPIC
  if (defined $deny) {
    if (scalar(@$deny)) {
      $forbiddenUsers = $this->expandUserList(@$deny);
    } else {

      $this->log("empty deny -> grant all access") if DEBUG;

      # Empty deny
      return ['all'];
    }
  }
  $this->log("(1) forbiddenUsers=@$forbiddenUsers") if DEBUG && defined $forbiddenUsers;

  # Check ALLOWTOPIC
  if (defined($allow)) {
    if (scalar(@$allow)) {
      $grantedUsers{$_} = 1 foreach @{$this->expandUserList(@$allow)};

      if (defined $forbiddenUsers) {
        delete $grantedUsers{$_} foreach @$forbiddenUsers;
      }
      my @grantedUsers = keys %grantedUsers;

      $this->log("(1) granting access for @grantedUsers") if DEBUG;

      # A non-empty ALLOW is final
      return \@grantedUsers;
    }
  }

  # use cache if possible (no topic-level perms set)
  if (!defined($deny) && exists $this->{_webACLCache}{$web}) {
    $this->log("found in acl cache ".join(", ", sort @{$this->{_webACLCache}{$web}})) if DEBUG;
    return $this->{_webACLCache}{$web};
  }

  my $webMeta = $meta->getContainer;
  my $webAllow = $this->getACL($webMeta, 'ALLOWWEBVIEW');
  my $webDeny = $this->getACL($webMeta, 'DENYWEBVIEW');

  if (DEBUG) {
    $this->log("webAllow=@$webAllow") if defined $webAllow;
    $this->log("webDeny=@$webDeny") if defined $webDeny;
  }

  # Check DENYWEB, but only if DENYTOPIC is not set 
  if (!defined($deny) && defined($webDeny) && scalar(@$webDeny)) {
    push @{$forbiddenUsers}, @{$this->expandUserList(@$webDeny)};
  }
  $this->log("(2) forbiddenUsers=@$forbiddenUsers") if DEBUG && defined $forbiddenUsers;

  if (defined($webAllow) && scalar(@$webAllow)) {
    $grantedUsers{$_} = 1 foreach @{$this->expandUserList(@$webAllow)};
  } elsif (!defined($deny) && !defined($webDeny)) {

    $this->log("no denies, no allows -> grant all access") if DEBUG;

    # No denies, no allows -> open door policy
    $this->{_webACLCache}{$web} = ['all'];
    return ['all'];

  } else {
    %grantedUsers = %{$this->getListOfUsers()};
  }

  if (defined $forbiddenUsers) {
    delete $grantedUsers{$_} foreach @$forbiddenUsers;
  }

  # get list of users granted access that actually still exist
  foreach my $user (keys %grantedUsers) {
    $grantedUsers{$user}++ if defined $this->isKnownUser($user);
  }

  my @grantedUsers = ();
  foreach my $user (keys %grantedUsers) {
    push @grantedUsers, $user if $grantedUsers{$user} > 1;
  }

  @grantedUsers = ('all') if scalar(@grantedUsers) == $this->nrKnownUsers;

  # can't cache when there are topic-level perms 
  $this->{_webACLCache}{$web} = \@grantedUsers unless defined($deny);

  $this->log("(2) granting access for ".join(", ", sort @grantedUsers)) if DEBUG;

  return \@grantedUsers;
}

################################################################################
# SMELL: coppied from core; only works with topic-based ACLs
sub getACL {
  my ($this, $meta, $mode) = @_;

  if (defined $meta->{_topic} && !defined $meta->{_loadedRev}) {
    # Lazy load the latest version.
    $meta->loadVersion();
  }

  my $text = $meta->getPreference($mode);
  return unless defined $text;

  # Remove HTML tags (compatibility, inherited from Users.pm
  $text =~ s/(<[^>]*>)//g;

  # Dump the users web specifier if userweb
  my @list = grep { /\S/ } map {
    s/^($Foswiki::cfg{UsersWebName}|%USERSWEB%|%MAINWEB%)\.//;
    $_
  } split(/[,\s]+/, $text);

  #print STDERR "getACL($mode): ".join(', ', @list)."\n";

  return \@list;
}

################################################################################
sub expandUserList {
  my ($this, @users) = @_;

  my %result = ();

  foreach my $id (@users) {
    $id =~ s/(<[^>]*>)//go;
    $id =~ s/^($Foswiki::cfg{UsersWebName}|%USERSWEB%|%MAINWEB%)\.//;
    next unless $id;

    if (Foswiki::Func::isGroup($id)) {
      $result{$_} = 1 foreach @{$this->_expandGroup($id)};
    } else {
      $result{getWikiName($id)} = 1;
    }
  }

  return [keys %result];
}

sub _expandGroup {
  my ($this, $group) = @_;

  return $this->{_groupCache}{$group} if exists $this->{_groupCache}{$group};

  my %result = ();

  my $it = Foswiki::Func::eachGroupMember($group);

  while ($it->hasNext) {
    my $id = $it->next;

    if (Foswiki::Func::isGroup($id)) {
      $result{$_} = 1 foreach @{$this->_expandGroup($id)};
    } else {
      $result{getWikiName($id)} = 1;
    }
  }

  $this->{_groupCache}{$group} = [keys %result];

  return [keys %result];
}


################################################################################
sub getAclFields {
  my $this = shift;

  my $grantedUsers = $this->getGrantedUsers(@_);
  return () unless $grantedUsers;
  return ('access_granted' => $grantedUsers);
}

################################################################################
sub getTimestampFile {
  my ($this, $web, $topic) = @_;

  return unless $web;
  return unless Foswiki::Func::webExists($web);

  $web =~ s/\//./g;

  my $timestampsDir = Foswiki::Func::getWorkArea('SolrPlugin') . '/timestamps';
  mkdir $timestampsDir unless -d $timestampsDir;

  return $timestampsDir . '/' . $web . '.timestamp' unless defined $topic;

  $timestampsDir .= '/' . $web;
  mkdir $timestampsDir unless -d $timestampsDir;

  return $timestampsDir . '/' . $topic . '.timestamp';
}

################################################################################
sub setTimestamp {
  my ($this, $web, $topic, $time) = @_;

  $time = time() unless defined $time;

  my $timestampFile = $this->getTimestampFile($web, $topic);
  return 0 unless $timestampFile;

  Foswiki::Func::saveFile($timestampFile, $time);

  return $time;
}

################################################################################
sub getTimestamp {
  my ($this, $web, $topic) = @_;

  my $timestampFile = $this->getTimestampFile($web, $topic);

  return 0 unless $timestampFile;

  my $data = Foswiki::Func::readFile($timestampFile);
  return ($data || 0);
}

1;

