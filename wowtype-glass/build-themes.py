#!/usr/bin/env python3
"""Build the Silky Glass light / dark fcitx5 skins for WowType.

Usage: build-themes.py OUTPUT_DIR   (creates OUTPUT_DIR/silky-glass-light and silky-glass-dark)

Both fcitx5's classicui (every app that uses the Wayland input-method protocol) and the
fcitx5-qt client bundled inside WeChat read these skins. WeChat's copy only understands
images, plain colours and margins (no blur, dark-theme or accent keys), so the rounded
corners and translucency live in the PNGs and Hyprland supplies the frosted blur behind them.
"""
import pathlib
import subprocess
import sys

R = 12  # panel corner radius (logical px), close to macOS menus and popovers
HR = 7  # highlight pill radius

SKINS = {
    "silky-glass-dark": {
        "name": "Silky Glass Dark",
        "panel": "rgba(38,38,42,0.74)",
        "rim": "rgba(255,255,255,0.11)",
        "sheen": "rgba(255,255,255,0.03)",
        "accent": "#0A84FF",
        "text": "#F5F5F7",
        "comment": "#A1A1A6",
        "arrow": "#EBEBF0",
        "menu_bg": "#2C2C2E",
        "menu_border": "#48484A",
        "menu_sep": "#3A3A3C",
    },
    "silky-glass-light": {
        "name": "Silky Glass Light",
        "panel": "rgba(252,252,254,0.84)",
        "rim": "rgba(0,0,0,0.10)",
        "sheen": "rgba(255,255,255,0.55)",
        "accent": "#007AFF",
        "text": "#1D1D1F",
        "comment": "#6E6E73",
        "arrow": "#3A3A3C",
        "menu_bg": "#F5F5F7",
        "menu_border": "#D1D1D6",
        "menu_sep": "#E5E5EA",
    },
}


def panel_svg(s):
    size = 2 * R + 16
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}">
  <rect x="0.5" y="0.5" width="{size - 1}" height="{size - 1}" rx="{R - 0.5}" fill="{s['panel']}" stroke="{s['rim']}"/>
  <rect x="1.5" y="1.5" width="{size - 3}" height="{size - 3}" rx="{R - 1.5}" fill="none" stroke="{s['sheen']}"/>
</svg>"""


def highlight_svg(s):
    size = 2 * HR + 10
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}">
  <rect width="{size}" height="{size}" rx="{HR}" fill="{s['accent']}"/>
</svg>"""


def arrow_svg(s, direction):
    path = "M9 4 L5 8 L9 12" if direction == "prev" else "M7 4 L11 8 L7 12"
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">
  <path d="{path}" fill="none" stroke="{s['arrow']}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""


def radio_svg(s):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">
  <circle cx="8" cy="8" r="3.5" fill="{s['accent']}"/>
</svg>"""


def theme_conf(s):
    pm = R + 2  # 9-slice margin: keeps the whole corner (and rim) out of the stretched part
    hm = HR + 2
    return f"""[Metadata]
Name={s['name']}
Version=1
Author=Silky Omarchy
Description=macOS-style frosted candidate window (rounded, translucent; Hyprland adds the blur)
ScaleWithDPI=True

[InputPanel]
NormalColor={s['text']}
HighlightCandidateColor=#FFFFFF
HighlightCandidateLabelColor=#FFFFFF
CandidateCommentColor={s['comment']}
HighlightCandidateCommentColor=#FFFFFFCC
HighlightColor={s['text']}
HighlightBackgroundColor={s['accent']}
EnableBlur=False
FullWidthHighlight=False
PageButtonAlignment=Last Candidate
Spacing=2

[InputPanel/ContentMargin]
Left=7
Right=7
Top=7
Bottom=7

[InputPanel/TextMargin]
Left=9
Right=9
Top=5
Bottom=5

[InputPanel/Background]
Image=panel.png

[InputPanel/Background/Margin]
Left={pm}
Right={pm}
Top={pm}
Bottom={pm}

[InputPanel/Highlight]
Image=highlight.png

[InputPanel/Highlight/Margin]
Left={hm}
Right={hm}
Top={hm}
Bottom={hm}

[InputPanel/PrevPage]
Image=prev.png

[InputPanel/PrevPage/ClickMargin]
Left=4
Right=4
Top=4
Bottom=4

[InputPanel/NextPage]
Image=next.png

[InputPanel/NextPage/ClickMargin]
Left=4
Right=4
Top=4
Bottom=4

[Menu]
NormalColor={s['text']}
HighlightCandidateColor=#FFFFFF

[Menu/Background]
Color={s['menu_bg']}
BorderColor={s['menu_border']}
BorderWidth=1

[Menu/Background/Margin]
Left=1
Right=1
Top=1
Bottom=1

[Menu/ContentMargin]
Left=4
Right=4
Top=4
Bottom=4

[Menu/Highlight]
Color={s['accent']}

[Menu/Highlight/Margin]
Left=5
Right=5
Top=4
Bottom=4

[Menu/Separator]
Color={s['menu_sep']}

[Menu/CheckBox]
Image=radio.png

[Menu/TextMargin]
Left=6
Right=6
Top=5
Bottom=5
"""


def render(svg, target):
    subprocess.run(["rsvg-convert", "-o", str(target)], input=svg.encode(), check=True)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = pathlib.Path(sys.argv[1])
    for slug, s in SKINS.items():
        d = out / slug
        d.mkdir(parents=True, exist_ok=True)
        render(panel_svg(s), d / "panel.png")
        render(highlight_svg(s), d / "highlight.png")
        render(arrow_svg(s, "prev"), d / "prev.png")
        render(arrow_svg(s, "next"), d / "next.png")
        render(radio_svg(s), d / "radio.png")
        (d / "theme.conf").write_text(theme_conf(s))
        print(d)


if __name__ == "__main__":
    main()
