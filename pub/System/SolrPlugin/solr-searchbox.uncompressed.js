jQuery(function($) {
"use strict";

  $(".solrSearchBox form").livequery(function() {
    var $this = $(this),
        action = $this.attr("action");
    $this.submit(function() {
      var search = $this.find("input[name='search']"),
          href = action + ((search && search.val())?'#q='+search.val():'');
      window.location.href = href;
      return false;
    });
  });
});
