# docker-uv

Minimal Docker-based `uv` wrapper for macOS users who do not want to install `uv` on the host machine.

[日本語はこちら](./README_ja.md)

## Overview

This repository provides:

- a Docker Compose service based on the official Astral `uv` image
- a small `uv` wrapper script that runs `uv` inside the container
- a local cache directory for faster repeated runs

The `uv` binary lives inside Docker only. Your macOS host does not need a native `uv` installation.

## Requirements

- macOS
- Docker Desktop, Colima, or another Docker environment with `docker compose`
- a POSIX-compatible shell such as `zsh` or `sh`

## How It Works

The wrapper script at `./uv`:

- resolves the repository root
- checks that the current directory is inside this repository
- launches `ghcr.io/astral-sh/uv:python3.12-trixie-slim` with Docker Compose
- forwards your current working directory into the container

The project is mounted to `/workspace`, and the `uv` cache is stored in `.docker/uv-cache/`.

## Setup

From the repository root:

```sh
mkdir -p "$HOME/bin"
ln -sf "$(pwd)/uv" "$HOME/bin/uv"
```

If `~/bin` is not already on your `PATH`, add this to `~/.zshrc`:

```sh
export PATH="$HOME/bin:$PATH"
```

Reload your shell:

```sh
source ~/.zshrc
```

## Usage

Run `uv` anywhere inside this repository:

```sh
uv --version
uv init
uv sync
uv run python -V
```

The first run pulls the Docker image if it is not already available locally.

## Limitations

- The wrapper only works while your current directory is inside this repository.
- Docker must be running before you execute `uv`.
- This project is designed to avoid installing `uv` on the host, not to replace Docker itself.

## Files

- `compose.yaml`: Docker Compose definition for the `uv` container
- `uv`: host-side wrapper script
- `.docker/uv-cache/`: local cache directory used by `uv` inside the container

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).
