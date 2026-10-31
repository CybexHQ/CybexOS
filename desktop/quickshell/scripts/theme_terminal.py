"""The terminal palette every terminal target renders.

kitty, Ghostty, Alacritty and foot show the same colours: the shell's base and
text, its selected fill with the ink drawn on it, an accent cursor and links
that stay readable on the base, and the sixteen ANSI colours. Each target only
writes them in its own file format.
"""
import theme_tokens

# The vendor fragments' size, in points, which every terminal keeps at the
# shell's default text size (theme_tokens.text_scale).
FONT_SIZE = 12.0
# The face the vendor fragments name; foot's theme file repeats it because
# foot sets the family and size in one key.
FONT_FAMILY = 'JetBrainsMono Nerd Font'


def colors(tokens):
    palette = tokens['colors']
    background = palette['background']
    # accentText already clears 4.5:1 on the shell's panels; the terminal base
    # can differ slightly from them in wallpaper mode.
    accent_text = theme_tokens.ensure_contrast(palette['accentText'], background, 4.5)
    # The shell's own selected fill and the ink it draws on it
    # (Theme.accentContainerFg).
    selection = palette['accentContainer']
    return {
        'foreground': palette['text'],
        'background': background,
        'selection_foreground': theme_tokens.foreground_for(selection),
        'selection_background': selection,
        'cursor': accent_text,
        'cursor_text': background,
        'url': accent_text,
        'ansi': theme_tokens.ansi_palette(tokens),
    }


def font_size(tokens):
    """The terminal's font size: its 12 pt default, scaled like the shell's text."""
    return f'{FONT_SIZE * theme_tokens.text_scale(tokens):.1f}'
