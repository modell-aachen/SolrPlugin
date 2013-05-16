/*
 * jQuery autosuggest plugin 1.00
 *
 * Copyright (c) 2013 Michael Daum http://michaeldaumconsulting.com
 *
 * Dual licensed under the MIT and GPL licenses:
 *   http://www.opensource.org/licenses/mit-license.php
 *   http://www.gnu.org/licenses/gpl.html
 *
 */
(function($) {

  $.widget( "solr.autosuggest", $.ui.autocomplete, {
    options: {
      thumbnailBase: foswiki.getPreference("SCRIPTURL") + "/rest/ImagePlugin/resize?size=48&crop=north",
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
        loading: "Loading ..."
      },

      templates: {
        "persons": "<li class='ui-menu-item person'><a href='${url}'><table class='foswikiNullTable'><tr><th><div><img class='thumbnail' width='48' alt='${name}' src='${thumbnail}' /></div></th><td>${title}<div class='foswikiGrayText'>${phoneNumber}</div></td></tr></table></a></li>",
        "default": "<li class='ui-menu-item'><a href='${url}'><table class='foswikiNullTable'><tr><th><div><img class='thumbnail' width='48' alt='${name}' src='${thumbnail}' /></div></th><td>${title}<div class='foswikiGrayText'>${container_title}</div></td></tr></table></a></li>",
        "header": "<li class='ui-menu-item ui-widget-header ${group}'><span class='ui-autosuggest-pager'><a class='ui-autosuggest-prev ui-icon ui-icon-circle-triangle-w' title='prev' href='#'></a><a class='ui-autosuggest-next ui-icon ui-icon-circle-triangle-e' title='next' href='#'></a></span>${title}</li>"
      },

      focus: function() {
        return false;
      },

      select: function(event, data) {
        if (event.keyCode == 13 || $.browser.msie) {
          window.location.href = data.item.url;
        }
        return false;
      },

      cache: true,
      source: foswiki.getPreference("SCRIPTURL") + '/rest/SolrPlugin/autosuggest'

    },

    _init: function() {
      var elem = this.menu.element;

      elem.addClass("ui-autosuggest").removeClass("ui-autocomplete");
    },

    _initSource: function() {
      var self = this;

      self.cache = {};

      self.source = function(request, response) {
        var term = request.term, cacheKey = term;

        // add extra parameters 
        if (typeof(self.options.extraParams) != 'undefined') {
          $.each(self.options.extraParams, function(key, param) {
            var val = typeof(param) === "function" ? param(self) : param;
            request[key] = val;
            cacheKey += ';' + key + '=' + val;
          });
        }

        // check cache
        if (self.options.cache && cacheKey in self.cache) {
          //console.log("found in cache",cacheKey);
          response(self.cache[cacheKey]);
          return;
        }

        // abort the last xhr
        if (self.xhr ) {
          self.xhr.abort();
        }

        // get result from backend
        self.xhr = $.ajax({
          url: self.options.source, 
          data: request, 
          dataType: "json",
          success: function(data, status, xhr) {
            if (self.options.cache) {
              self.cache[cacheKey] = data;
            }
            if (xhr === self.xhr) {
              response(data);
            }
          },
          error: function() {
            response([]);
          }
        });
      };
    },

    _renderMenu: function(ul, items) {
        var self = this;

        $.each(items, function(key, section) {
          var header;

          if (section.docs.length) {

            header = $.tmpl(self.options.templates.header, {
              group: section.group,
              title: self.options.locales[section.group] || key
            }).data("ui-autocomplete-item", {value:''}).appendTo(ul);

            header.find(".ui-autosuggest-pager a").css('visibility', 'hidden');

            if (section.start + 5 < section.numFound) {
              header.find(".ui-autosuggest-next").css('visibility', 'visible').click(function() {
                console.log(section.group+" next clicked");
                return false;
              });
            }

            if (section.start > 0) {
              header.find(".ui-autosuggest-prev").css('visibility','visible').click(function() {
                console.log(section.group+" prev clicked");
                return false;
              });
            }

            $.each(section.docs, function(index, item) {
              item.group = section.group;
              self._renderItemData(ul, item);
            });
          }
        });
      },

      _renderItem: function(ul, item) {
        var self = this, $row,
            template = self.options.templates[item.group] || self.options.templates["default"];

        if (typeof(item.thumbnail) !== 'undefined') {
          if (!/^(\/|http:)/.test(item.thumbnail)) {
            item.thumbnail = self.options.thumbnailBase + '&topic=' + item.web + '.' + item.topic + '&file=' + item.thumbnail;
          }
        } else {
          item.thumbnail = 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==';
        }

        $row = $.tmpl(template, item); 

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
