FOSWIKI_ROOT?=~/foswiki/trunk/core
TARGET=\
  ajax-solr.js \
  ajax-solr-widgets.js \
  ajax-solr-init.js \
  solrplugin.css \
  pattern.css \
  solr-searchbox.js \
  wikiusers.js \
  wikiusers.css \
  jquery.autosuggest.js \
  jquery.autosuggest.css

-include $(FOSWIKI_ROOT)/pub/System/JQueryPlugin/Makefile.include

AJAX_SOLR_SOURCE=\
  ajax-solr/core/Core.js \
  ajax-solr/core/Parameter.js \
  ajax-solr/core/ParameterStore.js \
  ajax-solr/core/ParameterHashStore.js \
  ajax-solr/core/AbstractManager.js \
  ajax-solr/core/AbstractWidget.js \
  ajax-solr/core/AbstractFacetWidget.js \
  ajax-solr/core/AbstractSpatialWidget.js \
  ajax-solr/core/AbstractSpellcheckWidget.js \
  ajax-solr/core/AbstractTextWidget.js \
  ajax-solr/managers/Manager.jquery.js \
  ajax-solr/helpers/ajaxsolr.support.js \
  ajax-solr-helpers.uncompressed.js \
  ajax-solr-dictionary.uncompressed.js

AJAX_SOLR_WIDGETS_SOURCE=\
  widgets/getWebMapping.uncompressed.js \
  widgets/AbstractJQueryWidget.uncompressed.js \
  widgets/AbstractJQueryFacetWidget.uncompressed.js \
  widgets/FacetFieldWidget.uncompressed.js \
  widgets/WebFacetWidget.uncompressed.js \
  widgets/ToggleFacetWidget.uncompressed.js \
  widgets/DefaultFacetWidget.uncompressed.js \
  widgets/PagerWidget.uncompressed.js \
  widgets/ResultsPerPageWidget.uncompressed.js \
  widgets/ResultWidget.uncompressed.js \
  widgets/SearchBoxWidget.uncompressed.js \
  widgets/CurrentSelectionWidget.uncompressed.js \
  widgets/SortWidget.uncompressed.js \
  widgets/TagCloudWidget.uncompressed.js \
  widgets/HierarchyWidget.uncompressed.js \
  widgets/SpellcheckWidget.uncompressed.js \
  widgets/TextInputWidget.uncompressed.js \
  widgets/RedirectFacetWidget.uncompressed.js

ajax-solr:
	git clone https://github.com/evolvingweb/ajax-solr.git

ajax-solr.uncompressed.js: Makefile ajax-solr $(AJAX_SOLR_SOURCE)
	@echo "generating ajax-solr.uncompressed.js"
	@$(CAT) $(AJAX_SOLR_SOURCE) > $@

ajax-solr-widgets.uncompressed.js: Makefile $(AJAX_SOLR_WIDGETS_SOURCE)
	@echo "generating ajax-solr-widgets.uncompressed.js"
	@$(CAT) $(AJAX_SOLR_WIDGETS_SOURCE) > $@
