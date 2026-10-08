/* Rendered by x11-theme; each Firefox profile's chrome/x11-theme.css links here
 * and its userChrome.css @imports it (needs
 * toolkit.legacyUserProfileCustomizations.stylesheets, set by the policy).
 *
 * The browser frame in the theme's colours: tab strip, toolbar, address bar,
 * menus and panels, and the theme's exact accent wherever Firefox uses its own
 * (focus rings, primary buttons, toggles, the selected tab). Firefox's own
 * pages (about:) are in firefox.userContent.css. Read at start.
 *
 * Token names are Firefox's design-system ones (checked against 157's
 * omni.ja: global/design-system/tokens-shared.css, tabbrowser/tab.tokens.css).
 * Firefox renames these between releases, and an unknown name is silently
 * ignored, so a frame that turns grey again after an upgrade means a rename. */
:root {
  /* tab strip */
  --lwt-accent-color: {{ dark_background }} !important;
  --lwt-text-color: {{ foreground }} !important;
  --toolbox-background-color: {{ dark_background }} !important;
  --toolbox-background-color-inactive: {{ dark_background }} !important;
  --toolbox-text-color: {{ foreground }} !important;
  --toolbox-text-color-inactive: {{ dark_foreground }} !important;
  --tab-text-color: {{ light_foreground }} !important;
  --tab-text-color-hover: {{ foreground }} !important;
  --tab-text-color-selected: {{ bright_foreground }} !important;
  --tab-background-color-hover: {{ mix dark_background lighter_background 50% }} !important;
  --tab-background-color-selected: {{ lighter_background }} !important;
  --tab-border-color-selected: transparent !important;
  --tabs-navbar-separator-color: {{ lighter_background }} !important;

  /* nav and bookmarks toolbars */
  --toolbar-background-color: {{ background }} !important;
  --toolbar-text-color: {{ foreground }} !important;
  --toolbarbutton-icon-fill: {{ foreground }} !important;
  --toolbarbutton-icon-fill-attention: {{ accent }} !important;
  --toolbarbutton-background-color-hover: {{ lighter_background }} !important;
  --toolbarbutton-background-color-active: {{ mix lighter_background accent 30% }} !important;
  --toolbarseparator-color: {{ lighter_background }} !important;

  /* address bar and its dropdown */
  --toolbar-field-background-color: {{ dark_background }} !important;
  --toolbar-field-background-color-focus: {{ darker_background }} !important;
  --toolbar-field-text-color: {{ bright_foreground }} !important;
  --toolbar-field-text-color-focus: {{ bright_foreground }} !important;
  --toolbar-field-border-color: {{ lighter_background }} !important;
  --toolbar-field-border-color-focus: {{ accent }} !important;
  --urlbar-box-background-color: {{ lighter_background }} !important;
  --urlbar-box-background-color-hover: {{ mix lighter_background accent 20% }} !important;
  --urlbar-box-text-color: {{ foreground }} !important;
  --urlbarview-background-color-hover: {{ lighter_background }} !important;
  --urlbarview-background-color-selected: {{ accent }} !important;
  --urlbarview-text-color-selected: {{ selection_foreground }} !important;
  --urlbarview-text-color-secondary: {{ dark_foreground }} !important;
  --urlbarview-text-color-action: {{ blue }} !important;
  --urlbarview-separator-color: {{ lighter_background }} !important;

  /* menus, panels, sidebar */
  --panel-background-color: {{ background }} !important;
  --panel-text-color: {{ foreground }} !important;
  --panel-border-color: {{ lighter_background }} !important;
  --panel-separator-color: {{ lighter_background }} !important;
  --sidebar-background-color: {{ dark_background }} !important;
  --sidebar-text-color: {{ foreground }} !important;
  --sidebar-border-color: {{ lighter_background }} !important;
  --tabpanel-background-color: {{ background }} !important;

  /* buttons, accent */
  --background-color-box: {{ dark_background }} !important;
  --background-color-canvas: {{ background }} !important;
  --text-color: {{ foreground }} !important;
  --border-color: {{ lighter_background }} !important;
  --button-background-color: {{ lighter_background }} !important;
  --button-background-color-hover: {{ mix lighter_background accent 20% }} !important;
  --button-background-color-active: {{ mix lighter_background accent 35% }} !important;
  --button-text-color: {{ foreground }} !important;
  --color-accent-primary: {{ accent }} !important;
  --color-accent-primary-hover: {{ mix accent bright_foreground 15% }} !important;
  --color-accent-primary-active: {{ mix accent bright_foreground 30% }} !important;
  --color-accent-primary-selected: {{ accent }} !important;
  --button-background-color-primary: {{ accent }} !important;
  --button-background-color-primary-hover: {{ mix accent bright_foreground 15% }} !important;
  --button-background-color-primary-active: {{ mix accent bright_foreground 30% }} !important;
  --button-text-color-primary: {{ selection_foreground }} !important;
  --button-text-color-primary-hover: {{ selection_foreground }} !important;
  --button-text-color-primary-active: {{ selection_foreground }} !important;
  --focus-outline-color: {{ accent }} !important;
  --tab-attention-dot-color: {{ accent }} !important;
  --toolbarbutton-badge-background-color: {{ accent }} !important;
  --link-color: {{ blue }} !important;
}
/* moz-button (the address bar's search-engine pill, panel buttons) declares
 * its button tokens on its shadow host, so :root never reaches them. */
moz-button {
  --button-background-color: {{ lighter_background }} !important;
  --button-background-color-hover: {{ mix lighter_background accent 20% }} !important;
  --button-background-color-active: {{ mix lighter_background accent 35% }} !important;
  --button-background-color-selected: {{ mix lighter_background accent 35% }} !important;
  --button-text-color: {{ foreground }} !important;
  --button-text-color-hover: {{ bright_foreground }} !important;
  --button-text-color-active: {{ bright_foreground }} !important;
  --button-text-color-selected: {{ bright_foreground }} !important;
  /* type="muted": the search-engine pill */
  --button-background-color-muted: {{ lighter_background }} !important;
  --button-background-color-muted-hover: {{ mix lighter_background accent 20% }} !important;
  --button-background-color-muted-active: {{ mix lighter_background accent 35% }} !important;
  --button-background-color-muted-selected: {{ mix lighter_background accent 35% }} !important;
  --button-text-color-muted: {{ foreground }} !important;
  --button-text-color-muted-hover: {{ bright_foreground }} !important;
  --button-text-color-muted-active: {{ bright_foreground }} !important;
  --button-text-color-muted-selected: {{ bright_foreground }} !important;
  /* type="ghost": transparent until hovered */
  --button-background-color-ghost-hover: {{ lighter_background }} !important;
  --button-background-color-ghost-active: {{ mix lighter_background accent 35% }} !important;
  --button-text-color-ghost: {{ foreground }} !important;
  --button-background-color-primary: {{ accent }} !important;
  --button-background-color-primary-hover: {{ mix accent bright_foreground 15% }} !important;
  --button-background-color-primary-active: {{ mix accent bright_foreground 30% }} !important;
  --button-text-color-primary: {{ selection_foreground }} !important;
}
#navigator-toolbox { background-color: {{ dark_background }} !important; }
/* Selected text in the address and search fields (GTK's blue otherwise). */
.urlbar-input::selection, #urlbar-input::selection, input::selection {
  background-color: {{ selection }} !important;
  color: {{ selection_foreground }} !important;
}
/* A thin accent line on the selected tab, as on the i3 bar. */
.tabbrowser-tab[selected] .tab-background {
  box-shadow: inset 0 -2px 0 {{ accent }} !important;
}
