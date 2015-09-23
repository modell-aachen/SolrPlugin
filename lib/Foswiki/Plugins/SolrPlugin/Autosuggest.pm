# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2013-2015 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
package Foswiki::Plugins::SolrPlugin::Autosuggest;

use strict;
use warnings;

use Foswiki::Plugins::JQueryPlugin::Plugin ();
our @ISA = qw( Foswiki::Plugins::JQueryPlugin::Plugin );

sub new {
  my $class = shift;

  my $this = bless(
    $class->SUPER::new(
      name => 'Autosuggest',
      version => '2.00',
      author => 'Michael Daum',
      homepage => 'http://foswiki.org/Extensions/SolrPlugin',
      css => ['jquery.autosuggest.css'],
      javascript => ['jquery.autosuggest.js', ],
      puburl => '%PUBURLPATH%/%SYSTEMWEB%/SolrPlugin',
      dependencies => ['ui::autocomplete', 'render', 'blockUI'],
    ),
    $class
  );

  return $this;
}

1;

