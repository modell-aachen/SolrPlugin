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
package Foswiki::Plugins::SolrPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Error qw(:try);

use Foswiki::Request();

BEGIN {
  # Backwards compatibility for Foswiki 1.1.x
  unless (Foswiki::Request->can('multi_param')) {
    no warnings 'redefine';
    *Foswiki::Request::multi_param = \&Foswiki::Request::param;
    use warnings 'redefine';
  }
}

our $VERSION = '4.00';
our $RELEASE = '4.00';
our $SHORTDESCRIPTION = 'Enterprise Search Engine for Foswiki based on [[http://lucene.apache.org/solr/][Solr]]';
our $NO_PREFS_IN_TOPIC = 1;
our %searcher;
our %indexer;
our %scheduler;
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

  Foswiki::Func::registerTagHandler('SOLRSCHEDULER', sub {
    my ($session, $params, $theTopic, $theWeb) = @_;

    return getScheduler($session)->handleSOLRSCHEDULER($params, $theWeb, $theTopic);
  });

  Foswiki::Func::registerRESTHandler('updateSchedule', sub {
      my $session = shift;
      return getScheduler($session)->restUpdateSchedule(@_);
    },
    authenticate => 1,
    validate => 0,
    http_allow => 'POST',
  );


  Foswiki::Func::registerRESTHandler('search', sub {
      my $session = shift;

      my $web = $session->{webName};
      my $topic = $session->{topicName};
      return getSearcher($session)->restSOLRSEARCH($web, $topic);
    }, 
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('proxy', sub {
      my $session = shift;

      my $web = $session->{webName};
      my $topic = $session->{topicName};
      return getSearcher($session)->restSOLRPROXY($web, $topic);
    },
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
  );


  Foswiki::Func::registerRESTHandler('similar', sub {
      my $session = shift;

      my $web = $session->{webName};
      my $topic = $session->{topicName};
      return getSearcher($session)->restSOLRSIMILAR($web, $topic);
    },
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('autocomplete', sub {
      my $session = shift;

      my $web = $session->{webName};
      my $topic = $session->{topicName};
      return getSearcher($session)->restSOLRAUTOCOMPLETE($web, $topic);
    },
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('autosuggest', sub {
      my $session = shift;

      my $web = $session->{webName};
      my $topic = $session->{topicName};
      return getSearcher($session)->restSOLRAUTOSUGGEST($web, $topic);
    },
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('webHierarchy', sub {
      my $session = shift;

      return getWebHierarchy($session)->restWebHierarchy(@_);
    },
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('optimize', sub {
      my $session = shift;
      return getIndexer($session)->optimize();
    },
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('crawl', sub {
      my $session = shift;

      my $query = Foswiki::Func::getCgiQuery();
      my $name = $query->param("name");
      my $path = $query->param("path");
      my $depth = $query->param("depth");

      return getCrawler($session, $name)->crawl($path, $depth);
    },
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  if ($Foswiki::cfg{Plugins}{TaskDaemonPlugin}{Enabled}) {
    Foswiki::Func::registerRESTHandler('index', \&_restIndex,
        authenticate => 1,
        validate => 0,
        http_allow => 'GET,POST',
    );
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

sub getScheduler {

  my $scheduler = $scheduler{$Foswiki::cfg{DefaultUrlHost}};
  unless ($scheduler) {
    require Foswiki::Plugins::SolrPlugin::Scheduler;
    $scheduler = $scheduler{$Foswiki::cfg{DefaultUrlHost}} = Foswiki::Plugins::SolrPlugin::Scheduler->new(@_);
  }

  return $scheduler;
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
  &_dispatchGrinderHandler;
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
  undef $scheduler{$Foswiki::cfg{DefaultUrlHost}};
}

# MaintenancePlugin compatibility
sub maintenanceHandler {
    Foswiki::Plugins::MaintenancePlugin::registerCheck("solrplugin:simplecontributors", {
        name => "SimpleContributors enabled",
        description => "Check if {SolrPlugin}{SimpleContributors} is enabled.",
        check => sub {
            if( $Foswiki::cfg{SolrPlugin}{SimpleContributors} ) {
                return { result => 0 };
            } else {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::WARN,
                    solution => "Unless there is any reason for it: enable {SolrPlugin}{SimpleContributors} in configure.",
                };
            }
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerCheck("solrplugin:mattcrontab", {
        name => "Restart cronjob established",
        description => "Crontab matt_restart should be existent.",
        check => sub {
            require File::Spec;
            unless( -f File::Spec->catfile('/', 'etc', 'cron.d', 'matt_restart')) {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                    solution => "Add crontab matt_restart according to documentation."
                };
            } else {
                return { result => 0 };
            }
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerCheck("solrplugin:schema:current", {
        name => "Solr schema is current",
        description => "Check if schema is up to date.",
        check => sub {
            require File::Spec;
            require Digest::SHA;

            # This is a list of possible schema locations:
            my @schemas = (
                File::Spec->catfile('/', 'var', 'solr', 'data', 'configsets', 'foswiki_configs', 'conf', 'schema.xml'),
            );

            # These schemas can be safely updated
            my %outdatedversions = (
                    'c0275bccfeb7324f04eb0633393749925522e06b3924cade011f95893f6f8414' => 1, # Riga 1.1
                    'fe0e1e7bf884725416c11ba9ad33c267cb1d910de03bdce2fcf0f56025bf1959' => 1, # Riga 1.0
                    '6d4c0879f1f4e4ed3127b7063a2b7385edb6555e6883e99aef3c595eb1b79005' => 1, # Riga 1.3
                    '61395eea5989b31aeae00e7af594298b21abe218499a8f1fcc9209821759b83e' => 1, # Riga 1.3, alternative version
                    'ee6a92157f764df3c79764c94de0b7c454ef39a05bc49a24dee8a146d102ad6f' => 1, # Riga 1.8, with new field 'host'
                    '01124a81b8889d9f34021859857659d20464463986ed9f41479567199f6ec0d6' => 1, # Riga 1.11, adds *_sort for form fields
                    '222bb96310716e3c485893c2f67dca5dae0a6de45bee43ff40fe0e7e54597e2a' => 1 # Riga 1.14, adds HyphenationCompoundWordTokenFilterFactory
            );
            # These schemas are current
            my %goodversions = (
                    '131ecabb1d451acf52c8121c844687316f297db6ad0a42d93138226bf73ff822' => 1 # Riga 1.15, adds json field for UserAdministration
            );

            # Schemas that passed the tests:
            my @goodSchemas = ();
            # Schemas that failed and the reason:
            my %badSchemas = ();

            foreach my $schema ( @schemas ) {
                next unless( -f $schema );
                my $IN_FILE;
                unless ( open( $IN_FILE, '<', $schema ) ) {
                    $badSchemas{$schema} = "failed to read $schema: $!";
                    next;
                };
                binmode($IN_FILE);
                local $/ = undef;
                my $data = <$IN_FILE>;
                close($IN_FILE);

                my $hash = Digest::SHA::sha256_hex($data);

                if( $goodversions{$hash} ) {
                    # Known good version
                    push( @goodSchemas, $schema );
                } elsif( $outdatedversions{$hash} ) {
                    # Known bad versions
                    $badSchemas{$schema} = "This schema is outdated, but can be safely updated (no customizations). Please copy =solr/configsets/foswiki_configs/conf/schema.xml= from your foswiki directory to =$schema=.";
                } else {
                    # Unknown versions
                    # We do not know this schema (probably customized). 
                    if( $data !~ m#name="catchall_autocomplete"# ) {
                        $badSchemas{$schema} = "This schema seems to be outdated (no =catchall_autocomplete=) *%RED%ATTENTION: THIS SCHEMA MIGHT HAVE BEEN CUSTOMIZED%ENDCOLOR%*."
                    } elsif ( $data !~ m#<dynamicField name="\*_msearch"# ) {
                        $badSchemas{$schema} = "This schema seems to be outdated (no =*_msearch=)  *%RED%ATTENTION: THIS SCHEMA MIGHT HAVE BEEN CUSTOMIZED%ENDCOLOR%*."
                    } else {
                        $badSchemas{$schema} = "The schema is unknown, and should be reviewed and updated using the file =solr/configsets/foswiki_configs/conf/schema.xml= from the foswiki directory. Checksum: =$hash=.";
                    }
                }
            }

            unless ( scalar @goodSchemas || scalar keys %badSchemas ) {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                    solution => "Could not find a schema, please check your configuration manually."
                }
            }
            if ( scalar keys %badSchemas ) {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                    solution => "The following schemas need to be checked:<br/>"
                        . join( "<br/>", map { " =$_=: $badSchemas{$_}" } keys %badSchemas),
                }
            } else {
                return { result => 0 };
            }
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerFileCheck(
        "solrplugin:config:ram",
        File::Spec->catfile('/', 'var', 'solr', 'solr.in.sh'),
        'resources/SolrPlugin/solr.in.sh',
        {
            "2d66842f26c6438d70705a88daae6e8919d9e833778d4c91d910ef30bf900e78" => 1, # riga 10
        },
        {
            "f6efb9745ee0293119f45550ac40d30d2ee769ddef9fb7609d75c5754a341457" => 1,
            "d8aef1acc0e56aaca29de623e1566d7116530929e5434cda8ec927e40dfede38" => 1, # riga 9
        },
    );

    Foswiki::Plugins::MaintenancePlugin::registerFileCheck(
        "solrplugin:config:listener",
        File::Spec->catfile('/', 'opt', 'solr', 'server', 'etc', 'jetty-http.xml'),
        'resources/SolrPlugin/jetty-http.xml',
        {"90d26b02557d2dfe8f2bad6da7f38f458d6dfaa9d32b167373edbca34908c20e" => 1},
        {
            "da519544b3baf86e0b431d78a802b2219c425c92dcaba9a805ba26dc0e02dfd2" => 1,
            "d48de31097cf3a3717e9424c27b148a10ee53eb2ef86d0865986dcab77c72e4c" => 1,
        }
    );
    Foswiki::Plugins::MaintenancePlugin::registerCheck("solrplugin:solrconfig:current", {
        name => "Solr config is current",
        description => "Check if solrconfig is up to date.",
        check => sub {
            require File::Spec;
            require Digest::SHA;

            # This is a list of possible schema locations:
            my @configs = (
                File::Spec->catfile('/', 'var', 'solr', 'data', 'configsets', 'foswiki_configs', 'conf', 'solrconfig.xml'),
            );

            # These configs can be safely updated
            my %outdatedversions = (
                    'd0f23b75e76313f41a593a7d250557949096066916387b53976bf0f6090d562e' => 1,
                    '97124e4b7fd5a6c46d032eddd2be1e94f2009431f3eaf41216deadd11dd70814' => 1,
            );
            # These configs are current
            my %goodversions = (
                    '5bd21e1515ed911edcd7c9377c656b759c3e434c2d4e974075dc4f670192a989' => 1,
            );

            # Configs that passed the tests:
            my @goodConfigs = ();
            # Configs that failed and the reason:
            my %badConfigs = ();

            foreach my $config ( @configs ) {
                next unless( -f $config );
                my $IN_FILE;
                unless ( open( $IN_FILE, '<', $config ) ) {
                    $badConfigs{$config} = "failed to read $config: $!";
                    next;
                };
                binmode($IN_FILE);
                local $/ = undef;
                my $data = <$IN_FILE>;
                close($IN_FILE);

                my $hash = Digest::SHA::sha256_hex($data);

                if( $goodversions{$hash} ) {
                    # Known good version
                    push( @goodConfigs, $config );
                } elsif( $outdatedversions{$hash} ) {
                    # Known bad versions
                    $badConfigs{$config} = "This config is outdated, but can be safely updated (no customizations). Please copy =solr/configsets/foswiki_configs/conf/*= from your foswiki directory to =the config folder (parent) of $config/=.";
                } else {
                    # Unknown versions
                    $badConfigs{$config} = "The config is unknown, and should be reviewed and updated using the file =solr/configsets/foswiki_configs/conf/solrconfig.xml= from the foswiki directory. Checksum: =$hash=.";
                }
            }

            unless ( scalar @goodConfigs || scalar keys %badConfigs ) {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                    solution => "Could not find a solrconfig, please check your configuration manually."
                }
            }
            if ( scalar keys %badConfigs ) {
                return {
                    result => 1,
                    priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                    solution => "The following files need to be checked:<br/>"
                        . join( "<br/>", map { " =$_=: $badConfigs{$_}" } keys %badConfigs),
                }
            } else {
                return { result => 0 };
            }
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerCheck("solrscheduler:crontab", {
        name => "Cronjob SolrScheduler",
        description => "Crontab with job for SolrScheduler shuld exist.",
        check => sub {
            require File::Spec;
            my $file = File::Spec->catfile('/', 'etc', 'cron.d', 'foswiki_jobs');
            if( -e $file) {
                open(my $fh, '<', $file) or die "Could not open file '$file' $!";
                local $/ = undef;
                my $hasScheduler = <$fh> =~ /--scheduler\b/;
                close $fh;
                unless($hasScheduler) {
                    return {
                        result => 1,
                        priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                        solution => "Add cronjob to foswiki_jobs according the documentation. [[%SYSTEMWEB%.SolrPlugin]] <verbatim>*/30 * * * * <apache-user> cd <foswiki-dir>/tools; FOSWIKI_ROOT=<foswiki-dir> LOG=<foswiki-dir>/working/logs/solrjob_$(date '+\%u\%H\%M).log ./solrjob --mode full --scheduler on --gracetime 30 >/dev/null 2>&1</verbatim>"
                    }
                }
            }
            return { result => 0 };
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerCheck("solrscheduler:skipscheduled", {
        name => "Cronjob SolrScheduler remove skipscheduled",
        description => "Crontab with job for SolrScheduler --skipscheduled shuld not exist.",
        check => sub {
            require File::Spec;
            my $file = File::Spec->catfile('/', 'etc', 'cron.d', 'foswiki_jobs');
            if( -e $file) {
                open(my $fh, '<', $file) or die "Could not open file '$file' $!";
                local $/ = undef;
                my $hasSkipscheduled = <$fh> =~ /skipscheduled/;
                close $fh;
                if($hasSkipscheduled) {
                    return {
                        result => 1,
                        priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                        solution => "Remove cronjob from foswiki_jobs for solrjob with --skipscheduled on parameter."
                    }
                }
            }
            return { result => 0 };
        }
    });
    Foswiki::Plugins::MaintenancePlugin::registerCheck("solrscheduler:delta", {
        name => "Cronjob SolrScheduler remove delta index",
        description => "Crontab with job for SolrScheduler delta index is not needed.",
        check => sub {
            require File::Spec;
            my $file = File::Spec->catfile('/', 'etc', 'cron.d', 'foswiki_jobs');
            if( -e $file) {
                open(my $fh, '<', $file) or die "Could not open file '$file' $!";
                local $/ = undef;
                my $hasDelta = <$fh> =~ /m delta/;
                close $fh;
                if($hasDelta) {
                    return {
                        result => 1,
                        priority => $Foswiki::Plugins::MaintenancePlugin::ERROR,
                        solution => "Remove cronjob from foswiki_jobs for solrjob with -m delta parameter."
                    }
                }
            }
            return { result => 0 };
        }
    });
}

1;
