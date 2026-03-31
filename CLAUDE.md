# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles and shell/Perl utilities for managing multi-cloud Kubernetes clusters (GKE, EKS, AKS) and general shell productivity. No build system—scripts run directly once executable and on `PATH`.

## PATH Setup

```sh
export PATH="$HOME/dotfiles:$HOME/dotfiles/kubectl-plugins:$PATH"
```

## Syntax Checking (no test suite)

```sh
bash -n <script>        # shell syntax check
perl -c <file.pl>       # Perl syntax check
shellcheck <script>     # optional, if installed
```

## Architecture

### Cluster Setup Scripts

Three parallel setup scripts write per-cluster kubeconfigs under cloud-specific directories:

| Script | Cloud | Kubeconfig path |
|---|---|---|
| `setup.sh` | GKE | `~/e/<project>/<cluster>` |
| `setup-aws.sh` | EKS | `~/e-aws/<profile>/<cluster>` |
| `setup-azure.sh` | AKS | `~/e-azure/<subscription>/<cluster>` |

All three follow the same pattern: with only the first arg, they discover clusters and emit runnable commands; with full args they write the kubeconfig and test reachability via `curl`.

### Shell Prompt (`bashrc`)

`__cloud_ps1` in `bashrc` reads `KUBECONFIG` path structure to infer the current cloud/project/cluster and inject it into `PS1` alongside `__git_ps1`. Azure subscriptions are resolved to human-friendly names via `~/.azure/azureProfile.json`.

### `kubectl-plugins/`

Each file is named `kubectl-<verb>` (e.g., `kubectl-shell`, `kubectl-nodeshell`, `kubectl-dnstest`) and must be executable. `kubectl` discovers them automatically from `PATH`.

### Local Overrides

`bashrc.local` and `~/e/<project>/project.sh` / `~/e-azure/<subscription>/account.sh` are not committed; they hold machine/environment-specific settings and credentials.

## Coding Conventions

- Shell: POSIX `sh` unless Bash features are needed; 2-space indent; quote variables; `set -e` where appropriate.
- Perl: `#!/usr/bin/env perl`, `use strict; use warnings;`, `.pl` suffix.
- Commit style: imperative with scope, e.g., `kubectl-plugins: add nodeshell`, `bashrc: improve prompt`.
