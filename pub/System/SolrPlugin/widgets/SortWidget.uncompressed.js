(function ($) {
  AjaxSolr.SortWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      defaultSort: 'score desc'
    },

    update: function(value) {
      var self = this;

      if (value == 'score desc') { // default in solrconfig.xml
        self.manager.store.remove("sort");
      } else {
        self.manager.store.addByValue("sort", value);
      }
    },

    afterRequest: function() {
      var self = this, 
          currentSort = self.manager.store.get("sort");

      if (currentSort) {
        self.$target.find("option").removeAttr("selected");
        self.$target.find("[value='"+currentSort.val()+"']").attr('selected', 'selected');
      }
    },

    init: function() {
      var self = this;

      self._super();
      self.$target.change(function() {
        self.update($(this).val());
        self.manager.doRequest(0);
      });
    }
    
  });

  AjaxSolr.Helpers.build("SortWidget");

})(jQuery);
