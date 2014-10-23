package Foswiki::Plugins::SolrPlugin::GrinderDispatch;

use strict;
use warnings;

use Foswiki::Func ();

my @flushCmd;

sub _send {
    my ($message, $type, $wait) = @_;

    Foswiki::Plugins::TaskDaemonPlugin::send($message, $type, 'SolrPlugin', $wait);
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

    if( not $oldTopic ) {
        _send("$newWeb", 'update_web'); # old web will be deleted automatically
    } else {
        # If attachment moved (i.e. $oldAttachment is not false), update oldtopic, otherweise, topic moved delete oldtopic..
        # Attachment moving or updating does not trigger afterSaveHandler.
        if ( $oldAttachment ) {
           _send("$oldWeb.$oldTopic", 'update_topic') unless $oldWeb eq $newWeb && $oldTopic eq $newTopic;
        } else {
           _send("$oldWeb.$oldTopic", 'delete_topic');
        }
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

sub afterUploadHandler {
    my( $attrHashRef, $meta ) = @_;

    my $web = $meta->web();
    my $topic = $meta->topic();

    _send("$web.$topic", 'update_topic');
}

sub _restIndex {
    my ( $session, $subject, $verb, $response ) = @_;

    if(!_isAllowed($Foswiki::cfg{SolrPlugin}{AllowRestInterface})) {
        $response->status( 403 );
        return;
    }
    my $params = $session->{request}->{param};
    my $web = $params->{w}[0] || '';
    my $topic = $params->{t}[0] || '';
    my $wait = $params->{wait}[0];

    ($web, $topic) = Foswiki::Func::normalizeWebTopicName( $web, $topic ) if $topic;

    if ( !$web || (!Foswiki::Func::webExists( $web ) && $web ne 'all' ) ) {
        $response->status( 400 );
        return;
    }

    if ( $topic ) {
        _send( "$web.$topic", 'update_topic', $wait );
    } else {
        _send( $web, "update_web", $wait );
    }

    $response->status( 200 );
}

# Copy/Paste KVPPlugin/WorkflowPlugin
sub _isAllowed {
    my ($allow) = @_;

    return 1 unless ($allow);

    # Always allow members of the admin group to edit
    return 1 if ( Foswiki::Func::isAnAdmin() );

    return 0 if ( $allow =~ /^\s*nobody\s*$/ );
    if($allow =~ /\bLOGGEDIN\b/ && not Foswiki::Func::isGuest()) {
        return 1;
    }

    if (
            ref( $Foswiki::Plugins::SESSION->{user} )
            && $Foswiki::Plugins::SESSION->{user}->can("isInList")
        )
    {
        return $Foswiki::Plugins::SESSION->{user}->isInList($allow);
    }
    elsif ( defined &Foswiki::Func::isGroup ) {
        my $thisUser = Foswiki::Func::getWikiName();
        foreach my $allowed ( split( /\s*,\s*/, $allow ) ) {
            ( my $waste, $allowed ) =
              Foswiki::Func::normalizeWebTopicName( undef, $allowed );
            if ( Foswiki::Func::isGroup($allowed) ) {
                return 1 if Foswiki::Func::isGroupMember( $allowed, $thisUser );
            }
            else {
                $allowed = Foswiki::Func::getWikiUserName($allowed);
                $allowed =~ s/^.*\.//;    # strip web
                return 1 if $thisUser eq $allowed;
            }
        }
    }

    return 0;
}

1;
