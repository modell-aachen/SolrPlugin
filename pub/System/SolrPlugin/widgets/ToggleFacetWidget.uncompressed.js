(function ($) {
"use strict";

  AjaxSolr.ToggleFacetWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    options: {
      templateName: '#solrToggleFacetTemplate',
      value: null,
      inverse: false
    },
    checkbox: null,

    afterRequest: function () {
      var self = this;

      if (self.isSelected(self.options.value)) {
        if (self.options.inverse) {
          self.checkbox.removeAttr("checked");
        } else {
          self.checkbox.attr("checked", "checked");
        }
      } else {
        if (self.options.inverse) {
          self.checkbox.attr("checked", "checked");
        } else {
          self.checkbox.removeAttr("checked");
        }
      }
    },

    init: function() {
      var self = this;

      self._super();
      self.$target.append($(self.options.templateName).render({
        id: AjaxSolr.Helpers.getUniqueID(),
        title: self.options.title
      }));

      self.checkbox = 
        self.$target.find("input[type='checkbox']").change(function() {
          if ($(this).is(":checked")) {
            if (self.options.inverse) {
              self.unclickHandler(self.options.value).call(self);
            } else {
              self.clickHandler(self.options.value).call(self);
            }
          } else {
            if (self.options.inverse) {
              self.clickHandler(self.options.value).call(self);
            } else {
              self.unclickHandler(self.options.value).call(self);
            }
          }
        });

      if (self.options.inverse) {
        self.add(self.options.value);
      }
    }

  });

  AjaxSolr.Helpers.build("ToggleFacetWidget");


})(jQuery);


