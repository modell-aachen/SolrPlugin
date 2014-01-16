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
      thumbnailBase: null, /* set in _init */ 
      delay: 500,
      minLength: 3,
      extraParams: {
        limit: 3,
        fields: "name,web,topic,container_title,title,type,thumbnail,url,field_Telephone_s,field_Phone_s,field_Mobile_s"
      },
      position: {
        my: "right top",
        at: "right+5 bottom+11",
        collision: "none"
      },

      locales: {
        persons: 'Persons',
        topics: 'Topics',
        attachments: 'Attachments',
        loading: "Loading ..."
      },

      templates: {
        "persons": "<li class='ui-autosuggest-item ${group} ${isFirst}'>{{html header}}"+
            "{{if phoneNumber}}<a class='ui-autosuggest-phone-number' href='sip:${phoneNumber}'></a>{{/if}}"+
            "<a href='${url}' class='ui-autosuggest-link'>"+
              "<table class='foswikiNullTable'><tr>"+
                "<th><div><img class='thumbnail' width='48' alt='${name}' src='${thumbnail}' /></div></th>"+
                "<td>${title}<div class='foswikiGrayText'>${phoneNumber}</div></td>"+
              "</tr></table></a>"+
            "</li>",
        "default": "<li class='ui-autosuggest-item ${group} ${isFirst}'>{{html header}}<a href='${url}' class='ui-autosuggest-link'><table class='foswikiNullTable'><tr><th><div><img class='thumbnail' width='48' alt='${name}' src='${thumbnail}' /></div></th><td>${title}<div class='foswikiGrayText'>${container_title}</div></td></tr></table></a></li>",
        "header": "<div class='ui-autosuggest-title ${group}'>${title}</div>"
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
      source: null,
      menuClass: null

    },

    _init: function() {
      var elem = this.menu.element;

      this.options.thumbnailBase = foswiki.getPreference("SCRIPTURL") + "/rest/ImagePlugin/resize?size=48&crop=north";

      elem.addClass("ui-autosuggest").removeClass("ui-autocomplete");
      if (this.options.menuClass) {
        elem.addClass(this.options.menuClass);
      }
    },

    _initSource: function() {
      var self = this;

      self.cache = {};
      self.options.source = self.options.source || foswiki.getPreference("SCRIPTURL") + '/rest/SolrPlugin/autosuggest';

      self.source = function(request, response) {
        var term = request.term.replace(/(^\s+)|(\s+$)/g, ""),
            cacheKey = term;

        // play back term with stripped whitespace
        request.term = term;

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

        //console.log("request=",request);

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
          error: function(data) {
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
            header = $.tmpl("<div>"+self.options.templates.header+"</div>", {
              group: section.group,
              title: self.options.locales[section.group] || section.group
            });

            $.each(section.docs, function(index, item) {
              item.phoneNumber = item.field_Telephone_s || item.field_Phone_s || item.field_Mobile_s;
              item.group = section.group;
              if (index == 0) {
                item.isFirst = 'ui-autosuggest-first-in-group';
                item.header = header.html();
              } else {
                item.isFirst = '';
                item.header = "";
              }
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
      }
  });

})(jQuery);
