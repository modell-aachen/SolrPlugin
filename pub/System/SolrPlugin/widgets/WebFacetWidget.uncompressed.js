(function($) {
"use strict";

  AjaxSolr.WebFacetWidget = AjaxSolr.FacetFieldWidget.extend({
    facetType: 'facet_fields',
    keyOfValue: {},

    getFacetKey: function(facet) {
      var self = this, key = self.keyOfValue[facet];
      return key?key:facet;
    },

    getFacetCounts: function() {
      var self = this,
          facetCounts = self._super(),
          facet;

      for (var i = 0, l = facetCounts.length; i < l; i++) {
        facet = facetCounts[i].facet;
        //self.keyOfValue[facet] = facetCounts[i].key = _(facet.slice(facet.lastIndexOf('.') + 1));
        self.keyOfValue[facet] = facetCounts[i].key = _(facet.replace(/\./g,"/"));
      }

      facetCounts.sort(function(a,b) {
        var aName = a.key.toLowerCase(), bName = b.key.toLowerCase();
        if (aName < bName) return -1;
        if (aName > bName) return 1;
        return 0;
      });

      return facetCounts;
    }

  });

  AjaxSolr.Helpers.build("WebFacetWidget");

})(jQuery);
