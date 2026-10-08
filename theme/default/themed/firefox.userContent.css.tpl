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
    --newtab-background-color: {{ background }} !important;
    --newtab-background-color-secondary: {{ dark_background }} !important;
    --newtab-text-primary-color: {{ foreground }} !important;
  }
}
