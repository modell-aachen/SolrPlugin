/***************************************************************************
 * SolrManager
 *
 * (c)opyright 2009-2010 Michael Daum http://michaeldaumconsulting.com
 */

var solr; /* last solr manager constructed; this is a singleton in most use cases */

(function($) {

  /***************************************************************************
   * constructor
   */
  $.SolrManager = function(elem, opts) {
    var self = this;
    self.log("SolrManager constructor called");

    /* basic properties */
    self.container = $(elem);
    self.opts = opts;
    self.suppressSubmit = false; 
    //self.suppressSetFilter = false;
    self.selection = [];
    self.mapping = [];

    self.initMapping();
    self.initGui();
  };

  /***************************************************************************
   * initMapping: read meta data and establish a translation map for strings
   */
  $.SolrManager.prototype.initMapping = function () {
    var self = this;
    self.log("initMapping called");

    /* get mappings from meta tags */
    $("meta[name^=foswiki.SolrPlugin.mapping]").each(function() {
      var $this = $(this);
      var key = $this.attr('name').replace(/^.*\./, '');
      var val = $this.attr('content');
      self.mapping['DATA::'+key] = val; // adding DATA:: prefix to prevent clashes with prototype properties of Arrays, like 'filter' 
      //self.log("mapping key="+key+", val="+val);
    });

    /* get mappings from facet values */
  };
 
  /***************************************************************************
   * getFacetValue: creates a FacetValue from the data embeded in a dom element
   */
  $.SolrManager.prototype.getFacetValue = function(elem) {
    var self = this;
    var $elem = $(elem);
    var val = $elem.attr('value');
    var title = $elem.attr('title') || undefined;
    //self.log("getFacetValue called for element "+$elem.attr('id')+", val="+val+" title="+title);
    var match = /^(.*?):(.*)$/.exec(val);
    if (match !== undefined) {
      var facetValue = {};
      facetValue.facet = match[1];
      facetValue.value = match[2];
      if (title !== undefined) {
        facetValue.valueTitle = title;
      }
      return facetValue;
    }
  };

  /***************************************************************************
   * showSelection: render "Your current selection" based on the current selection
   */
  $.SolrManager.prototype.showSelection = function() {
    var self = this;
    self.log("showSelection called");

    $(".solrYourSelection > ul > li:not(.solrNoSelection)").remove()
    if (self.selection.length) {
      var template = "<li>"+
        "<table class='foswikiLayoutTable' width='100%'>"+
          "<tr>"+
          "<td width='12px'><input type='checkbox' class='foswikiCheckbox solrDeleteFacetValue solrDeleteFacetValue_$facet' value='$facet:$value' id='del_$facet_$value' name='filter' checked='checked'/></td>"+
          "<td><label for='del_$facet_$value' style='display:block'>$valuetitle (<nop>$facettitle)</label></td>"+
          "</tr>"+
        "</table>"+
        "</li>";
      
      //self.debugSelection();

      var list = $(".solrYourSelection > ul");
      for (var i = 0; i < self.selection.length; i++) {
        var fv = self.selection[i];
        var valueTitle = fv.valueTitle;
        var facetTitle = fv.facetTitle;
        if (valueTitle === undefined) {
          valueTitle = self.mapping['DATA::'+fv.value];
          if (valueTitle === undefined) {
            valueTitle = fv.value;
          }
        }
        if (facetTitle === undefined) {
          facetTitle = self.mapping['DATA::'+fv.facet];
          if (facetTitle === undefined) {
            facetTitle = fv.facet;
          }
        }
        var item = template
          .replace(/\$valuetitle/g, valueTitle)
          .replace(/\$facettitle/g, facetTitle)
          .replace(/\$value/g, fv.value)
          .replace(/\$facet/g, fv.facet);
        //self.log("item="+item);
        //self.log("template="+template);
        list.append(item);
      }
      $(".solrClearAll").show();
      $(".solrNoSelection").hide();
    } else {
      $(".solrClearAll").hide();
      $(".solrNoSelection").show();
    }
  };

  /***************************************************************************
   * debug selection
   */
  $.SolrManager.prototype.debugSelection = function() {
    var self = this;
    if ($.SolrManager.DEBUG) {
      for (var i = 0; i < self.selection.length; i++) {
        self.log("selection["+i+"].facet="+self.selection[i].facet);
        self.log("selection["+i+"].facetTitle="+self.selection[i].facetTitle);
        self.log("selection["+i+"].value="+self.selection[i].value);
        self.log("selection["+i+"].valueTitle="+self.selection[i].valueTitle);
      }
    }
  };

  /***************************************************************************
   * selectFacetValue: adds a FacetValue to the selection and updates the ui
   */
  $.SolrManager.prototype.selectFacetValue = function(fv) {
    if (fv === undefined) {
      return 0;
    }

    var self = this;
    var retVal = 0; // 0: new fv, 1: replaced an old one

    //fv.value = fv.value.replace(/"/g, '');
    self.log("selectFacetValue("+fv.facet+", "+fv.value+", "+fv.facetTitle+", "+fv.valueTitle+") called");

    /* filter out old */
    var indexOf = -1;
    for (var i = 0; i < self.selection.length; i++) {
      if (self.selection[i].facet == fv.facet && self.selection[i].value == fv.value) {
        indexOf = i;
        break;
      }
    }
    if (indexOf >= 0) {
      self.selection.splice(indexOf, 1);
      retVal = 1;
    }
    self.selection.push(fv);

    if (fv.facet === 'keyword') {
      var keywords = self.getKeywordsFromSelection().join(' ');
      $(".solrSearchField").val(keywords);
    } else {
      $(".solrFacetValue[value="+fv.facet+":"+fv.value+"]").addClass("current").filter("input").attr('checked', 'checked');
    }


    return retVal; 
  };

  /***************************************************************************
   * unselectFacetValue: removes a FacetValue from the selection and updates the ui
   */
  $.SolrManager.prototype.unselectFacetValue = function(fv) {
    if (fv === undefined) {
      return 0
    }

    var self = this;
    var retVal = 0;

    //fv.value = fv.value.replace(/"/g, '');
    self.log("unselectFacetValue("+fv.facet+", "+fv.value+", "+fv.facetTitle+", "+fv.valueTitle+") called");
    
    /* filter out old */
    var indexOf = -1;
    for (var i = 0; i < self.selection.length; i++) {
      if (self.selection[i].facet == fv.facet && self.selection[i].value == fv.value) {
        indexOf = i;
        break;
      }
    }
    if (indexOf >= 0) {
      self.selection.splice(indexOf, 1);
      retVal = 1;
    }

    if (fv.facet === 'keyword') {
      $(".solrSearchField").val(self.getKeywordsFromSelection().join(' '));
    } else {
      $(".solrFacetValue[value="+fv.facet+":"+fv.value+"]").removeClass("current").filter("input").removeAttr('checked');
    }


    return retVal;
  };

  /***************************************************************************
   * getKeywords: get an arry of words and phrases in the search field
   */
  $.SolrManager.prototype.getKeywords = function () {
    var self = this;
    var search = $(".solrSearchField").val();
    var keywords = [];
    var re = /([\+\-]?(?:(?:[^\s"]+)|(?:"[^"]+")))/g; 
    while(re.exec(search)) { 
      keywords.push(RegExp.$1);
    }

    return keywords;
  };

  /***************************************************************************
   * getKeywordsFrom: get the list of selected words and phrases 
   */
  $.SolrManager.prototype.getKeywordsFromSelection = function () {
    var self = this;

    var keywords = [];
    for (var i = 0; i < self.selection.length; i++) {
      if (self.selection[i].facet === 'keyword') {
        keywords.push(self.selection[i].value);
      }
    }

    return keywords;
  };

  /***************************************************************************
   * initGui
   */
  $.SolrManager.prototype.initGui = function() {
    var self = this;
    self.log("initGui called");

    /* add filters to selection */
    $(".solrFilter").each(function() {
      var $this = $(this);
      var fv = $this.metadata();
      if (fv.value === undefined) {
        fv.value = $this.val();
      }
      fv.value = unescape(fv.value).replace(/(^")|("$)/g, '');
      self.selectFacetValue(fv);
    });

    /* add search to selection */
    var keywords = self.getKeywords();
    for (var i = 0; i < keywords.length; i++) {
      self.selectFacetValue({
        facet:'keyword',
        value:keywords[i]
      });
    }

    /* sort facets alphabetically */
    $(".solrFacetContainer.solrSort, .solrFacetContainer.solrSortReverse").each(function() {
      var $this = $(this);
      var $list = $this.find("ul");
      var items = $list.find("li").sort(function(a, b) {
        var valA = $("label", a).text().toUpperCase();
        var valB = $("label", b).text().toUpperCase();
        return (valA<valB)?-1:(valA>valB)?1:0;
      });
      if ($this.is(".solrSort")) {
        $.each(items, function(index, elem) {
          $list.append(elem);
        });
      } else {
        $.each(items, function(index, elem) {
          $list.prepend(elem);
        });
      }
      $this.removeClass("solrSort");
    });

    /* init autocompletion */
    var filter = [];
    for (var i = 0; i < self.selection.length; i++) {
      var fv = self.selection[i];
      if (fv.facet !== 'keyword') {
        filter.push(fv.facet+":"+fv.value);
      }
    }
    if (filter.length) {
      filter = "?filter="+filter.join(",");
    }
    $(".solrSearchField").autocomplete(foswiki.getPreference("SCRIPTURL")+'/rest/SolrPlugin/autocomplete'+filter, {
      selectFirst: false,
      autoFill:false,
      matchCase:false,
      matchSubset:false,
      matchContains:false,
      scrollHeight:'20em',
      formatItem: function(row, index, max, search) {
        return "<table width='100%'><tr><td>"+row[0]+"</td><td align='right'>"+row[2]+"</td></tr></table>";
      }
    });

    /* init facet container */
    $(".solrFacetContainer:not(.jqInitedFacetContainer)").each(function() {
      var $this = $(this);
      var $pager = $this.find('.solrFacetPager');
      if ($pager.length) {
        var $ul = $pager.find("ul:first");
        $this.addClass('jqInitedFacetContainer');

        // get options
        var opts = $.extend({
            pagesize: 10
          }, $pager.metadata());

        var nrVals = $ul.children('li').length;
        if (nrVals <= 1) {
          $this.hide();
          $pager.removeClass("solrFacetPager");
        } else {
          if ($pager.length && nrVals > opts.pagesize) {
            // add pager if pagesize is exceeded
            var $panel = $("<div class='panel'></div>").appendTo($pager);
            var nrPages = Math.ceil(nrVals / opts.pagesize);
            for (var page = 0; page < nrPages; page++) {
              var $newUl = $("<ul class='items'></ul>").appendTo($panel);
              $ul.find("li:lt("+opts.pagesize+")").appendTo($newUl);
            }
            var $buttons = $("<div class='solrFacetPagerButtons'></div>").insertAfter($pager);
            var prev = $("<a href='#' class='solrFacetPagerPrev'>prev</a>").appendTo($buttons);
            var next = $("<a href='#' class='solrFacetPagerNext'>next</a>").appendTo($buttons);
            var $counter = $("<div class='solrFacetPagerCounter'>1/"+nrPages+"</div>").appendTo($buttons);
            $("<span class='foswikiClear' />").appendTo($buttons);
            $ul.remove();
            $pager.serialScroll({
              items:'.items',
              prev:prev,
              next:next,
              constant:false,
              duration:500,
              start:0,
              force:false,
              cycle:true,
              lock:false,
              easing:'easeOutQuart',
              onBefore:function(e, elem, $pane, items, pos) {
                $counter.html((pos+1)+"/"+nrPages);
              }
            });
            $this.find(".foswikiClear").insertAfter($buttons);
            $this.find(".solrClear").addClass('solrInPagedFacet').insertAfter($buttons);
          } else {
            $pager.removeClass("solrFacetPager");
          }
        }
      }
    });

    /* behavior for sorting */
    $("#solrSorting").change(function() {
      $("#solrSortOption").val($(this).val());
      self.submit();
    });

    /* behavior for rows */
    $("#solrRows").change(function() {
      $("#solrRowsOption").val($(this).val());
      self.submit();
    });

    /* behavior for display */
    $(".solrDisplay").click(function(e) {
      self.log("solrDisplay clicked");
      $("#solrDisplayOption").val($(this).val());
      self.submit();
    });

    /* behavior for facets */
    $(".solrFacetValue:not(.solrFacetValueInited)").livequery(function() {
      var $this = $(this);
      $this.addClass("solrFacetValueInited");

      /* get mapping */
      var fv = self.getFacetValue(this);
      if (fv && fv.valueTitle) {
        self.mapping['DATA::'+fv.value] = fv.valueTitle;
        //self.log("mapping key="+fv.value+", val="+fv.valueTitle+" found in "+$(this).attr('id'));
      }

      /* update selection */
      if ($this.is(".current, :checked")) {
        if (self.selectFacetValue(fv) == 1) {
          self.showSelection();
          self.debugSelection();
        }
      }

      /* install change handler */
      $this.click(function(e) {
        self.log("solrFacetValue changed");
        if ($this.is("input[type=radio]")) {
          $("[name="+$this.attr('name')+"]").each(function() {
            var fv = self.getFacetValue(this);
            self.unselectFacetValue(fv);
          });
        }
        $this.toggleClass("current");
        $(".solrDeleteFacetValue[value="+$this.val()+"]").removeAttr("checked");
        if ($this.is(".current")) {
          self.selectFacetValue(fv);
        } else {
          self.unselectFacetValue(fv);
        }
        self.showSelection();
        self.submit();
        return false;
      });

      /* add hover handler */
      $this.parents('li:first').hover(
        function() { $(this).addClass("solrHover"); },
        function() { $(this).removeClass("solrHover"); }
      );
    });

    /* behaviour for delete facet */
    $(".solrDeleteFacetValue:not(.solrDeleteFacetValueInited)").livequery(function() {
      var $this = $(this);

      /* install click handler */
      $this.change(function(e) {
        self.log("solrDeleteFacetValue clicked");
        var fv = self.getFacetValue(this);
        $this.removeAttr('checked');
        self.unselectFacetValue(fv);
        self.showSelection();
        self.submit();
      });

      /* add hover handler */
      $this.parents('li:first').hover(
        function() { $(this).addClass("solrHover"); },
        function() { $(this).removeClass("solrHover"); }
      );
    });

    /* auto sumbit */
    $(".solrAutoSubmit").click(function(e) {
      self.log("solrAutoSubmit clicked");
      self.submit();
    });

    /* behavior for clear button */
    $(".solrClear").click(function(e) {
      self.log("solrClear clicked");
      var $this = $(this);
      var fv = $.extend({}, $this.metadata());

      /* get facet values to clear */
      var selector = fv.selector;
      if (!selector) {
        selector = ".solrFacetValue_"+fv.facet;
      }
      self.log("selector="+selector);

      /* clear selection */
      $(selector).each(function() {
        var fv = self.getFacetValue(this);
        self.unselectFacetValue(fv);
      });
      self.showSelection();
      self.submit();
      return false;

    }).each(function() {
      /* show when there's something to clear */
      var $this = $(this);
      if($this.parent().find("input:checked").length) {
        $this.show();
      }
    });

    /* switch on */
    self.showSelection();
    $(".solrYourSelection label").css('visibility', 'hidden');
    $(".solrFacetPager").show();

    window.setTimeout(function() {
      $(".solrYourSelection label").css('visibility', 'visible');
    }, 100);
  };

  /***************************************************************************
   * submit: submits the search form; before, the selection is linearized
   * as hidden solrFilter input fields
   */
  $.SolrManager.prototype.submit = function() {
    var self = this;
    self.log("submit called");
    $("body, a, input").css('cursor', 'progress');

    var $form = $(".solrSearchForm");
    $form.find(".solrFilter").remove();
    for (var i = 0; i < self.selection.length; i++) {
      var fv = self.selection[i];
      if (fv.facet !== 'keyword') {
        var filter = fv.facet+":";
        if (fv.value.match(/\s|(%20)/) && !fv.value.match(/^".*"$/)) {
          filter += "\""+fv.value+"\"";
        } else {
          filter += fv.value;
        }
        self.log("filter value="+filter);
        $form.prepend("<input type='hidden' class='solrFilter' name='filter' value='"+filter+"' />");
      }
    }

    if (self.suppressSubmit || $.SolrManager.SUPPRESSSUBMIT) {
      self.log("... suppressed");
      return;
    }

    $(".solrSearchForm").submit();
  };

  /***************************************************************************
   * logger
   */
  $.SolrManager.prototype.log = function(msg)  {
    if ($.SolrManager.DEBUG) {
      //$.log("SOLR: "+msg);
      window.console.log("SOLR: "+msg);
    }
  };

  /***************************************************************************
   * default options
   */
  $.SolrManager.defaults = {};

  /***************************************************************************
   * static flags
   */
  $.SolrManager.DEBUG = false; // enables logging messages using $.log(), that is: 
                              // you will need to load the jquery.debug module as well
  $.SolrManager.SUPPRESSSUBMIT = false; // if set to true, the search form will not be submitted

  /***************************************************************************
   * plugin constructor
   */
  $.fn.solrize = function(opts) {
    solr = new $.SolrManager(this, opts);
  };

  $(function() {
    $(".solrSearch:not(.solrSearchInited)").each(function() {
      var $this = $(this);
      var opts = $.extend({}, $.SolrManager.defaults, $this.metadata());
      $this.addClass("solrSearchInited");
      $this.solrize(opts);
    });
  });

})(jQuery);
