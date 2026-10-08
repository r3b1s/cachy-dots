/* Rendered by x11-theme; each Firefox profile's chrome/x11-theme-content.css
 * links here and its userContent.css @imports it. Only Firefox's own pages
 * (about:preferences, about:newtab, about:addons, ...) are themed; websites
 * are left alone. Read at start. */
@-moz-document url-prefix("about:") {
  :root {
    --color-accent-primary: {{ accent }} !important;
    --color-accent-primary-hover: {{ mix accent bright_foreground 15% }} !important;
    --color-accent-primary-active: {{ mix accent bright_foreground 30% }} !important;
    --color-accent-primary-selected: {{ accent }} !important;
    --button-text-color-primary: {{ selection_foreground }} !important;
    --focus-outline-color: {{ accent }} !important;
    --link-color: {{ blue }} !important;
    --in-content-page-background: {{ background }} !important;
    --in-content-page-color: {{ foreground }} !important;
    --in-content-box-background: {{ dark_background }} !important;
    --in-content-box-border-color: {{ lighter_background }} !important;
    --background-color-canvas: {{ background }} !important;
    --background-color-box: {{ dark_background }} !important;
    --text-color: {{ foreground }} !important;
    --text-color-deemphasized: {{ dark_foreground }} !important;
    --border-color: {{ lighter_background }} !important;
    --button-background-color: {{ lighter_background }} !important;
    --button-background-color-hover: {{ mix lighter_background accent 20% }} !important;
    --button-background-color-active: {{ mix lighter_background accent 35% }} !important;
    --button-text-color: {{ foreground }} !important;
    --button-background-color-primary: {{ accent }} !important;
    --button-background-color-primary-hover: {{ mix accent bright_foreground 15% }} !important;
    --button-background-color-primary-active: {{ mix accent bright_foreground 30% }} !important;
    --button-text-color-primary-hover: {{ selection_foreground }} !important;
    --button-text-color-primary-active: {{ selection_foreground }} !important;
    --table-background-color: {{ dark_background }} !important;
    --newtab-background-color: {{ background }} !important;
    --newtab-background-color-secondary: {{ dark_background }} !important;
    --newtab-text-primary-color: {{ foreground }} !important;
    --border-color-deemphasized: {{ lighter_background }} !important;
    --background-color-box-info: {{ dark_background }} !important;
    --background-color-information: {{ lighter_background }} !important;
  }
  /* Promo and notice boxes (the "Make default" card) declare their own tokens
   * on the element's shadow host, so they are overridden on the element. */
  moz-promo, moz-message-bar {
    --promo-background-color: {{ dark_background }} !important;
    --promo-background-color-vibrant: {{ lighter_background }} !important;
    --promo-border-color: {{ lighter_background }} !important;
    --promo-border-color-vibrant: {{ lighter_background }} !important;
    --promo-message-text-color-vibrant: {{ foreground }} !important;
    --message-bar-background-color: {{ lighter_background }} !important;
    --message-bar-text-color: {{ foreground }} !important;
  }
}
