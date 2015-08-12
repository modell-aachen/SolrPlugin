# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2013 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

package Foswiki::Plugins::SolrPlugin::WebHierarchy;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Plugins::JQueryPlugin::Plugins ();
use JSON ();

sub new {
  my $class = shift;
  my $session = shift;

  $session ||= $Foswiki::Plugins::SESSION;

  my $this = {
    @_
  };
  bless($this, $class);

  return $this;
}

# {
#   id => the full webname (e.g. Main.Foo.Bar)
#   name => the tail of the webname (e.g. Bar)
#   title => web title
#   parent => id of parent or list of parents
#   children => list of subwebs or subcats
#   type => 'web' or 'cat'
#   icon => the url path to an icon image for the item
# }
sub restWebHierarchy {
  my ($this, $subject, $verb, $response) = @_;

  my $request = Foswiki::Func::getRequestObject();
  my $theInclude = $request->param('include');
  my $theExclude = $request->param('exclude');
  my $theRoot = $request->param('root');
  my $theWeb = $request->param('web');
  my $theType = $request->param('type');

  $theExclude = $Foswiki::cfg{TrashWebName} unless defined $theExclude;

  my $hash = {};

  my $rootWeb;
  $rootWeb = $theWeb if $theWeb && Foswiki::Func::webExists($theWeb);

  my @webs = Foswiki::Func::getListOfWebs('user', $rootWeb); 
  push @webs, $rootWeb if defined $rootWeb;

  @webs = grep {!/$theExclude/} @webs if $theExclude;
  @webs = grep {/$theInclude/} @webs if $theInclude;

  if (!$theType || $theType =~ /\bwebs\b/) {
    my $defaultWebIcon = Foswiki::Plugins::JQueryPlugin::Plugins::getIconUrlPath('database');
    # collect all webs
    foreach my $web (@webs) {
      my $webIcon = Foswiki::Func::getPreferencesValue('WEBICON', $web) || $defaultWebIcon;
      $web =~ s/\//./g;
      $hash->{$web} = {
        id => $web,
        title => getWebTitle($web),
        name => $web,
        type => 'web',
        icon => $webIcon,
      };

      if ($web =~ /^(.*)\.(.*?)$/) {
        $hash->{$web}{parent} = $1;
        $hash->{$web}{name} = $2;
      }
    }

    # establish parent-child relation
    foreach my $web (@webs) {
      next if defined $hash->{$web}{children};
      my $parent = $hash->{$web}{parent};
      if ($parent) {
        push @{$hash->{$parent}{children}}, $web
          if defined $hash->{$parent};
      }
    }
  }

  if (!$theType || $theType =~ /\bcats\b/) {
    if (Foswiki::Func::getContext()->{ClassificationPluginEnabled}) {
      require Foswiki::Plugins::ClassificationPlugin;
      foreach my $web (@webs) {
        $web =~ s/\//./g;
        my $hierarchy = Foswiki::Plugins::ClassificationPlugin::getHierarchy($web);
        my @cats = ();
        if ($theRoot) {
          my $rootCat = $hierarchy->getCategory($theRoot);
          if ($rootCat) {
            @cats = $rootCat->getSubCategories();
            push @cats,$rootCat;
          }
        } else {
          @cats = $hierarchy->getCategories;
        }
        foreach my $cat (@cats) {
          next if $cat->{name} =~ /^(TopCategory|BottomCategory)$/;
          my $id = $web.'.'.$cat->getBreadCrumbs;
          $hash->{$id} = {
            id => $id,
            title => $cat->{title},
            type => 'cat',
            icon => $cat->getIconUrl(),
          };

          my @parents;
          foreach my $parent ($cat->getParents) {
            my $parentId = $web.'.'.$parent->getBreadCrumbs;
            if ($parent->{name} eq 'TopCategory') {
              if (!$theType || $theType =~ /\bwebs\b/) {
                push @parents, $web;
                push @{$hash->{$web}{children}}, $id;
              }
            } else {
              push @parents, $parentId;
            }
          }

          if (@parents) {
            if (scalar(@parents) == 1) {
              $hash->{$id}{parent} = $parents[0];
            } else {
              $hash->{$id}{parent} = \@parents;
            }
          }

          foreach my $child ($cat->getChildren) {
            next if $child->{name} eq 'BottomCategory';
            push @{$hash->{$id}{children}}, $web.'.'.$child->getBreadCrumbs;
          }
        }
      }
    };
  }

  $response->header(
    "-content_type" => "application/json; charset=".$Foswiki::cfg{Site}{CharSet},
    #"-cache-control" => "max-age=1000", # SMELL: make configurable
  );

  return JSON::to_json($hash, {pretty=>1});
}

sub getWebTitle {
  my $web = shift;

  my $topic = $Foswiki::cfg{HomeTopicName};
  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  my $webName = $web;
  if ($webName =~ /\.(.*?)$/) {
    $webName = $1;
  }

  if ($Foswiki::cfg{SecureTopicTitles}) {
    my $wikiName = Foswiki::Func::getWikiName();
    return $webName
      unless Foswiki::Func::checkAccessPermission('VIEW', $wikiName, $text, $topic, $web, $meta);
  }

  # read the formfield value
  my $title = $meta->get('FIELD', 'TopicTitle');
  $title = $title->{value} if $title;

  # read the topic preference
  unless ($title) {
    $title = $meta->get('PREFERENCE', 'TOPICTITLE');
    $title = $title->{value} if $title;
  }

  # read the preference
  unless ($title)  {
    Foswiki::Func::pushTopicContext($web, $topic);
    $title = Foswiki::Func::getPreferencesValue('TOPICTITLE');
    Foswiki::Func::popTopicContext();
  }

  # default to web name
  $title ||= $webName;

  $title =~ s/\s*$//;
  $title =~ s/^\s*//;

  return $title;
}

1;

