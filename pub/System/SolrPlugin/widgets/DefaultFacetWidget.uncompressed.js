(function ($) {
"use strict";

  AjaxSolr.DefaultFacetWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    options: {
      value: null
    },

    init: function() {
      var self = this;
      self._super();
      if (self.options.value !== null) {
          self.set.call(self, self.options.value);
      }
    }
  });

  AjaxSolr.Helpers.build("DefaultFacetWidget");
})(jQuery);
