(function ($) {
"use strict";

  AjaxSolr.CurrentSelectionWidget = AjaxSolr.AbstractJQueryWidget.extend({
    options: {
      defaultQuery: "",
      templateName: "#solrCurrentSelectionTemplate",
      keywordText: "keyword"
    },
    template: null,
    selectionContainer: null,

    getKeyOfValue: function(field, value) {
      var self = this, 
          key = value.replace(/^[\(\[]?(.*?)[\]\)]?$/, "$1"),
          responseParams = self.manager.response.responseHeader.params,
          facetTypes = ["facet.field", "facet.query", "facet.date"], //"facet.range"],
          //facetTypes = ["facet.query"],
          regex = /\s*([^=]+)='?([^'=]+)'?\s*/g, local, paramString, match;

      value = value.replace(/([\[\]\.\*\?\+\-\(\)])/g, "\\$1");

      for (var i in facetTypes) {
        for (var j in responseParams[facetTypes[i]]) {
          paramString = responseParams[facetTypes[i]][j];
          match = paramString.match("^{!(.*)}\\w+:"+value);
          if (match) {
            match = match[1];
            //console.log("match=",match);
            while ((local = regex.exec(match)) != null) {
              //console.log("local=",local[1],"=",local[2]);
              if (local[1] == 'key') {
                return local[2];
              }
            }
          }
        }
      }

      if (field == 'web') {
        var arr = key.split(/ /);
        for (var i = 0, l = arr.length; i < l; i++) {
          arr[i] = _(arr[i].replace(/\./g, '/'));
        }
        return arr.join(", ");
      }

      return _(key);
    },

    afterRequest: function () {
      var self = this, 
          fq = self.manager.store.values('fq'),
          q = self.manager.store.get('q').val(),
          match, field, value, key, count = 0;

      self.clearSelection();

      if (q && q !== self.options.defaultQuery) {
        count++;
        self.addSelection(self.options.keywordText, q, function() {
          self.manager.store.get('q').val(self.options.defaultQuery);
          self.manager.doRequest(0);
        });
      }

      for (var i = 0, l = fq.length; i < l; i++) {
        if (fq[i] && !self.manager.store.isHidden("fq="+fq[i])) {
          count++;
          match = fq[i].match(/^(?:{!.*?})?(.*?):(.*)$/);
          field = match[1];
          value = match[2]; 
          key = self.getKeyOfValue(field, value); 
          self.addSelection(field, key, self.removeFacet(field, value));
        }
      }

      if (count) {
        self.$target.find(".solrNoSelection").hide();
        self.$target.find(".solrClear").show();
      }
    },

    clearSelection: function()  {
      var self = this;
      self.selectionContainer.children().not(".solrNoSelection").remove();
      self.$target.find(".solrNoSelection").show();
        self.$target.find(".solrClear").hide();
    },

    addSelection: function(field, value, handler) {
      var self = this;

      if (field.match(/^([\-\+])/)) {
        field = field.substr(1);
        value = RegExp.$1 + value;
      }

      self.selectionContainer.append($(self.template.render({
        id: AjaxSolr.Helpers.getUniqueID(),
        field: _(field),
        facet: value
      }, {
        getWebMapping: AjaxSolr.getWebMapping,
        foswiki: window.foswiki
      })).change(handler));
    },

    removeFacet: function (field, value) {
      var self = this;

      return function() {
        if (self.manager.store.removeByValue('fq', field + ':' + AjaxSolr.Parameter.escapeValue(value))) {
          self.manager.doRequest(0);
        }
      }
    },

    init: function() {
      var self = this;

      self._super();
      self.template = $.templates(self.options.templateName);
      self.selectionContainer = self.$target.children("ul:first");
      self.$target.find(".solrClear").click(function() {
        self.clearSelection();
      });
    }
  });

  // integrate into jQuery 
  AjaxSolr.Helpers.build("CurrentSelectionWidget");


})(jQuery);

