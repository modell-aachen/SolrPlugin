(function ($) {

  AjaxSolr.ResultWidget = AjaxSolr.AbstractJQueryWidget.extend({
    defaults: {
      blockUi: '#solrSearch',
      firstLoadingMessage:'Loading ...',
      loadingMessage: '',
      displayAs: '.solrDisplay',
      defaultDisplay: 'list',
      smallSize: 64,
      largeSize: 150,
      dateFormat: 'dddd, Do MMMM YYYY, LT'
    },

    beforeRequest: function () {
      var self = this,
          pubUrlPath = foswiki.getPreference('PUBURLPATH'),
          systemWeb = foswiki.getPreference('SYSTEMWEB');

      if (self._isFirst) {
        $.blockUI({message:'<h1>'+_(self.options.firstLoadingMessage)+'</h1>'});
      } else {
        $(self.options.blockUi).block({message:'<h1>'+_(self.options.loadingMessage)+'</h1>'});
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

      self.$target.html($("#solrHitTemplate").tmpl(
        response.response.docs, {
          debug:function(msg) {
            //console.log(msg||'',this);
            return "";
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

            return "#solrHitTemplate_misc";
          },
          renderList: function(fieldName, separator, limit) {
            var list = this.data[fieldName], result = '';

            separator = separator || ', ';
            limit = limit || 10;

            if (list && list.length) {
              lines = [];
              $.each(list.sort().slice(0, limit), function(i, v) {
                lines.push(_(v));
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
              result += _('Filed in')+" ";
              lines = [];
              $.each(cats.sort().slice(0, 10), function(i, v) {
                lines.push(_(v));
              });
              result += lines.join(", ");
              if (cats.length > 10) {
                result += " ...";
              }
            } 
            if (tags && tags.length) {
              if (cats && cats.length) {
                result += ", "+_("tagged")+" ";
              } else {
                result += _("Tagged")+" ";
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
              return self.getSnippet(this.data)
            }
            hilite = response.highlighting[id];
            if (typeof(hilite) === 'undefined' || typeof(hilite.text) === 'undefined') {
              return self.getSnippet(this.data);
            } else {
              hilite = hilite.text.join(' ... ').replace(/^[^\w]+/, '') 
              return hilite || self.getSnippet(this.data);
            }
          },
          formatDate: function(dateString, dateFormat) {
            var oldFormat, result;

            if (dateString == '' || dateString == '0' || dateString == '1970-01-01T00:00:00Z') {
              return "???";
            }

            if (typeof(dateFormat) === 'undefined') {
              return moment(dateString).calendar();
            } 

            // hack it in temporarily ... jaul
            oldFormat = moment.calendar.sameElse;
            moment.calendar.sameElse = moment.calendar.lastWeek = dateFormat;
            result = moment(dateString).calendar();
            moment.calendar.sameElse = moment.calendar.lastWeek = oldFormat;
            
            return result;
          }
        }
      ));

      self.fixImageSize();
      self.$target.trigger("update");
    },

    fixImageSize: function() {
      var self = this, 
          elem = $(self.options.displayAs).filter(":checked"),
          size = (elem.val() == 'list')?self.options.smallSize:self.options.largeSize;

      self.$target.find(".solrImageFrame img").each(function() {
        var $this = $(this), src = $this.attr("src");
        $this.attr("src", src.replace(/size=(\d+)/, "size="+size)).attr("width", size);
      });
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
      self.fixImageSize();
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

      // customize formatCalendar
      moment.calendar.sameElse = self.options.dateFormat;
      moment.calendar.lastWeek = self.options.dateFormat; // too funky for most users
      moment.longDateFormat.LT = 'HH:mm';
    }
  });


  AjaxSolr.Helpers.build("ResultWidget");

})(jQuery);
