#!/usr/bin/env python3
"""
SwarmCLI version bump script.

Reads the current version from version.txt and updates all references
across the project: shell scripts, README, CHANGELOG.

Note: In CI, release-please handles versioning automatically.
This script is a manual fallback for local use.

Usage:
    python scripts/bump-version.py patch          # 0.2.0 -> 0.2.1
    python scripts/bump-version.py minor          # 0.2.0 -> 0.3.0
    python scripts/bump-version.py major          # 0.2.0 -> 1.0.0
    python scripts/bump-version.py 1.5.0          # explicit version
    python scripts/bump-version.py --current      # show current version

Options:
    --no-changelog    Skip CHANGELOG.md update
    --tag             Create a git tag after bump
"""
import argparse
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VERSION_FILE = ROOT / "version.txt"

TARGETS = [
    {
        "file": "bin/swarm.sh",
        "pattern": r'(VERSION=")[^"]*(")',
        "replace": r"\g<1>{version}\2",
    },
    {
        "file": "install.sh",
        "pattern": r'(VERSION=")[^"]*(")',
        "replace": r"\g<1>{version}\2",
    },
    {
        "file": "uninstall.sh",
        "pattern": r'(VERSION=")[^"]*(")',
        "replace": r"\g<1>{version}\2",
    },
    {
        "file": "README.md",
        "pattern": r"(\*\*Current:\*\* )[0-9]+\.[0-9]+\.[0-9]+",
        "replace": r"\g<1>{version}",
    },
]

SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def read_current_version() -> str:
    return VERSION_FILE.read_text(encoding="utf-8").strip()


def parse_version(v: str) -> tuple[int, int, int]:
    m = SEMVER_RE.match(v)
    if not m:
        print(f"error: invalid version format: {v}", file=sys.stderr)
        sys.exit(1)
    return int(m.group(1)), int(m.group(2)), int(m.group(3))


def bump(current: str, part: str) -> str:
    major, minor, patch = parse_version(current)
    if part == "major":
        return f"{major + 1}.0.0"
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    if part == "patch":
        return f"{major}.{minor}.{patch + 1}"
    parse_version(part)
    return part


def update_file(rel_path: str, pattern: str, replacement: str, new_version: str) -> bool:
    path = ROOT / rel_path
    if not path.exists():
        print(f"  skip: {rel_path} (not found)")
        return False

    content = path.read_text(encoding="utf-8")
    updated = re.sub(pattern, replacement.format(version=new_version), content)

    if content == updated:
        print(f"  skip: {rel_path} (no match)")
        return False

    path.write_text(updated, encoding="utf-8")
    print(f"  done: {rel_path}")
    return True


def update_changelog(old_version: str, new_version: str, today: str) -> bool:
    path = ROOT / "CHANGELOG.md"
    if not path.exists():
        print("  skip: CHANGELOG.md (not found)")
        return False

    content = path.read_text(encoding="utf-8")

    unreleased_header = "## [Unreleased]"
    if unreleased_header not in content:
        print("  skip: CHANGELOG.md (no [Unreleased] section)")
        return False

    new_version_header = f"## [{new_version}] - {today}"

    # Insert new version header after [Unreleased]
    # If [Unreleased] has content, it becomes the new version's content
    content = content.replace(
        f"{unreleased_header}\n\n## [{old_version}]",
        f"{unreleased_header}\n\n{new_version_header}\n\n## [{old_version}]",
    )

    # If [Unreleased] has content between it and the old version
    if new_version_header not in content:
        content = content.replace(
            unreleased_header,
            f"{unreleased_header}\n\n{new_version_header}",
            1,
        )

    # Update links at the bottom
    repo_url = "https://github.com/KoninMikhail/swarmcli"

    old_unreleased_link = (
        f"[Unreleased]: {repo_url}/compare/v{old_version}...HEAD"
    )
    new_unreleased_link = (
        f"[Unreleased]: {repo_url}/compare/v{new_version}...HEAD"
    )
    new_version_link = (
        f"[{new_version}]: {repo_url}/compare/v{old_version}...v{new_version}"
    )

    if old_unreleased_link in content:
        content = content.replace(
            old_unreleased_link,
            f"{new_unreleased_link}\n{new_version_link}",
        )
    else:
        print("  warn: CHANGELOG.md — could not update comparison links")

    path.write_text(content, encoding="utf-8")
    print("  done: CHANGELOG.md")
    return True


def main():
    parser = argparse.ArgumentParser(description="Bump SwarmCLI version")
    parser.add_argument(
        "version",
        nargs="?",
        help="major | minor | patch | explicit (e.g. 1.5.0)",
    )
    parser.add_argument("--current", action="store_true", help="Show current version")
    parser.add_argument("--no-changelog", action="store_true", help="Skip CHANGELOG update")
    parser.add_argument("--tag", action="store_true", help="Create git tag")

    args = parser.parse_args()

    current = read_current_version()

    if args.current:
        print(current)
        return

    if not args.version:
        parser.print_help()
        sys.exit(1)

    new_version = bump(current, args.version)

    if new_version == current:
        print(f"version is already {current}")
        sys.exit(0)

    today = date.today().isoformat()

    print(f"\n  {current} -> {new_version}\n")

    # Update VERSION file
    VERSION_FILE.write_text(new_version + "\n", encoding="utf-8")
    print("  done: version.txt")

    # Update all target files
    for target in TARGETS:
        update_file(target["file"], target["pattern"], target["replace"], new_version)

    # Update CHANGELOG
    if not args.no_changelog:
        update_changelog(current, new_version, today)

    print(f"\n  version bumped to {new_version}")

    if args.tag:
        import subprocess

        tag = f"v{new_version}"
        subprocess.run(["git", "tag", "-a", tag, "-m", f"Release {tag}"], check=True, cwd=ROOT)
        print(f"  tag created: {tag}")

    print()


if __name__ == "__main__":
    main()
