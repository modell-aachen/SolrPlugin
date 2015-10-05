(function($) {
"use strict";

  AjaxSolr.getWebMapping = function(web) {
      if(!AjaxSolr.Dicts.webmappings) return web;

      web = web.replace(/\./g, '/');

      // first, lets see if there is a mapping for the full path
      var mapped = AjaxSolr.Dicts.webmappings.get(web);
      if(mapped !== web) return mapped;

      // we did not find a mapping, or it is equal (no way to catch that)
      // lets try each part individually
      // XXX We should try combinations first eg. web='a/b/c' -> webmappings.get('a' + '/' + 'b') + '/' +webmappings('c')
      var mappings = [];
      $.each(web.split(/\//), function(idx, eachWeb){
          mappings[idx] = AjaxSolr.Dicts.webmappings.get(eachWeb);
      });
      return mappings.join('/');
  };
})(jQuery);
