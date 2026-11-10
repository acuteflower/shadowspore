#!/usr/bin/env python3
"""Publishes a GitHub Release for the current repository using credentials from git."""

import sys
import subprocess
import urllib.request
import json
from pathlib import Path

def get_git_token():
    try:
        p = subprocess.Popen(['git', 'credential', 'fill'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        out, _ = p.communicate('url=https://github.com/acuteflower/shadowspore.git\n')
        for line in out.splitlines():
            if line.startswith('password='):
                return line.split('=', 1)[1]
    except Exception as e:
        print(f"Error fetching token from git credential helper: {e}", file=sys.stderr)
    return None

def format_release_body(body_text: str, repo: str = "acuteflower/shadowspore", branch: str = "main") -> str:
    """Ensures images are properly formatted as markdown image tags with absolute GitHub raw URLs."""
    import re
    # 1. Transform bare image URLs on their own line into markdown image embeds:
    # e.g. https://raw.githubusercontent.com/.../img.png -> ![Image](https://...)
    body_text = re.sub(
        r'^(https?://\S+\.(?:png|jpg|jpeg|gif|webp))\s*$',
        r'![Showcase](\1)',
        body_text,
        flags=re.MULTILINE
    )
    # 2. Transform relative markdown images into raw GitHub URLs:
    # e.g. ![Alt](docs/img/...) -> ![Alt](https://raw.githubusercontent.com/acuteflower/shadowspore/main/docs/img/...)
    raw_base = f"https://raw.githubusercontent.com/{repo}/{branch}"
    def replace_relative_img(match):
        alt = match.group(1)
        path = match.group(2).lstrip("./")
        if not path.startswith("http://") and not path.startswith("https://"):
            return f"![{alt}]({raw_base}/{path})"
        return match.group(0)

    body_text = re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', replace_relative_img, body_text)
    return body_text


def create_release(tag_name, release_name, body_text, target="main", prerelease=True):
    token = get_git_token()
    if not token:
        print("Error: Could not retrieve GitHub token from git credentials.", file=sys.stderr)
        sys.exit(1)

    formatted_body = format_release_body(body_text, branch=target)

    url = 'https://api.github.com/repos/acuteflower/shadowspore/releases'
    payload = {
        'tag_name': tag_name,
        'target_commitish': target,
        'name': release_name,
        'body': formatted_body,
        'draft': False,
        'prerelease': prerelease
    }
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Shadowspore-Release-Agent',
        'Content-Type': 'application/json'
    })

    try:
        with urllib.request.urlopen(req) as resp:
            res = json.loads(resp.read().decode('utf-8'))
            print(f"Successfully created release: {res.get('html_url')}")
            return res
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode('utf-8')
        print(f"HTTP Error {e.code}: {err_msg}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: publish_release.py <tag_name> <release_name> [notes_file_or_text]", file=sys.stderr)
        sys.exit(1)

    tag = sys.argv[1]
    name = sys.argv[2]
    body = ""
    if len(sys.argv) >= 4:
        p = Path(sys.argv[3])
        if p.exists():
            body = p.read_text(encoding='utf-8')
        else:
            body = sys.argv[3]

    create_release(tag, name, body)
