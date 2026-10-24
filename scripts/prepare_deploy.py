"""Prepare public Flutter configuration without interpolating it into a shell."""

import argparse
import base64
import json
import os
from pathlib import Path
import re
from urllib.parse import urlsplit


def public_key(value: str) -> bool:
    """Catch accidental secret/service-role keys before a public web build."""
    if not value or any(character.isspace() for character in value):
        return False
    if value.startswith("sb_publishable_"):
        return len(value) > len("sb_publishable_")
    try:
        parts = value.split(".")
        if len(parts) != 3:
            return False
        payload = parts[1] + "=" * (-len(parts[1]) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
        return isinstance(claims, dict) and claims.get("role") == "anon"
    except (ValueError, TypeError, UnicodeDecodeError):
        return False


def base_href(repository: str) -> str:
    if not repository:
        return "/"
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Repository must have the form OWNER/REPOSITORY.")
    owner, name = repository.split("/")
    return "/" if name.lower() == f"{owner.lower()}.github.io" else f"/{name}/"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    project_url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_ANON_KEY", "").strip()
    if not project_url or not key:
        raise SystemExit(
            "Live configuration is missing. Set SUPABASE_URL and SUPABASE_ANON_KEY "
            "as GitHub repository variables (or local environment variables)."
        )
    parsed = urlsplit(project_url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or parsed.query or parsed.fragment
            or parsed.path not in ("", "/")):
        raise SystemExit("SUPABASE_URL must be the HTTPS project URL, without a path or credentials.")
    if not public_key(key):
        raise SystemExit(
            "SUPABASE_ANON_KEY must be a public publishable key or legacy anon key. "
            "Never use a secret or service_role key in a website."
        )
    try:
        href = base_href(args.repository)
    except ValueError as error:
        raise SystemExit(str(error)) from error

    runner_temp = os.environ.get("RUNNER_TEMP")
    output = args.output or (
        Path(runner_temp) / "costume-contest-config.json"
        if runner_temp else Path("config.local.json")
    )
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({
        "SUPABASE_URL": project_url.rstrip("/"),
        "SUPABASE_ANON_KEY": key,
        "DEMO_MODE": "false",
    }, indent=2) + "\n", encoding="utf-8")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with Path(github_output).open("a", encoding="utf-8") as handle:
            handle.write(f"base_href={href}\nconfig_file={output}\n")
    print(f"Prepared live build configuration. Website base path: {href}")


if __name__ == "__main__":
    main()
