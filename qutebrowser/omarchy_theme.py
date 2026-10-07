"""Omarchy-aware colours for qutebrowser.

Reads the palette of the currently applied omarchy theme and maps it onto
qutebrowser's colour options. Source it from config.py:

    config.source('omarchy_theme.py')

It is a no-op when no omarchy theme is present, so the same dotfiles work on a
machine without omarchy.
"""

import os

# The palette omarchy stages for the active theme. Colours come from here, not
# from the theme repo, so this follows every theme switch.
_THEME_FILE = os.path.expanduser(
    "~/.local/state/omarchy/current/theme/colors.toml"
)


def _read_palette(path):
    try:
        import tomllib

        with open(path, "rb") as handle:
            return tomllib.load(handle)
    except Exception:
        pass

    # tomllib is 3.11+. Fall back to the flat `key = "value"` lines omarchy
    # writes; a comment or an unquoted key simply does not match.
    import re

    palette = {}
    try:
        with open(path) as handle:
            for line in handle:
                match = re.match(r'\s*([A-Za-z0-9_-]+)\s*=\s*"([^"]*)"', line)
                if match:
                    palette[match.group(1)] = match.group(2)
    except OSError:
        pass
    return palette


# ── contrast helpers ────────────────────────────────────────────────────────
# Two of the tab colours cannot be taken from the palette directly and still
# read well in every theme, so they are derived from it here:
#
#   * the inactive tab's text, because a theme's `muted` is often close to its
#     own background (lumont's is 1.7:1, which is unreadable), and
#   * the active tab's fill, because a theme's `accent` is chosen to pop off a
#     terminal, which makes a full-width slab shout in a tab bar.
#
# Both are solved numerically rather than per theme, so a newly installed
# theme gets the same treatment without anyone tuning it by hand.

_MIN_TEXT_CONTRAST = 4.5  # WCAG AA for normal text
_MAX_ACTIVE_CONTRAST = 2.2  # how far the active fill may stand off the bar


def _channels(color):
    """'#rrggbb' -> three 0..1 channels."""
    color = color.lstrip("#")
    if len(color) == 3:
        color = "".join(ch * 2 for ch in color)
    return tuple(int(color[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _luminance(color):
    """WCAG relative luminance."""
    linear = [
        ch / 12.92 if ch <= 0.03928 else ((ch + 0.055) / 1.055) ** 2.4
        for ch in _channels(color)
    ]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def _contrast(a, b):
    """Contrast ratio between two colours, 1.0 to 21.0."""
    first, second = sorted((_luminance(a), _luminance(b)), reverse=True)
    return (first + 0.05) / (second + 0.05)


def _mix(bottom, top, amount):
    """Blend `top` into `bottom` by `amount` (0.0 to 1.0)."""
    low, high = _channels(bottom), _channels(top)
    # _channels yields 0..1, so the blend has to be scaled back to 0..255
    # before it is written as hex; rounding the fractions themselves would
    # collapse almost every colour to black.
    blended = [
        round(255 * (low[i] * (1 - amount) + high[i] * amount))
        for i in range(3)
    ]
    return "#%02x%02x%02x" % tuple(blended)


def _toward(bottom, top, is_enough):
    """Least blend of `top` into `bottom` that satisfies `is_enough`.

    Bisected rather than solved in closed form because contrast is a
    non-linear function of the blend, and the caller only cares that the
    smallest acceptable amount is used.
    """
    low, high = 0.0, 1.0
    for _ in range(24):
        middle = (low + high) / 2
        if is_enough(_mix(bottom, top, middle)):
            high = middle
        else:
            low = middle
    return _mix(bottom, top, high)


def _readable_on(backgrounds, muted, fg, minimum=_MIN_TEXT_CONTRAST):
    """A muted colour legible on every one of `backgrounds`.

    A theme's `muted` is sometimes barely distinguishable from its own
    background (lumont's is 1.7:1). When that happens it cannot be blended
    back towards readability, because it already sits on the far side of the
    background from the light direction: darkening it would only worsen it.
    So the fallback is `fg` pulled in just far enough from the background to
    read, which lands close to the muted colour a well-behaved theme supplies.

    Tabs alternate between two backgrounds, so the result has to clear the
    minimum against both of them, not just the lighter one.
    """
    if not isinstance(backgrounds, (tuple, list)):
        backgrounds = (backgrounds,)

    if all(_contrast(bg, muted) >= minimum for bg in backgrounds):
        return muted

    return _toward(
        backgrounds[0], fg,
        lambda c: all(_contrast(bg, c) >= minimum for bg in backgrounds),
    )


def _subtle_accent(accent, bg, ceiling=_MAX_ACTIVE_CONTRAST):
    """`accent` pulled toward `bg` until it stops dominating the tab bar.

    A theme's accent is tuned to read against a terminal background, where it
    only ever covers text. As a filled tab it becomes a slab of colour, so it
    is damped until its contrast with the bar is within `ceiling`.
    """
    if _contrast(accent, bg) <= ceiling:
        return accent
    return _toward(accent, bg, lambda c: _contrast(c, bg) <= ceiling)


_p = _read_palette(_THEME_FILE)

if _p:
    bg = _p.get("background", "#040003")
    fg = _p.get("foreground", "#f08a9b")
    accent = _p.get("accent", "#d40d40")
    accent2 = _p.get("magenta", accent)
    muted = _p.get("muted", _p.get("dark_foreground", fg))
    dark = _p.get("dark_background", bg)
    light = _p.get("lighter_background", dark)
    bright_fg = _p.get("bright_foreground", fg)
    purple = _p.get("purple", accent2)

    # Tab colours. `tab_fg` and `tab_fill` are derived rather than taken
    # straight from the palette; see the contrast helpers above.
    tab_fg = _readable_on((bg, dark), muted, fg)
    tab_fill = _subtle_accent(accent, bg)

    # ── completion ──────────────────────────────────────────────────────────
    c.colors.completion.fg = fg
    c.colors.completion.odd.bg = bg
    c.colors.completion.even.bg = dark
    c.colors.completion.category.fg = accent
    c.colors.completion.category.bg = bg
    c.colors.completion.category.border.top = accent
    c.colors.completion.category.border.bottom = accent
    c.colors.completion.item.selected.fg = bright_fg
    c.colors.completion.item.selected.bg = accent
    c.colors.completion.item.selected.border.top = accent
    c.colors.completion.item.selected.border.bottom = accent
    c.colors.completion.item.selected.match.fg = bright_fg
    c.colors.completion.match.fg = accent2
    c.colors.completion.scrollbar.fg = fg
    c.colors.completion.scrollbar.bg = bg

    # ── context menu ────────────────────────────────────────────────────────
    c.colors.contextmenu.menu.bg = bg
    c.colors.contextmenu.menu.fg = fg
    c.colors.contextmenu.selected.bg = accent
    c.colors.contextmenu.selected.fg = bright_fg

    # ── downloads ───────────────────────────────────────────────────────────
    c.colors.downloads.bar.bg = bg
    c.colors.downloads.start.fg = bg
    c.colors.downloads.start.bg = accent
    c.colors.downloads.stop.fg = bg
    c.colors.downloads.stop.bg = fg
    c.colors.downloads.error.fg = accent

    # ── hints ───────────────────────────────────────────────────────────────
    c.colors.hints.fg = bg
    c.colors.hints.bg = accent
    c.colors.hints.match.fg = fg

    # ── keyhint ─────────────────────────────────────────────────────────────
    c.colors.keyhint.fg = fg
    c.colors.keyhint.suffix.fg = accent
    c.colors.keyhint.bg = bg

    # ── messages ────────────────────────────────────────────────────────────
    c.colors.messages.error.fg = bright_fg
    c.colors.messages.error.bg = accent
    c.colors.messages.error.border = accent
    c.colors.messages.warning.fg = bright_fg
    c.colors.messages.warning.bg = muted
    c.colors.messages.warning.border = muted
    c.colors.messages.info.fg = fg
    c.colors.messages.info.bg = bg
    c.colors.messages.info.border = bg

    # ── prompts ─────────────────────────────────────────────────────────────
    c.colors.prompts.fg = fg
    c.colors.prompts.border = accent
    c.colors.prompts.bg = bg
    c.colors.prompts.selected.fg = bright_fg
    c.colors.prompts.selected.bg = accent

    # ── statusbar ───────────────────────────────────────────────────────────
    c.colors.statusbar.normal.fg = fg
    c.colors.statusbar.normal.bg = bg
    c.colors.statusbar.insert.fg = bg
    c.colors.statusbar.insert.bg = accent
    c.colors.statusbar.passthrough.fg = bg
    c.colors.statusbar.passthrough.bg = muted
    c.colors.statusbar.private.fg = bright_fg
    c.colors.statusbar.private.bg = purple
    c.colors.statusbar.command.fg = fg
    c.colors.statusbar.command.bg = bg
    c.colors.statusbar.command.private.fg = fg
    c.colors.statusbar.command.private.bg = bg
    c.colors.statusbar.caret.fg = bg
    c.colors.statusbar.caret.bg = accent
    c.colors.statusbar.caret.selection.fg = bg
    c.colors.statusbar.caret.selection.bg = fg
    c.colors.statusbar.progress.bg = accent
    c.colors.statusbar.url.fg = fg
    c.colors.statusbar.url.error.fg = accent
    c.colors.statusbar.url.hover.fg = bright_fg
    c.colors.statusbar.url.success.http.fg = muted
    c.colors.statusbar.url.success.https.fg = fg
    c.colors.statusbar.url.warn.fg = accent

    # ── tabs ────────────────────────────────────────────────────────────────
    # The indicator keeps the full-strength accent: it is a few pixels of
    # colour, so it should stay vivid. The selected tab's *fill* uses the damped
    # `tab_fill`, because a full-width slab of the accent is what reads as too
    # loud. Inactive tabs use `tab_fg`, which is guaranteed legible against
    # both tab backgrounds.
    c.colors.tabs.bar.bg = bg
    c.colors.tabs.indicator.start = accent
    c.colors.tabs.indicator.stop = fg
    c.colors.tabs.indicator.error = accent
    c.colors.tabs.odd.fg = tab_fg
    c.colors.tabs.odd.bg = bg
    c.colors.tabs.even.fg = tab_fg
    c.colors.tabs.even.bg = dark
    c.colors.tabs.pinned.even.fg = fg
    c.colors.tabs.pinned.even.bg = dark
    c.colors.tabs.pinned.odd.fg = fg
    c.colors.tabs.pinned.odd.bg = bg
    c.colors.tabs.pinned.selected.even.fg = bright_fg
    c.colors.tabs.pinned.selected.even.bg = tab_fill
    c.colors.tabs.pinned.selected.odd.fg = bright_fg
    c.colors.tabs.pinned.selected.odd.bg = tab_fill
    c.colors.tabs.selected.even.fg = bright_fg
    c.colors.tabs.selected.even.bg = tab_fill
    c.colors.tabs.selected.odd.fg = bright_fg
    c.colors.tabs.selected.odd.bg = tab_fill

    # ── website dark mode ───────────────────────────────────────────────────
    c.colors.webpage.darkmode.enabled = True
    c.colors.webpage.darkmode.policy.images = "smart"
    c.colors.webpage.darkmode.algorithm = "lightness-cielab"
    c.colors.webpage.bg = bg
