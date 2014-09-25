(function ($) {
"use strict";

  AjaxSolr.ResultWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      blockUi: '#solrSearch',
      firstLoadingMessage:'Loading ...',
      loadingMessage: '',
      displayAs: '.solrDisplay',
      defaultDisplay: 'list',
      dateFormat: 'dddd, Do MMMM YYYY, HH:mm',
      dictionary: 'default'
    },

    beforeRequest: function () {
      var self = this,
          pubUrlPath = foswiki.getPreference('PUBURLPATH'),
          systemWeb = foswiki.getPreference('SYSTEMWEB');

      if (self._isFirst) {
        $.blockUI({message:'<h1>'+_(self.options.firstLoadingMessage, self.options.dictionary)+'</h1>'});
      } else {
        $(self.options.blockUi).block({message:'<h1>'+_(self.options.loadingMessage, self.options.dictionary)+'</h1>'});
      }
    },

    getSnippet: function(data) {
      return data.text?data.text.substr(0, 300) + ' ...':'';
    },

    afterRequest: function () {
      var self = this,
          response = self.manager.response;

      //console.log("response=",response);
      if (self._isFirst) {
        self._isFirst = false;
        $.unblockUI();
      } else {
        $(self.options.blockUi).unblock();
      }

      if (!$("#solrSearch").is(":visible")) {
        $("#solrSearch").fadeIn();
      }

      self.$target.html($("#solrHitTemplate").render(
        response.response.docs, {
          debug:function(msg) {
            console.log(msg||'',this);
            return "";
          },
          encodeURIComponent: function(text) {
            return encodeURIComponent(text);
          },
          getTemplateName: function() {
            var type = this.data.type, 
                topicType = this.data.field_TopicType_lst || [],
                templateName;

            if (type == 'topic') {
              for (var i = 0, l = topicType.length; i < l; i++) {
                templateName = "#solrHitTemplate_"+topicType[i];
                if ($(templateName).length) {
                  return templateName;
                }
              }
              return "#solrHitTemplate_topic";
            } 

            if (type.match(/png|gif|jpe?g|tiff|bmp/)) {
              return "#solrHitTemplate_image";
            } 

            if (type.match(/comment/)) {
              return "#solrHitTemplate_comment";
            } 

            return "#solrHitTemplate_misc";
          },
          renderList: function(fieldName, separator, limit) {
            var list = this.data[fieldName], result = '', lines;

            separator = separator || ', ';
            limit = limit || 10;

            if (list && list.length) {
              lines = [];
              $.each(list.sort().slice(0, limit), function(i, v) {
                lines.push(_(v, self.options.dictionary));
              });
              result += lines.join(separator);
              if (list.length > limit) {
                result += " ...";
              }
            } 

            return result;
          },
          renderTopicInfo: function() {
            var cats = this.data.field_Category_flat_lst, 
                tags = this.data.tag,
                lines, result = '';

            if (cats && cats.length) {
              result += _('Filed in', self.options.dictionary)+" ";
              lines = [];
              $.each(cats.sort().slice(0, 10), function(i, v) {
                lines.push(_(v, self.options.dictionary));
              });
              result += lines.join(", ");
              if (cats.length > 10) {
                result += " ...";
              }
            } 
            if (tags && tags.length) {
              if (cats && cats.length) {
                result += ", "+_("tagged", self.options.dictionary)+" ";
              } else {
                result += _("Tagged", self.options.dictionary)+" ";
              }
              result += tags.sort().slice(0, 10).join(", ");
              if (tags.length > 10) {
                result += " ...";
              }
            }

            return result;
          },
          getHilite: function(id) {
            var hilite;
            if (typeof(response.highlighting) === 'undefined') {
              return '';//self.getSnippet(this.data)
            }
            hilite = response.highlighting[id];
            if (typeof(hilite) === 'undefined' || typeof(hilite.text) === 'undefined') {
              return '';//self.getSnippet(this.data);
            } else {
              hilite = hilite.text.join(' ... ');
              return hilite || '';//self.getSnippet(this.data);
            }
          },
          formatDate: function(dateString, dateFormat) {

            // convert epoch seconds to iso date string
            if (/^\d+$/.test(dateString)) {
              if (dateString.length == 10) {
                dateString += "000";
              }
              dateString = (new Date(parseInt(dateString))).toISOString();
            }

            if (typeof(dateString) === 'undefined' || dateString == '' || dateString == '0' || dateString == '1970-01-01T00:00:00Z') {
              return "???";
            }

            return moment(dateString).format(dateFormat || self.options.dateFormat);
            //return moment(dateString).calendar();
          }
        }
      ));

      self.$target.trigger("update");
    },

    update: function() {
      var self = this,
          elem = $(self.options.displayAs).filter(":checked");

      self.$target.removeClass("solrSearchHitsList solrSearchHitsGrid");
      if ((self.options.defaultDisplay == 'list' && !elem.length) || elem.val() == 'list') {
        self.$target.addClass("solrSearchHitsList");
      } else {
        self.$target.addClass("solrSearchHitsGrid");
      }
    },

    init: function() {
      var self = this;

      self._super();
      $(self.options.displayAs).change(function() {
        self.update();
      });
      $(self.options.displayAs).filter("[value='"+self.options.defaultDisplay+"']").attr("checked", "checked");
      self._isFirst = true;

      self.update();
    }
  });


  AjaxSolr.Helpers.build("ResultWidget");

})(jQuery);
