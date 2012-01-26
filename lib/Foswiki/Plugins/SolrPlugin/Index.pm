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

package Foswiki::Plugins::SolrPlugin::Index;
use strict;

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
use Foswiki::Contrib::StringifierContrib ();

use Time::HiRes ();

use constant DEBUG => 0; # toggle me
use constant VERBOSE => 1; # toggle me
use constant PROFILE => 0; # toggle me
use constant COMMIT_THRESHOLD => 100; # commit every 100 topics on a bulk index job
use constant WAIT_FLUSH => 0;
use constant WAIT_SEARCHER => 0;

################################################################################
sub finish {
  my $this = shift;
  
  $this->commit(1) if 
    $Foswiki::cfg{SolrPlugin}{EnableOnSaveUpdates} ||
    $Foswiki::cfg{SolrPlugin}{EnableOnUploadUpdates} ||
    $Foswiki::cfg{SolrPlugin}{EnableOnRenameUpdates};
}

################################################################################
# entry point to either update one topic or a complete web
sub index  {
  my $this = shift;

  # exclusively lock the indexer to prevent a delta and a full index
  # mode to run in parallel

  try {
    $this->lock();

    my $query = Foswiki::Func::getCgiQuery();
    my $web = $query->param('web') || 'all';
    my $topic = $query->param('topic');
    my $mode = $query->param('mode') || 'delta';
    my $optimize = $query->param('optimize') || 'off';

    if ($topic) {
      $web = $this->{session}->{webName} if !$web || $web eq 'all';
      #$this->log("doing a topic index $web.$topic");
      $this->updateTopic($web, $topic);
    } else {
      #$this->log("doing a web index in $mode mode");
      $this->update($web, $mode);
    }

    $this->commit(1) if $this->{commitCounter};
    $this->optimize() if $optimize eq 'on';
  }

  catch Error::Simple with {
    my $error = shift;
    print STDERR "Error: ".$error->{-text}."\n";
  }

  finally {
    $this->unlock();
  }
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
  my @aclFields = $this->getAclFields($web, $topic, $meta);

  $this->indexAttachment($web, $topic, $attachment, \@aclFields);
}

################################################################################
# update documents of a web - either in fully or incremental
# on a full update, the complete web is removed from the index prior to updating it;
# this calls indexTopic for each topic to be updated
sub update {
  my ($this, $web, $mode) = @_;

  $mode ||= 'full';

  my @webs;

  if (!defined($web) || $web eq 'all') {
    @webs = Foswiki::Func::getListOfWebs("user");
  } else {
    @webs = split(/\s*,\s*/, $web);
  }

  # TODO: check the list of webs we had the last time we did a full index
  # of all webs; then possibly delete them

  foreach my $web (@webs) {
    next if $this->isSkippedWeb($web);
    #$this->log("Indexing web $web");

    my $start_time = time();

    my $found = 0;
    if ($mode eq 'full') {
      # full
      $this->deleteWeb($web);
      foreach my $topic (Foswiki::Func::getTopicList($web)) {
        next if $this->isSkippedTopic($web, $topic);
        $this->indexTopic($web, $topic);
        my $found = 1;
      }
    } else { 
      # delta
      my $since = $this->getTimestamp($web);

      # SMELL: foswiki's eachChangSince is too imprecise, see http://foswiki.org/Tasks/Item8460
      # my $iterator = Foswiki::Func::eachChangeSince($web, $since);
      # while ($iterator->hasNext()) {
      #   my $change = $iterator->next();
      #   my $topic = $change->{topic};
      #   next if $this->isSkippedTopic($web, $topic);
      #   $this->indexTopic($web, $topic);
      #   $found = 1;
      # }

      my @topics = Foswiki::Func::getTopicList($web);
      foreach my $topic (@topics) {
        next if $this->isSkippedTopic($web, $topic);
        my $time;
        if ($Foswiki::Plugins::SESSION->can('getApproxRevTime')) {
          $time = $Foswiki::Plugins::SESSION->getApproxRevTime($web, $topic);
        } else {
          # This is here for old engines
          $time = $Foswiki::Plugins::SESSION->{store}->
            getTopicLatestRevTime($web, $topic);
        }
        next if $time < $since;
        $this->indexTopic($web, $topic);
        $found = 1;
      }
    }
    $this->setTimestamp($web) if $found;
  }
}

################################################################################
# update one specific topic; deletes the topic from the index before updating it again
sub updateTopic {
  my ($this, $web, $topic, $meta, $text) = @_;

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

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

  my $t0 = [Time::HiRes::gettimeofday] if PROFILE;

  # normalize web name
  $web =~ s/\//\./g;

  if (VERBOSE) {
    $this->log("Indexing topic $web.$topic");
  } else {
    $this->log(".", 1);
  }

  # new solr document for the current topic
  my $doc = $this->newDocument();

  unless (defined $meta && defined $text) {
    ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
  }

  # Eliminate Topic Makup Language elements and newlines.
  my $origText = $text;
  $text = $this->plainify($text, $web, $topic);

  # parent data
  my $parent = $meta->getParent();
  $parent =~ s/\//\./g;

  # get date
  my ($date) = getRevisionInfo($web, $topic);
  $date ||= 0; # prevent formatTime to crap out
  $date = Foswiki::Func::formatTime($date, 'iso', 'gmtime' );

  # get create date
  my ($createDate) = getRevisionInfo($web, $topic, 1);
  $createDate ||= 0; # prevent formatTime to crap out
  $createDate = Foswiki::Func::formatTime($createDate, 'iso', 'gmtime' );

  # get contributor and most recent author
  my @contributors = $this->getContributors($web, $topic);
  foreach my $contributor (@contributors) {
    $doc->add_fields(contributor=>$contributor);
  }
  my $author = pop @contributors;

  # get TopicTitle
  my $topicTitle;
  my $field = $meta->get('FIELD', 'TopicTitle');
  $topicTitle = $field->{value} if $field && $field->{value};
  unless ($topicTitle) {
    $field = $meta->get('PREFERENCE', 'TOPICTITLE');
    $topicTitle = $field->{value} if $field && $field->{value};
  }
  $topicTitle ||= $topic;

  # get summary
  my $summary;
  $field = $meta->get('FIELD', 'Summary');
  $summary = $field->{value} if $field && $field->{value};
  unless ($summary) {
    $field = $meta->get('FIELD', 'Teaser');
    $summary = $field->{value} if $field && $field->{value};
  }
  unless ($summary) {
    $field = $meta->get('PREFERENCE', 'SUMMARY');
    $summary = $field->{value} if $field && $field->{value};
  }
  $summary = substr($text, 0, 300) unless $summary;

  # url to topic
  my $url = Foswiki::Func::getViewUrl($web, $topic);

  $doc->add_fields(
    # common fields
    id => "$web.$topic",
    url => $url,
    topic => $topic,
    web => $web,
    webtopic => "$web.$topic",
    title => $topicTitle,
    text => $text,
    summary => $summary,
    author => $author,
    date => $date,
    createdate => $createDate,
    type => 'topic',
    # topic specific
    parent => $parent,
  );

  # process form
  my $formName = $meta->getFormName();
  if ($formName) {

    # read form definition to add field type hints 
    my $formDef;
    try {
      $formDef = new Foswiki::Form($this->{session}, $web, $formName);
    } catch Foswiki::OopsException with {
      # Form definition not found, ignore
      my $e = shift;
      $this->log("ERROR: can't read form definition for $formName");
    };

    $formName =~ s/\//\./g;
    $doc->add_fields(
      form => $formName
    );

    if ($formDef) { # form definition found, if not the formfields aren't indexed

      my %seenFields = ();
      foreach my $fieldDef (@{$formDef->getFields()}) {
        my $attrs = $fieldDef->{attributes}; # TODO: check for Facet
        my $name = $fieldDef->{name};
        my $type = $fieldDef->{type};
        my $field = $meta->get('FIELD', $name);
        next unless $field;

        # prevent from mall-formed formDefinitions 
        if ($seenFields{$name}) {
          $this->log("WARNING: walrofmed form definition for $web.$formName - field $name appear twice must be unique");
          next;
        }
        $seenFields{$name} = 1;

        my $value = $field->{value};

        # create a dynamic field indicating the field type to solr

        # date
        if ($type eq 'date') {
          my $epoch = $value;
          $epoch = Foswiki::Time::parseTime($value) unless $epoch =~ /^\d+$/;
          $epoch ||= 0; # prevent formatTime to crap out
          $value = Foswiki::Time::formatTime($epoch, 'iso', 'gmtime');
          $doc->add_fields(
            'field_'.$name.'_dt' => $value,
          );
        } 

        # multi-valued types
        elsif ($type =~ /^(checkbox|select|radio|textboxlist)$/ ||
               $name =~ /TopicType/) { # TODO: make this configurable
          foreach my $item (split(/\s*,\s*/, $value)) {
            $doc->add_fields(
              'field_'.$name.'_lst' => $item
            );
          }
        }

        # make it a text field unless its name does not indicate otherwise
        else {
          my $fieldName = 'field_'.$name;
          my $fieldType = '_s';
          if ($fieldName =~ /(_(?:i|s|l|t|b|f|dt|lst))$/) {
            $fieldType = $1;
          }
          $doc->add_fields(
            $fieldName.$fieldType => $value,
          );
        }
      }
    }
  }

  # all prefs are of type _t
  # TODO it may pay off to detect floats and ints
  my @prefs = $meta->find('PREFERENCE');
  if (@prefs) {
    foreach my $pref (@prefs) {
      $doc->add_fields(
        'preference_'.$pref->{name}.'_t' => $pref->{value},
        'preference' => $pref->{value}
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
    } catch Foswiki::OopsException with {
      my $e = shift;
      $this->log("ERROR: while calling indexTopicHandler: ".$e->stringify());
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
    foreach my $attachment (@attachments) {

      # is the attachment is the skip list?
      my $name = $attachment->{'name'} || '';
      if ($this->isSkippedAttachment($web, $topic, $name)) {
        $this->log("Skipping attachment $web.$topic.$name");
        next;
      }

      # add attachment names to the topic doc
      $doc->add_fields('attachment' => $name);

      # then index each of them
      $this->indexAttachment($web, $topic, $attachment, \@aclFields);
    }
  }

  if (PROFILE) {
    my $elapsed = int(Time::HiRes::tv_interval($t1) * 1000);
    $this->log("took $elapsed ms to index all attachments at $web.$topic");
    $t1 = [Time::HiRes::gettimeofday];
  }

  # add the document to the index
  try {
    $this->add($doc);
    $this->commit();
  } catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: ".$e->{-text});
  };


  if (PROFILE) {
    my $elapsed = int(Time::HiRes::tv_interval($t0) * 1000);
    $this->log("took $elapsed ms to index topic $web.$topic");
    $t0 = [Time::HiRes::gettimeofday];
  }

}

################################################################################
# add the given attachment to the index.
sub indexAttachment {
  my ($this, $web, $topic, $attachment, $commonFields) = @_;

  #my $t0 = [Time::HiRes::gettimeofday] if PROFILE;

  my $name = $attachment->{'name'} || '';
  if (VERBOSE) {
    $this->log("Indexing attachment $web.$topic.$name");
  } else {
    $this->log("a", 1);
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
  my $summary = substr($attText, 0, 300);

#  my $author = $attachment->{'user'} || $attachment->{'author'} || '';
#  $author = Foswiki::Func::getWikiName($author) || 'UnknownUser';
#  # weed out some strangers
#  $author = 'UnknownUser' unless Foswiki::Func::isValidWikiWord($author);

  # get contributor and most recent author
  my @contributors = $this->getContributors($web, $topic, $attachment);

  foreach my $contributor (@contributors) {
    $doc->add_fields(contributor=>$contributor);
  }


  # normalize web name
  $web =~ s/\//\./g;
  my $id = "$web.$topic.$name";

  # view url
  my $url = Foswiki::Func::getScriptUrl($web, $topic, 'viewfile', 
    filename=>$name);

  $doc->add_fields(
      # common fields
      id => $id,
      url => $url,
      web => $web,
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
  );

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
    $this->commit();
  } catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: ".$e->{-text});
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

  return unless $this->{solr};
  return $this->{solr}->add($doc);
}

################################################################################
# optimize index
sub optimize {
  my $this = shift;

  return unless $this->{solr};

  $this->{solr}->commit();
  $this->log("Optimizing index");
  $this->{solr}->optimize();
}


################################################################################
# commit every COMMIT_THRESHOLD times
sub commit {
  my ($this, $force) = @_;

  return unless $this->{solr};

  $this->{commitCounter}++;

  if ($this->{commitCounter} > 1 && ($this->{commitCounter} >= COMMIT_THRESHOLD || $force)) {
    $this->log("Committing index");
    $this->{solr}->commit({
        waitFlush => WAIT_FLUSH,
        waitSearcher => WAIT_SEARCHER
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
    $this->deleteByQuery("web:$web topic:$topic");
  }
}

################################################################################
sub deleteWeb {
  my ($this, $web) = @_;
  $this->deleteByQuery("web:$web");
}

################################################################################
sub deleteByQuery {
  my ($this, $query) = @_;

  return unless $query;

  $this->log("Deleting documents by query $query");

  my $success;
  try {
    $success = $this->{solr}->delete_by_query($query);
    $this->commit();
  } catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: ".$e->{-text});
  };
  
  return $success;
}

################################################################################
sub deleteDocument {
  my ($this, $web, $topic, $attachment) = @_;

  $web =~ s/\//\./g;
  my $id = "$web.$topic";
  $id .= ".$attachment" if $attachment;

  $this->log("Deleting document $id");

  try {
    $this->{solr}->delete_by_id($id);
    $this->commit();
  } catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: ".$e->{-text});
  };

}

################################################################################
sub lock {
  my $this = shift;

  my $lockfile = Foswiki::Func::getWorkArea('SolrPlugin')."/indexer.lock";
  open($this->{lock}, ">$lockfile") 
    or die "can't create lockfile $lockfile";

  flock ($this->{lock}, LOCK_EX) 
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

  my $workArea = Foswiki::Func::getWorkArea('SolrPlugin');
  my $cachedFilename = "$workArea/$web/$topic/$attachment.txt";

  # untaint..
  $cachedFilename =~ /(.*)/;
  $cachedFilename = $1;

  mkdir "$workArea/$web" unless -d "$workArea/$web";
  mkdir "$workArea/$web/$topic" unless -d "$workArea/$web/$topic";

  my $origModified = modificationTime($filename);
  my $cachedModified = modificationTime($cachedFilename);

  my $attText = '';
  if ($origModified > $cachedModified) {
    #$this->log("caching stringified version of $attachment in $cachedFilename");
    $attText = Foswiki::Contrib::StringifierContrib->stringFor($filename) || '';
    Foswiki::Func::saveFile($cachedFilename, $attText);
  } else {
    #$this->log("found stringified version of $attachment in cache");
    $attText = Foswiki::Func::readFile($cachedFilename);
  }

  return $attText;
}

################################################################################
sub modificationTime {
  my $filename = shift;

  my @stat = stat($filename);
  return $stat[9] || $stat[10] || 0;
}

################################################################################
sub plainify {
  my ($this, $text, $web, $topic) = @_;

  my $wtn = Foswiki::Func::getPreferencesValue('WIKITOOLNAME') || '';
  my $STARTWW = qr/^|(?<=[\s\(])/m;
  my $ENDWW = qr/$|(?=[\s,.;:!?)])/m;

  # from Foswiki:Extensions/GluePlugin
  $text =~ s/^#~~(.*?)$//gom;  # #~~
  $text =~ s/%~~\s+([A-Z]+[{%])/%$1/gos;  # %~~
  $text =~ s/\s*[\n\r]+~~~\s+/ /gos;   # ~~~
  $text =~ s/\s*[\n\r]+\*~~\s+//gos;   # *~~

  # from Fosiki::Render
  $text =~ s/\r//g;    # SMELL, what about OS10?
  $text =~ s/%META:[A-Z].*?}%//g;

  $text =~ s/%WEB%/$web/g;
  $text =~ s/%TOPIC%/$topic/g;
  $text =~ s/%WIKITOOLNAME%/$wtn/g;
  $text =~ s/%$Foswiki::regex{tagNameRegex}({.*?})?%//g;    # remove

  # Format e-mail to add spam padding (HTML tags removed later)
  $text =~ s/$STARTWW((mailto\:)?[a-zA-Z0-9-_.+]+@[a-zA-Z0-9-_.]+\.[a-zA-Z0-9-_]+)$ENDWW//gm;
  $text =~ s/<!--.*?-->//gs;       # remove all HTML comments
  $text =~ s/<(?!nop)[^>]*>//g;    # remove all HTML tags except <nop>
  $text =~ s/\&[a-z]+;/ /g;        # remove entities

  # keep only link text of legacy [[prot://uri.tld/ link text]]
  $text =~ s/
          \[
              \[$Foswiki::regex{linkProtocolPattern}\:
                  ([^\s<>"\]]+[^\s*.,!?;:)<|\]])
                      \s+([^\[\]]*?)
              \]
          \]/$3/gx;

  #keep only test portion of [[][]] links
  $text =~ s/\[\[([^\]]*\]\[)(.*?)\]\]/$2/g;

  # remove "Web." prefix from "Web.TopicName" link
  $text =~ s/$STARTWW(($Foswiki::regex{webNameRegex})\.($Foswiki::regex{wikiWordRegex}|$Foswiki::regex{abbrevRegex}))/$3/g;
  $text =~ s/[\[\]\*\|=_\&\<\>]/ /g;    # remove Wiki formatting chars
  $text =~ s/^\-\-\-+\+*\s*\!*/ /gm;    # remove heading formatting and hbar
  $text =~ s/[\+\-]+/ /g;               # remove special chars
  $text =~ s/^\s+//;                    # remove leading whitespace
  $text =~ s/\s+$//;                    # remove trailing whitespace
  $text =~ s/!(\w+)/$1/gs;    # remove all nop exclamation marks before words
  $text =~ s/[\r\n]+/\n/s;
  $text =~ s/[ \t]+/ /s;

  # remove/escape special chars
  $text =~ s/\\//g;
  $text =~ s/"//g;
  $text =~ s/%//g;
  $text =~ s/\$percnt//g;
  $text =~ s/\$dollar//g;
  $text =~ s/\n/ /g;
  $text =~ s/~~~/ /g;
  $text =~ s/^$//gs;

  return $text;
}

################################################################################
# Get a list of all registered users
# excludes out admin users
sub getListOfUsers {
  my $this = shift;

  unless (defined $this->{knownUsers}) { 

    my $it = Foswiki::Func::eachUser();
    while ($it->hasNext()) {
      my $user = $it->next();
      $this->{knownUsers}{$user} = 1;
    }

    #$this->log("known users=".join(", ", sort keys %{$this->{knownUsers}})) if DEBUG;
    $this->{nrKnownUsers} = scalar(keys %{$this->{knownUsers}});
    #$this->log("found ".$this->{nrKnownUsers}." users");
  }

  return $this->{knownUsers}; 
}

################################################################################
sub getContributors {
  my ($this, $web, $topic, $attachment) = @_;

  #my $t0 = [Time::HiRes::gettimeofday] if PROFILE;

  my %contributors = ();

  my $maxRev;
  try {
    (undef, undef, $maxRev) = getRevisionInfo($web, $topic, undef, $attachment);
  } catch Error::Simple with {
    my $e = shift;
    $this->log("ERROR: ".$e->{-text});
  };
  return () unless defined $maxRev;

  $maxRev =~ s/r?1\.//go;  # cut 'r' and major
  
  my $mostRecent;
  for (my $i = $maxRev; $i >= 0; $i--) {
    my (undef, $user, $rev) = getRevisionInfo($web, $topic, $i, $attachment, $maxRev);
    my $wikiName = getWikiName($user);
    $mostRecent = $wikiName unless $mostRecent;
    $contributors{$wikiName} = 1;
  }

  # put most revent at the top, rest unsorted
  delete $contributors{$mostRecent};
  my @contributors = keys %contributors;
  push @contributors, $mostRecent;

  #if (PROFILE) {
  #  my $elapsed = int(Time::HiRes::tv_interval($t0) * 1000);
  #  $this->log("took $elapsed ms to get contributors of $web.$topic".($attachment?'.'.$attachment->{name}:''));
  #}

  return @contributors;
}

################################################################################
sub getWikiName {
  my $user = shift;
  
  my $wikiName = Foswiki::Func::getWikiName($user) || 'UnknownUser';
  $wikiName = 'UnknownUser' unless Foswiki::Func::isValidWikiWord($wikiName); # weed out some strangers

  return $wikiName;
}

################################################################################
# wrapper around original getRevisionInfo which 
# can't deal with dots in the webname
sub getRevisionInfo {
  my ($web, $topic, $rev, $attachment, $maxRev) = @_;

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  if ($attachment && (!defined($rev) || $rev == $maxRev)) {
    # short cut for attachments
    my $info = {};
    $info->{version} = $attachment->{version} || $maxRev;
    $info->{date} = $attachment->{date};
    $info->{author}  = $attachment->{author} || $attachment->{user};
    #$info->{date} = $this->getTimestamp() unless defined $info->{date};
    #$info->{author} = $Foswiki::Users::BaseUserMapping::DEFAULT_USER_CUID unless defined $info->{author};
    return $info;
  } else {
    return Foswiki::Func::getRevisionInfo($web, $topic, $rev, $attachment);
  }
}

################################################################################
sub getGrantedUsers {
  my ($this, $web, $topic, $meta, $text) = @_;

  # get {knownUsers}
  $this->getListOfUsers();

  my @grantedUsers = ();

  foreach my $user (keys %{$this->{knownUsers}}) {
    my $wikiName = Foswiki::Func::getWikiName($user);

    # check web permission
    my $webViewPermission = $this->{_webViewPermission}{$web}{$wikiName};
    unless (defined $webViewPermission) {
      $webViewPermission = $this->{_webViewPermission}{$web}{$wikiName} =
        Foswiki::Func::checkAccessPermission('VIEW', $wikiName, undef, undef, $web);
    }

    my $topicHasPerms  = ($text =~ /(ALLOW|DENY)/ || 
        $meta->get('PREFERENCES', 'ALLOWTOPICVIEW') ||
        $meta->get('PREFERENCES', 'DENYTOPICVIEW'))?1:0;
    
    if ($topicHasPerms) {
      # detailed access check
      #print STDERR "detailed perms check for $web.$topic\n";
      if (Foswiki::Func::checkAccessPermission('VIEW', $wikiName, $text, $topic, $web, $meta)) {
        push @grantedUsers, $wikiName;
        #print STDERR "$wikiName has got access to $web.$topic\n";
      }
    } else {
      if ($webViewPermission) {
        push @grantedUsers, $wikiName;
        #print STDERR "$wikiName has got access to $web.$topic\n";
      }
    }
  }

  return @grantedUsers;
}

################################################################################
sub getAclFields {
  my ($this, $web, $topic, $meta, $text) = @_;

  $text = $meta->text() unless defined $text;

  my @aclFields = ();

  # permissions
  my @grantedUsers = $this->getGrantedUsers($web, $topic, $meta, $text);
  if (scalar(@grantedUsers) == $this->{nrKnownUsers}) {
    push @aclFields, 'access_granted' => 'all';

  } else {
    foreach my $wikiName (@grantedUsers) {
      push @aclFields, 'access_granted' => $wikiName;
    }
  }

  return @aclFields;
}

################################################################################
sub getTimestampFile {
  my ($this, $web) = @_;

  return unless $web;
  return unless Foswiki::Func::webExists($web);

  $web =~ s/\//./g;
  return Foswiki::Func::getWorkArea('SolrPlugin').'/'.$web.'.timestamp';
}

################################################################################
sub setTimestamp {
  my ($this, $web) = @_;

  my $timestampFile = $this->getTimestampFile($web);
  return 0 unless $timestampFile;

  my $time ||= time();
  Foswiki::Func::saveFile($timestampFile, $time);

  return $time;
}

################################################################################
sub getTimestamp {
  my ($this, $web) = @_;

  my $timestampFile = $this->getTimestampFile($web);

  return 0 unless $timestampFile;

  my $data = Foswiki::Func::readFile($timestampFile);
  return ($data || 0);
}

1;

