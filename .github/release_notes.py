"""Builds the GitHub release notes for one version from CHANGELOG.md.

Usage: python3 .github/release_notes.py 2.0.0 > notes.md
"""
import re
import sys

REPO = "Vega421/tobs_bankrobbery"
ZIP = "tobs_bankrobbery-v{version}.zip"
DOCS = "https://vega421.github.io/scripts/tobs-bankrobbery/"

version = sys.argv[1].lstrip("v")
changelog = open("CHANGELOG.md", encoding="utf-8").read()
match = re.search(r"^## v?" + re.escape(version) + r"\b.*?\n(.*?)(?=^## |\Z)", changelog, re.S | re.M)
changes = match.group(1).strip() if match else "See the [changelog](https://github.com/{}/blob/main/CHANGELOG.md).".format(REPO)

print(f"""## What's new

{changes}

## Install

1. Download **`{ZIP.format(version=version)}`** below.
2. Delete your old `tobs_bankrobbery` (or `tobs_blaine`) folder, then unzip this one into `resources/`.
3. Add the items for your inventory from the `install/` folder.
4. Add `ensure tobs_bankrobbery` to `server.cfg` below your framework.

**Works with:** Qbox · ESX · QBCore (detected automatically) · [ox_lib](https://github.com/overextended/ox_lib) (recommended) · [ox_target](https://github.com/overextended/ox_target) (optional)

---

📖 [Documentation]({DOCS}) · 📝 [Full changelog](https://github.com/{REPO}/blob/main/CHANGELOG.md) · 🐛 [Report a problem](https://github.com/{REPO}/issues)""")
