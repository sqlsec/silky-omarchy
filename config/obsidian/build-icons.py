#!/usr/bin/env python3
"""Regenerate the file-explorer icon block of the Silky macOS Obsidian theme.

The icons are drawn here as small SVGs (no third-party artwork) and embedded as data URIs between the
`@silky-icons-start` / `@silky-icons-end` markers in theme.css, so the theme stays a single file.

    python3 config/obsidian/build-icons.py
"""
from pathlib import Path
from urllib.parse import quote

THEME = Path(__file__).resolve().parent / "themes" / "Silky macOS" / "theme.css"
START, END = "/* @silky-icons-start */", "/* @silky-icons-end */"

FONT = "font-family='Inter,-apple-system,sans-serif' font-weight='800' text-anchor='middle'"


def svg(body: str, defs: str = "") -> str:
    return f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><defs>{defs}</defs>{body}</svg>"


def uri(markup: str) -> str:
    return 'url("data:image/svg+xml,' + quote(markup, safe=" =:/'(),;-.") + '")'


# ── Finder folder ──────────────────────────────────────────────────────────────
FOLDER_DEFS = (
    "<linearGradient id='b' x1='0' y1='0' x2='0' y2='1'>"
    "<stop offset='0' stop-color='#4fb2f5'/><stop offset='1' stop-color='#1e8fe6'/></linearGradient>"
    "<linearGradient id='f' x1='0' y1='0' x2='0' y2='1'>"
    "<stop offset='0' stop-color='#8ad2ff'/><stop offset='1' stop-color='#4cb3f7'/></linearGradient>"
)
FOLDER_BACK = (
    "<path d='M3 8.2A2.7 2.7 0 0 1 5.7 5.5h6.6c.8 0 1.5.3 2 .9l1.5 1.7h10.5A2.7 2.7 0 0 1 29 10.8V24H3z' fill='url(#b)'/>"
)
FOLDER = svg(
    FOLDER_BACK
    + "<rect x='3' y='10.5' width='26' height='17' rx='2.6' fill='url(#f)'/>"
    + "<path d='M5.6 11.3h20.8' stroke='#fff' stroke-opacity='.55' stroke-width='.9' stroke-linecap='round'/>",
    FOLDER_DEFS,
)
FOLDER_OPEN = svg(
    FOLDER_BACK
    + "<rect x='6' y='9' width='20' height='10' rx='1.2' fill='#fff' fill-opacity='.92'/>"
    + "<path d='M2.4 14.6a2.4 2.4 0 0 1 2.4-2.6h22.4a2.4 2.4 0 0 1 2.4 2.6l-1 10.5a2.6 2.6 0 0 1-2.6 2.4H6a2.6 2.6 0 0 1-2.6-2.4z' fill='url(#f)'/>",
    FOLDER_DEFS,
)

# ── Documents ──────────────────────────────────────────────────────────────────
PAGE = (
    "<path d='M8 3h11.5L27 10.5V27a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z' fill='{fill}' "
    "stroke='{stroke}' stroke-width='.8'/>"
    "<path d='M19.5 3v5.5a2 2 0 0 0 2 2H27' fill='{fold}' stroke='{stroke}' stroke-width='.8' stroke-linejoin='round'/>"
)


def page(inner: str, fill="#ffffff", fold="#e3e3e8", stroke="#b8b8c0") -> str:
    return svg(PAGE.format(fill=fill, fold=fold, stroke=stroke) + inner)


def lines(color="#c7c7cc", top=13, widths=(14, 14, 11, 14, 8)) -> str:
    return "".join(
        f"<rect x='9.5' y='{top + i * 3}' width='{w}' height='1.3' rx='.65' fill='{color}'/>"
        for i, w in enumerate(widths)
    )


def band(label: str, color: str) -> str:
    return (
        f"<rect x='6' y='18' width='21' height='8.5' fill='{color}'/>"
        f"<text x='16.5' y='24.6' font-size='6.6' fill='#fff' {FONT}>{label}</text>"
    )


def code(glyph_color: str, label: str = "") -> str:
    glyph = (
        f"<path d='M13.5 14.5l-3.5 3.5 3.5 3.5M19.5 14.5l3.5 3.5-3.5 3.5' fill='none' stroke='{glyph_color}' "
        "stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/>"
    )
    if label:
        glyph = (
            f"<text x='16.5' y='21.5' font-size='{7 if len(label) < 3 else 5.6}' fill='{glyph_color}' {FONT}>{label}</text>"
        )
    return page(
        "<circle cx='10' cy='7' r='1' fill='#ff5f57'/><circle cx='13' cy='7' r='1' fill='#febc2e'/>"
        "<circle cx='16' cy='7' r='1' fill='#28c840'/>" + glyph,
        fill="#2a2a30",
        fold="#44444c",
        stroke="#18181c",
    )


ICONS = {
    "doc": page(lines()),
    "md": page(
        "<rect x='9.5' y='12' width='9' height='2' rx='1' fill='#0a84ff'/>" + lines(top=16.5, widths=(14, 11, 14, 8))
    ),
    "txt": page(lines("#aeaeb2")),
    "canvas": page(
        "<path d='M12 15.5L20.5 14M12 15.5l6 7.5' stroke='#ff9f0a' stroke-width='1.2'/>"
        "<rect x='9' y='13' width='6' height='5' rx='1.3' fill='#ff9f0a'/>"
        "<rect x='18' y='11.5' width='6' height='5' rx='1.3' fill='#ffb340'/>"
        "<rect x='15.5' y='20.5' width='6' height='5' rx='1.3' fill='#ff9500'/>"
    ),
    "base": page(
        "<rect x='9' y='12' width='15' height='13' rx='1.8' fill='#30b0c7'/>"
        "<path d='M9 16.3h15M9 20.6h15M14 12v13M19 12v13' stroke='#fff' stroke-width='.9'/>"
    ),
    "pdf": page(lines() + band("PDF", "#ff3b30")),
    "word": page(lines() + band("DOC", "#2b6cde")),
    "sheet": page(
        "<rect x='9' y='12' width='15' height='13' rx='1.5' fill='#34c759'/>"
        "<path d='M9 15.3h15M9 18.6h15M9 21.9h15M14 12v13M19 12v13' stroke='#fff' stroke-width='.8'/>"
    ),
    "slides": page(
        "<rect x='9' y='12' width='15' height='9' rx='1.3' fill='#ff9500'/>"
        "<path d='M14.5 14.3v4.4l3.8-2.2z' fill='#fff'/><rect x='12' y='23' width='9' height='1.4' rx='.7' fill='#c7c7cc'/>"
    ),
    "image": page(
        "<rect x='8.5' y='12' width='16' height='13' rx='1.8' fill='#64d2ff'/>"
        "<circle cx='20.5' cy='15.5' r='1.7' fill='#ffd60a'/>"
        "<path d='M8.5 22.5l5-5.5 4 4 2.5-2.3 4.5 4.3v.2a1.8 1.8 0 0 1-1.8 1.8H10.3a1.8 1.8 0 0 1-1.8-1.8z' fill='#30d158'/>"
    ),
    "svg": page(
        "<path d='M10 22.5c3-9 9.5-9 13 0' fill='none' stroke='#ff9f0a' stroke-width='1.6'/>"
        "<rect x='8.5' y='21' width='3' height='3' fill='#fff' stroke='#636366' stroke-width='.8'/>"
        "<rect x='21.5' y='21' width='3' height='3' fill='#fff' stroke='#636366' stroke-width='.8'/>"
        "<rect x='15' y='13' width='3' height='3' fill='#fff' stroke='#636366' stroke-width='.8'/>"
    ),
    "audio": page(
        "<circle cx='16.5' cy='18.5' r='6.5' fill='#ff375f'/>"
        "<path d='M15.5 21.2V15l4-1v5.2' fill='none' stroke='#fff' stroke-width='1.3'/>"
        "<circle cx='14.4' cy='21.3' r='1.4' fill='#fff'/><circle cx='18.4' cy='20.3' r='1.4' fill='#fff'/>"
    ),
    "video": page(
        "<rect x='8.5' y='12.5' width='16' height='12' rx='2' fill='#bf5af2'/>"
        "<path d='M14.5 15.5v6l5-3z' fill='#fff'/>"
    ),
    "archive": page(
        "<path d='M16.5 3v14' stroke='#8e8e93' stroke-width='3' stroke-dasharray='1.5 1.5'/>"
        "<rect x='14' y='17' width='5' height='7' rx='1.2' fill='#8e8e93'/>"
        "<rect x='15.4' y='19.5' width='2.2' height='2.6' rx='.5' fill='#fff'/>"
    ),
    "web": page(
        "<circle cx='16.5' cy='18.5' r='6.5' fill='none' stroke='#0a84ff' stroke-width='1.3'/>"
        "<ellipse cx='16.5' cy='18.5' rx='2.8' ry='6.5' fill='none' stroke='#0a84ff' stroke-width='1.1'/>"
        "<path d='M10 18.5h13' stroke='#0a84ff' stroke-width='1.1'/>"
    ),
    "code": code("#67b7a4"),
    "js": code("#ffd60a", "JS"),
    "ts": code("#5ea8ff", "TS"),
    "py": code("#ffd43b", "PY"),
    "sh": code("#30d158", "$_"),
    "json": code("#ff9f0a", "{ }"),
    "css": code("#bf5af2", "#"),
    "html": code("#ff7a45"),
    "lua": code("#6b8cff", "LUA"),
    "yaml": code("#ff7ab2", "YML"),
    "rs": code("#ff9f6b", "RS"),
    "go": code("#64d2ff", "GO"),
    "c": code("#a1c4ff", "C"),
}

EXTENSIONS = {
    "md": ["md", "markdown"],
    "txt": ["txt", "log", "rtf"],
    "canvas": ["canvas"],
    "base": ["base"],
    "pdf": ["pdf"],
    "word": ["doc", "docx", "odt", "pages", "wps"],
    "sheet": ["xls", "xlsx", "csv", "tsv", "ods", "numbers", "et"],
    "slides": ["ppt", "pptx", "odp", "key", "dps"],
    "image": ["png", "jpg", "jpeg", "gif", "webp", "avif", "bmp", "heic", "tif", "tiff"],
    "svg": ["svg"],
    "audio": ["mp3", "wav", "m4a", "flac", "ogg", "aac", "webm"],
    "video": ["mp4", "mov", "mkv", "avi", "ogv"],
    "archive": ["zip", "7z", "rar", "tar", "gz", "tgz", "xz", "bz2", "zst"],
    "web": ["url", "webloc"],
    "html": ["html", "htm", "xml"],
    "js": ["js", "mjs", "cjs", "jsx"],
    "ts": ["ts", "tsx"],
    "py": ["py", "ipynb"],
    "sh": ["sh", "bash", "zsh", "fish", "ps1"],
    "json": ["json", "jsonc", "toml", "ini", "conf"],
    "css": ["css", "scss", "less"],
    "lua": ["lua"],
    "yaml": ["yml", "yaml"],
    "rs": ["rs"],
    "go": ["go"],
    "c": ["c", "h", "cpp", "hpp", "cc", "java", "kt", "swift"],
    "code": ["sql", "rb", "php", "qml", "vue", "svelte", "dart", "diff", "patch"],
}


def build() -> str:
    out = [START, "body {"]
    out.append(f"  --silky-icon-folder: {uri(FOLDER)};")
    out.append(f"  --silky-icon-folder-open: {uri(FOLDER_OPEN)};")
    for name, markup in ICONS.items():
        out.append(f"  --silky-icon-{name}: {uri(markup)};")
    out.append("}\n")
    for name, exts in EXTENSIONS.items():
        selectors = ",\n".join(
            f'.nav-file-title[data-path$=".{ext}" i] .nav-file-title-content::before' for ext in exts
        )
        out.append(f"{selectors} {{\n  background-image: var(--silky-icon-{name});\n}}\n")
    out.append(END)
    return "\n".join(out)


def main() -> None:
    css = THEME.read_text()
    head, rest = css.split(START, 1)
    _, tail = rest.split(END, 1)
    THEME.write_text(head + build() + tail)
    print(f"icons written to {THEME}")


if __name__ == "__main__":
    main()
