/* Rendered by x11-theme; each Firefox profile's chrome/x11-theme.css links here
 * and its userChrome.css @imports it (needs
 * toolkit.legacyUserProfileCustomizations.stylesheets, set by the policy).
 *
 * The browser frame in the theme's colours: tab strip, toolbar, address bar,
 * menus and panels, and the theme's exact accent wherever Firefox uses its own
 * (focus rings, primary buttons, toggles, the selected tab). Firefox's own
 * pages (about:) are in firefox.userContent.css. Read at start. */
:root {
  /* surfaces */
  --lwt-accent-color: {{ dark_background }} !important;             /* tab strip */
  --lwt-text-color: {{ foreground }} !important;
  --toolbox-bgcolor: {{ dark_background }} !important;
  --toolbox-textcolor: {{ foreground }} !important;
  --toolbar-bgcolor: {{ background }} !important;
  --toolbar-color: {{ foreground }} !important;
  --toolbar-field-background-color: {{ dark_background }} !important;
  --toolbar-field-color: {{ bright_foreground }} !important;
  --toolbar-field-focus-background-color: {{ darker_background }} !important;
  --toolbar-field-focus-color: {{ bright_foreground }} !important;
  --toolbar-field-border-color: {{ lighter_background }} !important;
  --tabpanel-background-color: {{ background }} !important;
  --tab-selected-bgcolor: {{ lighter_background }} !important;
  --tab-selected-textcolor: {{ bright_foreground }} !important;
  --tab-hover-background-color: {{ mix dark_background lighter_background 50% }} !important;
  --arrowpanel-background: {{ background }} !important;
  --arrowpanel-color: {{ foreground }} !important;
  --arrowpanel-border-color: {{ lighter_background }} !important;
  --panel-separator-color: {{ lighter_background }} !important;
  --sidebar-background-color: {{ dark_background }} !important;
  --sidebar-text-color: {{ foreground }} !important;
  --urlbarView-highlight-background: {{ accent }} !important;
  --urlbarView-highlight-color: {{ selection_foreground }} !important;
  --button-hover-bgcolor: {{ lighter_background }} !important;

  /* accent */
  --color-accent-primary: {{ accent }} !important;
  --color-accent-primary-hover: {{ mix accent bright_foreground 15% }} !important;
  --color-accent-primary-active: {{ mix accent bright_foreground 30% }} !important;
  --color-accent-primary-selected: {{ accent }} !important;
  --button-text-color-primary: {{ selection_foreground }} !important;
  --focus-outline-color: {{ accent }} !important;
  --toolbar-field-focus-border-color: {{ accent }} !important;
  --tab-attention-icon-color: {{ accent }} !important;
  --link-color: {{ blue }} !important;
}
#navigator-toolbox { background-color: {{ dark_background }} !important; }
/* A thin accent line on the selected tab, as on the i3 bar. */
.tabbrowser-tab[selected] .tab-background {
  box-shadow: inset 0 -2px 0 {{ accent }} !important;
}
