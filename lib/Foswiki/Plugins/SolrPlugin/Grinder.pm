use strict;
use warnings;

use Encode;

{
    cache_fields => ['groups_members', 'web_acls'],
    handle_message => sub {
        my ($host, $t, $hdl, $run_engine, $json) = @_;
        if ($t =~ m'delete_topic|update_topic|update_web') {
            $main::mattworker_data{caches} = $json->{cache};
            eval { $run_engine->(); };
            if ($@) {
                print "Worker: $t exception: $@\n";
            } else {
                return {
                    caches => $main::mattworker_data{caches},
                };
            }
        } elsif ($t eq 'flush_acls') {
            print STDERR "Flush web ACL cache\n";
            $hdl->push_write(json => {type => 'clear_cache', host => $host});
        } elsif ($t eq 'flush_groups') {
            print STDERR "Flush group membership cache\n";
            $hdl->push_write(json => {type => 'clear_cache', host => $host});
        }
        return {};
    },
    engine_part => sub {
        my ($session, $type, $data, $caches) = @_;
        my $indexer = Foswiki::Plugins::SolrPlugin::getIndexer($session);
        $indexer->groupsCache($caches->{groups_members}) if $caches->{groups_members};
        $indexer->webACLsCache($caches->{web_acls}) if $caches->{web_acls};

        # Workaround for excessive Unicodization in JSON layer
        $data = Encode::encode_utf8($data);

        if ($type eq 'update_topic') {
            $indexer->updateTopic(undef, $data);
            $indexer->commit(1);
        }
        elsif ($type eq 'delete_topic') {
            my ($web, $topic) = Foswiki::Func::normalizeWebTopicName(undef, $data);
            $indexer->deleteTopic($web, $topic);
            $indexer->commit(1);
        }
        elsif ($type eq 'update_web') {
            $indexer->update($data);
            $indexer->commit(1);
        }

        $main::mattworker_data{caches} = {
            groups_members => $indexer->groupsCache(),
            web_acls => $indexer->webACLsCache(),
        };
    },
};
