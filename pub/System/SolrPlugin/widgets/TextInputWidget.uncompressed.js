(function ($) {
  AjaxSolr.TextInputWidget = AjaxSolr.AbstractWidget.extend({
    options: {
      templateName: '#solrTextInputFacetTemplate',
    },

    afterRequest: function () {
      var self = this;
    },

    beforeRequest: function() {
      var self = this;

      self.manager.store.removeByValue('fq', new RegExp('^-?' + self.field + ':'));

      var val = $(self.target).find('input').val();
      if(val) {
        self.append.call(self, '"'+val+'"');
      }
    },

    init: function() {
      var self = this;

      self._super();

      var doRequest = function() {
          var val = $target.find('input').val();
          if(self.lastVal === val) return;
          if(val) {
              self.doRequest(0);
          }
          self.lastVal = val;
      };

      var $target = $(self.target);
      var metadata = $target.metadata();
      self.autocompleteField = metadata.autocompleteField;
      if(!self.autocompleteField) {
          self.autocompleteField = self.field;
      }

      $target.append($(self.options.templateName).render({
        id: AjaxSolr.Helpers.getUniqueID(),
        foswiki: window.foswiki
      }));
      var $input = $target.find('input').keypress(function(ev) {
          if(ev.which == 13) {
              doRequest();
          }
      })
      if(!metadata.noautocomplete) $input.autocomplete({
            source: function(request, response) {
                var term = metadata.doNotLcTerm ? request.term : request.term.toLocaleLowerCase();
                $.ajax({
                    url:foswiki.getPreference('SCRIPTURLPATH') + 'rest' + foswiki.getPreference('SCRIPTSUFFIX') + '/SolrPlugin/proxy',
                    data: {
                        q: self.autocompleteField + ':' + term + '*',
                        'facet.field': self.field,
                        'facet.mincount': 1,
                        facet: true
                    },
                    success: function(data, textStatux, jqXHR) {
                        var results = [];
                        if(data && data.facet_counts && data.facet_counts.facet_fields[self.field]) {
                            var facets = data.facet_counts.facet_fields[self.field];
                            var pos;
                            for(pos = 0; pos < facets.length - 1; pos += 2) {
                                results.push({ label: facets[pos] + ' (' + facets[pos + 1] + ')', value: facets[pos] });
                            }
                        }
                        response(results);
                    }
                });
            },
            change: doRequest
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
      var param = this.manager.store.addByValue('fq', this.fq('(' + value + ')'));
        if (param && this.tag) {
          param.local("tag", this.tag);
          param.local("q.op", "OR");
        }
        return true;
    }

  });

  AjaxSolr.Helpers.build("TextInputWidget");

})(jQuery);
