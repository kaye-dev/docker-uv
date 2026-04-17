#!/bin/sh
set -eu

DOCKER_UV_TAB=$(printf '\t')

docker_uv_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

docker_uv_safe_name() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

docker_uv_command_path() {
  command -v "$1" 2>/dev/null || true
}

docker_uv_has_command() {
  command -v "$1" >/dev/null 2>&1
}

docker_uv_file_older_than_days() {
  file=$1
  days=$2

  if [ ! -e "$file" ]; then
    return 1
  fi

  threshold=$((days - 1))
  if [ "$threshold" -lt 0 ]; then
    threshold=0
  fi

  [ -n "$(find "$file" -mtime "+$threshold" -print -quit 2>/dev/null)" ]
}

docker_uv_file_timestamp() {
  target=$1

  if [ ! -e "$target" ]; then
    printf 'n/a\n'
    return 0
  fi

  if stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$target" >/dev/null 2>&1; then
    stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$target"
  else
    stat -c '%y' "$target" | cut -d'.' -f1
  fi
}

docker_uv_dir_size() {
  target=$1

  if [ ! -e "$target" ]; then
    printf '0B\n'
    return 0
  fi

  size=$(du -sh "$target" 2>/dev/null | awk '{print $1}')
  if [ -n "${size:-}" ]; then
    printf '%s\n' "$size"
  else
    printf '0B\n'
  fi
}

docker_uv_read_meta_value() {
  file=$1
  key=$2

  if [ ! -e "$file" ]; then
    return 1
  fi

  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, length($1) + 2); exit }' "$file"
}

docker_uv_extract_tool_requirement_from_receipt() {
  receipt=$1

  if [ ! -e "$receipt" ]; then
    return 1
  fi

  awk -F'"' '/requirements = \[\{ name = "/ { print $2; exit }' "$receipt"
}

docker_uv_write_metadata() {
  file=$1
  shift
  tmp_file=$file.tmp.$$

  : > "$tmp_file"
  while [ "$#" -gt 1 ]; do
    key=$1
    value=$2
    printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
    shift 2
  done

  mv "$tmp_file" "$file"
}

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
  PROJECT_CACHE_ROOT="$REPO_ROOT/.docker/projects"
  PROJECT_CACHE_SOURCE="$PROJECT_CACHE_ROOT/$PROJECT_KEY/uv-cache"
  TOOLS_SOURCE="$REPO_ROOT/.docker/uv-tools"
  LEGACY_CACHE_ROOT="$REPO_ROOT/.docker/uv-cache"
  STATE_ROOT="$REPO_ROOT/.docker/state"
  PROJECT_STATE_DIR="$STATE_ROOT/projects"
  TOOL_STATE_DIR="$STATE_ROOT/tools"
  HINT_STATE_FILE="$STATE_ROOT/last-hint"

  mkdir -p "$PROJECT_CACHE_SOURCE" "$TOOLS_SOURCE" "$PROJECT_STATE_DIR" "$TOOL_STATE_DIR"
}

docker_uv_project_state_file() {
  printf '%s/%s.meta\n' "$PROJECT_STATE_DIR" "$1"
}

docker_uv_tool_state_file() {
  printf '%s/%s.meta\n' "$TOOL_STATE_DIR" "$(docker_uv_safe_name "$1")"
}

docker_uv_restore_structure() {
  mkdir -p "$PROJECT_CACHE_ROOT" "$PROJECT_STATE_DIR" "$TOOL_STATE_DIR" "$TOOLS_SOURCE" "$LEGACY_CACHE_ROOT"
  touch \
    "$PROJECT_CACHE_ROOT/.gitkeep" \
    "$PROJECT_STATE_DIR/.gitkeep" \
    "$TOOL_STATE_DIR/.gitkeep" \
    "$TOOLS_SOURCE/.gitkeep" \
    "$LEGACY_CACHE_ROOT/.gitkeep"
}

docker_uv_remove_tool_state() {
  tool_name=$1
  rm -f "$(docker_uv_tool_state_file "$tool_name")"
}

docker_uv_clear_current_project_cache() {
  rm -rf "$PROJECT_CACHE_ROOT/$PROJECT_KEY"
  mkdir -p "$PROJECT_CACHE_SOURCE"
}

docker_uv_clear_all_project_caches() {
  rm -rf "$PROJECT_CACHE_ROOT"
  mkdir -p "$PROJECT_CACHE_ROOT"
  touch "$PROJECT_CACHE_ROOT/.gitkeep"
}

docker_uv_clear_all_installed_tools() {
  rm -rf "$TOOLS_SOURCE" "$TOOL_STATE_DIR"
  mkdir -p "$TOOLS_SOURCE" "$TOOL_STATE_DIR"
  touch "$TOOLS_SOURCE/.gitkeep" "$TOOL_STATE_DIR/.gitkeep"
}

docker_uv_reset_all_local_data() {
  rm -rf "$PROJECT_CACHE_ROOT" "$STATE_ROOT" "$TOOLS_SOURCE" "$LEGACY_CACHE_ROOT"
  docker_uv_restore_structure
}

docker_uv_record_project_usage() {
  docker_uv_write_metadata \
    "$(docker_uv_project_state_file "$PROJECT_KEY")" \
    project_key "$PROJECT_KEY" \
    project_path "$MOUNT_ROOT" \
    last_wrapper "$COMMAND_NAME" \
    updated_at "$(docker_uv_now)"
}

docker_uv_extract_uvx_tool() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --)
        shift
        [ "$#" -gt 0 ] && printf '%s\n' "$1"
        return 0
        ;;
      --from|--with|--with-executables-from|--python|--index|--default-index|--index-url|--extra-index-url|--allow-insecure-host|--refresh-package|--config-file|--project|--directory)
        [ "$#" -ge 2 ] || return 1
        shift 2
        ;;
      -f|-p)
        [ "$#" -ge 2 ] || return 1
        shift 2
        ;;
      -*)
        shift
        ;;
      *)
        printf '%s\n' "$1"
        return 0
        ;;
    esac
  done

  return 1
}

docker_uv_record_tool_usage() {
  tool_request=${1:-}
  if [ -z "$tool_request" ]; then
    return 0
  fi

  tool_name=${tool_request%%@*}

  docker_uv_write_metadata \
    "$(docker_uv_tool_state_file "$tool_name")" \
    tool_name "$tool_name" \
    last_request "$tool_request" \
    last_wrapper "$COMMAND_NAME" \
    updated_at "$(docker_uv_now)"
}

docker_uv_count_installed_tools() {
  count=0

  for tool_dir in "$TOOLS_SOURCE"/tools/*; do
    [ -d "$tool_dir" ] || continue
    count=$((count + 1))
  done

  printf '%s\n' "$count"
}

docker_uv_count_stale_projects() {
  stale_days=$1
  count=0

  for meta in "$PROJECT_STATE_DIR"/*.meta; do
    [ -e "$meta" ] || continue
    docker_uv_file_older_than_days "$meta" "$stale_days" || continue
    count=$((count + 1))
  done

  printf '%s\n' "$count"
}

docker_uv_count_stale_tools() {
  stale_days=$1
  count=0

  for tool_dir in "$TOOLS_SOURCE"/tools/*; do
    [ -d "$tool_dir" ] || continue
    tool_name=$(basename -- "$tool_dir")
    tool_meta=$(docker_uv_tool_state_file "$tool_name")

    if [ -e "$tool_meta" ]; then
      docker_uv_file_older_than_days "$tool_meta" "$stale_days" || continue
    else
      docker_uv_file_older_than_days "$tool_dir" "$stale_days" || continue
    fi

    count=$((count + 1))
  done

  printf '%s\n' "$count"
}

docker_uv_list_stale_projects() {
  stale_days=$1

  for meta in "$PROJECT_STATE_DIR"/*.meta; do
    [ -e "$meta" ] || continue
    docker_uv_file_older_than_days "$meta" "$stale_days" || continue

    project_key=$(basename -- "$meta" .meta)
    project_path=$(docker_uv_read_meta_value "$meta" project_path || true)
    cache_dir="$PROJECT_CACHE_ROOT/$project_key"
    cache_size=$(docker_uv_dir_size "$cache_dir")
    last_used=$(docker_uv_file_timestamp "$meta")

    if [ -n "$project_path" ] && [ -e "$project_path" ]; then
      path_status=exists
    else
      path_status=missing
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$project_key" \
      "${project_path:-"(unknown project)"}" \
      "$last_used" \
      "$cache_size" \
      "$path_status"
  done
}

docker_uv_list_all_projects() {
  for project_dir in "$PROJECT_CACHE_ROOT"/*; do
    [ -d "$project_dir" ] || continue

    project_key=$(basename -- "$project_dir")
    meta=$(docker_uv_project_state_file "$project_key")
    cache_size=$(docker_uv_dir_size "$project_dir")

    if [ -e "$meta" ]; then
      project_path=$(docker_uv_read_meta_value "$meta" project_path || true)
      last_used=$(docker_uv_file_timestamp "$meta")
      if [ -n "$project_path" ] && [ -e "$project_path" ]; then
        path_status=exists
      else
        path_status=missing
      fi
    else
      project_path="(unknown project)"
      last_used=$(docker_uv_file_timestamp "$project_dir")
      path_status=untracked
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$project_key" \
      "$project_path" \
      "$last_used" \
      "$cache_size" \
      "$path_status"
  done
}

docker_uv_list_installed_tools() {
  for tool_dir in "$TOOLS_SOURCE"/tools/*; do
    [ -d "$tool_dir" ] || continue

    tool_name=$(basename -- "$tool_dir")
    receipt="$tool_dir/uv-receipt.toml"
    package_name=$(docker_uv_extract_tool_requirement_from_receipt "$receipt" || true)
    if [ -z "$package_name" ]; then
      package_name=$tool_name
    fi

    tool_meta=$(docker_uv_tool_state_file "$tool_name")
    if [ -e "$tool_meta" ]; then
      last_used=$(docker_uv_file_timestamp "$tool_meta")
    else
      last_used=never-tracked
    fi

    installed_at=$(docker_uv_file_timestamp "$tool_dir")
    tool_size=$(docker_uv_dir_size "$tool_dir")

    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$tool_name" \
      "$package_name" \
      "$last_used" \
      "$installed_at" \
      "$tool_size"
  done
}

docker_uv_print_review_candidates() {
  stale_days=$1
  project_lines=$(docker_uv_list_stale_projects "$stale_days")
  tool_lines=$(docker_uv_list_installed_tools | while IFS="$DOCKER_UV_TAB" read -r tool_name package_name last_used installed_at tool_size; do
    tool_meta=$(docker_uv_tool_state_file "$tool_name")
    if [ -e "$tool_meta" ]; then
      docker_uv_file_older_than_days "$tool_meta" "$stale_days" || continue
    else
      docker_uv_file_older_than_days "$TOOLS_SOURCE/tools/$tool_name" "$stale_days" || continue
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' "$tool_name" "$package_name" "$last_used" "$installed_at" "$tool_size"
  done)

  printf 'docker-uv review candidates older than %s days\n' "$stale_days"

  printf '\nProject caches\n'
  if [ -n "$project_lines" ]; then
    printf '%s\n' "$project_lines" | while IFS="$DOCKER_UV_TAB" read -r project_key project_path last_used cache_size path_status; do
      printf -- '- %s\n' "$project_path"
      printf '  last used: %s\n' "$last_used"
      printf '  cache size: %s\n' "$cache_size"
      printf '  path status: %s\n' "$path_status"
    done
  else
    printf -- '- none\n'
  fi

  printf '\nInstalled tools\n'
  if [ -n "$tool_lines" ]; then
    printf '%s\n' "$tool_lines" | while IFS="$DOCKER_UV_TAB" read -r tool_name package_name last_used installed_at tool_size; do
      printf -- '- %s\n' "$tool_name"
      printf '  package: %s\n' "$package_name"
      printf '  last tracked use: %s\n' "$last_used"
      printf '  install size: %s\n' "$tool_size"
      printf '  installed at: %s\n' "$installed_at"
    done
  else
    printf -- '- none\n'
  fi

  if [ -z "$project_lines" ] && [ -z "$tool_lines" ]; then
    printf '\nNo inactive project caches or installed tools older than %s days were found.\n' "$stale_days"
  else
    printf '\nReview the candidates above and remove only the ones you no longer need.\n'
  fi
}

docker_uv_print_installed_tools() {
  tool_lines=$(docker_uv_list_installed_tools)

  printf 'Installed tools\n'
  if [ -n "$tool_lines" ]; then
    printf '%s\n' "$tool_lines" | while IFS="$DOCKER_UV_TAB" read -r tool_name package_name last_used installed_at tool_size; do
      printf -- '- %s\n' "$tool_name"
      printf '  package: %s\n' "$package_name"
      printf '  last tracked use: %s\n' "$last_used"
      printf '  install size: %s\n' "$tool_size"
      printf '  installed at: %s\n' "$installed_at"
    done
  else
    printf -- '- none\n'
  fi
}

docker_uv_print_storage_usage() {
  project_lines=$(docker_uv_list_all_projects)
  tool_lines=$(docker_uv_list_installed_tools)

  printf 'docker-uv storage usage\n'
  printf -- '- total .docker: %s\n' "$(docker_uv_dir_size "$REPO_ROOT/.docker")"
  printf -- '- project caches: %s\n' "$(docker_uv_dir_size "$PROJECT_CACHE_ROOT")"
  printf -- '- legacy shared cache: %s\n' "$(docker_uv_dir_size "$LEGACY_CACHE_ROOT")"
  printf -- '- installed tools: %s\n' "$(docker_uv_dir_size "$TOOLS_SOURCE")"
  printf -- '- state metadata: %s\n' "$(docker_uv_dir_size "$STATE_ROOT")"
  printf -- '- current project cache: %s\n' "$(docker_uv_dir_size "$PROJECT_CACHE_ROOT/$PROJECT_KEY")"

  printf '\nProject caches\n'
  if [ -n "$project_lines" ]; then
    printf '%s\n' "$project_lines" | while IFS="$DOCKER_UV_TAB" read -r project_key project_path last_used cache_size path_status; do
      printf -- '- %s\n' "$project_path"
      printf '  key: %s\n' "$project_key"
      printf '  cache size: %s\n' "$cache_size"
      printf '  last used: %s\n' "$last_used"
      printf '  path status: %s\n' "$path_status"
    done
  else
    printf -- '- none\n'
  fi

  printf '\nInstalled tools\n'
  if [ -n "$tool_lines" ]; then
    printf '%s\n' "$tool_lines" | while IFS="$DOCKER_UV_TAB" read -r tool_name package_name last_used installed_at tool_size; do
      printf -- '- %s\n' "$tool_name"
      printf '  package: %s\n' "$package_name"
      printf '  install size: %s\n' "$tool_size"
      printf '  last tracked use: %s\n' "$last_used"
      printf '  installed at: %s\n' "$installed_at"
    done
  else
    printf -- '- none\n'
  fi
}

docker_uv_docker_context_name() {
  if ! docker_uv_has_command docker; then
    printf '\n'
    return 0
  fi

  docker context show 2>/dev/null || true
}

docker_uv_docker_context_host() {
  context_name=$1

  if ! docker_uv_has_command docker || [ -z "$context_name" ]; then
    printf '\n'
    return 0
  fi

  docker context inspect "$context_name" --format '{{(index .Endpoints "docker").Host}}' 2>/dev/null || true
}

docker_uv_docker_daemon_detail() {
  if ! docker_uv_has_command docker; then
    printf 'missing\tDocker CLI is not installed\n'
    return 0
  fi

  if output=$(docker info --format '{{.ServerVersion}}' 2>&1); then
    printf 'ready\t%s\n' "$output"
    return 0
  fi

  message=$(printf '%s' "$output" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')

  if printf '%s' "$message" | grep -qi 'permission denied'; then
    printf 'permission-error\t%s\n' "$message"
  elif printf '%s' "$message" | grep -qi 'cannot connect\|docker daemon\|context deadline exceeded\|no such file or directory\|connect:'; then
    printf 'unreachable\t%s\n' "$message"
  else
    printf 'error\t%s\n' "$message"
  fi
}

docker_uv_runtime_ready() {
  detail=$(docker_uv_docker_daemon_detail)
  status=${detail%%"$DOCKER_UV_TAB"*}
  [ "$status" = "ready" ]
}

docker_uv_colima_detail() {
  if ! docker_uv_has_command colima; then
    printf 'not-installed\tColima is not installed\n'
    return 0
  fi

  if output=$(colima status 2>&1); then
    detail=$(printf '%s' "$output" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
    if [ -z "$detail" ]; then
      detail='Colima is running'
    fi
    printf 'running\t%s\n' "$detail"
    return 0
  fi

  message=$(printf '%s' "$output" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')
  if printf '%s' "$message" | grep -qi 'is not running'; then
    printf 'stopped\tColima is not running\n'
  else
    printf 'error\t%s\n' "$message"
  fi
}

docker_uv_maybe_print_hint() {
  if [ "${DOCKER_UV_NO_HINTS:-0}" = "1" ]; then
    return 0
  fi

  stale_days=${DOCKER_UV_RECOMMEND_AFTER_DAYS:-30}
  hint_interval_days=${DOCKER_UV_HINT_INTERVAL_DAYS:-1}

  if [ -e "$HINT_STATE_FILE" ] && ! docker_uv_file_older_than_days "$HINT_STATE_FILE" "$hint_interval_days"; then
    return 0
  fi

  stale_projects=$(docker_uv_count_stale_projects "$stale_days")
  stale_tools=$(docker_uv_count_stale_tools "$stale_days")

  if [ "$stale_projects" -gt 0 ] || [ "$stale_tools" -gt 0 ]; then
    printf 'note: docker-uv found %s inactive project cache(s) and %s installed tool candidate(s) older than %s days; run `docker-uv-status` for details.\n' \
      "$stale_projects" "$stale_tools" "$stale_days" >&2
  fi

  : > "$HINT_STATE_FILE"
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

docker_uv_run_compose() {
  if [ -t 0 ] && [ -t 1 ]; then
    docker_uv_compose -w "$CONTAINER_DIR" "$@"
  else
    docker_uv_compose -T -w "$CONTAINER_DIR" "$@"
  fi
}

docker_uv_run() {
  if docker_uv_run_compose uv "$COMMAND_NAME" "$@"; then
    docker_uv_record_project_usage
    if [ "$COMMAND_NAME" = "uvx" ]; then
      docker_uv_record_tool_usage "$(docker_uv_extract_uvx_tool "$@" || true)"
    fi
    docker_uv_maybe_print_hint
  else
    return $?
  fi
}

docker_uv_run_inner() {
  if docker_uv_run_compose uv "$@"; then
    docker_uv_record_project_usage
    docker_uv_maybe_print_hint
  else
    return $?
  fi
}
