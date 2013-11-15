#!/usr/bin/perl -w
BEGIN { unshift @INC, split( /:/, $ENV{FOSWIKI_LIBS} ); }
use Foswiki::Contrib::Build;

# Create the build object
$build = new Foswiki::Contrib::Build('SolrPlugin');

$build->{UPLOADTARGETWEB} = 'Extensions';
$build->{UPLOADTARGETPUB} = 'http://extensions.open-quality.com/pub';
$build->{UPLOADTARGETSCRIPT} = 'http://extensions.open-quality.com/bin';
$build->{UPLOADTARGETSUFFIX} = '';

$build->build($build->{target});

