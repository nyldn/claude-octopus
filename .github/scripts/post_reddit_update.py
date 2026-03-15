#!/usr/bin/env python3
"""
Post a human-sounding community update to r/ClaudeOctopus.

Works in two modes:
  1. GitHub Actions: uses REDDIT_CLIENT_ID/SECRET/REFRESH_TOKEN env vars
  2. Local: uses devvit auth token from ~/.devvit/token

Environment variables (for GitHub Actions):
  REDDIT_CLIENT_ID      - Reddit app client ID
  REDDIT_CLIENT_SECRET  - Reddit app client secret
  REDDIT_REFRESH_TOKEN  - Reddit OAuth refresh token for u/nyldn
  RELEASE_TAG           - Git tag for the release (e.g. v8.25.0)
  RELEASE_BODY          - Release notes body from GitHub
  INPUT_TITLE           - Custom title override
  INPUT_MESSAGE         - Custom message override

Usage:
  python3 post_reddit_update.py                    # Auto-detect from git
  python3 post_reddit_update.py --dry-run          # Preview only
  python3 post_reddit_update.py --version v8.25.0  # Specific version
"""

import argparse
import json
import base64
import os
import re
import subprocess
import sys

import requests

SUBREDDIT = "ClaudeOctopus"


# --- Auth ---

def get_access_token_ci():
    """Get access token via Reddit OAuth (for CI)."""
    client_id = os.environ["REDDIT_CLIENT_ID"]
    client_secret = os.environ["REDDIT_CLIENT_SECRET"]
    refresh_token = os.environ["REDDIT_REFRESH_TOKEN"]

    resp = requests.post(
        "https://www.reddit.com/api/v1/access_token",
        auth=(client_id, client_secret),
        data={"grant_type": "refresh_token", "refresh_token": refresh_token},
        headers={"User-Agent": "ClaudeOctopusUpdater/1.0 by nyldn"},
    )
    resp.raise_for_status()
    return resp.json()["access_token"]


def get_access_token_local():
    """Get access token from devvit auth (for local use)."""
    token_path = os.path.expanduser("~/.devvit/token")
    with open(token_path) as f:
        token_data = json.loads(f.read())
    raw = token_data["token"]
    raw += "=" * (4 - len(raw) % 4)
    decoded = json.loads(base64.b64decode(raw))
    return decoded["accessToken"]


def get_access_token():
    """Get access token from CI env or local devvit auth."""
    if os.environ.get("REDDIT_CLIENT_ID"):
        return get_access_token_ci()
    return get_access_token_local()


# --- Change detection ---

def get_recent_commits(limit=20):
    """Get recent commit messages."""
    result = subprocess.run(
        ["git", "log", f"--max-count={limit}", "--pretty=format:%s"],
        capture_output=True, text=True,
    )
    if result.returncode == 0:
        return [l for l in result.stdout.strip().split("\n") if l]
    return []


def get_changelog_entry(version=None):
    """Extract a changelog entry."""
    for path in ["CHANGELOG.md", "plugin/CHANGELOG.md"]:
        if os.path.exists(path):
            with open(path) as f:
                content = f.read()
            if version:
                pattern = rf"(## \[?{re.escape(version)}\]?.*?)(?=\n## |\Z)"
            else:
                pattern = r"(## \[?\d+\.\d+\.\d+\]?.*?)(?=\n## |\Z)"
            match = re.search(pattern, content, re.DOTALL)
            if match:
                return match.group(1).strip()
    return None


def categorize_changes(commits):
    """Group commits into human-friendly categories."""
    cats = {"new": [], "improved": [], "fixed": [], "other": []}
    for msg in commits:
        lower = msg.lower()
        if any(w in lower for w in ["add", "new", "create", "introduce", "implement"]):
            cats["new"].append(msg)
        elif any(w in lower for w in ["fix", "bug", "patch", "resolve"]):
            cats["fixed"].append(msg)
        elif any(w in lower for w in ["improve", "update", "enhance", "refactor", "optimize"]):
            cats["improved"].append(msg)
        else:
            cats["other"].append(msg)
    return cats


# --- Post generation ---

def clean_commit_msg(msg, prefixes):
    """Strip conventional commit prefixes for readability."""
    cleaned = re.sub(
        r"^(" + "|".join(prefixes) + r")[\(:]?\s*",
        "", msg, flags=re.IGNORECASE,
    ).strip()
    # Capitalize first letter
    if cleaned:
        cleaned = cleaned[0].upper() + cleaned[1:]
    return cleaned.rstrip(".")


def generate_post(version=None):
    """Generate a conversational Reddit post from changes."""
    release_body = os.environ.get("RELEASE_BODY", "")
    custom_message = os.environ.get("INPUT_MESSAGE", "")
    custom_title = os.environ.get("INPUT_TITLE", "")

    if custom_message:
        return {
            "title": custom_title or "Update from the team",
            "body": custom_message,
        }

    changelog = get_changelog_entry(version)
    commits = get_recent_commits(30)
    categories = categorize_changes(commits)
    display_version = version or "latest"

    title = custom_title or f"What's new in {display_version}"

    lines = []
    lines.append("Hey everyone,\n")

    if version:
        lines.append(f"Just shipped **{display_version}** — here's what's in it.\n")
    else:
        lines.append("Quick update on what we've been working on.\n")

    if categories["new"]:
        lines.append("**New stuff:**\n")
        for item in categories["new"][:5]:
            clean = clean_commit_msg(item, ["feat", "add", "new", "create"])
            lines.append(f"- {clean}")
        lines.append("")

    if categories["improved"]:
        lines.append("**Improvements:**\n")
        for item in categories["improved"][:5]:
            clean = clean_commit_msg(item, ["improve", "update", "enhance", "refactor", "optimize"])
            lines.append(f"- {clean}")
        lines.append("")

    if categories["fixed"]:
        lines.append("**Fixes:**\n")
        for item in categories["fixed"][:5]:
            clean = clean_commit_msg(item, ["fix", "bug", "patch", "resolve"])
            lines.append(f"- {clean}")
        lines.append("")

    # If release body exists from GitHub, include it
    if release_body:
        lines.append("---\n")
        lines.append("<details><summary>Full release notes</summary>\n")
        lines.append(release_body)
        lines.append("\n</details>\n")
    elif changelog:
        lines.append("---\n")
        lines.append("<details><summary>Full changelog</summary>\n")
        lines.append(changelog)
        lines.append("\n</details>\n")

    lines.append("---\n")
    lines.append("Update with:\n")
    lines.append("```")
    lines.append("/plugin update octo@nyldn-plugins")
    lines.append("```\n")
    lines.append(
        "Questions, bugs, ideas? Drop them below or "
        "[open an issue](https://github.com/nyldn/claude-octopus/issues).\n"
    )
    lines.append("\u2014 nyldn")

    return {"title": title, "body": "\n".join(lines)}


# --- Reddit API ---

def post_to_reddit(title, body, dry_run=False):
    """Submit a post to r/ClaudeOctopus."""
    if dry_run:
        print("=" * 60)
        print("DRY RUN \u2014 would post:\n")
        print(f"Title: {title}")
        print(f"Subreddit: r/{SUBREDDIT}")
        print(f"\n{body}")
        print("=" * 60)
        return

    access_token = get_access_token()
    headers = {
        "Authorization": f"Bearer {access_token}",
        "User-Agent": "ClaudeOctopusUpdater/1.0 by nyldn",
    }

    resp = requests.post(
        "https://oauth.reddit.com/api/submit",
        headers=headers,
        data={
            "sr": SUBREDDIT,
            "api_type": "json",
            "kind": "self",
            "title": title,
            "text": body,
            "sendreplies": True,
        },
    )

    if resp.status_code != 200:
        print(f"Failed: {resp.status_code} - {resp.text[:300]}")
        sys.exit(1)

    result = resp.json()
    errors = result.get("json", {}).get("errors", [])
    if errors:
        print(f"Reddit API errors: {errors}")
        sys.exit(1)

    post_url = result.get("json", {}).get("data", {}).get("url", "")
    thing_name = result.get("json", {}).get("data", {}).get("name", "")
    print(f"Posted: {post_url}")

    # Set Announcement flair
    if thing_name:
        requests.post(
            f"https://oauth.reddit.com/r/{SUBREDDIT}/api/selectflair",
            headers=headers,
            data={"api_type": "json", "link": thing_name, "text": "Announcement"},
        )
        print("Flair set: Announcement")


def is_major_release(version):
    """Only post to Reddit for major/minor releases (X.Y.0), not patches (X.Y.Z where Z>0)."""
    if not version:
        return True  # No version specified — let it through
    clean = version.lstrip("v")
    parts = clean.split(".")
    if len(parts) >= 3:
        try:
            patch = int(parts[2])
            return patch == 0
        except ValueError:
            return True
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--version", default=os.environ.get("RELEASE_TAG", ""))
    parser.add_argument("--title-override", action="store_true")
    parser.add_argument("--force", action="store_true", help="Post even for patch releases")
    args = parser.parse_args()

    version = args.version or None

    if version and not args.force and not is_major_release(version):
        print(f"Skipping Reddit post for patch release {version} (use --force to override)")
        return

    post = generate_post(version=version)
    post_to_reddit(post["title"], post["body"], dry_run=args.dry_run)


if __name__ == "__main__":
    main()
