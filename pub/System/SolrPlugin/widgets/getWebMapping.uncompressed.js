(function($) {
"use strict";

  AjaxSolr.getWebMapping = function(web) {
      if(!AjaxSolr.Dicts.webmappings) return web;
      var mappings = [];
      web.split(/\./).forEach(function(eachWeb, idx){
          mappings[idx] = AjaxSolr.Dicts.webmappings.get(eachWeb);
      });
      return mappings.join('/');
  };
})(jQuery);
