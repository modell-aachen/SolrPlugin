var _;

(function($) {
  AjaxSolr.Dictionary = {
    data: {},
    init: function(elem) {
      AjaxSolr.Dictionary.data = $.parseJSON($(elem).text());
    },
    _: function(key) {
      key = key.replace(/^\s*(.*?)\s*$/, "$1");
      return AjaxSolr.Dictionary.data[key]?AjaxSolr.Dictionary.data[key]:key;
    }
  };

  $(function() {
    AjaxSolr.Dictionary.init(".solrDictionary");
    _ = AjaxSolr.Dictionary._;
  });
})(jQuery);
