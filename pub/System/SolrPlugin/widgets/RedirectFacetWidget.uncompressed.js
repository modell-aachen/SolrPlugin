(function ($) {
  AjaxSolr.RedirectFacetWidget = AjaxSolr.AbstractWidget.extend({
    options: {
      templateName: '#solrRedirectFacetTemplate',
    },

    // Takes the string from the query and puts it into a fq
    beforeRequest: function() {
      var self = this;

      self._super();

      self.manager.store.removeByValue('fq', new RegExp('^-?' + self.field + ':'));
      if($(self.target).find('input').prop('checked')) {
        var val = $('.solrSearchField:first').val();
        self.manager.store.removeByValue('q', /./);
        self.append.call(self, '"'+val+'"');
      }
    },

    // Takes the string from the fq and puts it back into the query
    afterRequest: function () {
      var self = this;

      var $input = $(self.target).find('input');
      if($input.prop('checked')) {
        var fq = self.manager.store.values('fq');
        var reg = new RegExp('^'+self.field+':"(.*)"$');
        for (var i = 0, l = fq.length; i < l; i++) {
          if (fq[i] && !self.manager.store.isHidden("fq="+fq[i])) {
            match = fq[i].match(reg);
            if(match) {
                self.manager.store.get('q').val(match[1]);
                self.manager.store.removeByValue('fq', fq[i]);
                break;
            }
          }
        }
      }
    },

    init: function() {
      var self = this;

      self._super();

      var doRequest = function() {
        var val = $('.solrSearchField:first').val();
        if(val) {
          self.doRequest(0);
        }
      };

      var $target = $(self.target);
      var metadata = $target.metadata();
      if(metadata.template) self.options.templateName = metadata.template;

      var checked = false;
      var fq = self.manager.store.values('fq');
      var reg = new RegExp("^" + self.field + ":");
      for (var i = 0, l = fq.length; i < l; i++) {
        if (fq[i] && !self.manager.store.isHidden("fq="+fq[i]) && reg.test(fq[i])) {
          checked = true;
          break;
        }
      }

      $target.append($(self.options.templateName).render(
        {
          id: AjaxSolr.Helpers.getUniqueID(),
          checked: checked
        }, {
          foswiki: window.foswiki,
        }
      ));
      var $input = $target.find('input').change(function() {
        doRequest();
      });
    },
    fq: function (value, exclude) {
      if (/^[^\[].*:.*$/.test(value)) {
        return (exclude ? '-' : '') + AjaxSolr.Parameter.escapeValue(value);
      } else {
        return (exclude ? '-' : '') + this.field + ':' + AjaxSolr.Parameter.escapeValue(value);
      }
    },
    append: function(value) {
      var param = this.manager.store.addByValue('fq', this.fq(value));
        if (param && this.tag) {
          param.local("tag", this.tag);
          param.local("q.op", "AND");
        }
        return true;
    }

  });

  AjaxSolr.Helpers.build("RedirectFacetWidget");

})(jQuery);
