(function($) {
"use strict";

  AjaxSolr.Helpers = {
    getUniqueID: function() {
      var uid = new Date().getTime().toString(32), i;
      for (i = 0; i < 5; i++) {
        uid += Math.floor(Math.random() * 65535).toString(32);
      }
      return uid;
    },

    build: function(widgetName) {
      $.fn["solr"+widgetName] = function(manager, opts) {
        return this.each(function() {
          var $this = $(this),
              field = $this.data('field'),
              id = $this.attr('id'),
              widget;

          if(typeof(id) === 'undefined') {
            id = AjaxSolr.Helpers.getUniqueID();
            $this.attr('id', id);
          }

          widget = new AjaxSolr[widgetName]({
            id: id,
            target: '#'+id,
            field: field,
            options: opts
          });

          $this.data('widget', widget);
          manager.addWidget(widget);
        });
      };
    }
  };
})(jQuery);
