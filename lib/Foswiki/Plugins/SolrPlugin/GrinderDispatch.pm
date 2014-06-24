package Foswiki::Plugins::SolrPlugin::GrinderDispatch;

use strict;
use warnings;

use Foswiki::Func ();

my @flushCmd;

sub _send {
    my ($message, $type) = @_;

    Foswiki::Plugins::TaskDaemonPlugin::send($message, $type, 'SolrPlugin');
}

sub beforeSaveHandler {
    my ( $text, $topic, $web, $meta ) = @_;

    return unless $topic eq $Foswiki::cfg{WebPrefsTopicName};

    my ($oldMeta) = Foswiki::Func::readTopic($web, $topic);
    if ($oldMeta->getPreference('ALLOWWEBVIEW') ne $meta->getPreference('ALLOWWEBVIEW') ||
            $oldMeta->getPreference('DENYWEBVIEW') ne $meta->getPreference('DENYWEBVIEW')) {
        @flushCmd = ([$web, 'flush_acls'], [$web, 'update_web']);
    }
}

sub afterSaveHandler {
    my ( $text, $topic, $web, $error, $meta ) = @_;

    foreach my $cmd (@flushCmd) {
        _send(@$cmd);
    }
    if (!@flushCmd) {
        _send("$web.$topic", 'update_topic');
    }
    undef @flushCmd;
}

sub afterRenameHandler {
    my ( $oldWeb, $oldTopic, $oldAttachment,
         $newWeb, $newTopic, $newAttachment ) = @_;

     if(not $oldTopic) {
         _send("$newWeb", 'update_web'); # old web will be deleted automatically
     } else {
         # XXX when a topic is being moved in the frontend a
         # _send("$newWeb.$newTopic") will be fired by afterSaveHandler, since
         # a %META:TOPICMOVED{...}% will be inserted
         _send("$oldWeb.$oldTopic", 'update_topic');
         _send("$newWeb.$newTopic", 'update_topic');
     }
}

sub completePageHandler {
    my( $html, $httpHeaders ) = @_;

    my $session = $Foswiki::Plugins::SESSION;
    my $req = $session->{request};
    if ($req->action eq 'manage' && $req->param('action') =~ /^(?:add|remove)User(?:To|From)Group$/ ||
        $req->param('refreshldap'))
    {
        _send('', 'flush_groups');
        _send("$Foswiki::cfg{UsersWebName}.". $req->param('groupname'), 'update_topic') if $req->param('groupname');
    }
}

# Disabled -> let afterSave handle it
sub afterUploadHandlerDisabled {
    my( $attrHashRef, $meta ) = @_;

    my $web = $meta->web();
    my $topic = $meta->topic();

    _send("$web.$topic", 'update_topic');
}

sub _restIndex {
    my ( $session, $subject, $verb, $response ) = @_;

    my $params = $session->{request}->{param};
    my ($web, $topic) = Foswiki::Func::normalizeWebTopicName( $params->{w}[0], $params->{t}[0] );

    $web = '' if ( !$params->{w}[0] );
    $topic = '' if ( !$params->{t}[0] );

    if ( !$web || !Foswiki::Func::webExists( $web ) ) {
        $response->status( 400 );
        return;
    }

    if ( $topic ) {
        _send( "$web.$topic", 'update_topic' );
    } else {
        _send( $web, "update_web" );
    }

    $response->status( 200 );
}

1;
