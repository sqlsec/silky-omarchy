#!/usr/bin/env python3
"""Give every launcher app a MacTahoe-style icon.

Apps the MacTahoe set does not cover fall back to their vendors' hicolor icons, which come in every shape and size
(circles, bare glyphs, full-bleed squares), so the Applications panel and the Dock looked mixed. Two fixes, both
installed into MacTahoe/apps/scalable so they win over hicolor everywhere (Applications, Dock, Spotlight):

- utilities and Omarchy's own apps point at the matching macOS icon from the set (a symlink, like omacalc -> calc);
- branded apps keep their logo but are redrawn on MacTahoe's exact tile: the same 442/512 rounded square
  (corner radius 100) and the same soft shadow, taken from the set's own Zoom icon.

Desktop entries that pointed at a hand-made PNG are switched to the theme name. Needs ImageMagick 7 (magick).
Safe to run again: it only rewrites what it created.
"""
import base64
import os
import re
import subprocess
import sys
import tempfile

HOME = os.path.expanduser("~")
ICONS = os.path.join(HOME, ".local/share/icons")
APPS = os.path.join(ICONS, "MacTahoe/apps/scalable")
LOCAL_APPS = os.path.join(HOME, ".local/share/applications")
MARK = "silky-app-icon"  # written into generated SVGs so a re-run knows they are ours

# icon name -> MacTahoe icon it should look like
ALIASES = {
    "zoom": "Zoom",
    "google-maps": "web-google-maps",
    "google-photos": "gnome-photos",
    "google-contacts": "contacts",
    "wemeetapp": "meeting",
    "imv": "accessories-image-viewer",
    "LimineSnapperSync": "timeshift",
    "disktree": "disk-usage-analyzer",
    "cliamp": "audio-player",
    "omasnap": "accessories-screenshot",
    "omacut": "org.gnome.gitlab.YaLTeR.VideoTrimmer",
    "monologue": "cheese",
    "hype": "libreoffice-impress",
    "gliff": "remote-desktop",
    "signed": "application-pdf",
    "aether": "preferences-desktop-theme",
    "moonlight": "applications-games",
    "macshell-installer": "system-software-install",
}

# icon name -> (source image, style).
# "tile": the logo already is a square, so it fills the tile;
# "card" / "round-card": a bordered dark/solid card with an outer stroke and hard drop shadow (e.g. Omarchy SVGs),
#   trimmed clean and centered on its own background colour;
# "glyph": a bare or round logo, so it sits on a light tile like Apple's own apps.
SILKY = os.path.join(ICONS, "silky-apps")
BRANDS = {
    "kimi-code": ("kimi-code", "tile"),
    "claude-desktop": ("claude-desktop", "tile"),
    "hey": ("hey", "tile"),
    "superwhisper": ("superwhisper", "tile"),
    "workbuddy": ("workbuddy", "tile"),
    "xiezuo": ("xiezuo", "tile"),
    "wowtype": ("wowtype", "glyph"),
    "fantasi": ("fantasi", "round-card"),
    "flowtunes": ("flowtunes", "round-card"),
    "omarchy-agent-claude": ("omarchy-agent-claude", "card"),
    "omarchy-agent-codex": ("omarchy-agent-codex", "card"),
    "omarchy-agent-dsh": ("omarchy-agent-dsh", "card"),
    "omarchy-agent-kimi": ("omarchy-agent-kimi", "card"),
    "omarchy-terminal": ("omarchy-terminal", "card"),
    "omarchy-browser": ("omarchy-browser", "glyph"),
    "omaview": ("omaview", "glyph"),
    "omarchy-game-vibes": ("omarchy-game-vibes", "glyph"),
    "silky-basecamp": (os.path.join(SILKY, "basecamp-compact.png"), "tile"),
    "silky-netcatty": (os.path.join(SILKY, "netcatty-compact.png"), "tile"),
    "silky-google-messages": (os.path.join(SILKY, "google-messages-compact.png"), "glyph"),
    "silky-clippy": (os.path.join(ICONS, "clippy-paste-rounded.png"), "tile"),
    "silky-lite-work": (os.path.join(HOME, "Projects/Work/Softs/lite-work/app/icon-rounded-compact.png"), "tile"),
    "omalogi": (os.path.join(SILKY, "omalogi.svg"), "tile"),  # drawn in config/icons, see docs/14
}

# desktop entry (in ~/.local/share/applications, or copied from /usr/share/applications) -> icon name it should use
ENTRIES = {
    "antigravity.desktop": "antigravity",
    "kimi-code.desktop": "kimi-code",
    "Basecamp.desktop": "silky-basecamp",
    "netcatty.desktop": "silky-netcatty",
    "Google Messages.desktop": "silky-google-messages",
    "Google Contacts.desktop": "google-contacts",
    "clippy.desktop": "silky-clippy",
    "lite-work.desktop": "silky-lite-work",
    "wemeetapp.desktop": "wemeetapp",
    "macshell-installer.desktop": "macshell-installer",
    "kbd-layout-viewer5.desktop": "keyboard",
}

SIZE, TILE0, TILE1, RADIUS = 512, 35, 476, 100


def magick(*args):
    subprocess.run(["magick", *map(str, args)], check=True, stdout=subprocess.DEVNULL)


def vendor_icon(name):
    if os.path.isabs(name):
        return name if os.path.exists(name) else None
    for base in (os.path.join(ICONS, "hicolor"), "/usr/share/icons/hicolor"):
        for size in ("scalable", "1024x1024", "512x512", "256x256", "192x192", "128x128", "96x96", "64x64", "48x48"):
            for ext in ("svg", "png"):
                path = f"{base}/{size}/apps/{name}.{ext}"
                if os.path.exists(path):
                    return path
    for ext in ("svg", "png"):
        path = f"/usr/share/pixmaps/{name}.{ext}"
        if os.path.exists(path):
            return path
    return None


def ours(path):
    if os.path.islink(path) or not os.path.exists(path):
        return True
    with open(path, "rb") as f:
        return MARK.encode() in f.read(400)


def build(src, style, out_png, tmp):
    raw = os.path.join(tmp, "raw.png")
    magick("-background", "none", "-density", 384, src, "-resize", "1024x1024", f"PNG32:{raw}")
    # bounding box of the opaque part, so a vendor's own padding or soft shadow does not shrink the logo
    box = subprocess.run(["magick", raw, "-alpha", "extract", "-threshold", "50%", "-format", "%@", "info:"],
                         check=True, capture_output=True, text=True).stdout.strip()
    art = os.path.join(tmp, "art.png")
    magick(raw, "-crop", box, "+repage", f"PNG32:{art}")

    side = TILE1 - TILE0 + 1
    face = os.path.join(tmp, "face.png")
    if style == "tile":
        # fill the tile; the logo's own edge colour backs any corner its rounder shape leaves open
        edge = subprocess.run(["magick", art, "-format", "%[pixel:p{%[fx:int(w*0.03)],%[fx:int(h/2)]}]", "info:"],
                              check=True, capture_output=True, text=True).stdout.strip()
        magick(art, "-background", edge, "-flatten", "-resize", f"{side}x{side}^", "-gravity", "center",
               "-extent", f"{side}x{side}", f"PNG32:{face}")
    elif style in ("card", "round-card"):
        # bordered solid card (e.g. Omarchy SVGs with an outer grey stroke and bottom hard shadow):
        # trim away the stroke and hard shadow, sample the interior fill, and center cleanly without cropping.
        dims = subprocess.run(["magick", art, "-format", "%w %h", "info:"],
                              check=True, capture_output=True, text=True).stdout.strip().split()
        aw, ah = int(dims[0]), int(dims[1])
        trim = 0.085 if style == "round-card" else 0.03
        bottom_extra = 0.02 if style == "round-card" else 0.025
        sample_pct = 0.12 if style == "round-card" else 0.08
        bg = subprocess.run(
            ["magick", art, "-format", f"%[pixel:p{{%[fx:int(w*{sample_pct})],%[fx:int(h*0.12)]}}]", "info:"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        cx, cy = int(aw * trim), int(ah * trim)
        cw, ch = aw - 2 * cx, ah - cy - int(ah * (trim + bottom_extra))
        inner = os.path.join(tmp, "inner.png")
        magick(art, "-crop", f"{cw}x{ch}+{cx}+{cy}", "+repage", f"PNG32:{inner}")
        fit = int(side * (0.86 if style == "round-card" else 0.90))
        magick("-size", f"{side}x{side}", f"xc:{bg}",
               "(", inner, "-resize", f"{fit}x{fit}", ")", "-gravity", "center", "-composite", f"PNG32:{face}")
    else:
        glyph = int(side * 0.66)
        magick("-size", f"{side}x{side}", "gradient:#ffffff-#e9e9ee",
               "(", art, "-resize", f"{glyph}x{glyph}", ")", "-gravity", "center", "-composite", f"PNG32:{face}")

    shadow = os.path.join(tmp, "shadow.png")
    zoom = os.path.join(APPS, "Zoom.svg")
    magick("-background", "none", "-density", 600, zoom, "-resize", f"{SIZE}x{SIZE}", "-fill", "black",
           "-colorize", "100", "-colorspace", "sRGB", f"PNG32:{shadow}")
    mask = os.path.join(tmp, "mask.png")
    magick("-size", f"{SIZE}x{SIZE}", "xc:black", "-fill", "white",
           "-draw", f"roundrectangle {TILE0},{TILE0} {TILE1},{TILE1} {RADIUS},{RADIUS}", mask)
    placed = os.path.join(tmp, "placed.png")
    magick("-size", f"{SIZE}x{SIZE}", "xc:none", face, "-geometry", f"+{TILE0}+{TILE0}", "-composite",
           mask, "-alpha", "off", "-compose", "CopyOpacity", "-composite", "-type", "TrueColorAlpha", f"PNG32:{placed}")
    # the all-black shadow is read back as Gray; keep sRGB or the composite comes out greyscale
    magick(shadow, placed, "-colorspace", "sRGB", "-composite", f"PNG32:{out_png}")


def write_svg(png, path):
    data = base64.b64encode(open(png, "rb").read()).decode()
    with open(path, "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
                f'width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}"><!-- {MARK} -->'
                f'<image width="{SIZE}" height="{SIZE}" xlink:href="data:image/png;base64,{data}"/></svg>\n')


def set_icon(entry, icon):
    path = os.path.join(LOCAL_APPS, entry)
    if not os.path.exists(path):
        sys_path = os.path.join("/usr/share/applications", entry)
        if not os.path.exists(sys_path):
            return
        os.makedirs(LOCAL_APPS, exist_ok=True)
        text = open(sys_path).read()
    else:
        text = open(path).read()
    new, n = re.subn(r"(?m)^Icon=.*$", f"Icon={icon}", text, count=1)
    if n == 0:
        new = text.replace("[Desktop Entry]\n", f"[Desktop Entry]\nIcon={icon}\n", 1)
    if not os.path.exists(path) or new != text:
        open(path, "w").write(new)
        print(f"  {entry}: Icon={icon}")


def main():
    if not os.path.isfile(os.path.join(APPS, "Zoom.svg")):
        sys.exit("MacTahoe icons are not installed (run scripts/install-macos-theme.sh first).")

    for name, target in ALIASES.items():
        link = os.path.join(APPS, f"{name}.svg")
        if not os.path.exists(os.path.join(APPS, f"{target}.svg")) or not ours(link):
            continue
        if os.path.lexists(link):
            os.remove(link)
        source = open(os.path.realpath(os.path.join(APPS, f"{target}.svg"))).read()
        # A few upstream icons carry an invisible element squashed to zero width (transform="matrix(0 0 0 …)");
        # Qt warns "requested buffer size is too big" every time it draws one. Write a copy without it.
        cleaned = re.sub(r'<[a-z]+\b[^<>]*transform="matrix\(0 0 0 [^"]*"[^<>]*/>', "", source)
        if cleaned != source:
            with open(link, "w") as f:
                f.write(cleaned.replace(">", f"><!-- {MARK} -->", 1))
            print(f"  {name} -> {target} (cleaned copy)")
            continue
        os.symlink(f"{target}.svg", link)
        print(f"  {name} -> {target}")

    with tempfile.TemporaryDirectory(prefix="silky-icons.") as tmp:
        for name, (source, style) in BRANDS.items():
            out = os.path.join(APPS, f"{name}.svg")
            src = vendor_icon(source)
            if not src or not ours(out):
                continue
            png = os.path.join(tmp, "out.png")
            build(src, style, png, tmp)
            if os.path.lexists(out):
                os.remove(out)
            write_svg(png, out)
            print(f"  {name}: retiled from {src}")

    for entry, icon in ENTRIES.items():
        set_icon(entry, icon)

    for theme in ("MacTahoe", "MacTahoe-dark", "MacTahoe-light"):
        subprocess.run(["gtk-update-icon-cache", "-q", "-f", os.path.join(ICONS, theme)],
                       stderr=subprocess.DEVNULL, check=False)
    subprocess.run(["update-desktop-database", LOCAL_APPS], stderr=subprocess.DEVNULL, check=False)


if __name__ == "__main__":
    main()
