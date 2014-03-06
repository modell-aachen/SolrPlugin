jQuery(function($) {
  $(".solrSearchHits .foswikiProfileInfo:nth-child(3n+1)").livequery(function() {
    $(this).addClass("first");
  });
});
