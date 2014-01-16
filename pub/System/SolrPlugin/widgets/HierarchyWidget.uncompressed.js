(function ($) {

  AjaxSolr.HierarchyWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    defaults: {
      templateName: '#solrHierarchyTemplate',
      container: '.solrHierarchyContainer',
      breadcrumbs: '.solrHierarchyBreadcrumbsContainer',
      hideNullValues: false,
      hideSingle: false,
      name: null
    },

    updateHierarchy: function() {
      var self = this, dict;

      if (typeof(self.hierarchy) === 'undefined') {
        $.ajax({
          url: foswiki.getPreference('SCRIPTURL')+'/rest/SolrPlugin/webHierarchy',
          async: false,
          success: function(data) {
            self.hierarchy = data;
          }
        });

        dict = AjaxSolr.Dicts["default"];
        $.each(self.hierarchy, function(i, entry) {
          var id = entry.id, 
              title = entry.title,
              label = entry.id.split(/\s*\.\s*/).pop();
          dict.set(id, title);
          dict.set(label, title);
        });
      }

      
      return self.hierarchy;
    },

    getChildren: function(id) {
      var self = this, children = [];

      if (typeof(id) !== 'undefined') {
        if (typeof(self.hierarchy[id].children) !== 'undefined') {
          $.each(self.hierarchy[id].children, function(i, val) {
            var entry = self.hierarchy[val];
            if (self.facetCounts[val]) {// || entry.type == 'web') {
              children.push(entry);
            }
          });
        }
      } else {
        $.each(self.hierarchy, function(i, entry) {
          if (typeof(entry['parent']) === 'undefined' && (self.facetCounts[entry.id] || entry.type == 'web')) {
            children.push(entry);
          }
        });
      }

      if (children.length == 1) {
        return self.getChildren(children[0].id);
      }

      return children.sort(function(a, b) {
        return (a.title < b.title ? -1 : (a.title > b.title ? 1 : 0));
      });
    },

    afterRequest: function () {
      var self = this, currrent, children = [], facetCounts = {}, breadcrumbs = [], prefix = [];

      self.$target.hide();
      self.facetCounts = self.getFacetCounts();

      if (typeof(self.facetCounts) === 'undefined' || self.facetCounts.length == 0) {
        return;
      } 

      if (this.options.hideSingle && self.facetCounts.length == 1) {
        return;
      } 

      $.each(self.facetCounts, function(i, entry) {
        facetCounts[entry.facet] = entry.count;
      });

      self.facetCounts = facetCounts;

      current = self.getQueryValues(self.getParams());
      if (typeof(current) === 'undefined') {
        return;
      }

      current = current[0];

      self.breadcrumbs.empty();
      breadcrumbs.push("<a href='#' class='solrFacetValue root' data-value='"+current+"'>"+_("Root")+"</a>");
      if (typeof(current) !== 'undefined') {
        $.each(current.split(/\s*\.\s*/), function(i, val) {
          prefix.push(val);
          breadcrumbs.push("<a href='#' class='solrFacetValue' data-value='"+prefix.join(".")+"'>"+_(val)+"</a>");
        });
      }
      self.breadcrumbs.append(breadcrumbs.join("&nbsp;&#187; "));

      children = self.getChildren(current);
//      if (children.length == 0) {
//        return;
//      }

      // okay lets do it
      self.$target.show();
      self.container.html($.tmpl(self.template, children, {
        renderFacetCount: function(facet) {
          var count = self.facetCounts[facet];
          return count?"<span class='solrHierarchyFacetCount'>("+count+")</span>":""; 
        },
        getCategory: function(id) {
          return self.hierarchy[id];
        },
        getChildren: function() {
          return self.getChildren(this.data.id);
        }
      }));

      if (typeof(current) !== 'undefined') {
        self.container.find("a.cat_"+current.replace(/\./g, "\\.")).addClass("current");
      }

      self.container.parent().find("a").click(function() {
        var $this = $(this),
            value = $(this).data("value");
        if ($this.is(".root")) {
          self.unclickHandler(value).apply(self);
        } else {
          self.clickHandler(value).apply(self);
        }
        return false;
      });

    },

    init: function() {
      var self = this;

      self._super();
      self.template = $(self.options.templateName).template();
      self.container = self.$target.find(self.options.container);
      self.breadcrumbs = self.$target.find(self.options.breadcrumbs);
      self.updateHierarchy();

    }

  });

  AjaxSolr.Helpers.build("HierarchyWidget");


})(jQuery);
