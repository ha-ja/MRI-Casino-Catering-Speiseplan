# MRI Casino Catering – Speiseplan

Fetches the current meal plan from [casinocatering.de](https://casinocatering.de/speiseplan/) and prints it to the terminal.

## Usage

```bash
bin/speiseplan.sh          # Full week
bin/speiseplan.sh today    # Today only
bin/speiseplan.sh --plain  # No colors
```

**Requirements:** `curl`, `python3`

## CI

GitHub Actions runs the script automatically every weekday at 09:00 UTC (11:00 Berlin time).
