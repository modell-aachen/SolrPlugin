;(function ($, document, window, undefined) {
  var initializing = true;

  var initScheduler = function() {
    $('.solr-schedule .scheduler-time').each(function() {
      var $self = $(this);
      var $toggle = $self.closest('tr').find('.scheduler-toggle');
      var picker = initTimePicker.call(this);

      if (!$toggle.is(':checked')) {
        $self.attr('disabled', 'disabled');
        picker.set('disable', true);
      }
    });

    initializing = false;
  };

  var initTimePicker = function() {
    var $picker = $(this);
    var name = $picker.attr('name');
    var format = $picker.data('format') || 'HH:i';
    var interval = $picker.data('interval');
    if (/^\d+$/.test(interval)) {
      interval = parseInt(interval);
    } else {
      interval = 60;
    }

    var opts = {
      clear: false,
      format: format,
      hiddenName: true,
      interval: interval,
      onSet: function(ctx) {
        if (initializing === false) {
          var web = this.$node.attr('name').replace('tm_', '');
          setCustomTime(web, ctx.select);
        }
      }
    };

    $picker.pickatime(opts);
    return $picker.pickatime('picker');
  };

  var onCustomScheduleToggled = function() {
    var $self = $(this);
    var $picker = $self.closest('tr').find('.scheduler-time');

    var web = $self.attr('name');
    var picker = $picker.pickatime('picker');
    if (!$self.is(':checked')) {
      picker.set('disable', true);
      $picker.attr('disabled', 'disabled');
      unsetCustomTime(web);
    } else {
      $picker.removeAttr('disabled');
      picker.set('disable', false);

      var minutes = $picker.attr('data-value');
      if (/^\d+/.test(minutes)) {
        minutes = parseInt(minutes);
        setCustomTime(web, minutes);
      }
    }
  };

  var unsetCustomTime = function(web) {
    sendAsync({action: 'unset', webname: web});
  };

  var setCustomTime = function(web, minutes) {
    if (!minutes) return;
    sendAsync({action: 'set', webname: web, minutes: minutes});
  };

  var sendAsync = function(payload) {
    var url = [
      foswiki.getPreference('SCRIPTURLPATH'),
      'rest' + foswiki.getPreference('SCRIPTSUFFIX'),
      'SolrPlugin',
      'updateSchedule'
    ];

    $.ajax({
      url: url.join('/'),
      method: 'POST',
      data: payload
    }).done(function(data, status, xhr) {
      console.log(status, data);
    }).fail(function(xhr, status, error) {
      logError(error);
    });
  };

  var logError = function(msg) {
    if (window.console && console.error) {
      console.error(msg);
    }
  };

  $(document).ready(function() {
    $('.solr-schedule').on('change', '.scheduler-toggle', onCustomScheduleToggled);
    initScheduler();
  });
}(jQuery, document, window, undefined));
