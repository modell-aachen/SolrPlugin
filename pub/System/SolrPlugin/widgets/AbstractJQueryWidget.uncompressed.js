(function($) {
"use strict";

  AjaxSolr.AbstractJQueryWidget = AjaxSolr.AbstractWidget.extend({
    defaults: {},
    options: {},
    $target: null,
    init: function() {
      var self = this;
      self.$target = $(self.target);
      self.options = $.extend({}, self.defaults, self.options, self.$target.data());
    }
  });
})(jQuery);

