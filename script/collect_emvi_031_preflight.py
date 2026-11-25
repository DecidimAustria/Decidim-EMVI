#!/usr/bin/env python3
"""Collect aggregate, read-only findings. Never export plans or contact details."""

import argparse
import json
import os
from pathlib import Path
import subprocess


def check_payload(value):
    if isinstance(value, dict):
        forbidden = {"name", "email", "nickname", "title", "gid", "resources", "plan", "rows"}
        if forbidden.intersection(value):
            raise ValueError("Unexpected private field in aggregate output")
        for child in value.values():
            check_payload(child)
    elif isinstance(value, list):
        for child in value:
            check_payload(child)
    elif isinstance(value, str) and any(part in value for part in ("@", "gid://", "http://", "https://")):
        raise ValueError("Unexpected contact/URL/reference in aggregate output")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proposed", action="store_true", help="Evaluate reviewed label/path/filter repairs in memory")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repository = Path(__file__).resolve().parents[1]
    workspace = next(parent for parent in repository.parents if (parent / "AGENTS.md").is_file() and not (parent / ".git").exists())
    output = args.output.resolve()
    if not output.is_relative_to(workspace / ".upgrade-backups"):
        raise ValueError("Use the private workspace backup directory")
    code = ""
    if args.proposed:
        code += (repository / "lib/emvi/maintenance/taxonomy_planning.rb").read_text() + "\n"
    code += (repository / "script/emvi_031_production_preflight.rb").read_text()
    command = ["kubectl", "--context", "kubernetes-admin@cluster1", "-n", "decidim-emvi-production", "exec", "-i", "deployment/production", "-c", "auto-deploy-app", "--", "env", "DISABLE_SPRING=1", "EMVI_READ_ONLY_PLANNING=1"]
    if args.proposed:
        command += ["EMVI_PLAN_REPAIRS=1"]
    command += ["bundle", "exec", "rails", "runner", "-"]
    result = subprocess.run(command, input=code, text=True, capture_output=True, timeout=150)
    if result.returncode:
        error_class = "unknown"
        for line in result.stderr.splitlines():
            try:
                error = json.loads(line)
            except ValueError:
                continue
            if isinstance(error, dict) and isinstance(error.get("error_class"), str):
                error_class = error["error_class"]
        raise RuntimeError("Read-only preflight failed: %s; no payload saved (exit %d)" % (error_class, result.returncode))
    markers = [line for line in result.stdout.splitlines() if line.startswith("EMVI_PRODUCTION_PREFLIGHT=")]
    if len(markers) != 1:
        raise ValueError("Expected exactly one aggregate result")
    payload = json.loads(markers[0].split("=", 1)[1])
    check_payload(payload)
    if not payload.get("transaction_read_only"):
        raise ValueError("Read-only protection not confirmed")
    output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(output.parent, 0o700)
    with open(output, "w", opener=lambda path, flags: os.open(path, flags, 0o600)) as handle:
        json.dump(payload, handle, indent=2)
    os.chmod(output, 0o600)
    print(json.dumps({"captured_at": payload["captured_at"], "counts": payload["counts"], "coverage": payload["coverage"]}, indent=2))


if __name__ == "__main__":
    main()
