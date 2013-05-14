// (c)opyright 2013 Michael Daum http://michaeldaumconsulting.com

(function($) {

  $.widget( "solr.autosuggest", $.ui.autocomplete, {
    options: {
      source: foswiki.getPreference("SCRIPTURL") + '/rest/SolrPlugin/autosuggest',
      thumbnailUrl: foswiki.getPreference("SCRIPTURL") + "/rest/ImagePlugin/resize?size=48&crop=north",
      delay: 500,
      minLength: 3,
      position: {
        my: "right top",
        at: "right bottom",
        collision: "none"
      },

      locales: {
        persons: 'Persons',
        topics: 'Topics',
        attachments: 'Attachments',
        more: "show more &#187;",
        loading: "Loading ..."
      },

      itemTemplate: "<li><a href='${url}'><table class='foswikiNullTable'><tr><th><div><img class='${imgClass}' width='48' alt='${name}' src='${thumbnailUrl}' /></div></th><td>${title}<div class='foswikiGrayText'>${description}</div></td></tr></table></a></li>",
      headerTemplate: "<li class='ui-menu-item ui-widget-header ${key}'><a class='ui-autosuggest-more' href='${moreUrl}'>${more}</a>${title}</li>",

      focus: function() {
        return false;
      },

      select: function(event, data) {
        if (event.keyCode == 13) {
          window.location.href = data.item.url;
        }
        return false;
      }
    },

    _init: function() {
      var elem = this.menu.element;

      elem.addClass("ui-autosuggest").removeClass("ui-autocomplete");
    },

    _renderMenu: function(ul, items) {
        var self = this,
            sections = {};

        $.each(items, function(index, item) {
          if (typeof(sections[item._section]) === 'undefined') {
            sections[item._section] = [];
          }
          sections[item._section].push(item);
        });

        $.each(sections, function(key, section) {

          $.tmpl(self.options.headerTemplate, {
            key: key,
            title: self.options.locales[key] || key,
            more: self.options.locales.more,
            moreUrl: foswiki.getPreference("SCRIPTURLPATH")+"/System/WebHome"
          }).data("ui-autocomplete-item", {value:''}).appendTo(ul);

          ul.find("a.ui-autosuggest-more").click(function() {
            window.location.href = $(this).attr("href");
            $.blockUI({message:"<h1>"+self.options.locales.loading+"</h1>"});
            return false;
          });

          $.each(section, function(index, item) {
            self._renderItemData(ul, item);
          });
        });
      },

      _renderItem: function(ul, item) {
        var self = this, thumbnailUrl, $row, imgClass;

          if (typeof(item.thumbnail) !== 'undefined') {
            imgClass = "thumbnail";
            if (/^(\/|http:)/.test(item.thumbnail)) {
              thumbnailUrl = item.thumbnail;
            } else {
              thumbnailUrl = self.options.thumbnailUrl + '&topic=' + item.web + '.' + item.topic + '&file=' + item.thumbnail;
            }
          } else {
            imgClass = "thumbnail dummy";
            thumbnailUrl = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
          }

          $row = $.tmpl(self.options.itemTemplate, {
            url: item.url,
            thumbnailUrl: thumbnailUrl,
            imgClass: imgClass,
            name: item.name,
            title: item._section === 'attachments' ?  item.name : item.title,
            description: typeof(item.container_title) !== 'undefined' ?  item.container_title : ''
          });          

        return $row.appendTo(ul);
      },
      _normalize: function( items ) {
        return items; // don't normalize 
      },
      _move: function(direction, event) {
        var elem;

        this._super(direction, event);

        elem = this.menu.active;

        if ($(elem).is(".ui-widget-header")) {
          this._super(direction, event);
        }
      }
  });

})(jQuery);
