# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2009-2015 Michael Daum http://michaeldaumconsulting.com
# Copyright (C) 2013-2015 Modell Aachen GmbH http://modell-aachen.de
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
use Foswiki::Plugins::SolrPlugin::Scheduler;
use Foswiki::Form ();
use Foswiki::OopsException ();
use Foswiki::Time ();
use Foswiki::Contrib::Stringifier ();
use Time::Local;
use Time::HiRes qw( time );
use POSIX qw( strftime );

use constant TRACE => 0;    # toggle me
use constant VERBOSE => 1;  # toggle me
use constant PROFILE => 0;  # toggle me

#use Time::HiRes (); # enable this too when profiling

##############################################################################
sub new {
  my ($class, $session) = @_;

  my $this = $class->SUPER::new($session);

  $this->{url} = $Foswiki::cfg{SolrPlugin}{UpdateUrl} || $Foswiki::cfg{SolrPlugin}{Url};

  $this->{_groupCache} = {};
  $this->{_webACLCache} = {};

  $this->{_AddQueue} = [];
  $this->{_DeleteQueue} = [];

  throw Error::Simple("no solr url defined") unless defined $this->{url};

  # Compared to the Search constructor there's no autostarting here
  # to prevent any indexer to accidentally create a solrindex lock and further
  # java inheriting it. So we simply test for connectivity and barf if that fails.
  $this->connect();

  unless ($this->{solr}) {
    $this->log("ERROR: can't connect to solr daemon");
  }

  # trap SIGINT
  $SIG{INT} = sub {
    $this->log("got interrupted ... finishing work");
    $this->{_trappedSignal} = 1; # will be detected by loops further down
  };

  $this->{workArea} = Foswiki::Func::getWorkArea('SolrPlugin');

  $this->{TopicTitleCache} = {};

  return $this;
}

################################################################################
sub finish {
  my $this = shift;

  undef $this->{_knownUsers};
  undef $this->{_groupCache};
  undef $this->{_webACLCache};
}

sub clearWebACLs {
  my $this = shift;
  undef $this->{_webACLCache};
}

################################################################################
# entry point to either update one topic or a complete web
sub index {
  my $this = shift;

  # exclusively lock the indexer to prevent a delta and a full index
  # mode to run in parallel

  try {
    my $query = Foswiki::Func::getRequestObject();
    my $web = $query->param('web') || 'all';
    my $topic = $query->param('topic');
    my $mode = $query->param('mode') || 'delta';
    my $optimize = Foswiki::Func::isTrue($query->param('optimize'));
    my $useScheduler = Foswiki::Func::isTrue($query->param('scheduler'));
    my $gracetime = $query->param('gracetime');
    my $skipScheduled = Foswiki::Func::isTrue($query->param('skipscheduled'));

    if ($topic) {
      $web = $this->{session}->{webName} if !$web || $web eq 'all';

      $this->log("doing a topic index $web.$topic") if TRACE;
      $this->updateTopic($web, $topic);
    } else {

      local $this->{bulkoperation} = 1;
      $this->log("doing a web index in $mode mode") if TRACE;
      $this->update($web, $mode, $useScheduler, $gracetime, $skipScheduled);
    }

    $this->commit($mode eq 'full' && !$topic);
    $this->optimize() if $optimize;
  }

  catch Error::Simple with {
    my $error = shift;
    print STDERR "ERROR: " . $error->{-text} . "\n";
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

  $this->indexAttachment($web, $topic, $attachment, \@aclFields, $meta);
}

sub _filterMappedWebs {
  my ($this, $web, $skipLog) = @_;

  my $targetHost = $this->{wikiHostMap}{$_} || $this->{wikiHost};
  return 1 if $this->{wikiHost} eq $targetHost;
  $this->log("$_: not indexing because it belongs to $targetHost") unless $skipLog;
  0;
}

################################################################################
# update documents of a web - either in fully or incremental
# on a full update, the complete web is removed from the index prior to updating it;
# this calls updateTopic for each topic to be updated
sub update {
  my ($this, $web, $mode, $useScheduler, $gracetime, $skipScheduled) = @_;

  $mode ||= 'full';

  my $searcher = Foswiki::Plugins::SolrPlugin::getSearcher();

  # remove non-existing webs
  my @webs = grep { $this->_filterMappedWebs($_, 1) } $searcher->getListOfWebs();

  foreach my $thisWeb (@webs) {
    next if Foswiki::Func::webExists($thisWeb);
    $this->log("$thisWeb doesn't exist anymore ... deleting");
    $this->deleteWeb($thisWeb);
  }

  if (!defined($web) || $web eq 'all') {
    @webs = Foswiki::Func::getListOfWebs("user");
  } else {
    @webs = ();
    # Add Web and subwebs to indexing list
    foreach my $item (split(/\s*,\s*/, $web)) {
      push @webs, $item;
      push @webs, Foswiki::Func::getListOfWebs("user", $item);
    }
  }
  @webs = grep { $this->_filterMappedWebs($_) } @webs;

  # TODO: check the list of webs we had the last time we did a full index
  # of all webs; then possibly delete them

  my $skipAll = Foswiki::Func::getPreferencesValue('SOLR_SCHEDULER_SKIP_ALL') || 0;
  my ($schedule, $midnight, $now);
  my $scheduler = Foswiki::Plugins::SolrPlugin::Scheduler->new($this->{session});
  $schedule = $scheduler->readSchedule;
  if ($useScheduler && !$skipAll) {
    $gracetime = ($gracetime || 30) * 60;
    $now = time;
    my ($day, $month, $year) = (gmtime)[3..5];
    $midnight = timelocal(0, 0, 0, $day, $month, $year);
  }

  foreach my $web (@webs) {

    my $origWeb = $web;
    $origWeb =~ s/\./\//g;
    $web =~ s/\//./g;

    if ($this->isSkippedWeb($web)) {
      #$this->log("Skipping web $web");
      next;
    }

    my $skip = Foswiki::Func::getPreferencesValue('SOLR_SCHEDULER_SKIP_WEB', $web) || 0;
    if ($useScheduler) {
      next if Foswiki::Func::isTrue($skipAll);
      next if Foswiki::Func::isTrue($skip);
      $schedule->{$web} = ($Foswiki::cfg{SolrPlugin}{DefaultScheduleTime} || 360) unless defined $schedule->{$web};
      my $itime = $schedule->{$web} * 60 + $midnight;
      next unless $itime > $now - $gracetime && $itime < $now + $gracetime;
    } elsif ($skipScheduled) {
      next if defined $schedule->{$web} && !Foswiki::Func::isTrue($skip);
    }

    # remove all non-existing topics
    foreach my $topic ($searcher->getListOfTopics($web)) {
      next if Foswiki::Func::topicExists($web, $topic);
      $this->log("$web.$topic gone ... deleting");
      $this->deleteTopic($web, $topic);
    }

    if ($mode eq 'full') {
      $this->_updateAllTopicsAndRemoveOldEntriesOf($web);
    } else {
      $this->_updateAllTopicsWithChangesOf($web, $origWeb);
    }

    last if $this->{_trappedSignal};
  }
  $this->commitPendingWork();
}

sub commitPendingWork {
    my ($this) = @_;

    if((scalar @{$this->{_AddQueue}}) || (scalar @{$this->{_DeleteQueue}})) {
        $this->commit;
    }
}

sub _updateAllTopicsAndRemoveOldEntriesOf {

  my ( $this, $web, ) = @_;
  my $timestamp = $this->_getLatestSolrTimestamp();

  foreach my $topic (Foswiki::Func::getTopicList($web)) {
    $this->deleteTopic($web, $topic);
    next if $this->isSkippedTopic($web, $topic);
    $this->indexTopic($web, $topic);
    last if $this->{_trappedSignal};
  }

  if (defined $timestamp && !$this->{_trappedSignal}) {
      $this->commitPendingWork();
      $this->log("Deleting old data");
      $this->deleteByQuery("web:\"$web\" -task_id_s:* -type:\"ua_user\" -type:\"ua_group\""
          . " timestamp:[* TO $timestamp]");
  }
  $this->commitPendingWork();
}

sub _getLatestSolrTimestamp {
  my ( $this, ) = @_;

  my $searcher = Foswiki::Plugins::SolrPlugin::getSearcher();
  my $response = $searcher->solrSearch(
      "timestamp:*",
      {
          rows => 1,
          sort => "timestamp desc",
      }
  );

  my $timestamp;
  my @docs = $response->docs;
  if (scalar(@docs) == 1) {
      $timestamp = $docs[0]->value_for("timestamp");
  }

  return $timestamp;
}

sub _updateAllTopicsWithChangesOf {
  my ( $this, $web, $origWeb, ) = @_;
  my %timeStamps = ();

  # get all timestamps for this web
  my $searcher = Foswiki::Plugins::SolrPlugin::getSearcher();
  $searcher->iterate({
      query => "web:$web type:topic",
      fields => "topic,timestamp",
      process => sub {
        my $doc = shift;
        my $topic = $doc->value_for("topic");
        my $time = $doc->value_for("timestamp");
        $time =~ s/\.\d+Z$/Z/g; # remove miliseconds as that's incompatible with perl
        $time = int(Foswiki::Time::parseTime($time));
        $timeStamps{$topic} = $time;
      }
    });

  # delta
  my @topics = Foswiki::Func::getTopicList($web);
  foreach my $topic (@topics) {
    next if $this->isSkippedTopic($web, $topic);

    my $changed;
    if ($Foswiki::Plugins::SESSION->can('getApproxRevTime')) {
      $changed = $Foswiki::Plugins::SESSION->getApproxRevTime($origWeb, $topic);
    } else {

      # This is here for old engines
      $changed = $Foswiki::Plugins::SESSION->{store}->getTopicLatestRevTime($origWeb, $topic);
    }

    my $topicTime = $timeStamps{$topic} || 0;
    next if $topicTime > $changed;

    $this->indexTopic($web, $topic);

    last if $this->{_trappedSignal};
  }
}

################################################################################
# update one specific topic; deletes the topic from the index before updating it again
sub updateTopic {
  my ($this, $web, $topic, $meta, $text) = @_;

  ($web, $topic) = $this->normalizeWebTopicName($web, $topic);

  $this->deleteTopic($web, $topic);

  return if $this->isSkippedWeb($web);
  return if $this->isSkippedTopic($web, $topic);

  if (Foswiki::Func::topicExists($web, $topic)) {
    $this->indexTopic($web, $topic, $meta, $text);
  } else {
    $this->log("... topic $web.$topic does not exist") if TRACE;
  }
}

################################################################################
# work horse: index one topic and all attachments
sub indexTopic {
  my ($this, $web, $topic, $meta, $text) = @_;

  my $t0 = [Time::HiRes::gettimeofday] if PROFILE;

  # Normalize web name
  $web =~ s/\//\./g;

  if (VERBOSE) {
    $this->log("Indexing topic $web.$topic");
  }

  # New Solr document for the current topic
  my $doc = $this->newDocument();

  unless (defined $meta && defined $text) {
    ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
    $text = '' unless defined $text; # not sure why this happens, but it does
  }

  # remove inline base64 resources
  $text =~ s/<[^>]+\s+src=["']data:[^"']+;base64,[a-z0-9+\/=]+["'][^>]+>//gi;

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
  }

  # all webs
  # get date
  my ($date, undef, $rev) = $this->getRevisionInfo($web, $topic);
  $date ||= 0;    # prevent formatTime to crap out
  $date = Foswiki::Func::formatTime($date, 'iso', 'gmtime');

  unless ($rev =~ /^\d+$/) {
    $this->log("Warning: invalid version '$rev' of $web.$topic");
    $rev = 1;
  }

  # get create date
  my ($createDate) = eval{$this->getRevisionInfo($web, $topic, 1)};
  $createDate ||= 0;    # prevent formatTime to crap out
  $createDate = Foswiki::Func::formatTime($createDate, 'iso', 'gmtime');

  #print STDERR "createDate=$createDate\n";

  # get contributor and most recent author
  my @contributors = $this->getContributors($web, $topic);
  my %contributors = map {$_ => 1} @contributors;
  $doc->add_fields(contributor => [keys %contributors]);

  my $author = $contributors[0];
  my $createAuthor = $contributors[ scalar(@contributors) - 1 ];

  # gather all webs and parent webs
  my @webCats = ();
  my @prefix = ();
  foreach my $component (split(/\./, $web)) {
    push @prefix, $component;
    push @webCats, join(".", @prefix);
  }

  my $title = $this->getTopicTitle($web, $topic, $meta);
  my $container_title = $this->getTopicTitle($web, $Foswiki::cfg{HomeTopicName});

  $doc->add_fields(

    # common fields
    id => "$web.$topic",
    url => $this->getScriptUrlPath($web, $topic, "view"),
    topic => $topic,
    web => $web,
    webcat => [@webCats],
    webtopic => "$web.$topic",
    title => $title,
    title_escaped_s => $this->escapeHtml($title),
    text => $text,
    summary => $this->getTopicSummary($web, $topic, $meta, $text),
    author => $author,
    date => $date,
    version => $rev,
    createauthor => $createAuthor,
    createdate => $createDate,
    type => 'topic',
    container_id => $web . '.'. $Foswiki::cfg{HomeTopicName},
    container_web => $web,
    container_topic => $Foswiki::cfg{HomeTopicName},
    container_url => $this->getScriptUrlPath($web, $Foswiki::cfg{HomeTopicName}, "view"),
    container_title => $container_title,
    container_title_escaped_s => $this->escapeHtml($container_title),
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
          my $mapped;
          my $escaped = $value;

          if ($isValueMapped) {

            # get mapped value
            if ($fieldDef->can('getDisplayValue')) {
              $mapped = $fieldDef->getDisplayValue($value);
            } else {

              # backwards compatibility
              $fieldDef->getOptions();    # load value map
              if (defined $fieldDef->{valueMap}) {
                my @values = ();
                foreach my $v (split(/\s*,\s*/, $value)) {
                  if (defined $fieldDef->{valueMap}{$v}) {
                    push @values, $fieldDef->{valueMap}{$v};
                  } else {
                    push @values, $v;
                  }
                }
                $mapped = join(", ", @values);
              }
            }
            $mapped = $value unless defined $mapped;
          }

          # bit of cleanup
          $mapped = $this->escapeHtml($mapped) if defined $mapped;
          $escaped = $this->escapeHtml($value) if defined $value;
          
          # create a dynamic field indicating the field type to solr
          if($fieldDef->can("solrIndexFieldHandler")){
            $fieldDef->solrIndexFieldHandler($doc,$value,$mapped);
          }

          #Date does not implement solrIndexFieldHandler, because it is a core-FormField
          if ($type =~ /^date/) {
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
          if ($isMultiValued || $name =~ /TopicType/ || $type eq 'radio') {    # TODO: make this configurable
            my $fieldName = 'field_' . $name;
            $fieldName =~ s/(_(?:i|s|l|t|b|f|dt|lst))$//;

            # For user+multi fields, all cuids have to be transformed to displayvalues
            if($type =~/^user\+multi/) {
              my $dv = [ split(/\s*,\s*/, $fieldDef->getDisplayValue($value)) ];
              $doc->add_fields($fieldName . '_dv_lst' => $dv);
              $doc->add_fields($fieldName . '_dv_msearch' => $dv);
            }

            $doc->add_fields($fieldName . '_lst' => [ split(/\s*,\s*/, $value) ]);
            $doc->add_fields($fieldName . '_lst_msearch' => [ split(/\s*,\s*/, $value) ]);
            $doc->add_fields($fieldName . '_escaped_lst' => [ split(/\s*,\s*/, $escaped) ]);
            $doc->add_fields($fieldName . '_select_lst' => [ split(/\s*,\s*/, $mapped) ]) if defined $mapped;
          }

          # finally make it a non-list field as well 
          {
            my $fieldName = 'field_' . $name;
            my $fieldType = '_s';

            # is there an explicit type info part of the formfield name?
            if ($fieldName =~ s/(_(?:i|s|l|t|b|f|dt|lst))$//) {
              $fieldType = $1;
            }

            # add an extra check for floats
            if ($fieldType eq '_f') {
              if ($value =~ /^\s*([\-\+]?\d+(\.\d+)?)\s*$/) {
                $doc->add_fields($fieldName . '_f' => $1,);
              } else {
                $this->log("WARNING: malformed float value '$value'");
              }
            } else {
              $doc->add_fields($fieldName . $fieldType => $value) if defined $value && $value ne '';
              $doc->add_fields($fieldName . '_escaped' . $fieldType => $escaped) if defined $escaped && $escaped ne '';
              $doc->add_fields($fieldName . '_select' . $fieldType => $mapped) if defined $mapped && $mapped ne '';
            }
          }
        }
      }
    }
  }

  # all prefs are of type _t
  # TODO it may pay off to detect floats and ints
  my @prefs = $meta->find('PREFERENCE');
  my $foundWorkflow = 0;
  if (@prefs) {
    foreach my $pref (@prefs) {
      my $name = $pref->{name};
      my $value = $pref->{value};
      $doc->add_fields(
        'preference_' . $name . '_s' => $value,
        'preference' => $name,
      );
      $foundWorkflow = 1 if $name eq 'WORKFLOW' and $value ne '';
    }
  }

  # add support for WorkflowPlugin 
  if ($foundWorkflow) {
    my $workflow = $meta->get('WORKFLOW');
    if ($workflow) {
      $doc->add_fields(
        state => $workflow->{name},
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

      # check whether the current attachment is a provis diagram.
      # if so, skip indexing if there's no according %PROCESS% macro present.
      if ( ( exists $attachment->{comment} && $attachment->{comment} ) eq 'ProVisPlugin Upload' || $attachment->{name} =~ m/^__provis_.*/ ) {
        my @arr = split( '\.', $attachment->{name} );
        my $name = $arr[0];
        my $pattern = "%PROCESS\\{.*name=\"$name\".*\\}%";
        if ( $meta->text() !~ m/$pattern/ ) {
          next;
        }
      }

      # add attachment names to the topic doc
      $doc->add_fields('attachment' => $name);

      # decide on thumbnail
      if (!defined $thumbnail && (($attachment->{attr} && $attachment->{attr} =~ /t/) || $attachment->{extraattr} && $attachment->{extraattr} =~ /t/)) {
        $thumbnail = $name;
      }
      if (!defined $firstImage && $name =~ /\.(png|jpe?g|gif|bmp|svg)$/i) {
        $firstImage = $name;
      }

      # then index each of them
      $this->indexAttachment($web, $topic, $attachment, \@aclFields, $meta);
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
  my $contentLanguage = $Foswiki::cfg{SolrPlugin}{SupportedLanguages}{$prefsLanguage};

  #$this->log("contentLanguage=$contentLanguage") if TRACE;

  Foswiki::Func::popTopicContext() if $donePush;

  return $contentLanguage;
}

################################################################################
# add the given attachment to the index.
sub indexAttachment {
  my ($this, $web, $topic, $attachment, $commonFields, $meta) = @_;

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
  #  $this->log("... attachment $web.$topic.$name not found") if TRACE;
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
  my $rev = $attachment->{'version'} || 1;

  unless ($rev =~ /^\d+$/) {
    $this->log("Warning: invalid version '$rev' of attachment $name in $web.$topic");
    $rev = 1;
  }

  # get summary
  my $summary = "";#substr($attText, 0, 300);

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

  # gather all webs and parent webs
  my @webCats = ();
  my @prefix = ();
  foreach my $component (split(/\./, $web)) {
    push @prefix, $component;
    push @webCats, join(".", @prefix);
  }

  my $container_title = $this->getTopicTitle($web, $topic, $meta);

  # TODO: what about createdate and createauthor for attachments
  $doc->add_fields(
    # common fields
    id => $id,
    url => $Foswiki::cfg{PubUrlPath}.'/'.$webDir.'/'.$topic.'/'.$name,
    web => $web,
    webcat => [@webCats],
    topic => $topic,
    webtopic => "$web.$topic",
    title => $title,
    title_escaped_s => $this->escapeHtml($title),
    type => $extension,
    text => $attText,
    summary => $summary,
    author => $author,
    date => $date,
    version => $rev,

    # attachment fields
    name => $name,
    name_escaped_s => $this->escapeHtml($name),
    comment => $comment,
    comment_scaped_s => $this->escapeHtml($comment),
    size => $size,
    icon => $this->mapToIconFileName($extension),
    container_id => $web . '.' . $topic,
    container_web => $web,
    container_topic => $topic,
    container_url => $this->getScriptUrlPath($web, $topic, "view"),
    container_title => $container_title,
    container_title_escaped_s => $this->escapeHtml($container_title),
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

  my $web = $doc->value_for('web');
  my $host = $this->{wikiHostMap}{$web} || $this->{wikiHost};
  $doc->add_fields(host => $host);
  foreach my $field (@{$doc->fields}) {
      if($field->{name} && $field->{name} eq 'id') {
          $field->{value} = "$host#$field->{value}";
      }
  }

  return unless $this->{solr};

  my $res;
  push @{$this->{_AddQueue}}, $doc;

  if (scalar @{$this->{_AddQueue}} >= 100) {
    $this->commit;
  }

  $res;
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

  $this->log("Optimizing index");
  $this->{solr}->optimize({
    waitSearcher => "true",
    softCommit => "true",
  });

  $agent->timeout($oldTimeout);
}

################################################################################
sub commit {
    my ($this, $hard) = @_;

    return unless $this->{solr};

    if(VERBOSE) {
        if(scalar @{$this->{_DeleteQueue}} || scalar @{$this->{_AddQueue}}) {
            $this->log('Sending data');
        }
    }

    if(scalar @{$this->{_DeleteQueue}}) {
        try {
            my $combinedQuery = join(' OR ', map{"( $_ )"} @{$this->{_DeleteQueue}});
            $this->{solr}->delete_by_query($combinedQuery);
        } catch Error::Simple with {
            my $e = shift;
            $this->log("ERROR: " . $e->{-text});
        };
        $this->{_DeleteQueue} = [];
    }

    if(scalar @{$this->{_AddQueue}}) {
        try {
            $this->{solr}->add($this->{_AddQueue});
        } catch Error::Simple with {
            my $e = shift;
            $this->log("ERROR: " . $e->{-text});
        };
        $this->{_AddQueue} = [];
    }

    unless($this->{bulkoperation}) {
        try {
            $this->log("Committing index") if VERBOSE;
            $this->{solr}->commit({
                waitSearcher => "true",
                softCommit => $hard ? "false" : "true",
            });
        } catch Error::Simple with {
            my $e = shift;
            $this->log("ERROR: " . $e->{-text});
        };
    }

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

################################################################################
sub newDocument {

  #my $this = shift;

  return WebService::Solr::Document->new;
}

################################################################################
sub deleteTopic {
  my ($this, $web, $topic) = @_;

  $this->deleteByQuery("web:\"$web\" topic:\"$topic\" -task_id_s:*");
}

################################################################################
sub deleteWeb {
  my ($this, $web) = @_;

  $web =~ s/\//./g;
  $this->deleteByQuery("web:\"$web\" -task_id_s:* -type:\"ua_user\" -type:\"ua_group\"");
}

################################################################################
sub deleteByQuery {
  my ($this, $query) = @_;

  return unless $query;

  #$this->log("Deleting documents by query $query") if VERBOSE;

  my $hostFilterQuery = "($query) " . $this->buildHostFilter;

  push @{$this->{_DeleteQueue}}, $hostFilterQuery;
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
  }
  catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: " . $e->{-text});
  };

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

  my $workArea = $this->{workArea};
  my $cachedFilename = "$workArea/$web/$topic/$attachment";

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

  my $utf8Text = eval { Encode::decode('utf-8', $attText, 1) };
  $attText = $utf8Text if defined $utf8Text;

  # only cache the first 10MB at most, TODO: make size configurable
  if (length($attText) > 1014*1000*10) {
    $this->log("Warning: ignoring attachment $attachment at $web.$topic larger than 10MB");
    $attText = '';
  }

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
      next if $user eq 'UnknownUser';
      $this->{_knownUsers}{$user} = 1;# if Foswiki::Func::topicExists($Foswiki::cfg{UsersWebName}, $user);
    }

    #$this->log("known users=".join(", ", sort keys %{$this->{_knownUsers}})) if TRACE;
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
  my $mostRecent = $user || $Foswiki::Users::BaseUserMapping::UNKNOWN_USER_CUID;

  # get creator
  (undef, $user, $rev) = $this->getRevisionInfo($web, $topic, 1, $attachment, $maxRev);
  my $creator = $user || $Foswiki::Users::BaseUserMapping::UNKNOWN_USER_CUID;

  return ($mostRecent, $creator) if $Foswiki::cfg{SolrPlugin}{SimpleContributors};
  $contributors{$mostRecent} = 1;

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

  return $wikiName;
}

################################################################################
# wrapper around original getRevisionInfo which
# can't deal with dots in the webname
sub getRevisionInfo {
  my ($this, $web, $topic, $rev, $attachment, $maxRev) = @_;

  ($web, $topic) = $this->normalizeWebTopicName($web, $topic);

  if ($attachment && (!defined($rev) || $rev == $maxRev)) {
    return ($attachment->{date}, $attachment->{author} || $attachment->{user}, $attachment->{version} || $maxRev);
  } else {
    return Foswiki::Func::getRevisionInfo($web, $topic, $rev, $attachment);
  }
}

################################################################################
# returns the list of users granted view access (or "all" if all users have got view access) and a list of denied users
sub getGrantedDeniedUsers {
  my ($this, $web, $topic, $meta, $text) = @_;

    my ($allowList, $denyList);
    my $mapping = $Foswiki::Plugins::SESSION->{users}->{mapping};

    $allowList = _getACL( $meta, 'ALLOWTOPICVIEW' );
    $denyList  = _getACL( $meta, 'DENYTOPICVIEW' );
    while (not defined $allowList) {
        unless(exists $this->{aclWebCache}->{$web . ' allow'}) {
            ($meta) = Foswiki::Func::readTopic($web, undef);
            $this->{aclWebCache}->{$web . ' allow'} = _getACL( $meta, 'ALLOWWEBVIEW' );
            $this->{aclWebCache}->{$web . ' deny'} = _getACL( $meta, 'DENYWEBVIEW' );
        }
        $allowList = $this->{aclWebCache}->{$web . ' allow'};
        my $webDenyList = $this->{aclWebCache}->{$web . ' deny'};
        if($webDenyList) {
            $denyList ||= [];
            push @$denyList, @$webDenyList;
        }
        last unless $web =~ s#(.*)[./].*#$1#;
    }
    if (not defined $allowList) {
        unless(exists $this->{aclWebCache}->{'site allow'}) {
            my ($sw, $st) = Foswiki::Func::normalizeWebTopicName(undef, $Foswiki::cfg{LocalSitePreferences});
            ($meta) = Foswiki::Func::readTopic($sw, $st);
            $this->{aclWebCache}->{'site allow'} = _getACL( $meta, 'ALLOWROOTVIEW' );
            $this->{aclWebCache}->{'site deny'} = _getACL( $meta, 'DENYROOTVIEW' );
        }
        $allowList = $this->{aclWebCache}->{'site allow'};
        my $rootDenyList = $this->{aclWebCache}->{'site deny'};
        if($rootDenyList) {
            $denyList ||= [];
            push @$denyList, @$rootDenyList;
        }
    }
    if (not defined $allowList) {
        $allowList = ['all'];
    }

    # make sure they exist and filter duplicates
    sub unique {
        my @data = @{shift || []};
        my %hash = map { $_ => 1 } @data;
        my @keys = keys %hash;
        return \@keys;
    };
    $allowList = unique($allowList);
    $denyList = unique($denyList);

    return ($allowList, $denyList);
}

sub _getACL {
    my ( $meta, $mode ) = @_;

    if ( defined $meta->topic && !defined $meta->getLoadedRev ) {
        # Lazy load the latest version.
        $meta->loadVersion();
    }

    my $text = $meta->getPreference($mode);
    return undef unless defined $text;

    # Remove HTML tags (compatibility, inherited from Users.pm
    $text =~ s/(<[^>]*>)//g;

    # Dump the users web specifier if userweb
    # Convert to cUIDs
    my $mapping = $Foswiki::Plugins::SESSION->{users}->{mapping};
    my @list = grep { /\S/ } map {
        my $item = $_;
        $item =~ s/^(?:$Foswiki::cfg{UsersWebName}|%USERSWEB%|%MAINWEB%)\.//;
        if($item eq '*') {
            $item = 'all';
        } elsif($item && $mapping->can('loginOrGroup2cUID')) {
            $item = $mapping->loginOrGroup2cUID($item) || $item; # Note: $item must not become empty (eg. unknown group), or this might be treated as an unset list
        }
        $item
    } split( /[,\s]+/, $text );

    return undef unless scalar @list; # empty counts as 'not set'
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

  my ($grantedUsers, $deniedUsers) = $this->getGrantedDeniedUsers(@_);
  return ('access_granted' => $grantedUsers, 'access_denied' => $deniedUsers);
}

################################################################################
sub groupsCache {
    my $this = shift;
    $this->{_groupCache} = shift if @_;
    $this->{_groupCache};
}

################################################################################
sub webACLsCache {
    my $this = shift;
    $this->{_webACLCache} = shift if @_;
    $this->{_webACLCache};
}

##############################################################################
sub getTopicTitle {
  my ($this, $web, $topic, $meta) = @_;

  return $this->{TopicTitleCache}{$web}{$topic} if exists $this->{TopicTitleCache}{$web}{$topic};

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

  $this->{TopicTitleCache}{$web}{$topic} = $topicTitle;
  return $topicTitle;
}

1;
