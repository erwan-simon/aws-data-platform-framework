import os
import subprocess
from urllib.parse import urlsplit, urlunsplit

GIT_REPOSITORY = "{{cookiecutter.git_repository}}"
TERRAFORM_BACKEND_BUCKET = "{{cookiecutter.terraform_backend_bucket_name}}"


def strip_credentials(url: str) -> str:
    # Drop any user:password@ baked into the URL so the remote we store doesn't carry secrets.
    parts = urlsplit(url)
    if not parts.hostname:
        return url
    netloc = parts.hostname + (f":{parts.port}" if parts.port else "")
    return urlunsplit((parts.scheme, netloc, parts.path, parts.query, parts.fragment))


def has_git_identity() -> bool:
    return all(
        subprocess.run(
            ["git", "config", "--get", f"user.{key}"], capture_output=True
        ).returncode
        == 0
        for key in ("name", "email")
    )


def main():
    if not TERRAFORM_BACKEND_BUCKET and os.path.exists("iac/backend.hcl"):
        # Local backend: backend.hcl has no purpose; drop it so `terraform init` works without -backend-config.
        os.remove("iac/backend.hcl")
        print(
            "No terraform_backend_bucket_name provided — using local Terraform backend, removed iac/backend.hcl."
        )
    subprocess.run(["git", "init", "-q"], check=True)
    clean_repository = strip_credentials(GIT_REPOSITORY) if GIT_REPOSITORY else ""
    if clean_repository:
        subprocess.run(["git", "remote", "add", "origin", clean_repository], check=True)
    subprocess.run(["git", "add", "-A"], check=True)
    # Fall back to a placeholder identity when none is configured (typical in CI runners with
    # no global git config); applied via `-c` so we don't touch local or global config.
    commit_cmd = [
        "git",
        "commit",
        "-q",
        "-m",
        "chore: initial scaffold from cookiecutter",
    ]
    if not has_git_identity():
        commit_cmd = [
            "git",
            "-c",
            "user.name=cookiecutter",
            "-c",
            "user.email=cookiecutter@local",
        ] + commit_cmd[1:]
    subprocess.run(commit_cmd, check=True)
    print("Initialized git repo with initial scaffold commit.")
    if clean_repository:
        print(f"Remote 'origin' set to {clean_repository}.")
    else:
        print(
            "Did not set git repo 'origin' because cookiecutter 'git_repository' field was not set."
        )


if __name__ == "__main__":
    main()
