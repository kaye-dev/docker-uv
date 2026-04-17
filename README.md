# docker-uv

`docker-uv` is a small Docker-based wrapper for people who want to use `uv` and `uvx` on macOS without installing `uv` on the host.

[日本語はこちら](./README_ja.md)

## Overview

This repository includes a Docker Compose service based on Astral's official `uv` image, along with small host-side wrapper scripts for `uv`, `uvx`, and a few related helper commands.

The actual `uv` and `uvx` binaries live inside Docker. On the macOS side, you only install lightweight wrapper scripts.

## Requirements

- macOS
- Docker Desktop, Colima, or another Docker environment with `docker compose`
- a POSIX-compatible shell such as `zsh` or `sh`

## How It Works

The wrappers in `./uv` and `./uvx` resolve the repository root, start `ghcr.io/astral-sh/uv:python3.12-trixie-slim` with Docker Compose, and mount the nearest project root or Git root from your current directory. If neither exists, they fall back to the current directory.

Your relative working directory is preserved inside the container, so running commands from a subdirectory still behaves as expected. Cache data is stored per discovered project root, Git root, or current-directory fallback under `.docker/projects/`, and installed tools are kept under `.docker/uv-tools/`.

In practice, this means you can run `uv` or `uvx` from different working directories without installing `uv` natively and without mixing all cache state into one host-global location.

## What This Solves

This setup gives you a few concrete benefits.

- You can use `uv` and `uvx` without installing either of them on the macOS host.
- Cache and tool data live under this repository's `.docker/` directory instead of a host-global `uv` location.
- Cache is separated by discovered project root, Git root, or current-directory fallback, which reduces cache sharing across unrelated projects when you use this wrapper.
- The Compose configuration explicitly sets `UV_LINK_MODE=copy`, so installed files are copied from cache into the target environment instead of being linked back to the cache.

That last point matters if you want to reduce coupling between cached packages and project environments. With this setup, editing installed package files inside one environment is less likely to affect another environment through shared cache state or linked files.

At the same time, this repository does not disable `uv` caching, and it does not make manual edits to installed packages safe in general. It only narrows the blast radius by isolating cache per project root and avoiding linked installs from cache in this Docker-based setup.

## Setup

From the repository root, create symlinks in `~/bin`:

```sh
mkdir -p "$HOME/bin"
ln -sf "$(pwd)/uv" "$HOME/bin/uv"
ln -sf "$(pwd)/uvx" "$HOME/bin/uvx"
ln -sf "$(pwd)/uv-refresh" "$HOME/bin/uv-refresh"
ln -sf "$(pwd)/uv-cache-clean" "$HOME/bin/uv-cache-clean"
```

If `~/bin` is not already on your `PATH`, add this to `~/.zshrc`:

```sh
export PATH="$HOME/bin:$PATH"
```

Then reload your shell:

```sh
source ~/.zshrc
```

## Usage

Once the setup is in place, you can run `uv` and `uvx` from your usual working directories:

```sh
uv --version
uv init
uv sync
uv run python -V
uvx --version
uvx ruff --version
```

There are also a couple of convenience commands:

```sh
uv-refresh
uv-cache-clean
uv-cache-clean ruff
```

`uv-refresh` is a shortcut for `uv sync --refresh`. `uv-cache-clean` is a shortcut for `uv cache clean` against the current project's isolated cache.

If your MCP client or local automation launches stdio servers with `uvx`, you can point it to this wrapper instead of a host-installed `uvx`. Configuration format varies by client, so this repository does not prescribe a single MCP config format.

Tools installed with `uv tool install` are persisted across runs:

```sh
uv tool install ruff
uv tool dir
uv tool dir --bin
```

The first run pulls the Docker image if it is not already available locally.

## Uninstall and Cleanup

If you want to stop using these wrappers, remove the symlinks:

```sh
rm -f "$HOME/bin/uv" "$HOME/bin/uvx" "$HOME/bin/uv-refresh" "$HOME/bin/uv-cache-clean"
```

If you also want to remove cache data and installed tools managed by this repository, run:

```sh
rm -rf .docker/projects .docker/uv-tools .docker/uv-cache
mkdir -p .docker/projects .docker/uv-tools .docker/uv-cache
touch .docker/projects/.gitkeep .docker/uv-tools/.gitkeep .docker/uv-cache/.gitkeep
```

If you want to clean up Docker resources created for this project as well:

```sh
docker compose down --remove-orphans
docker image rm ghcr.io/astral-sh/uv:python3.12-trixie-slim
```

## Limitations

There are also a few things this repository does not change.

- Docker must be running before you execute `uv`.
- The goal is to avoid installing `uv` on the host, not to avoid Docker itself.
- Installed tools live inside Docker-managed directories under `.docker/uv-tools/`, not as native macOS binaries.

## Files

The main files in this repository are:

- `compose.yaml`: Docker Compose definition for the `uv` container
- `docker-uv-common.sh`: shared wrapper logic for project discovery and cache isolation
- `uv`: host-side wrapper for `uv`
- `uvx`: host-side wrapper for `uvx`
- `uv-refresh`: convenience wrapper for `uv sync --refresh`
- `uv-cache-clean`: convenience wrapper for `uv cache clean`
- `.docker/projects/`: per-project cache directories
- `.docker/uv-tools/`: persistent `uv tool install` data and executables

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).
