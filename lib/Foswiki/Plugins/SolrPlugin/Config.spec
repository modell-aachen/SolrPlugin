# ---+ Extensions
# ---++ SolrPlugin

# **STRING**
# Comma seperated list of webs to skip
$Foswiki::cfg{SolrPlugin}{SkipWebs} = 'Trash, TWiki, TestCases';

# **STRING**
# List of topics to skip.
# Topics can be in the form of Web.MyTopic, or if you want a topic to be excluded from all webs just enter MyTopic.
# For example: Main.WikiUsers, WebStatistics
$Foswiki::cfg{SolrPlugin}{SkipTopics} = 'WebRss, WebSearch, WebStatistics, WebTopicList, WebLeftBar, WebPreferences, WebSearchAdvanced, WebIndex, WebAtom, WebChanges, WebCreateNewTopic, WebNotify';

# **STRING**
# Comma seperated list of extenstions to read, Their metadata is added to the index in any case.
$Foswiki::cfg{SolrPlugin}{IndexExtensions} = 'txt, html, xml, doc, docx, xls, xlsx, ppt, pptx, pdf';

# **STRING**
# List of attachments to skip                                                                                         
# For example: Web.SomeTopic.AnAttachment.txt, Web.OtherTopic.OtherAttachment.pdf 
# Note that neither metadata nor the content of the attachment is added to the index
$Foswiki::cfg{SolrPlugin}{SkipAttachments} = '';

# **BOOLEAN**
# Update the index when a topic is created or save.
# If this flag is disabled, you will have to install a cronjob to update the index regularly.
$Foswiki::cfg{SolrPlugin}{EnableOnSaveUpdates} = 0;

# **BOOLEAN**
# Update the index whenever a file is attached to an existing topic. 
# If this flag is disabled, you will have to install a cronjob to update the index regularly.
$Foswiki::cfg{SolrPlugin}{EnableOnUploadUpdates} = 0;

# **BOOLEAN**
# Update the index whenever a topic is renamed.
# If this flag is disabled, you will have to install a cronjob to update the index regularly.
$Foswiki::cfg{SolrPlugin}{EnableOnRenameUpdates} = 1;

# **PERL H**
# This setting is required to enable executing the solrsearch script from the bin directory
$Foswiki::cfg{SwitchBoard}{solrsearch} = ['Foswiki::Plugins::SolrPlugin', 'searchCgi', { 'solrsearch' => 1 }];

# **PERL H**
$Foswiki::cfg{SwitchBoard}{solrindex} = ['Foswiki::Plugins::SolrPlugin', 'indexCgi', { 'solrindex' => 1 }];

# **STRING**
# Url where to find the solr server
$Foswiki::cfg{SolrPlugin}{Url} = 'http://localhost:8983/solr';

# **BOOLEAN**
# Enable this flag to automatically start a solr instance coming with this plugin
$Foswiki::cfg{SolrPlugin}{AutoStartDaemon} = 0;

# **COMMAND**
# Command used to start the solr instance. Note that <code>solrstart</code> is a shell script wrapping
# around the actual startup routine
$Foswiki::cfg{SolrPlugin}{SolrStartCmd} = $Foswiki::cfg{ToolsDir}.'/solrstart %SOLRHOME|F%';

# **PATH**
# Path to the directory containing the <code>start.jar</code> file. That's where the jetty engine is 
# located and where solr puts its data further down the directory structure
$Foswiki::cfg{SolrPlugin}{SolrHome} = '/home/www-data/foswiki/solr';

1;
