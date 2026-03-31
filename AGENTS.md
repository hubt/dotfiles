# Repository Guidelines

## Project Structure & Modules
- Root: shell and Perl utilities (e.g., `ccut`, `cpaste`, `awsfind.pl`, `kube-node-shell`).
- Dotfiles: `bashrc`, `vimrc`, `screenrc`, `psqlrc`, `pythonrc.py`, `git-prompt.sh`.
- Kubernetes: `kubectl-plugins/` contains `kubectl-*` plugin scripts; `genv` and `setup.sh` help manage GCP/GKE contexts and `KUBECONFIG` files.
- Misc assets: resume files are read-only artifacts.

## Build, Test, and Development Commands
- No formal build. Scripts run directly once executable and on `PATH`.
- Path setup: `export PATH="$HOME/dotfiles:$HOME/dotfiles/kubectl-plugins:$PATH"`.
- Shell init: source `bashrc` or selectively source `genv` in your shell profile.
- GKE setup: `./setup.sh <project> <cluster>` (or `./setup.sh <project>` to generate kubeconfigs). Requires `gcloud`, `jq`, `yq`, `curl`.

## Coding Style & Naming Conventions
- Shell: prefer POSIX `sh` unless Bash features are needed. Use clear shebangs (`#!/bin/sh` or `#!/bin/bash`), 2‑space indentation, quote variables, `set -e` where appropriate.
- Perl: `#!/usr/bin/env perl`, add `use strict; use warnings;` for new code; use `.pl` suffix.
- Plugins: name as `kubectl-<verb>` and keep files executable (`chmod +x`).
- Local overrides: place machine/user-specific settings in `bashrc.local` (not committed).

## Testing Guidelines
- Shell syntax: `sh -n script` or `bash -n script`; optional `shellcheck script` if available.
- Perl syntax: `perl -c file.pl`.
- Manual checks: run key paths, e.g., `echo hi | ./ccut`, `kubectl-plugins/kubectl-dnstest -h`.
- Keep changes backward-compatible across Linux/macOS/WSL when feasible.

## Commit & Pull Request Guidelines
- Commits: imperative, concise, include scope, e.g., `kubectl-plugins: add nodeshell`, `bashrc: improve prompt`.
- PRs: include summary, rationale, verification steps, OS/cluster assumptions, and risks. Link related issues when applicable; add screenshots only if UI-related output aids review.

## Security & Configuration Tips
- Do not commit secrets, tokens, or kubeconfigs. Use `bashrc.local` and `~/e/<project>/project.sh` for local-only settings.
- `setup.sh` modifies `KUBECONFIG` and calls GCP APIs—review before running in shared environments.
