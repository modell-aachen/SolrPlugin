(function ($) {
"use strict";

  AjaxSolr.PagerWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults:  {
      prevText: 'Previous',
      nextText: 'Next',
      enableScroll: false,
      scrollTarget: '.solrPager:first',
      scrollSpeed: 250
    },

    clickHandler: function (page) {
      var self = this;
      return function () {
        var start = page * (self.manager.response.responseHeader.params && self.manager.response.responseHeader.params.rows || 20)
        //console.log("page=",page,"start="+start);
        //self.manager.store.get('start').val(start);
        self.manager.doRequest(start);
        if (self.options.enableScroll) {
          $.scrollTo(self.options.scrollTarget, self.options.scrollSpeed);
        }
        return false;
      }
    },

    afterRequest: function () {
      var self = this,
          response = self.manager.response,
          responseHeader = response.responseHeader,
          entriesPerPage = parseInt(responseHeader.params && responseHeader.params.rows || 20),
          totalEntries = parseInt(response.response.numFound),
          start = parseInt(responseHeader.params && responseHeader.params.start || 0),
          startPage,
          endPage,
          currentPage,
          lastPage,
          count,
          marker;

      self.$target.empty();

      //console.log("responseHeader=",responseHeader, "totalEntries=",totalEntries);

      lastPage = Math.ceil(totalEntries / entriesPerPage) - 1;
      //console.log("lastPage=",lastPage);
      if (lastPage <= 0) {
        self.$target.hide();
        return;
      }
      self.$target.show();

      currentPage = Math.ceil(start / entriesPerPage);
      //console.log("currentPage=",currentPage,"lastPage=",lastPage);

      if (currentPage > 0) {
        $("<a href='#' class='solrPagerPrev'>"+self.options.prevText+"</a>").click(self.clickHandler(currentPage-1)).appendTo(self.$target);
      } else {
        self.$target.append("<span class='solrPagerPrev foswikiGrayText'>"+self.options.prevText+"</span>");
      }

      startPage = currentPage - 4;
      endPage = currentPage + 4;
      if (endPage >= lastPage) {
        startPage -= (endPage-lastPage+1);
        endPage = lastPage;
      }
      if (startPage < 0) {
        endPage -= startPage;
        startPage = 0;
      }
      if (endPage > lastPage) {
        endPage = lastPage;
      }

      if (startPage > 0) {
        $("<a href='#'>1</a>").click(self.clickHandler(0)).appendTo(self.$target);
      }

      if (startPage > 1) {
        self.$target.append("<span class='solrPagerEllipsis'>&hellip;</span>");
      }

      count = 1;
      marker = '';
      for (var i = startPage; i <= endPage; i++) {
        marker = i == currentPage?'current':'';
        $("<a href='' class='"+marker+"'>"+(i+1)+"</a>").click(self.clickHandler(i)).appendTo(self.$target);
        count++;
      }

      if (endPage < lastPage-1) {
        self.$target.append("<span class='solrPagerEllipsis'>&hellip;</span>");
      }

      if (endPage < lastPage) {
        marker = currentPage == lastPage?'current':'';
        $("<a href='#' class='"+marker+"'>"+(lastPage+1)+"</a>").click(self.clickHandler(lastPage)).appendTo(self.$target);
      }

      if (currentPage < lastPage) {
        $("<a href='#' class='solrPagerNext'>"+self.options.nextText+"</a>").click(self.clickHandler(currentPage+1)).appendTo(self.$target);
      } else {
        self.$target.append("<span class='solrPagerNext foswikiGrayText'>"+self.options.nextText+"</span>");
      }
    },
  });

  // integrate into jQuery 
  AjaxSolr.Helpers.build("PagerWidget");

})(jQuery);
