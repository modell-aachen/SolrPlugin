use strict;
use warnings;

{
    handle_message => sub {
        my ($host, $t, $hdl, $run_engine, $json) = @_;
        my $core = $Foswiki::cfg{ScriptDir};
        $core =~ s#/bin/?$##;
        if ($t =~ m'delete_topic|update_topic|update_web|(?:web_)?check_backlinks') {
            eval { $run_engine->(); };
            if ($@) {
                print "Worker: $t exception: $@\n";
            } else {
                return {};
            }
        }
        return {};
    },
    engine_part => sub {
        my ($session, $type, $data) = @_;
        my $indexer = Foswiki::Plugins::SolrPlugin::getIndexer($session);

        my $reindex_backlinks = sub {
            my ($wt, $isWeb, $broken) = @_;
            my $suffix = $broken ? '_broken' : '';
            my $linktype = $broken ? 'broken' : 'outgoing';
            my $searcher = Foswiki::Plugins::SolrPlugin::getSearcher($session);
            my $data = $wt;
            $data .= '.*' if $isWeb;

            my $res = $searcher->solrSearch(
                "outgoingWiki${suffix}_lst:$data OR outgoingAttachment${suffix}_lst:$data\\/*",
                { rows => 99999999, wt => 'json' })->raw_response->content;
            eval {
                $res = decode_json($res);
            };
            if ($@) {
                warn "Can't understand $linktype links for $wt from Solr: $@\n";
                return;
            }
            return unless $res->{response} && $res->{response}{numFound};
            for my $doc (@{$res->{response}{docs}}) {
                $indexer->updateTopic(undef, $doc->{webtopic});
            }
            $indexer->commit(1);
        };

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
        elsif ($type eq 'web_check_backlinks') {
            if (Foswiki::Func::webExists($data)) {
                # new location, check for any broken links pointing here
                $reindex_backlinks->($data, 1, 1);
            } else {
                # old location, check for any working links we need to mark as
                # broken
                $reindex_backlinks->($data, 1, 0);
            }
        } elsif ($type eq 'check_backlinks') {
            if (Foswiki::Func::topicExists(undef, $data)) {
                # new location, check for any broken links pointing here
                $reindex_backlinks->($data, 0, 1);
            } else {
                # old location, check for any working links we need to mark as
                # broken
                $reindex_backlinks->($data, 0, 0);
            }
        }
    },
};
