# docker-uv

Minimal Docker-based `uv` and `uvx` wrappers for macOS users who do not want to install `uv` on the host machine.

[日本語はこちら](./README_ja.md)

## Overview

This repository provides:

- a Docker Compose service based on the official Astral `uv` image
- host-side `uv` and `uvx` wrapper scripts that run inside the container
- persistent cache and tool directories stored in this repository

The `uv` and `uvx` binaries live inside Docker only. Your macOS host does not need a native `uv` installation.

## Requirements

- macOS
- Docker Desktop, Colima, or another Docker environment with `docker compose`
- a POSIX-compatible shell such as `zsh` or `sh`

## How It Works

The wrapper scripts at `./uv` and `./uvx`:

- resolves the repository root
- launches `ghcr.io/astral-sh/uv:python3.12-trixie-slim` with Docker Compose
- finds the nearest project root or Git root from your current directory and bind-mounts it into the container
- preserves your relative working directory inside the container
- persists cache and installed tools under this repository's `.docker/` directory

This lets you run `uv` or `uvx` from any working directory while keeping project-relative behavior and centralized Docker-managed state.

## Setup

From the repository root:

```sh
mkdir -p "$HOME/bin"
ln -sf "$(pwd)/uv" "$HOME/bin/uv"
ln -sf "$(pwd)/uvx" "$HOME/bin/uvx"
```

If `~/bin` is not already on your `PATH`, add this to `~/.zshrc`:

```sh
export PATH="$HOME/bin:$PATH"
```

Reload your shell:

```sh
source ~/.zshrc
```

## Uninstall and Cleanup

To stop using these wrappers, remove the symlinks:

```sh
rm -f "$HOME/bin/uv" "$HOME/bin/uvx"
```

To also remove cached data and installed tools managed by this repository:

```sh
rm -rf .docker/uv-cache .docker/uv-tools
mkdir -p .docker/uv-cache .docker/uv-tools
touch .docker/uv-cache/.gitkeep .docker/uv-tools/.gitkeep
```

If you also want to remove Docker resources created for this project:

```sh
docker compose down --remove-orphans
docker image rm ghcr.io/astral-sh/uv:python3.12-trixie-slim
```

## Usage

Run `uv` or `uvx` from any working directory:

```sh
uv --version
uv init
uv sync
uv run python -V
uvx --version
uvx ruff --version
```

If your MCP client or local automation launches stdio servers with `uvx`, you can point it to this wrapper instead of a host-installed `uvx`.

Configuration format varies by client, so this repository does not prescribe a single MCP config format.

Installed tools are persisted across runs:

```sh
uv tool install ruff
uv tool dir
uv tool dir --bin
```

The first run pulls the Docker image if it is not already available locally.

## Limitations

- Docker must be running before you execute `uv`.
- This project is designed to avoid installing `uv` on the host, not to replace Docker itself.
- Installed tools live inside Docker-managed directories under `.docker/uv-tools/`, not as native macOS binaries.

## Files

- `compose.yaml`: Docker Compose definition for the `uv` container
- `uv`: host-side wrapper for `uv`
- `uvx`: host-side wrapper for `uvx`
- `.docker/uv-cache/`: persistent cache directory
- `.docker/uv-tools/`: persistent `uv tool install` data and executables

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).
