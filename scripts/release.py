#!/usr/bin/env python3
"""Build and publish a signed release while keeping the signing key on this Mac."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
REPO = "jeethsuresh/weather"


def run(*args, capture=False, env=None):
    return subprocess.run(args, cwd=ROOT, env=env, check=True, text=True,
                          capture_output=capture).stdout


def github_environment():
    env = os.environ.copy()
    if not env.get("GH_TOKEN") and not env.get("GITHUB_TOKEN"):
        credential = subprocess.run(["git", "credential", "fill"],
            input="protocol=https\nhost=github.com\n\n", text=True,
            capture_output=True, env={**env, "GIT_TERMINAL_PROMPT": "0"})
        fields = dict(line.split("=", 1) for line in credential.stdout.splitlines() if "=" in line)
        if fields.get("password"):
            env["GH_TOKEN"] = fields["password"]
    return env


def main():
    version = re.search(r"^version:\s*(\S+)", (ROOT / "pubspec.yaml").read_text(), re.M)[1]
    if not re.fullmatch(r"\d+\.\d+\.\d+\+\d+", version):
        raise SystemExit("Use a pubspec version such as 1.0.1+2.")
    tag = "v" + version.split("+")[0]
    if run("git", "status", "--porcelain", capture=True).strip():
        raise SystemExit("Commit your changes before publishing a release.")
    if run("git", "branch", "--show-current", capture=True).strip() != "main":
        raise SystemExit("Publish releases from main.")
    gh = shutil.which("gh") or str(ROOT / ".tools" / "gh")
    env = github_environment()
    existing = json.loads(run(gh, "release", "list", "--repo", REPO, "--limit", "100",
                              "--json", "tagName", capture=True, env=env))
    if any(r["tagName"] == tag for r in existing):
        raise SystemExit(f"{tag} is already published. Increase the version and build number.")
    flutter = shutil.which("flutter")
    if not flutter:
        raise SystemExit("Install Flutter or put its bin directory on PATH.")
    run(flutter, "--no-version-check", "pub", "get", "--enforce-lockfile")
    run(flutter, "--no-version-check", "analyze")
    run(flutter, "--no-version-check", "test", "--reporter", "expanded")
    run(flutter, "--no-version-check", "build", "apk", "--release", "--target-platform", "android-arm64")
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    apk = dist / "daybreak-android-arm64.apk"
    shutil.copyfile(ROOT / "build/app/outputs/flutter-apk/app-release.apk", apk)
    (dist / "SHA256SUMS").write_text(hashlib.sha256(apk.read_bytes()).hexdigest() + "  " + apk.name + "\n")
    run("git", "tag", tag)
    run("git", "push", "origin", "main", tag)
    notes = ("Install **daybreak-android-arm64.apk** from the assets below on your Android phone.\n\n"
             "Signed with Daybreak’s permanent release certificate. Updates from earlier GitHub releases install in place.\n\n"
             "If you installed the original development-key APK from the chat, uninstall it once before installing this release.\n\n"
             "Canada / US NWS / Open-Meteo, local caching, home-screen widget and hourly background checks. "
             "Android controls actual background timing.\n")
    notes_file = dist / "release-notes.md"
    notes_file.write_text(notes)
    run(gh, "release", "create", tag, str(apk), str(dist / "SHA256SUMS"), "--repo", REPO,
        "--verify-tag", "--title", "Daybreak " + version.split("+")[0], "--notes-file", str(notes_file), env=env)
    print(f"Published https://github.com/{REPO}/releases/tag/{tag}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(f"Release stopped because a command failed (exit {error.returncode}).") from error
