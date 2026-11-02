# Nerd Font icon catalogue

`glyphs.json` maps Nerd Font icon names to their codepoints for the Control
Center button's icon (Settings -> Bar & Control Center -> Control Center ->
Button icon; `Common/ControlIconHelpers.js`). It holds names and codepoints
only; the glyphs themselves come from JetBrainsMono Nerd Font, which every
installation has, so the bar and the fish prompt draw the same icon.

Pinned source: [`glyphnames.json`](https://github.com/ryanoasis/nerd-fonts/blob/v3.5.0/glyphnames.json)
from Nerd Fonts 3.5.0, the release of `nerd-fonts.jetbrains-mono` in this
tree's Nixpkgs. File SHA-256:
`0842e1a0f6a2e3d8fa7fd22b5aab4ff93878269c8c2c9155b307f000eaea0f94`.

`scripts/update-nerd-icons` regenerates it. It keeps the icon sets worth a
button (Material Design, Font Awesome and its extension, Devicons, Octicons,
Codicons, Weather Icons, Seti UI, the Linux logos and Nerd Fonts' own), and
only glyphs in the private use areas, so an emoji font never draws one
instead. When Nixpkgs moves to another Nerd Fonts release, update `VERSION`
and `SHA256` there and run it again, so each codepoint still names the glyph
the installed font has.

The Nerd Fonts glyph list is distributed under the MIT License:

The MIT License (MIT)

Copyright (c) 2014 Ryan L McIntyre

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Names and logos remain trademarks of their respective owners.
