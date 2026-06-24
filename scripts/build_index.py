"""Build a PEP 503 simple index from GitHub Releases of a private repo.

Usage:
    GH_TOKEN=ghp_xxx python build_index.py \\
        --repo Kyle-J-Sun/SuperModelingFactory_protected \\
        --package supermodelingfactory \\
        --output-dir simple
"""

from __future__ import annotations

import argparse
import hashlib
import html
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

GITHUB_API = "https://api.github.com"


def gh_get(url: str, token: str) -> list | dict:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "smf-index-builder",
        },
    )
    with urllib.request.urlopen(req) as resp:
        import json
        return json.loads(resp.read())


def list_release_assets(repo: str, token: str) -> list[dict]:
    """Return all wheel and sdist assets across all releases of `repo`."""
    assets: list[dict] = []
    page = 1
    while True:
        releases = gh_get(f"{GITHUB_API}/repos/{repo}/releases?per_page=100&page={page}", token)
        if not releases:
            break
        for rel in releases:
            if rel.get("draft") or rel.get("prerelease"):
                continue
            for asset in rel.get("assets", []):
                name = asset["name"]
                if name.endswith((".whl", ".tar.gz")):
                    assets.append({
                        "name": name,
                        "url": asset["browser_download_url"],
                        "size": asset["size"],
                        "release_tag": rel["tag_name"],
                    })
        page += 1
    return assets


PEP503_INDEX_TEMPLATE = """<!DOCTYPE html>
<html>
<head>
  <meta name="pypi:repository-version" content="1.0">
  <title>Simple index</title>
</head>
<body>
  <h1>Simple index</h1>
{links}
</body>
</html>
"""

PEP503_PROJECT_TEMPLATE = """<!DOCTYPE html>
<html>
<head>
  <meta name="pypi:repository-version" content="1.0">
  <title>Links for {package}</title>
</head>
<body>
  <h1>Links for {package}</h1>
{links}
</body>
</html>
"""


def normalize(name: str) -> str:
    """PEP 503 normalization."""
    import re
    return re.sub(r"[-_.]+", "-", name).lower()


def build(repo: str, package: str, output_dir: Path, token: str) -> None:
    assets = list_release_assets(repo, token)
    if not assets:
        print(f"[warn] no wheel/sdist assets found in {repo}", file=sys.stderr)

    norm_pkg = normalize(package)
    pkg_dir = output_dir / norm_pkg
    pkg_dir.mkdir(parents=True, exist_ok=True)

    # Project page: simple/<package>/index.html
    asset_links = []
    for asset in sorted(assets, key=lambda a: a["name"]):
        href = html.escape(asset["url"], quote=True)
        text = html.escape(asset["name"])
        asset_links.append(f'    <a href="{href}">{text}</a><br>')

    (pkg_dir / "index.html").write_text(
        PEP503_PROJECT_TEMPLATE.format(
            package=html.escape(package),
            links="\n".join(asset_links),
        ),
        encoding="utf-8",
    )

    # Root: simple/index.html listing the package
    (output_dir / "index.html").write_text(
        PEP503_INDEX_TEMPLATE.format(
            links=f'    <a href="{norm_pkg}/">{html.escape(package)}</a><br>',
        ),
        encoding="utf-8",
    )

    print(f"[ok] wrote index for {len(assets)} asset(s) to {output_dir}/")
    for a in assets:
        print(f"  - {a['name']} ({a['release_tag']})")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, help="owner/repo of the private wheel source")
    ap.add_argument("--package", required=True, help="PyPI-style package name")
    ap.add_argument("--output-dir", default="simple", type=Path)
    args = ap.parse_args()

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        print("error: GH_TOKEN (or GITHUB_TOKEN) env var required", file=sys.stderr)
        return 2

    build(args.repo, args.package, args.output_dir, token)
    return 0


if __name__ == "__main__":
    sys.exit(main())
