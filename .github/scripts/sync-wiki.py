#!/usr/bin/env python3
"""
Sync docs/wiki/*.md from the main repository into the GitHub Wiki repo.

The GitHub Wiki is a separate git repository (<repo>.wiki.git) that only
contains Markdown pages - it has no access to sibling files in the main
repo. This script:

  1. Copies every top-level *.md file from docs/wiki/ into the wiki repo.
  2. Renames index.md -> Home.md (GitHub's wiki landing page).
  3. Rewrites relative links that point at files outside docs/wiki/
     (scripts, backend-service, custom-connector, SharedMailboxSkills)
     into absolute GitHub "blob" URLs on the main branch, since those
     files are not mirrored into the wiki repo.

Usage: sync-wiki.py <main_repo_path> <wiki_repo_path> <owner/repo>
"""
import re
import sys
from pathlib import Path

def main():
    if len(sys.argv) != 4:
        print("Usage: sync-wiki.py <main_repo_path> <wiki_repo_path> <owner/repo>")
        sys.exit(1)

    main_repo = Path(sys.argv[1])
    wiki_repo = Path(sys.argv[2])
    repo_full_name = sys.argv[3]

    src_dir = main_repo / "docs" / "wiki"
    base_blob_url = f"https://github.com/{repo_full_name}/blob/main/"

    if not src_dir.is_dir():
        print(f"Source directory not found: {src_dir}")
        sys.exit(1)

    wiki_repo.mkdir(parents=True, exist_ok=True)

    # Only top-level *.md files are wiki pages; docs/wiki/scripts/ stays in
    # the main repo and is linked to via absolute blob URLs instead.
    md_files = sorted(src_dir.glob("*.md"))
    if not md_files:
        print(f"No markdown files found in {src_dir}")
        sys.exit(1)

    for md_file in md_files:
        content = md_file.read_text(encoding="utf-8")

        # Links to docs/wiki/scripts/*.ps1 -> absolute blob URL
        content = re.sub(
            r"\]\(scripts/",
            f"]({base_blob_url}docs/wiki/scripts/",
            content,
        )
        # Links to repo-root-relative paths (../../backend-service/, etc.)
        # -> absolute blob URL
        content = re.sub(
            r"\]\(\.\./\.\./",
            f"]({base_blob_url}",
            content,
        )

        dest_name = "Home.md" if md_file.name == "index.md" else md_file.name
        dest_path = wiki_repo / dest_name
        dest_path.write_text(content, encoding="utf-8")
        print(f"Synced {md_file.relative_to(main_repo)} -> {dest_path.name}")

    print(f"Done. Synced {len(md_files)} page(s) to the wiki repo.")

if __name__ == "__main__":
    main()