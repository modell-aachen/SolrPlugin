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
    var suggestions;

    this.suggestions = []

    if (this.manager.response.spellcheck && this.manager.response.spellcheck.collations) {
      suggestions = this.manager.response.spellcheck.collations;

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
