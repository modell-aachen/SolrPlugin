(function ($) {
"use strict";

  AjaxSolr.TagCloudWidget = AjaxSolr.AbstractJQueryFacetWidget.extend({
    defaults: {
      title: 'title not set',
      buckets: 20,
      offset: 11,
      container: ".solrTagCloudContainer",
      normalize: true,
      facetMincount: 1,
      facetLimit: 100,
      templateName: "#solrTagCloudTemplate",
      startColor: [ 104, 144, 184 ],
      endColor: [ 0, 102, 255 ]
    },
    $container: null,
    template: null,
    facetType: 'facet_fields',

    getFacetCounts: function() {
      var self = this, 
          facetCounts = self._super(),
          floor = -1, ceiling = 0, diff, incr = 1,
          selectedValues = {};

      $.each(self.getQueryValues(self.getParams()), function(index, value) {
        selectedValues[value.replace(/^"(.*)"$/, "$1")] = true;
      });
     
      // normalize, floor, ceiling
      $.each(facetCounts, function(index, value) {
        if (self.options.normalize) {
          value.normCount = Math.log(value.count);
        } else {
          value.normCount = value.count;
        }

        if (value.normCount > ceiling) {
          ceiling = value.normCount;
        }
        if (value.normCount < floor || floor < 0) {
          floor = value.normCount;
        }
      });
      
      // compute the weights and rgb
      diff = ceiling - floor;
      if (diff) {
        incr = diff / (self.options.buckets-1);
      } 
      
      // sort
      facetCounts.sort(function(a,b) {
        var aName = a.facet.toLowerCase(), bName = b.facet.toLowerCase();
        if (aName < bName) return -1;
        if (aName > bName) return 1;
        return 0;
      });

      var lastGroup = '';
      $.each(facetCounts, function(index, value) {
        var c = value.facet.substr(0,1).toUpperCase();
        value.weight = Math.round((value.normCount - floor)/incr)+self.options.offset+1;
        value.color = self.fadeRGB(value.weight);
        if (c == lastGroup) {
          value.group = '';
        } else {
          value.group = ' <strong>'+c+'</strong>&nbsp;';
          lastGroup = c;
        }
        value.current = selectedValues[value.facet]?'current':'';
      });

      return facetCounts;
    },

    fadeRGB: function(weight) {
      var self = this, 
          max = self.options.buckets + self.options.offset,
          red = Math.round(self.options.startColor[0] * (max-weight) / max + self.options.endColor[0] * weight / max),
          green = Math.round(self.options.startColor[1]*(max-weight)/max+self.options.endColor[1]*weight/max),
          blue = Math.round(self.options.startColor[2]*(max-weight)/max+self.options.endColor[2]*weight/max);

      return "rgb("+red+","+green+","+blue+")";
    },

    afterRequest: function() {
      var self = this, 
          facetCounts = self.getFacetCounts();

      if (facetCounts.length) {
        self.$target.show();
        self.$container.empty();
        self.$container.append(self.template.render(facetCounts));
        self.$container.find("a").click(function() {
          var $this = $(this),
              term = $(this).text();
          if ($this.is(".current")) {
            self.unclickHandler(term).apply(self);
          } else {
            self.clickHandler(term).apply(self);
          }
          return false;
        });
      } else {
        self.$target.hide();
      }
    },

    init: function() {
      var self = this;

      self._super();
      self.$container = self.$target.find(self.options.container);
      self.template = $.templates(self.options.templateName);
      self.multivalue = true;
    }
  });

  AjaxSolr.Helpers.build("TagCloudWidget");

})(jQuery);

