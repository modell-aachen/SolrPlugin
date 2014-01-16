var _ = function(key, id) {
  id = id || 'default'
  var dict = AjaxSolr.Dicts[id];
  if (typeof(dict) !== 'undefined') {
    return dict.get(key);
  } 
  return key;

};

(function($) {
  AjaxSolr.Dictionary = function(elem, opts) {
    var self = this, 
        $elem = $(elem),
        thisOpts = $.extend({}, $elem.data(), opts);

    self.id = $elem.attr('id') || thisOpts.id || 'default';
    self.data = {};
    self.container = $elem;
    self.opts = thisOpts;
    self.init();
  };

  AjaxSolr.Dictionary.prototype.init = function() {
    var self = this;
    self.text = self.container.text();
    self.data = $.parseJSON(self.text);
  };

  AjaxSolr.Dictionary.prototype.get = function(key) {
    var self = this, val, subDict;

    key = key.replace(/^\s*(.*?)\s*$/, "$1");
    val = self.data[key];

    if (typeof(val) !== 'undefined') {
      return val;
    }

    if (typeof(self.opts.subDictionary) === 'undefined') {
      return key;
    }

    subDict = AjaxSolr.Dicts[self.opts.subDictionary];
    if (typeof(subDict) !== 'undefined') {
      return subDict.get(key);
    }

    return key;
  };

  AjaxSolr.Dictionary.prototype.set = function(key, val) {
    var self = this;
    key = key.replace(/^\s*(.*?)\s*$/, "$1");
    self.data[key] = val;
  };

  $(function() {
    var first;

    AjaxSolr.Dicts = {};

    $(".solrDictionary").each(function() {
      var dict = new AjaxSolr.Dictionary(this);
      if(!first) first = dict;
      AjaxSolr.Dicts[dict.id] = dict;
    });

    AjaxSolr.Dicts['default'] = AjaxSolr.Dicts['default'] || first;

  });
})(jQuery);
