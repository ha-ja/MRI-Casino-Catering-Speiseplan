#!/usr/bin/env bash
set -euo pipefail

URL="https://casinocatering.de/speiseplan/"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage:
  ./speiseplan.sh          Zeigt den kompletten Speiseplan
  ./speiseplan.sh today    Zeigt nur den heutigen Tag
  ./speiseplan.sh --plain  Ohne Farben

Benötigt:
  curl
  python3
EOF
  exit 0
fi

command -v curl >/dev/null || { echo "Fehler: curl fehlt." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Fehler: python3 fehlt." >&2; exit 1; }

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

curl -fsSL --compressed \
  -A "Mozilla/5.0 (speiseplan-terminal)" \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
  "$URL" \
  -o "$TMP_FILE"

python3 - "$@" "$TMP_FILE" <<'PY'
import sys
import re
import os
import datetime as dt
from pathlib import Path
from html import unescape
from html.parser import HTMLParser

args = sys.argv[1:-1]
html_file = Path(sys.argv[-1])

show_today = "today" in args or "--today" in args or "-t" in args
plain = "--plain" in args or not sys.stdout.isatty() or os.getenv("NO_COLOR") is not None

class TextExtractor(HTMLParser):
    BLOCK_TAGS = {
        "p", "div", "section", "article", "main",
        "br", "li", "ul", "ol",
        "h1", "h2", "h3", "h4", "h5", "h6"
    }

    def __init__(self):
        super().__init__()
        self.parts = []
        self.skip_depth = 0

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()

        if tag in {"script", "style", "noscript"}:
            self.skip_depth += 1
            return

        if self.skip_depth == 0 and tag in self.BLOCK_TAGS:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        tag = tag.lower()

        if tag in {"script", "style", "noscript"} and self.skip_depth > 0:
            self.skip_depth -= 1
            return

        if self.skip_depth == 0 and tag in self.BLOCK_TAGS:
            self.parts.append("\n")

    def handle_data(self, data):
        if self.skip_depth == 0:
            self.parts.append(data)

def clean_lines(html: str) -> list[str]:
    parser = TextExtractor()
    parser.feed(html)

    text = unescape("".join(parser.parts))
    text = text.replace("\xa0", " ")

    lines = []
    for line in text.splitlines():
        line = re.sub(r"\s+", " ", line).strip()
        if line:
            lines.append(line)

    return lines

def color(text, code):
    if plain:
        return text
    return f"\033[{code}m{text}\033[0m"

def parse_german_date(header: str):
    months = {
        "januar": 1,
        "februar": 2,
        "märz": 3,
        "maerz": 3,
        "april": 4,
        "mai": 5,
        "juni": 6,
        "juli": 7,
        "august": 8,
        "september": 9,
        "oktober": 10,
        "november": 11,
        "dezember": 12,
    }

    match = re.search(
        r"(\d{1,2}),\s*([A-Za-zÄÖÜäöüß]+),\s*(\d{4})",
        header
    )

    if not match:
        return None

    day = int(match.group(1))
    month_name = match.group(2).lower()
    year = int(match.group(3))

    month = months.get(month_name)
    if month is None:
        return None

    return dt.date(year, month, day)

html = html_file.read_text(encoding="utf-8", errors="replace")
lines = clean_lines(html)

start = None
for i, line in enumerate(lines):
    if "Diese Woche" in line:
        start = i
        break

if start is None:
    print("Konnte den Speiseplan auf der Seite nicht finden.", file=sys.stderr)
    sys.exit(2)

stop = len(lines)
for i in range(start, len(lines)):
    if (
        "Änderungen im Speiseplan" in lines[i]
        or "Zu weiteren Fragen" in lines[i]
        or lines[i] == "Casino Catering"
    ):
        stop = i
        break

content = lines[start:stop]

day_pattern = re.compile(
    r"^(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag)\b.*\b20\d{2}$"
)

intro = []
sections = []
current = None

for line in content:
    if day_pattern.match(line):
        current = {
            "header": line,
            "items": []
        }
        sections.append(current)
    elif current is None:
        intro.append(line)
    else:
        current["items"].append(line)

if show_today:
    today = dt.date.today()
    sections = [
        section for section in sections
        if parse_german_date(section["header"]) == today
    ]

    if not sections:
        print(color("Für heute wurde kein Eintrag auf der Seite gefunden.", "33;1"))
        sys.exit(1)

print(color("Casino Catering – Speiseplan", "1;36"))
print()

for line in intro:
    print(color(line, "2"))

if intro:
    print()

for section in sections:
    print(color(section["header"], "1;34"))

    if not section["items"]:
        print("  - Keine Gerichte gefunden.")
    else:
        for item in section["items"]:
            item = re.sub(r"^[•\-\*\s]+", "", item).strip()
            print(f"  • {item}")

    print()
PY
