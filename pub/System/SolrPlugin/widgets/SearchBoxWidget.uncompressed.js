(function ($) {
"use strict";

  AjaxSolr.SearchBoxWidget = AjaxSolr.AbstractTextWidget.extend({
    defaults: {
      instantSearch: false,
      instantSearchDelay: 1000,
      instantSearchMinChars: 3
    },
    $input: null,
    doRequest: false,
    intervalID: null,

    afterRequest: function() {
      var self = this,
          q = self.manager.store.get("q");

      if (q && self.$input) {
        self.$input.val(q.val());
      }
    },

    installAutoSumbit: function() {
      var self = this;

      // clear an old one
      if (self.intervalID) {
        window.clearInterval(self.intervalID);
      }

      // install a new one
      self.intervalID = window.setInterval(function() {
        if (self.doRequest) {
          self.$target.submit();
        }
      }, self.options.instantSearchDelay);
    },
  
    init: function () {
      var self = this, search;

      self._super();
      self.$target = $(self.target);
      self.$input  = self.$target.find(".solrSearchField");
      self.options = $.extend({}, self.defaults, self.options, self.$target.data());

      if (self.options.instantSearch) {
        self.installAutoSumbit();

        self.$input.bind("keydown", function() {
          self.installAutoSumbit();
          if (self.$input.val().length >= self.options.instantSearchMinChars) {
            self.doRequest = true;
          }
        });
      } 

      self.$target.submit(function() {
        var value = self.$input.val();
        if (self.set(value)) {
          self.doRequest = false;
          self.manager.doRequest(0);
        }
        return false;
      });
    }

  });

  AjaxSolr.Helpers.build("SearchBoxWidget");

})(jQuery);



