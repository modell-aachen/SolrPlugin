package Foswiki::Plugins::SolrPlugin::Scheduler;

use strict;
use warnings;

use Foswiki::Func;
use Foswiki::OopsException;
use Foswiki::Plugins;
use Foswiki::Time;

use File::Spec;
use Foswiki::Contrib::PickADateContrib;
use Foswiki::Plugins::JQueryPlugin;
use JSON;

sub new {
  my ($class, $session) = @_;

  my $this = bless {}, $class;
  $this->{session} = $session;
  $this->{workArea} = Foswiki::Func::getWorkArea('SolrPlugin');
  $this->{scheduler_file} = File::Spec->catfile($this->{workArea}, 'schedule.json');
  return $this;
}

sub handleSOLRSCHEDULER {
  my $this = shift;
  my ($params, $theWeb, $theTopic) = @_;

  my $interval = $params->{interval} || 60;

  Foswiki::Func::addToZone(
    'script',
    'SOLRPLUGIN::SCHEDULER::JS',
    '<script type="text/javascript" src="%PUBURL%/%SYSTEMWEB%/SolrPlugin/solr-scheduler.js"></script>',
    'JQUERYPLUGIN::FOSWIKI::PREFERENCES'
  );

  Foswiki::Func::addToZone(
    'head',
    'SOLRPLUGIN::SCHEDULER::CSS',
    '<link rel="stylesheet" type="text/css" media="all" href="%PUBURLPATH%/%SYSTEMWEB%/SolrPlugin/solr-scheduler.css" />'
  );

  Foswiki::Func::addToZone(
    'head',
    'FLATSKIN_WRAPPED',
    '<link rel="stylesheet" type="text/css" media="all" href="%PUBURLPATH%/%SYSTEMWEB%/FlatSkin/css/flatskin_wrapped.min.css" />'
  );

  Foswiki::Contrib::PickADateContrib::initTimePicker;
  my @webs = Foswiki::Func::getListOfWebs('user');
  my $schedule = $this->readSchedule;

  my $tf = $Foswiki::cfg{PickADateContrib}{TimeFormat} || '24';
  my $format = $tf =~ /24/ ? 'HH:i' : 'hh:i a';
  my $defaultTime = 360;

  my @output;
  foreach my $web (@webs) {
    my $enabled = '';
    my $minutes = $schedule->{$web};

    $enabled = 'checked=\"checked\"' if defined $minutes;
    my $value = $minutes || $defaultTime;
    my $skip = Foswiki::Func::getPreferencesValue('SOLR_SCHEDULER_SKIP_WEB', $web) || 0;
    my $skipped = Foswiki::Func::isTrue($skip) ? 'yes' : 'no';

    my $tmpl = <<TMPL;
"SolrScheduler::Entry"
  ENABLED="$enabled"
  FORMAT="$format"
  INTERVAL="$interval"
  SKIPPED="$skipped"
  VALUE="$value"
  WEBNAME="$web"
TMPL
    push @output, Foswiki::Func::expandTemplate($tmpl);
  }

  my $header = Foswiki::Func::expandTemplate("SolrScheduler::Header");
  my $footer = Foswiki::Func::expandTemplate("SolrScheduler::Footer");

  my $skipNote = '';
  my $skipAll = Foswiki::Func::getPreferencesValue('SOLR_SCHEDULER_SKIP_ALL') || 0;
  if (Foswiki::Func::isTrue($skipAll)) {
    $skipNote = Foswiki::Func::expandTemplate("SolrScheduler::SkipNote");
  }

  return join("\n", $skipNote, $header, @output, $footer);
}

sub restUpdateSchedule {
  my $this = shift;
  my ($subject, $verb, $response) = @_;

  unless (Foswiki::Func::isAnAdmin()) {
    $response->header(-status => 403);
    $response->body(
      encode_json({
        status => 'forbidden',
        msg => 'Insufficient access permissions.'
      })
    );
  }

  my $q = $this->{session}->{request};
  my $action = $q->param('action');
  unless ($action =~ /^(set|unset)$/) {
    $response->header(-status => 400);
    $response->body(
      encode_json({
        status => 'error',
        msg => 'Invalid action.'
      })
    );
  }

  my $web = $q->param('webname');
  unless ($web && Foswiki::Func::webExists($web)) {
    $response->header(-status => 400);
    $response->body(
      encode_json({
        status => 'error',
        msg => 'Invalid web.'
      })
    );
  }

  my $minutes = $q->param('minutes');
  unless ($action eq 'set' && $minutes) {
    $response->header(-status => 400);
    $response->body(
      encode_json({
        status => 'error',
        msg => 'Invalid time format.'
      })
    );
  }

  my $schedule = $this->readSchedule;
  $schedule->{$web} = $minutes if ($action eq 'set');
  delete $schedule->{$web} if ($action eq 'unset');
  $this->writeSchedule($schedule);

  $response->header(-status => 200);
  $response->body(encode_json({status => 'ok'}));
  return '';
}

sub readSchedule {
  my $this = shift;

  return {} unless -f $this->{scheduler_file};
  my $json = Foswiki::Func::readFile(
    $this->{scheduler_file},
    $Foswiki::UNICODE || 0
  ) || '{}';

  return decode_json($json);
}

sub writeSchedule {
  my ($this, $schedule) = @_;
  Foswiki::Func::saveFile(
    $this->{scheduler_file},
    encode_json($schedule),
    $Foswiki::UNICODE || 0
  );
}

# Copyright (C) 2017  Modell Aachen GmbH

# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.

# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.

# You should have received a copy of the GNU General Public License along
# with this program.  If not, see <http://www.gnu.org/licenses/>.

1;
