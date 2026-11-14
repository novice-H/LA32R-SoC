"""Read-only checks for shared inputs and ignored local environment files."""

from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parent.parent
LOCAL_PATHS = (
    "LOCAL.md",
    "requirements/local/README.md",
    "requirements/local/env.sh",
    "requirements/env.local.sh",
    "Makefile.local",
    ".env",
    ".venv/pyvenv.cfg",
    ".vscode/settings.json",
    ".codebuddy/state.json",
    ".codex/file-management/project.json",
    ".codex/file-management/work/runs/probe/run.json",
    "outputs/probe.md",
    "requirements/verilator-smoke/obj_dir/probe.cpp",
    "requirements/verilator-smoke/obj_dir_trace/probe.cpp",
    "requirements/loongarch32r-linux-gnusf-2.0/bin/probe",
)
SHARED_PATHS = (
    "requirements/README.md",
    "requirements/env.sh",
    "requirements/env.example.sh",
    "requirements/setup-deps.sh",
    "requirements/loongarch32r-linux-gnusf-2.0.tar.gz",
    "LOCAL.example.md",
    "docs/local-and-shared.md",
    "tools/check-local-isolation.py",
)


def git(*args):
    result = subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, check=False
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace"))
    return result


def main():
    errors = []
    for paths, expected in ((LOCAL_PATHS, True), (SHARED_PATHS, False)):
        for path in paths:
            ignored = git("check-ignore", "--quiet", "--no-index", "--", path).returncode == 0
            if ignored != expected:
                errors.append(f"{path}: expected ignored={expected}, got {ignored}")

    tracked = git("ls-files", "--cached", "--ignored", "--exclude-standard", "-z")
    for path in tracked.stdout.decode("utf-8").split("\0"):
        if path:
            errors.append(f"tracked local/generated file: {path}")

    if errors:
        print("FAIL:\n" + "\n".join(errors))
        return 1
    print(f"PASS: {len(LOCAL_PATHS)} local paths ignored; {len(SHARED_PATHS)} shared paths trackable; no tracked ignored files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
