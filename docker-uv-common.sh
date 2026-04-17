#!/bin/sh
set -eu

docker_uv_init() {
  SCRIPT_PATH=$1
  REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd -P)
  CURRENT_DIR=$(pwd -P)
  COMMAND_NAME=$(basename -- "$SCRIPT_PATH")
  MOUNT_ROOT=$CURRENT_DIR
  SEARCH_DIR=$CURRENT_DIR

  while :; do
    if [ -e "$SEARCH_DIR/pyproject.toml" ] || [ -e "$SEARCH_DIR/uv.toml" ] || [ -e "$SEARCH_DIR/.git" ]; then
      MOUNT_ROOT=$SEARCH_DIR
      break
    fi

    if [ "$SEARCH_DIR" = "/" ]; then
      break
    fi

    SEARCH_DIR=$(CDPATH='' cd -- "$SEARCH_DIR/.." && pwd -P)
  done

  case "$CURRENT_DIR" in
    "$MOUNT_ROOT")
      CONTAINER_DIR=/workspace
      ;;
    "$MOUNT_ROOT"/*)
      CONTAINER_DIR=/workspace${CURRENT_DIR#"$MOUNT_ROOT"}
      ;;
    *)
      printf 'Failed to resolve mount root for %s\n' "$CURRENT_DIR" >&2
      exit 1
      ;;
  esac

  PROJECT_KEY=$(printf '%s\n' "$MOUNT_ROOT" | shasum -a 256 | awk '{print $1}')
  PROJECT_CACHE_SOURCE="$REPO_ROOT/.docker/projects/$PROJECT_KEY/uv-cache"
  TOOLS_SOURCE="$REPO_ROOT/.docker/uv-tools"

  mkdir -p "$PROJECT_CACHE_SOURCE" "$TOOLS_SOURCE"
}

docker_uv_compose() {
  env UID="$(id -u)" GID="$(id -g)" \
    WORKSPACE_DIR="$MOUNT_ROOT" \
    UV_CACHE_SOURCE="$PROJECT_CACHE_SOURCE" \
    UV_TOOLS_SOURCE="$TOOLS_SOURCE" \
    docker compose \
      --project-directory "$REPO_ROOT" \
      -f "$REPO_ROOT/compose.yaml" \
      run --rm --no-deps "$@"
}

docker_uv_exec() {
  if [ -t 0 ] && [ -t 1 ]; then
    docker_uv_compose -w "$CONTAINER_DIR" "$@"
  else
    docker_uv_compose -T -w "$CONTAINER_DIR" "$@"
  fi
}
