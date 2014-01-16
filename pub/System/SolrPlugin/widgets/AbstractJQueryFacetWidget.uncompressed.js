(function($) {
  AjaxSolr.AbstractJQueryFacetWidget = AjaxSolr.AbstractFacetWidget.extend({
    defaults: {
      facetType: 'facet_fields',
      facetMincount: 1,
      multiValue: false,
      union: false,
      exclusion: false,
      label: null,
      exclude: null,
      include: null,
      facetSortReverse: false
    },
    options: {},
    $target: null,
    facetCounts: [],

    isSelected: function(value) {
      var self = this,
          query = self.getQueryByKey(value);
      
      if (query) {
        value = query.value;
      }

      value = value.replace(/^(.*?):/, '');

      return self.inQuery(value) >= 0;
    },

    getQueryByKey: function(key) {
      var self = this;

      if (self.queries) {
        for (var i = 0, l = self.queries.length; i < l; i++) {
          if (self.queries[i].key == key) {
            return self.queries[i];
          }
        }
      }

      return;
    },

    getQueryByValue: function(value) {
      var self = this;

      if (self.queries) {
        for (var i = 0, l = self.queries.length; i < l; i++) {
          if (self.queries[i].value == value) {
            return self.queries[i];
          }
        }
      }

      return;
    },

    getFacetCounts: function() {
      var self = this,
          allFacetCounts = this._super();
          facetCounts = [];

      if (self.options.facetMincount == 0) {
        return allFacetCounts;
      }

      // filter never the less
      $.each(allFacetCounts, function(index, value) {
        if (
          value.count >= self.options.facetMincount && 
          (!self.options.exclude || !value.facet.match(self.options.exclude)) &&
          (!self.options.include || value.facet.match(self.options.include))
        ) {
          facetCounts.push(value);
        }
      });
      
      return (self.options.facetSortReverse?facetCounts.reverse():facetCounts);
    },


    init: function() {
      var self = this;

      self.$target = $(self.target);
      self.options = $.extend({}, self.defaults, self.options, self.$target.data());
      self.facetType = self.options.facetType;

      // propagate some 
      self['facet.mincount'] = self.options.facetMincount;
      self['facet.sort'] = self.options.facetSort;
      self['facet.prefix'] = self.options.facetPrefix;
      self['facet.limit'] = self.options.facetLimit;
      self['facet.offset'] = self.options.facetOffset;
      self['facet.missing'] = self.options.facetMissing;
      self['facet.method'] = self.options.facetMethod;
      self['facet.enum.cache.minDf'] = self.options.facetEnumCacheMinDf;

      switch (self.facetType) {
        case 'facet_dates':
          self['facet.date.start'] = self.options.facetDateStart;
          self['facet.date.end'] = self.options.facetDateEnd;
          self['facet.date.gap'] = self.options.facetDateGap;
          self['facet.date.hardend'] = self.options.facetDateHardend;
          self['facet.date.other'] = self.options.facetDateOther;
          self['facet.date.include'] = self.options.facetDateInclude;
          break;
        case 'facet_ranges':
          self['facet.range.start'] = self.options.facetRangeStart;
          self['facet.range.end'] = self.options.facetRangeEnd;
          self['facet.range.gap'] = self.options.facetRangeGap;
          self['facet.range.hardend'] = self.options.facetRangeHardend;
          self['facet.range.other'] = self.options.facetRangeOther;
          self['facet.range.include'] = self.options.facetRangeInclude;
          break;
      }

      self.key = self.options.label;
      self.field = self.options.field;

      var param = self.manager.store.get("fl"),
          val = param.val();

      if (val == undefined) {
        param.val([self.field]);
      } else {
        val.push(self.field);
      }

      if (self.options.union) {
        self.multivalue = true;
        self.union = self.options.union;
      }

      if (self.options.multiValue) {
        self.tag = self.tag || self.field;
        self.multivalue = true;
      } else {
        self.multivalue = false;
      }

      if (self.options.exclusion) {
        self.tag = self.tag || self.field;
        self.ex = self.tag;
      }

      if (typeof(self.options.defaultValue) !== 'undefined') {
       var meth = self.multivalue ? (self.union ? 'append' : 'add') : 'set';
       self[meth].call(self, self.options.defaultValue);
      }

      self._super();
    },

  });
})(jQuery);
