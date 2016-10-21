package Foswiki::Plugins::SolrPlugin::GrinderDispatch;

use strict;
use warnings;

use Foswiki::Func ();

my @flushCmd;
my $isNewTopic;

sub _send {
    my ($message, $type, $wait) = @_;

    Foswiki::Plugins::TaskDaemonPlugin::send($message, $type, 'SolrPlugin', $wait);
}

sub beforeSaveHandler {
    my ( $text, $topic, $web, $meta ) = @_;

    $isNewTopic = !Foswiki::Func::topicExists($web, $topic);
    return unless $topic eq $Foswiki::cfg{WebPrefsTopicName};

    my ($oldMeta) = Foswiki::Func::readTopic($web, $topic);

    # check if preferences are set, if set check permissions
    my ($AVold, $AV ) = ( $oldMeta->getPreference('ALLOWWEBVIEW'), $meta->getPreference('ALLOWWEBVIEW'));
    my ($DVold, $DV ) = ( $oldMeta->getPreference('DENYWEBVIEW'), $meta->getPreference('DENYWEBVIEW'));
    if (( (defined $AVold && defined $AV) && ($AVold  ne $AV) ) ||
            ( (defined $DVold && defined $DV) && ($DVold  ne $DV) )) {
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
        _send("$web.$topic", 'check_backlinks') if $isNewTopic;
    }
    undef @flushCmd;
}

sub afterRenameHandler {
    my ( $oldWeb, $oldTopic, $oldAttachment,
         $newWeb, $newTopic, $newAttachment ) = @_;

    if( not $oldTopic ) {
        _send("$newWeb", 'update_web'); # old web will be deleted automatically
        _send("$oldWeb", 'web_check_backlinks');
        _send("$newWeb", 'web_check_backlinks');
    } else {
        # If attachment moved (i.e. $oldAttachment is not false), update oldtopic. Otherwise, topic moved: Delete oldtopic.
        # Attachment moving or updating does not trigger afterSaveHandler.
        if ( $oldAttachment ) {
            # update topic if not only attachment moved.
           _send("$oldWeb.$oldTopic", 'update_topic') unless $oldWeb eq $newWeb && $oldTopic eq $newTopic;
        } else {
           _send("$oldWeb.$oldTopic", 'delete_topic');
        }
        _send("$newWeb.$newTopic", 'update_topic');
        _send("$oldWeb.$oldTopic", 'check_backlinks');
        _send("$newWeb.$newTopic", 'check_backlinks');
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

    # Always allow members of the admin group to edit
    return 1 if ( Foswiki::Func::isAnAdmin() );

    return 0 if ( ( ! $allow ) || ( $allow =~ /^\s*nobody\s*$/ ) );
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
