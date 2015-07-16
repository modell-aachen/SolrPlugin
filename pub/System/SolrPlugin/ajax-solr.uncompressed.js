// $Id$

/**
 * @namespace A unique namespace for the AJAX Solr library.
 */
AjaxSolr = function () {};

/**
 * @namespace Baseclass for all classes
 */
AjaxSolr.Class = function () {};

/**
 * A class 'extends' itself into a subclass.
 *
 * @static
 * @param properties The properties of the subclass.
 * @returns A function that represents the subclass.
 */
AjaxSolr.Class.extend = function (properties) {
  var klass = this; // Safari dislikes 'class'
  // The subclass is just a function that when called, instantiates itself.
  // Nothing is _actually_ shared between _instances_ of the same class.
  var subClass = function (options) {
    // 'this' refers to the subclass, which starts life as an empty object.
    // Add its parent's properties, its own properties, and any passed options.
    AjaxSolr.extend(this, new klass(options), properties, options);
  }
  // Allow the subclass to extend itself into further subclasses.
  subClass.extend = this.extend;
  return subClass;
};

/**
 * @static
 * @param {Object} obj Any object.
 * @returns {Number} the number of properties on an object.
 * @see http://stackoverflow.com/questions/5223/length-of-javascript-associative-array
 */
AjaxSolr.size = function (obj) {
  var size = 0;
  for (var key in obj) {
    if (obj.hasOwnProperty(key)) {
      size++;
    }
  }
  return size;
};

/**
 * @static
 * @param foo A value.
 * @param bar A value.
 * @returns {Boolean} Whether the two given values are equal.
 */
AjaxSolr.equals = function (foo, bar) {
  if (AjaxSolr.isArray(foo) && AjaxSolr.isArray(bar)) {
    if (foo.length !== bar.length) {
      return false;
    }
    for (var i = 0, l = foo.length; i < l; i++) {
      if (foo[i] !== bar[i]) {
        return false;
      }
    }
    return true;
  }
  else if (AjaxSolr.isRegExp(foo) && AjaxSolr.isString(bar)) {
    return bar.match(foo);
  }
  else if (AjaxSolr.isRegExp(bar) && AjaxSolr.isString(foo)) {
    return foo.match(bar);
  }
  else {
    return foo === bar;
  }
};

/**
 * @static
 * @param value A value.
 * @param array An array.
 * @returns {Boolean} Whether value exists in the array.
 */
AjaxSolr.inArray = function (value, array) {
  if (array) {
    for (var i = 0, l = array.length; i < l; i++) {
      if (AjaxSolr.equals(array[i], value)) {
        return i;
      }
    }
  }
  return -1;
};

/**
 * A copy of MooTools' Array.flatten function.
 *
 * @static
 * @see http://ajax.googleapis.com/ajax/libs/mootools/1.2.4/mootools.js
 */
AjaxSolr.flatten = function(array) {
  var ret = [];
  for (var i = 0, l = array.length; i < l; i++) {
    ret = ret.concat(AjaxSolr.isArray(array[i]) ? AjaxSolr.flatten(array[i]) : array[i]);
  }
  return ret;
};

/**
 * A copy of jQuery's jQuery.grep function.
 *
 * @static
 * @see http://ajax.googleapis.com/ajax/libs/jquery/1.3.2/jquery.js
 */
AjaxSolr.grep = function(array, callback) {
  var ret = [];
  for (var i = 0, l = array.length; i < l; i++) {
    if (!callback(array[i], i) === false) {
      ret.push(array[i]);
    }
  }
  return ret;
}

/**
 * Equivalent to Ruby's Array#compact.
 */
AjaxSolr.compact = function(array) {
  return AjaxSolr.grep(array, function (item) {
    return item.toString();
  });
}

/**
 * Can't use toString.call(obj) === "[object Array]", as it may return
 * "[xpconnect wrapped native prototype]", which is undesirable.
 *
 * @static
 * @see http://thinkweb2.com/projects/prototype/instanceof-considered-harmful-or-how-to-write-a-robust-isarray/
 * @see http://ajax.googleapis.com/ajax/libs/prototype/1.6.0.3/prototype.js
 */
AjaxSolr.isArray = function (obj) {
  return obj != null && typeof obj == 'object' && 'splice' in obj && 'join' in obj;
};

/**
 * @param obj Any object.
 * @returns {Boolean} Whether the object is a RegExp object.
 */
AjaxSolr.isRegExp = function (obj) {
  return obj != null && (typeof obj == 'object' || typeof obj == 'function') && 'ignoreCase' in obj;
};

/**
 * @param obj Any object.
 * @returns {Boolean} Whether the object is a String object.
 */
AjaxSolr.isString = function (obj) {
  return obj != null && typeof obj == 'string';
};

/**
 * Define theme functions to separate, as much as possible, your HTML from your
 * JavaScript. Theme functions provided by AJAX Solr are defined in the
 * AjaxSolr.theme.prototype namespace, e.g. AjaxSolr.theme.prototype.select_tag.
 *
 * To override a theme function provided by AJAX Solr, define a function of the
 * same name in the AjaxSolr.theme namespace, e.g. AjaxSolr.theme.select_tag.
 *
 * To retrieve the HTML output by AjaxSolr.theme.prototype.select_tag(...), call
 * AjaxSolr.theme('select_tag', ...).
 *
 * @param {String} func
 *   The name of the theme function to call.
 * @param ...
 *   Additional arguments to pass along to the theme function.
 * @returns
 *   Any data the theme function returns. This could be a plain HTML string,
 *   but also a complex object.
 *
 * @static
 * @throws Exception if the theme function is not defined.
 * @see http://cvs.drupal.org/viewvc.py/drupal/drupal/misc/drupal.js?revision=1.58
 */
AjaxSolr.theme = function (func) {
  if (AjaxSolr.theme[func] || AjaxSolr.theme.prototype[func] == undefined) {
    console.log('Theme function "' + func + '" is not defined.');
  }
  else {
    for (var i = 1, args = []; i < arguments.length; i++) {
      args.push(arguments[i]);
    }
    return (AjaxSolr.theme[func] || AjaxSolr.theme.prototype[func]).apply(this, args);
  }
};

/**
 * A simplified version of jQuery's extend function.
 *
 * @static
 * @see http://ajax.googleapis.com/ajax/libs/jquery/1.2.6/jquery.js
 */
AjaxSolr.extend = function () {
  var target = arguments[0] || {}, i = 1, length = arguments.length, options;
  for (; i < length; i++) {
    if ((options = arguments[i]) != null) {
      for (var name in options) {
        var src = target[name], copy = options[name];
        if (target === copy) {
          continue;
        }
        if (copy && typeof copy == 'object' && !copy.nodeType) {
          target[name] = AjaxSolr.extend(src || (copy.length != null ? [] : {}), copy);
        }
        else if (copy && src && typeof copy == 'function' && typeof src == 'function') {
          target[name] = (function(superfn, fn) {
            return function () {
              var tmp = this._super, ret;
              this._super = superfn;
              ret = fn.apply(this, arguments);
              this._super = tmp;
              return ret;
            };
          })(src, copy);
        }
        else if (copy !== undefined) {
          target[name] = copy;
        }
      }
    }
  }
  return target;
};

AjaxSolr.parseStringList = function(sl) {
  var regex = /("[^"]*"|[^ ]*)?(.*)/;
  var vals = [];
  var ar;
  do {
    ar = regex.exec(sl.trim());
    vals.push(ar[1]);
    sl = ar[2];
  } while(sl.trim());
  return vals;
};
// $Id$

/**
 * Represents a Solr parameter.
 *
 * @param properties A map of fields to set. Refer to the list of public fields.
 * @class Parameter
 */
AjaxSolr.Parameter = AjaxSolr.Class.extend(
  /** @lends AjaxSolr.Parameter.prototype */
  {
  /**
   * The parameter's name.
   *
   * @field
   * @private
   * @type String
   */
  name: null,

  /**
   * The parameter's value.
   *
   * @field
   * @private
   * @type String
   */
  value: null,

  /**
   * The parameter's local parameters.
   *
   * @field
   * @private
   * @type Object
   * @default {}
   */
  locals: {},

  /**
   * Returns the value. If called with an argument, sets the value.
   *
   * @param {String|Number|String[]|Number[]} [value] The value to set.
   * @returns The value.
   */
  val: function (value) {
    if (value === undefined) {
      return this.value;
    }
    else {
      this.value = value;
    }
  },

  /**
   * Returns the value of a local parameter. If called with a second argument,
   * sets the value of a local parameter.
   *
   * @param {String} name The name of the local parameter.
   * @param {String|Number|String[]|Number[]} [value] The value to set.
   * @returns The value.
   */
  local: function (name, value) {
    if (value === undefined) {
      return this.locals[name];
    }
    else {
      this.locals[name] = value;
    }
  },

  /**
   * Deletes a local parameter.
   *
   * @param {String} name The name of the local parameter.
   */
  remove: function (name) {
    delete this.locals[name];
  },

  /**
   * Returns the Solr parameter as a query string key-value pair.
   *
   * <p>IE6 calls the default toString() if you write <tt>store.toString()
   * </tt>. So, we need to choose another name for toString().</p>
   */
  string: function () {
    var pairs = [];

    for (var name in this.locals) {
      if (this.locals[name]) {
        pairs.push(name + '=' + encodeURIComponent(this.locals[name]));
      }
    }

    var prefix = pairs.length ? '{!' + pairs.join('%20') + '}' : '';

    if (this.value) {
      return this.name + '=' + prefix + this.valueString(this.value);
    }
    // For dismax request handlers, if the q parameter has local params, the
    // q parameter must be set to a non-empty value. In case the q parameter
    // has local params but is empty, use the q.alt parameter, which accepts
    // wildcards.
    else if (this.name == 'q' && prefix) {
      return 'q.alt=' + prefix + encodeURIComponent('*:*');
    }
    else {
      return '';
    }
  },

  /**
   * Parses a string formed by calling string().
   *
   * @param {String} str The string to parse.
   */
  parseString: function (str) {
    var param = str.match(/^([^=]+)=(?:\{!([^\}]*)\})?(.*)$/);
    if (param) {
      var matches;

      while (matches = /([^\s=]+)=(\S*)/g.exec(decodeURIComponent(param[2]))) {
        this.locals[matches[1]] = decodeURIComponent(matches[2]);
        param[2] = param[2].replace(matches[0], ''); // Safari's exec seems not to do this on its own
      }

      if (param[1] == 'q.alt') {
        this.name = 'q';
        // if q.alt is present, assume it is because q was empty, as above
      }
      else {
        this.name = param[1];
        this.value = this.parseValueString(param[3]);
      }
    }
  },

  /**
   * Returns the value as a URL-encoded string.
   *
   * @private
   * @param {String|Number|String[]|Number[]} value The value.
   * @returns {String} The URL-encoded string.
   */
  valueString: function (value) {
    value = AjaxSolr.isArray(value) ? value.join(',') : value;
    return encodeURIComponent(value);
  },

  /**
   * Parses a URL-encoded string to return the value.
   *
   * @private
   * @param {String} str The URL-encoded string.
   * @returns {Array} The value.
   */
  parseValueString: function (str) {
    str = decodeURIComponent(str);
    return str.indexOf(',') == -1 ? str : str.split(',');
  }
});

/**
 * Escapes a value, to be used in, for example, an fq parameter. Surrounds
 * strings containing spaces or colons in double quotes.
 *
 * @public
 * @param {String|Number} value The value.
 * @returns {String} The escaped value.
 */
AjaxSolr.Parameter.escapeValue = function (value) {
  // If the field value has a space or a colon in it, wrap it in quotes,
  // unless it is a range query or it is already wrapped in quotes.
  if (value.match(/[ :]/) && !value.match(/[\[\{]\S+ TO \S+[\]\}]/) && !value.match(/^["\(].*["\)]$/)) {
    return '"' + value + '"';
  }
  return value;
}
// $Id$

/**
 * The ParameterStore, as its name suggests, stores Solr parameters. Widgets
 * expose some of these parameters to the user. Whenever the user changes the
 * values of these parameters, the state of the application changes. In order to
 * allow the user to move back and forth between these states with the browser's
 * Back and Forward buttons, and to bookmark these states, each state needs to
 * be stored. The easiest method is to store the exposed parameters in the URL
 * hash (see the <tt>ParameterHashStore</tt> class). However, you may implement
 * your own storage method by extending this class.
 *
 * <p>For a list of possible parameters, please consult the links below.</p>
 *
 * @see http://wiki.apache.org/solr/CoreQueryParameters
 * @see http://wiki.apache.org/solr/CommonQueryParameters
 * @see http://wiki.apache.org/solr/SimpleFacetParameters
 * @see http://wiki.apache.org/solr/HighlightingParameters
 * @see http://wiki.apache.org/solr/MoreLikeThis
 * @see http://wiki.apache.org/solr/SpellCheckComponent
 * @see http://wiki.apache.org/solr/StatsComponent
 * @see http://wiki.apache.org/solr/TermsComponent
 * @see http://wiki.apache.org/solr/TermVectorComponent
 * @see http://wiki.apache.org/solr/LocalParams
 *
 * @param properties A map of fields to set. Refer to the list of public fields.
 * @class ParameterStore
 */
AjaxSolr.ParameterStore = AjaxSolr.Class.extend(
  /** @lends AjaxSolr.ParameterStore.prototype */
  {
  /**
   * The names of the exposed parameters. Any parameters that your widgets
   * expose to the user, directly or indirectly, should be listed here.
   *
   * @field
   * @public
   * @type String[]
   * @default []
   */
  exposed: [],

  /**
   * The parameters to be hidden. This list consists of those parameter values
   * that should not be exposed even though their field is exposed.
   *
   * @field
   * @public
   * @type String[]
   * @default []
   */
  hidden: [],

  /**
   * The Solr parameters.
   *
   * @field
   * @private
   * @type Object
   * @default {}
   */
  params: {},

  /**
   * A reference to the parameter store's manager. For internal use only.
   *
   * @field
   * @private
   * @type AjaxSolr.AbstractManager
   */
  manager: null,

  /**
   * An abstract hook for child implementations.
   *
   * <p>This method should do any necessary one-time initializations.</p>
   */
  init: function () {},

  /**
   * Some Solr parameters may be specified multiple times. It is easiest to
   * hard-code a list of such parameters. You may change the list by passing
   * <code>{ multiple: /pattern/ }</code> as an argument to the constructor of
   * this class or one of its children, e.g.:
   *
   * <p><code>new ParameterStore({ multiple: /pattern/ })</code>
   *
   * @param {String} name The name of the parameter.
   * @returns {Boolean} Whether the parameter may be specified multiple times.
   * @see http://lucene.apache.org/solr/api/org/apache/solr/handler/DisMaxRequestHandler.html
   */
  isMultiple: function (name) {
    return name.match(/^(?:bf|bq|facet\.date|facet\.date\.other|facet\.date\.include|facet\.field|facet\.pivot|facet\.range|facet\.range\.other|facet\.range\.include|facet\.query|fq|group\.field|group\.func|group\.query|pf|qf)$/);
  },

  /**
   * Tests if the parameter is listed in @hidden.
   *
   * @param {AjaxSolr.Parameter|String} The parameter.
   * @returns boolean
   */
  isHidden: function(param) {
    if (typeof(param) === 'object') {
      param = decodeURIComponent(param.string());
    }
    for (var i = 0, l = this.hidden.length; i < l; i++) {
      if (this.hidden[i] == param) {
        return true;
      }
    }
    return false;
  },

  /**
   * Returns a parameter. If the parameter doesn't exist, creates it.
   *
   * @param {String} name The name of the parameter.
   * @returns {AjaxSolr.Parameter|AjaxSolr.Parameter[]} The parameter.
   */
  get: function (name) {
    if (this.params[name] === undefined) {
      var param = new AjaxSolr.Parameter({ name: name });
      if (this.isMultiple(name)) {
        this.params[name] = [ param ];
      }
      else {
        this.params[name] = param;
      }
    }
    return this.params[name];
  },

  /**
   * If the parameter may be specified multiple times, returns the values of
   * all identically-named parameters. If the parameter may be specified only
   * once, returns the value of that parameter.
   *
   * @param {String} name The name of the parameter.
   * @returns {String[]|Number[]} The value(s) of the parameter.
   */
  values: function (name) {
    if (this.params[name] !== undefined) {
      if (this.isMultiple(name)) {
        var values = [];
        for (var i = 0, l = this.params[name].length; i < l; i++) {
          values.push(this.params[name][i].val());
        }
        return values;
      }
      else {
        return [ this.params[name].val() ];
      }
    }
    return [];
  },

  /**
   * If the parameter may be specified multiple times, adds the given parameter
   * to the list of identically-named parameters, unless one already exists with
   * the same value. If it may be specified only once, replaces the parameter.
   *
   * @param {String} name The name of the parameter.
   * @param {AjaxSolr.Parameter} [param] The parameter.
   * @returns {AjaxSolr.Parameter|Boolean} The parameter, or false.
   */
  add: function (name, param) {
    if (param === undefined) {
      param = new AjaxSolr.Parameter({ name: name });
    }
    if (this.isMultiple(name)) {
      if (this.params[name] === undefined) {
        this.params[name] = [ param ];
      }
      else {
        if (AjaxSolr.inArray(param.val(), this.values(name)) == -1) {
          this.params[name].push(param);
        }
        else {
          return false;
        }
      }
    }
    else {
      this.params[name] = param;
    }
    return param;
  },

  /**
   * Deletes a parameter.
   *
   * @param {String} name The name of the parameter.
   * @param {Number} [index] The index of the parameter.
   */
  remove: function (name, index) {
    if (index === undefined) {
      delete this.params[name];
    }
    else {
      this.params[name].splice(index, 1);
      if (this.params[name].length == 0) {
        delete this.params[name];
      }
    }
  },

  /**
   * Finds all parameters with matching values.
   *
   * @param {String} name The name of the parameter.
   * @param {String|Number|String[]|Number[]|RegExp} value The value.
   * @returns {String|Number[]} The indices of the parameters found.
   */
  find: function (name, value) {
    if (this.params[name] !== undefined) {
      if (this.isMultiple(name)) {
        var indices = [];
        for (var i = 0, l = this.params[name].length; i < l; i++) {
          if (AjaxSolr.equals(this.params[name][i].val(), value)) {
            indices.push(i);
          }
        }
        return indices.length ? indices : false;
      }
      else {
        if (AjaxSolr.equals(this.params[name].val(), value)) {
          return name;
        }
      }
    }
    return false;
  },

  /**
   * If the parameter may be specified multiple times, creates a parameter using
   * the given name and value, and adds it to the list of identically-named
   * parameters, unless one already exists with the same value. If it may be
   * specified only once, replaces the parameter.
   *
   * @param {String} name The name of the parameter.
   * @param {String|Number|String[]|Number[]} value The value.
   * @param {Object} [locals] The parameter's local parameters.
   * @returns {AjaxSolr.Parameter|Boolean} The parameter, or false.
   */
  addByValue: function (name, value, locals) {
    if (locals === undefined) {
      locals = {};
    }
    if (this.isMultiple(name) && AjaxSolr.isArray(value)) {
      var ret = [];
      for (var i = 0, l = value.length; i < l; i++) {
        ret.push(this.add(name, new AjaxSolr.Parameter({ name: name, value: value[i], locals: locals })));
      }
      return ret;
    }
    else {
      return this.add(name, new AjaxSolr.Parameter({ name: name, value: value, locals: locals }));
    }
  },

  /**
   * Deletes any parameter with a matching value.
   *
   * @param {String} name The name of the parameter.
   * @param {String|Number|String[]|Number[]|RegExp} value The value.
   * @returns {String|Number[]} The indices deleted.
   */
  removeByValue: function (name, value) {
    var indices = this.find(name, value);
    if (indices) {
      if (AjaxSolr.isArray(indices)) {
        for (var i = indices.length - 1; i >= 0; i--) {
          this.remove(name, indices[i]);
        }
      }
      else {
        this.remove(indices);
      }
    }
    return indices;
  },

  /**
   * Returns the Solr parameters as a query string.
   *
   * <p>IE6 calls the default toString() if you write <tt>store.toString()
   * </tt>. So, we need to choose another name for toString().</p>
   */
  string: function () {
    var params = [];
    for (var name in this.params) {
      if (this.isMultiple(name)) {
        for (var i = 0, l = this.params[name].length; i < l; i++) {
          params.push(this.params[name][i].string());
        }
      }
      else {
        params.push(this.params[name].string());
      }
    }
    return AjaxSolr.compact(params).join('&');
  },

  /**
   * Parses a query string into Solr parameters.
   *
   * @param {String} str The string to parse.
   */
  parseString: function (str) {
    var pairs = str.split('&');
    for (var i = 0, l = pairs.length; i < l; i++) {
      if (pairs[i]) { // ignore leading, trailing, and consecutive &'s
        var param = new AjaxSolr.Parameter();
        param.parseString(pairs[i]);
        if (param.name) {
          this.add(param.name, param);
        }
      }
    }
  },

  /**
   * Returns the exposed parameters as a query string.
   *
   * @returns {String} A string representation of the exposed parameters.
   */
  exposedString: function () {
    var params = [];
    for (var i = 0, l = this.exposed.length; i < l; i++) {
      if (this.params[this.exposed[i]] !== undefined) {
        if (this.isMultiple(this.exposed[i])) {
          for (var j = 0, m = this.params[this.exposed[i]].length; j < m; j++) {
            if (!this.isHidden(this.params[this.exposed[i]][j])) {
              params.push(this.params[this.exposed[i]][j].string());
            }
          }
        }
        else {
          if (!this.isHidden(this.params[this.exposed[i]])) {
            params.push(this.params[this.exposed[i]].string());
          }
        }
      }
    }
    return AjaxSolr.compact(params).join('&');
  },

  /**
   * Resets the values of the exposed parameters.
   */
  exposedReset: function () {
    var param;
    for (var i = 0, l = this.exposed.length; i < l; i++) {
      this.remove(this.exposed[i]);
    }
    for (var i = 0, l = this.hidden.length; i < l; i++) {
      param = new AjaxSolr.Parameter();
      param.parseString(this.hidden[i]);
      this.add(param.name, param);
    }
  },

  /**
   * Loads the values of exposed parameters from persistent storage. It is
   * necessary, in most cases, to reset the values of exposed parameters before
   * setting the parameters to the values in storage. This is to ensure that a
   * parameter whose name is not present in storage is properly reset.
   *
   * @param {Boolean} [reset=true] Whether to reset the exposed parameters.
   *   before loading new values from persistent storage. Default: true.
   */
  load: function (reset) {
    if (reset === undefined) {
      reset = true;
    }
    if (reset) {
      this.exposedReset();
    }
    this.parseString(this.storedString());
  },

  /**
   * An abstract hook for child implementations.
   *
   * <p>Stores the values of the exposed parameters in persistent storage. This
   * method should usually be called before each Solr request.</p>
   */
  save: function () {},

  /**
   * An abstract hook for child implementations.
   *
   * <p>Returns the string to parse from persistent storage.</p>
   *
   * @returns {String} The string from persistent storage.
   */
  storedString: function () {
    return '';
  }
});
// $Id$

/**
 * A parameter store that stores the values of exposed parameters in the URL
 * hash to maintain the application's state.
 *
 * <p>The ParameterHashStore observes the hash for changes and loads Solr
 * parameters from the hash if it observes a change or if the hash is empty.</p>
 *
 * @class ParameterHashStore
 * @augments AjaxSolr.ParameterStore
 */
AjaxSolr.ParameterHashStore = AjaxSolr.ParameterStore.extend(
  /** @lends AjaxSolr.ParameterHashStore.prototype */
  {
  /**
   * The interval in milliseconds to use in <tt>setInterval()</tt>. Do not set
   * the interval too low as you may set up a race condition.
   *
   * @field
   * @public
   * @type Number
   * @default 250
   * @see ParameterHashStore#init()
   */
  interval: 250,

  /**
   * Reference to the setInterval() function.
   *
   * @field
   * @private
   * @type Function
   */
  intervalId: null,

  /**
   * A local copy of the URL hash, so we can detect changes to it.
   *
   * @field
   * @private
   * @type String
   * @default ""
   */
  hash: '',

  /**
   * If loading and saving the hash take longer than <tt>interval</tt>, we'll
   * hit a race condition. However, this should never happen.
   */
  init: function () {
    if (this.exposed.length) {
      this.intervalId = window.setInterval(this.intervalFunction(this), this.interval);
    }
  },

  /**
   * Stores the values of the exposed parameters in both the local hash and the
   * URL hash. No other code should be made to change these two values.
   */
  save: function () {
    this.hash = this.exposedString();
    if (this.storedString()) {
      // make a new history entry
      window.location.hash = this.hash;
    }
    else {
      // replace the old history entry
      window.location.replace(window.location.href.replace('#', '') + '#' + this.hash);
    }
  },

  /**
   * @see ParameterStore#storedString()
   */
  storedString: function () {
    // Some browsers automatically unescape characters in the hash, others
    // don't. Fortunately, all leave window.location.href alone. So, use that.
    var index = window.location.href.indexOf('#');
    if (index == -1) {
      return '';
    }
    else {
      return window.location.href.substr(index + 1);
    }
  },

  /**
   * Checks the hash for changes, and loads Solr parameters from the hash and
   * sends a request to Solr if it observes a change or if the hash is empty
   */
  intervalFunction: function (self) {
    return function () {
      // Support the back/forward buttons. If the hash changes, do a request.
      var hash = self.storedString();
      if (self.hash != hash && decodeURIComponent(self.hash) != decodeURIComponent(hash)) {
        self.load();
        self.manager.doRequest();
      }
    }
  }
});
// $Id$

/**
 * The Manager acts as the controller in a Model-View-Controller framework. All
 * public calls should be performed on the manager object.
 *
 * @param properties A map of fields to set. Refer to the list of public fields.
 * @class AbstractManager
 */
AjaxSolr.AbstractManager = AjaxSolr.Class.extend(
  /** @lends AjaxSolr.AbstractManager.prototype */
  {
  /**
   * The fully-qualified URL of the Solr application. You must include the
   * trailing slash. Do not include the path to any Solr servlet.
   *
   * @field
   * @public
   * @type String
   * @default "http://localhost:8983/solr/"
   */
  solrUrl: 'http://localhost:8983/solr/',

  /**
   * If we want to proxy queries through a script, rather than send queries
   * to Solr directly, set this field to the fully-qualified URL of the script.
   *
   * @field
   * @public
   * @type String
   */
  proxyUrl: null,

  /**
   * The default Solr servlet. You may prepend the servlet with a core if using
   * multiple cores.
   *
   * @field
   * @public
   * @type String
   * @default "select"
   */
  servlet: 'select',

  /**
   * The most recent response from Solr.
   *
   * @field
   * @private
   * @type Object
   * @default {}
   */
  response: {},

  /**
   * A collection of all registered widgets. For internal use only.
   *
   * @field
   * @private
   * @type Object
   * @default {}
   */
  widgets: {},

  /**
   * The parameter store for the manager and its widgets. For internal use only.
   *
   * @field
   * @private
   * @type Object
   */
  store: null,

  /**
   * Whether <tt>init()</tt> has been called yet. For internal use only.
   *
   * @field
   * @private
   * @type Boolean
   * @default false
   */
  initialized: false,

  /**
   * An abstract hook for child implementations.
   *
   * <p>This method should be called after the store and the widgets have been
   * added. It should initialize the widgets and the store, and do any other
   * one-time initializations, e.g., perform the first request to Solr.</p>
   *
   * <p>If no store has been set, it sets the store to the basic <tt>
   * AjaxSolr.ParameterStore</tt>.</p>
   */
  init: function () {
    this.initialized = true;
    if (this.store === null) {
      this.setStore(new AjaxSolr.ParameterStore());
    }
    this.store.load(false);
    for (var widgetId in this.widgets) {
      this.widgets[widgetId].init();
    }
    this.store.init();
  },

  /**
   * Set the manager's parameter store.
   *
   * @param {AjaxSolr.ParameterStore} store
   */
  setStore: function (store) {
    store.manager = this;
    this.store = store;
  },

  /**
   * Adds a widget to the manager.
   *
   * @param {AjaxSolr.AbstractWidget} widget
   */
  addWidget: function (widget) {
    widget.manager = this;
    this.widgets[widget.id] = widget;
  },

  /**
   * Stores the Solr parameters to be sent to Solr and sends a request to Solr.
   *
   * @param {Boolean} [start] The Solr start offset parameter.
   * @param {String} [servlet] The Solr servlet to send the request to.
   */
  doRequest: function (start, servlet) {
    if (this.initialized === false) {
      this.init();
    }
    // Allow non-pagination widgets to reset the offset parameter.
    if (start !== undefined) {
      this.store.get('start').val(start);
    }
    if (servlet === undefined) {
      servlet = this.servlet;
    }

    this.store.save();

    for (var widgetId in this.widgets) {
      this.widgets[widgetId].beforeRequest();
    }

    this.executeRequest(servlet);
  },

  /**
   * An abstract hook for child implementations.
   *
   * <p>Sends the request to Solr, i.e. to <code>this.solrUrl</code> or <code>
   * this.proxyUrl</code>, and receives Solr's response. It should send <code>
   * this.store.string()</code> as the Solr query, and it should pass Solr's
   * response to <code>handleResponse()</code> for handling.</p>
   *
   * <p>See <tt>managers/Manager.jquery.js</tt> for a jQuery implementation.</p>
   *
   * @param {String} servlet The Solr servlet to send the request to.
   * @throws If not defined in child implementation.
   */
  executeRequest: function (servlet) {
    throw 'Abstract method executeRequest must be overridden in a subclass.';
  },

  /**
   * This method is executed after the Solr response data arrives. Allows each
   * widget to handle Solr's response separately.
   *
   * @param {Object} data The Solr response.
   */
  handleResponse: function (data) {
    this.response = data;

    for (var widgetId in this.widgets) {
      this.widgets[widgetId].afterRequest();
    }
  }
});
// $Id$

/**
 * Baseclass for all widgets.
 *
 * Provides abstract hooks for child classes.
 *
 * @param properties A map of fields to set. May be new or public fields.
 * @class AbstractWidget
 */
AjaxSolr.AbstractWidget = AjaxSolr.Class.extend(
  /** @lends AjaxSolr.AbstractWidget.prototype */
  {
  /**
   * A unique identifier of this widget.
   *
   * @field
   * @public
   * @type String
   */
  id: null,

  /**
   * The CSS selector for this widget's target HTML element, e.g. a specific
   * <tt>div</tt> or <tt>ul</tt>. A Widget is usually implemented to perform
   * all its UI changes relative to its target HTML element.
   *
   * @field
   * @public
   * @type String
   */
  target: null,

  /**
   * A reference to the widget's manager. For internal use only.
   *
   * @field
   * @private
   * @type AjaxSolr.AbstractManager
   */
  manager: null,

  /**
   * The offset parameter. Set this field to make the widget reset the offset
   * parameter to the given value on each request.
   *
   * @field
   * @public
   * @type Number
   */
  start: undefined,

  /**
   * The Solr servlet for this widget. You may prepend the servlet with a core
   * if using multiple cores. If none is set, it will default to the manager's
   * servlet.
   *
   * @field
   * @public
   * @type String
   */
  servlet: undefined,

  /**
   * An abstract hook for child implementations.
   *
   * <p>This method should do any necessary one-time initializations.</p>
   */
  init: function () {},

  /**
   * An abstract hook for child implementations.
   *
   * <p>This method is executed before the Solr request is sent.</p>
   */
  beforeRequest: function () {},

  /**
   * An abstract hook for child implementations.
   *
   * <p>This method is executed after the Solr response is received.</p>
   */
  afterRequest: function () {},

  /**
   * A proxy to the manager's doRequest method.
   *
   * @param {Boolean} [start] The Solr start offset parameter.
   * @param {String} [servlet] The Solr servlet to send the request to.
   */
  doRequest: function (start, servlet) {
    this.manager.doRequest(start || this.start, servlet || this.servlet);
  }
});
// $Id$

/**
 * Baseclass for all facet widgets.
 *
 * @class AbstractFacetWidget
 * @augments AjaxSolr.AbstractWidget
 */
AjaxSolr.AbstractFacetWidget = AjaxSolr.AbstractWidget.extend(
  /** @lends AjaxSolr.AbstractFacetWidget.prototype */
  {
  /**
   *    * This widget will by default set the offset parameter to 0 on each request.
   *       */
  start: 0,

  /**
   * The field to facet on.
   *
   * @field
   * @public
   * @type String
   */
  field: null,

  /**
   * Set to <tt>false</tt> to force a single "fq" parameter for this widget.
   *
   * @field
   * @public
   * @type Boolean
   * @default true
   */
  multivalue: true,

  /**
   * Set to <tt>true</tt> to have a facet query that returns a union (or).
   */
  union : false,

  /**
   * Set a tag for the fq parameter like fq={!tag=mytag}field.
   */
  tag : null,

  /**
   * Set to change the key i.e. facet.query={!key=today ex=dateFacet}dates:[NOW/DAY TO *]
   */
  key : null,

  /**
   * Set a local exclude for the facet.field i.e.
   * facet.field={!ex=mytag}field
   */
  ex : null,

  /**
   * Set to one of <tt>facet_fields</tt>, <tt>facet_dates</tt>, <tt>facet_queries</tt>, <tt>facet_ranges</tt>
   *
   * @field
   * @public
   * @type String
   * @default null
   */
  facetType: null,

  /** A list of queries to be used in facet queries
   *
   * @field
   * @public
   * @type Array
   * @default []
   */
  queries: [],

  init: function () {
    this.initStore();
  },

  /**
   * Add facet parameters to the parameter store.
   */
  initStore: function () {
    var param;

    /* http://wiki.apache.org/solr/SimpleFacetParameters */
    var parameters = [
      'facet.prefix',
      'facet.sort',
      'facet.limit',
      'facet.offset',
      'facet.mincount',
      'facet.missing',
      'facet.method',
      'facet.enum.cache.minDf'
    ];

    this.manager.store.addByValue('facet', true);

    // Set facet.field, facet.date or facet.range to truthy values to add
    // related per-field parameters to the parameter store.
    switch (this.getFacetType()) {
      case 'facet_fields':
        param = this.manager.store.addByValue('facet.field', this.field);
        break;
      case 'facet_dates':
        param = this.manager.store.addByValue('facet.date', this.field);
        parameters = parameters.concat([
          'facet.date.start',
          'facet.date.end',
          'facet.date.gap',
          'facet.date.hardend',
          'facet.date.other',
          'facet.date.include'
        ]);
        break;
      case 'facet_queries':
        if (this.queries == undefined) {
          throw "no queries for field "+this.field;
        }
        for(var i = 0, l = this.queries.length; i < l; i++) {
          param = this.manager.store.addByValue('facet.query', this.queries[i].value);
          if (this.queries[i].key) {
            param.local("key", "'"+this.queries[i].key.replace(/\\/g, "\\\\").replace(/'/g, "\\'")+"'");
            if (this.ex) {
              param.local("ex", this.ex);
            }
          }
        }
        param = null;
        break;
      case 'facet_ranges':
        param = this.manager.store.addByValue('facet.range', this.field);
        parameters = parameters.concat([
          'facet.range.start',
          'facet.range.end',
          'facet.range.gap',
          'facet.range.hardend',
          'facet.range.other',
          'facet.range.include'
        ]);
        break;
    }

    if (param) {
      if (this.key) {
        param.local("key", this.key);
      }
      if (this.ex) {
        param.local("ex", this.ex);
      }
    }

    for (var i = 0, l = parameters.length; i < l; i++) {
      if (this[parameters[i]] !== undefined) {
        this.manager.store.addByValue('f.' + this.field + '.' + parameters[i], this[parameters[i]]);
      }
    }
  },

  /**
   * @returns {Boolean} Whether any filter queries have been set using this
   *   widget's facet field.
   */
  isEmpty: function () {
    return !this.manager.store.find('fq', new RegExp('^-?' + this.field + ':'));
  },

  /**
   * Sets the filter query.
   *
   * @returns {Boolean} Whether the selection changed.
   */
  set: function (value) {
    return this.changeSelection(function () {
      var a = this.manager.store.removeByValue('fq', new RegExp('^-?' + this.field + ':')),
          b = this.manager.store.addByValue('fq', this.fq(value));
      if (b && this.tag) {
        b.local("tag", this.tag);
      }
      return a || b;
    });
  },

  /**
   * Adds a filter query.
   *
   * @returns {Boolean} Whether a filter query was added.
   */
  add: function (value) {
    return this.changeSelection(function () {
      var param = this.manager.store.addByValue('fq', this.fq(value));
      if (param && this.tag) {
        param.local("tag", this.tag);
      }
      return param;
    });
  },

  /**
   * Append to the filter query.
   *
   * @returns {Boolean} Whether the selection changed.
   */
  append: function(value) {
    return this.changeSelection(function() {
      var params, param, vals;
      value = AjaxSolr.Parameter.escapeValue(value);
      params = this.getParams();
      if (params) {
        vals = this.getQueryValues(params);
        param = params[0];
        if (AjaxSolr.inArray(value, vals) < 0) {
          vals.push(value);
          param.val(this.fq('(' + vals.join(" ") + ')'));
          return true;
        }
      } else {
        param = this.manager.store.addByValue('fq', this.fq('(' + value + ')'));
        if (param && this.tag) {
          param.local("tag", this.tag);
          param.local("q.op", "OR");
        }
        return true;
      }

      return false;
    });
  },


  /**
   * Removes a filter query.
   *
   * @returns {Boolean} Whether a filter query was removed.
   */
  remove: function (value) {
    return this.changeSelection(function () {
      if (this.multivalue && this.union) {
        var params, param, vals;
        value = AjaxSolr.Parameter.escapeValue(value);
        params = this.getParams();
        if (params) {
          vals = this.getQueryValues(params).filter(function(elmt, idx) {
            return elmt != value;
          });
          if (vals.length > 0) {
            params[0].val(this.fq('(' + vals.join(" ") + ')'));
            return true;
          } else {
            return this.manager.store.removeByValue('fq', this.fq('(' + value + ')'));
          }
        }
      }

      return this.manager.store.removeByValue('fq', this.fq(value));
    });
  },

  /**
   * Removes all filter queries using the widget's facet field.
   *
   * @returns {Boolean} Whether a filter query was removed.
   */
  clear: function () {
    return this.changeSelection(function () {
      return this.manager.store.removeByValue('fq', new RegExp('^-?' + this.field + ':'));
    });
  },

  /**
   * Helper for selection functions.
   *
   * @param {Function} Selection function to call.
   * @returns {Boolean} Whether the selection changed.
   */
  changeSelection: function (func) {
    changed = func.apply(this);
    if (changed) {
      this.afterChangeSelection();
    }
    return changed;
  },

  /**
   * An abstract hook for child implementations.
   *
   * <p>This method is executed after the filter queries change.</p>
   */
  afterChangeSelection: function () {},

  /**
   * @returns {String} the facet type used by this facet. This is the
   * key used by solr to store the facet counts.
   */
  getFacetType: function () {
    if (this.facetType !== undefined) {
      return this.facetType;
    }
    for (var name in this.manager.response.facet_counts) {
      if (this.manager.response.facet_counts[name][this.field] !== undefined) {
        this.facetType = name;
        return name;
      }
    }
    return;
  },

  /**
   * @returns {Array} An array of objects with the properties <tt>facet</tt> and
   * <tt>count</tt>, e.g <tt>{ facet: 'facet', count: 1 }</tt>.
   */

  getFacetCounts: function () {
    var facetType = this.getFacetType();

    switch (facetType) {
      case 'facet_fields':
        return this.getFacetCountsFlat(facetType);
      case 'facet_dates':
        return this.getFacetCountsArrarr(facetType);
      case 'facet_queries':
        return this.getFacetCountsMap(facetType);
      case 'facet_ranges':
        return this.getFacetCountsRange(facetType);
      default:
        return this.getFacetCountsFlat(facetType);
    }
  },

  /**
   * Used if the facet counts are represented as a JSON object.
   *
   * @param {String} type "facet_fields", "facet_dates", "facet_queries" or "facet_ranges".
   * @returns {Array} An array of objects with the properties <tt>facet</tt> and
   * <tt>count</tt>, e.g <tt>{ facet: 'facet', count: 1 }</tt>.
   */
  getFacetCountsMap: function (type) {
    var counts = [],
        facet_counts = (type != 'facet_queries' && this.field)?this.manager.response.facet_counts[type][this.field]:this.manager.response.facet_counts[type];

    for (var facet in facet_counts) {
      counts.push({
        facet: facet,
        count: parseInt(facet_counts[facet])
      });
    }
    return counts;
  },

  /**
   * Used if the facet counts are represented as an array of two-element arrays.
   *
   * @param {String} type "facet_fields", "facet_dates", "facet_queries" or "facet_ranges".
   * @returns {Array} An array of objects with the properties <tt>facet</tt> and
   * <tt>count</tt>, e.g <tt>{ facet: 'facet', count: 1 }</tt>.
   */
  getFacetCountsArrarr: function (type) {
    var counts = [],
        facet_counts = (this.field)?this.manager.response.facet_counts[type][this.field]:this.manager.response.facet_counts[type];

    for (var i = 0, l = facet_counts.length; i < l; i++) {
      counts.push({
        facet: facet_counts[i][0],
        count: parseInt(facet_counts[i][1])
      });
    }
    return counts;
  },

  /**
   * Used if the facet counts are represented as a flat array.
   *
   * @param {String} type "facet_fields", "facet_dates", "facet_queries" or "facet_ranges".
   * @returns {Array} An array of objects with the properties <tt>facet</tt> and
   * <tt>count</tt>, e.g <tt>{ facet: 'facet', count: 1 }</tt>.
   */
  getFacetCountsFlat: function (type) {
    var counts = [],
        facet_counts = this.manager.response.facet_counts;

    if(facet_counts !== undefined &&
       facet_counts[type] !== undefined &&
       facet_counts[type][this.field] !== undefined
      ) {
      facet_counts = facet_counts[type][this.field];
      for (var i = 0, l = facet_counts.length; i < l; i += 2) {
        counts.push({
          facet: facet_counts[i],
          count: parseInt(facet_counts[i+1])
        });
      }
    }
    return counts;
  },

  /**
   * Used if the facet counts are represented as a flat array inside a counts object.
   *
   * @param {String} type "facet_fields", "facet_dates", "facet_queries" or "facet_ranges".
   * @returns {Array} An array of objects with the properties <tt>facet</tt> and
   * <tt>count</tt>, e.g <tt>{ facet: 'facet', count: 1 }</tt>.
   */
  getFacetCountsRange: function (type) {
    var counts = [],
        facet_counts = this.manager.response.facet_counts;

    if(facet_counts !== undefined &&
       facet_counts[type] !== undefined &&
       facet_counts[type][this.field] !== undefined &&
       facet_counts[type][this.field].counts !== undefined
      ) {
      facet_counts = facet_counts[type][this.field].counts;
      for (var i = 0, l = facet_counts.length; i < l; i += 2) {
        counts.push({
          facet: facet_counts[i],
          count: parseInt(facet_counts[i+1])
        });
      }
    }
    return counts;
  },

  /**
   * @param {String} value The value.
   * @returns {Function} Sends a request to Solr if it successfully adds a
   *   filter query with the given value.
   */
  clickHandler: function (value) {
    var self = this, meth = this.multivalue ? (this.union ? 'append' : 'add') : 'set';
    return function () {
      if (self[meth].call(self, value)) {
        self.doRequest(0);
      }
      return false;
    }
  },

  /**
   * @param {String} value The value.
   * @returns {Function} Sends a request to Solr if it successfully removes a
   *   filter query with the given value.
   */
  unclickHandler: function (value) {
    var self = this;
    return function () {
      if (self.remove(value)) {
        self.doRequest(0);
      }
      return false;
    }
  },

  /**
   * @param {String} value The facet value.
   * @param {Boolean} exclude Whether to exclude this fq parameter value.
   * @returns {String} An fq parameter value.
   */
  fq: function (value, exclude) {
    if (/^[^\[].*:.*$/.test(value)) {
      return (exclude ? '-' : '') + AjaxSolr.Parameter.escapeValue(value);
    } else {
      return (exclude ? '-' : '') + this.field + ':' + AjaxSolr.Parameter.escapeValue(value);
    }
  },

  /**
   * Retrieve all fq parameters of this widget
   *
   * @returns
   */
  getParams: function() {
    var a = this.manager.store.find('fq', new RegExp('^-?' + this.field
        + ':'));
    var params = [];
    for ( var i in a) {
      params.push(this.manager.store.params.fq[a[i]]);
    }
    return params.length == 0 ? false : params;
  },

  /**
   * Return an array of the selected facet values.
   *
   * @param params
   * @returns {Array}
   */
  getQueryValues: function(params) {
    var param, q, i;
    var values = [];
    if (params) {
      for (i in params) {
        param = params[i];
        q = (this.union ? new RegExp('^-?' + this.field + ':\\((.*)\\)')
            : new RegExp('^-?' + this.field + ':(.*)')).exec(param.val())[1];
        if (this.union) {
          values = AjaxSolr.parseStringList(q).slice();
        } else {
          values.push(q);
        }
      }
    }
    return values;
  },

  /**
   * Return the position of the given value in the array of selected facet
   * values. -1 if not selected.
   *
   * @param value
   * @returns
   */
  inQuery: function(value) {
    return AjaxSolr.inArray(AjaxSolr.Parameter.escapeValue(value),
      this.getQueryValues(this.getParams()));
  }
});
// $Id$

/**
 * Offers an interface to the local parameters used by the Spatial Solr plugin.
 *
 * @see http://www.jteam.nl/news/spatialsolr
 *
 * @class AbstractSpatialWidget
 * @augments AjaxSolr.AbstractWidget
 */
AjaxSolr.AbstractSpatialWidget = AjaxSolr.AbstractWidget.extend(
  /** @lends AjaxSolr.AbstractSpatialWidget.prototype */
  {
  /**
   * Sets the Spatial Solr local parameters.
   *
   * @param {Object} params The local parameters to set.
   * @param {Number} params.lat Latitude of the center of the search area.
   * @param {Number} params.lng Longitude of the center of the search area.
   * @param {Number} params.radius Radius of the search area.
   * @param {String} [params.unit] Unit the distances should be calculated in:
   *   "km" or "miles".
   * @param {String} [params.calc] <tt>GeoDistanceCalculator</tt> that will be
   *   used to calculate the distances. "arc" for
   *   <tt>ArchGeoDistanceCalculator</tt> and "plane" for
   *   <tt>PlaneGeoDistanceCalculator</tt>.
   * @param {Number} [params.threadCount] Number of threads that will be used
   *   by the <tt>ThreadedDistanceFilter</tt>.
   */
  set: function (params) {
    this.manager.store.get('q').local('type', 'spatial');
    this.manager.store.get('q').local('lat', params.lat);
    this.manager.store.get('q').local('long', params.lng);
    this.manager.store.get('q').local('radius', params.radius);
    if (params.unit !== undefined) {
      this.manager.store.get('q').local('unit', params.unit);
    }
    if (params.calc !== undefined) {
      this.manager.store.get('q').local('calc', params.calc);
    }
    if (params.threadCount !== undefined) {
      this.manager.store.get('q').local('threadCount', params.threadCount);
    }
  },

  /**
   * Removes the Spatial Solr local parameters.
   */
  clear: function () {
    this.manager.store.get('q').remove('type');
    this.manager.store.get('q').remove('lat');
    this.manager.store.get('q').remove('long');
    this.manager.store.get('q').remove('radius');
    this.manager.store.get('q').remove('unit');
    this.manager.store.get('q').remove('calc');
    this.manager.store.get('q').remove('threadCount');
  }
});
// $Id$

/**
 * Interacts with Solr's SpellCheckComponent.
 *
 * @see http://wiki.apache.org/solr/SpellCheckComponent
 *
 * @class AbstractSpellcheckWidget
 * @augments AjaxSolr.AbstractWidget
 */
AjaxSolr.AbstractSpellcheckWidget = AjaxSolr.AbstractWidget.extend(
  /** @lends AjaxSolr.AbstractSpellcheckWidget.prototype */
  {
  /**
   * The suggestions.
   *
   * @field
   * @private
   * @type Object
   * @default []
   */
  suggestions: [],

  afterRequest: function () {
    var suggestions, record;

    this.suggestions = []

    if (this.manager.response.spellcheck && this.manager.response.spellcheck.suggestions) {
      suggestions = this.manager.response.spellcheck.suggestions;

      //console.log("suggestions=",suggestions);

      for (var i = 0, l = suggestions.length; i < l; i++) {

        if (suggestions[i] == 'collation') {
          i++;
          this.suggestions.push(suggestions[i]);
        }
      }

      if (this.suggestions.length) {
        this.handleSuggestions(this.manager.response);
      }
    }
  },

  /**
   * An abstract hook for child implementations.
   *
   * <p>Allow the child to handle the suggestions without parsing the response.</p>
   */
  handleSuggestions: function () {}
});
// $Id$

/**
 * Baseclass for all free-text widgets.
 *
 * @class AbstractTextWidget
 * @augments AjaxSolr.AbstractWidget
 */
AjaxSolr.AbstractTextWidget = AjaxSolr.AbstractWidget.extend(
  /** @lends AjaxSolr.AbstractTextWidget.prototype */
  {
  /**
   * This widget will by default set the offset parameter to 0 on each request.
   */
  start: 0,

  /**
   * Sets the main Solr query to the given string.
   *
   * @param {String} q The new Solr query.
   * @returns {Boolean} Whether the selection changed.
   */
  set: function (q) {
    return this.changeSelection(function () {
      this.manager.store.get('q').val(q);
    });
  },

  /**
   * Sets the main Solr query to the empty string.
   *
   * @returns {Boolean} Whether the selection changed.
   */
  clear: function () {
    return this.changeSelection(function () {
      this.manager.store.remove('q');
    });
  },

  /**
   * Helper for selection functions.
   *
   * @param {Function} Selection function to call.
   * @returns {Boolean} Whether the selection changed.
   */
  changeSelection: function (func) {
    var before = this.manager.store.get('q').val();
    func.apply(this);
    var after = this.manager.store.get('q').val();
    if (after !== before) {
      this.afterChangeSelection(after);
    }
    return after !== before;
  },

  /**
   * An abstract hook for child implementations.
   *
   * <p>This method is executed after the main Solr query changes.</p>
   *
   * @param {String} value The current main Solr query.
   */
  afterChangeSelection: function (value) {},

  /**
   * Returns a function to unset the main Solr query.
   *
   * @returns {Function}
   */
  unclickHandler: function () {
    var self = this;
    return function () {
      if (self.clear()) {
        self.doRequest();
      }
      return false;
    }
  },

  /**
   * Returns a function to set the main Solr query.
   *
   * @param {String} value The new Solr query.
   * @returns {Function}
   */
  clickHandler: function (q) {
    var self = this;
    return function () {
      if (self.set(q)) {
        self.doRequest();
      }
      return false;
    }
  }
});
// $Id$

/**
 * @see http://wiki.apache.org/solr/SolJSON#JSON_specific_parameters
 * @class Manager
 * @augments AjaxSolr.AbstractManager
 */
AjaxSolr.Manager = AjaxSolr.AbstractManager.extend(
  /** @lends AjaxSolr.Manager.prototype */
  {
  executeRequest: function (servlet, string, handler) {
    var self = this;
    string = string || this.store.string();
    handler = handler || function (data) {
      self.handleResponse(data);
    };
    if (this.proxyUrl) {
      jQuery.post(this.proxyUrl, { query: string }, handler, 'json');
    }
    else {
      //jQuery.getJSON(this.solrUrl + servlet + '?' + string + '&wt=json&json.wrf=?', {}, handler);
      jQuery.ajax({
        url: this.solrUrl + servlet + '?' + string + '&wt=json&json.wrf=?',
        dataType: 'json',
        success: handler,
        error: function(xhr, status, error) {
          throw(status);
        }
      });
    }
  }
});
// $Id$

/**
 * Strip whitespace from the beginning and end of a string.
 *
 * @returns {String} The trimmed string.
 */
String.prototype.trim = function () {
  return this.replace(/^ +/, '').replace(/ +$/, '');
};

/**
 * A utility method for escaping HTML tag characters.
 * <p>From Ruby on Rails.</p>
 *
 * @returns {String} The escaped string.
 */
String.prototype.htmlEscape = function () {
  return this.replace(/"/g, '&quot;').replace(/>/g, '&gt;').replace(/</g, '&lt;').replace(/&/g, '&amp;');
};

/**
 * Escapes the string without affecting existing escaped entities.
 * <p>From Ruby on Rails.</p>
 *
 * @returns {String} The escaped string
 */
String.prototype.escapeOnce = function () {
  return this.replace(/"/g, '&quot;').replace(/>/g, '&gt;').replace(/</g, '&lt;').replace(/&(?!([a-zA-Z]+|#\d+);)/g, '&amp;');
};

/**
 * <p>From Ruby on Rails.</p>
 *
 * @see http://www.w3.org/TR/html4/types.html#type-name
 */
String.prototype.sanitizeToId = function () {
  return this.replace(/\]/g, '').replace(/[^-a-zA-Z0-9:.]/g, '_');
};

/**
 * Does the string end with the specified <tt>suffix</tt>?
 * <p>From Ruby on Rails.</p>
 *
 * @param {String} suffix The specified suffix.
 * @returns {Boolean}
 */
String.prototype.endsWith = function (suffix) {
  return this.substring(this.length - suffix.length) == suffix;
};

/**
 * Does the string start with the specified <tt>prefix</tt>?
 * <p>From Ruby on Rails.</p>
 *
 * @param {String} prefix The speficied prefix.
 * @returns {Boolean}
 */
String.prototype.startsWith = function (prefix) {
  return this.substring(0, prefix.length) == prefix;
};

/**
 * Equivalent to PHP's two-argument version of strtr.
 *
 * @see http://php.net/manual/en/function.strtr.php
 * @param {Object} replacePairs An associative array in the form: {'from': 'to'}
 * @returns {String} A translated copy of the string.
 */
String.prototype.strtr = function (replacePairs) {
  var str = this;
  for (var from in replacePairs) {
    str = str.replace(new RegExp(from, 'g'), replacePairs[from]);
  }
  return str;
};
(function(a){AjaxSolr.Helpers={getUniqueID:function(){var a=(new Date).getTime().toString(32),b;for(b=0;b<5;b++)a+=Math.floor(Math.random()*65535).toString(32);return a},build:function(b){a.fn["solr"+b]=function(c,d){return this.each(function(){var e=a(this),f=e.data("field"),g=e.attr("id"),h;typeof g=="undefined"&&(g=AjaxSolr.Helpers.getUniqueID(),e.attr("id",g)),h=new AjaxSolr[b]({id:g,target:"#"+g,field:f,options:d}),e.data("widget",h),c.addWidget(h)})}}}})(jQuery);var _=function(a,b){b=b||"default";var c=AjaxSolr.Dicts[b];return typeof c!="undefined"?c.get(a):a};(function(a){AjaxSolr.Dictionary=function(b,c){var d=this,e=a(b),f=a.extend({},e.data(),c);d.id=e.attr("id")||f.id||"default",d.data={},d.container=e,d.opts=f,d.init()},AjaxSolr.Dictionary.prototype.init=function(){var b=this;b.text=b.container.text(),b.data=a.parseJSON(b.text)},AjaxSolr.Dictionary.prototype.get=function(a){var b=this,c,d;return a=a.replace(/^\s*(.*?)\s*$/,"$1"),c=b.data[a],typeof c!="undefined"?c:typeof b.opts.subDictionary=="undefined"?a:(d=AjaxSolr.Dicts[b.opts.subDictionary],typeof d!="undefined"?d.get(a):a)},AjaxSolr.Dictionary.prototype.set=function(a,b){var c=this;a=a.replace(/^\s*(.*?)\s*$/,"$1"),c.data[a]=b},a(function(){var b;AjaxSolr.Dicts={},a(".solrDictionary").each(function(){var a=new AjaxSolr.Dictionary(this);b||(b=a),AjaxSolr.Dicts[a.id]=a}),AjaxSolr.Dicts["default"]=AjaxSolr.Dicts["default"]||b})})(jQuery);
