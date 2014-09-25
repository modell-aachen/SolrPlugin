jQuery(function($) {
"use strict";

  $(".solrSearchBox form").submit(function() {
    var $this = $(this),
        action = $this.attr("action"),
        search = $this.find("input[name='search']"),
        href = action + ((search && search.val())?'#q='+search.val():'');
    window.location.href = href;
    return false;
  });
});

