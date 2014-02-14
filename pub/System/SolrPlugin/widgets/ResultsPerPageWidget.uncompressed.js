(function ($) {
  
  AjaxSolr.ResultsPerPageWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      rows: 20,
      templateName: '#solrResultsPerPageTemplate'
    },
    template: null,

    afterRequest: function() {
      var self = this,
          rows = self.manager.store.get('rows').val(),
          responseHeader = self.manager.response.responseHeader,
          numFound = parseInt(self.manager.response.response.numFound),
          entriesPerPage = parseInt(responseHeader.params && responseHeader.params.rows || 20),
          from = parseInt(responseHeader.params && responseHeader.params.start || 0),
          to = from+entriesPerPage;

      if (to > numFound) {
        to = numFound;
      }

      self.$target.empty();

      self.$target.append($.tmpl(self.template, {
        from: from+1,
        to: to,
        count: numFound
      }));

      if (numFound > 0) {
        self.$target
          .find(".solrRows").show()
          .find("option[value='"+rows+"']").attr("selected", "selected")
          .end().find("select").change(function() {
            var rows = $(this).val();
            self.manager.store.get('rows').val(rows);
            self.manager.doRequest(0);
          });

      } else {
        self.$target.find(".solrRows").hide();
      }
    },

    init: function () {
      var self = this;

      self._super();
      self.template = $(self.options.templateName).template();
      if (!self.template) {
        throw "template "+self.options.templateName+" not found";
      }
    }
  });

  // integrate into jQuery 
  AjaxSolr.Helpers.build("ResultsPerPageWidget");

})(jQuery);

