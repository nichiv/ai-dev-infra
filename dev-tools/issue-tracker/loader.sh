#!/usr/bin/env bash
# loader.sh - Issue tracker provider loader
#
# Reads issue_tracker from .config/project.yml, sources the matching provider,
# and validates that required functions are defined.
#
# Usage:
#   source "${SCRIPT_DIR}/issue-tracker/loader.sh"
#   tracker_get_issue "$ISSUE_NUMBER" "$REPO"

_TRACKER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "$_TRACKER_DIR/../.." && pwd)"

# Load .env from project root if it exists (does not override existing env vars)
if [ -f "$_REPO_ROOT/.env" ]; then
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    value="${value%\"}" && value="${value#\"}"
    value="${value%\'}" && value="${value#\'}"
    if [ -z "${!key:-}" ]; then
      export "$key=$value"
    fi
  done < "$_REPO_ROOT/.env"
fi

# Resolve provider from config (default: github)
_ISSUE_TRACKER=$(config_get '.issue_tracker' 2>/dev/null) || _ISSUE_TRACKER="github"

case "$_ISSUE_TRACKER" in
  github)
    source "${_TRACKER_DIR}/github.sh"
    ;;
  youtrack)
    source "${_TRACKER_DIR}/youtrack.sh"
    ;;
  *)
    echo "ERROR: Unknown issue_tracker provider: $_ISSUE_TRACKER" >&2
    echo "Supported: github, youtrack" >&2
    return 1
    ;;
esac

# Validate that required functions are defined
for _fn in tracker_get_issue tracker_get_comments tracker_post_comment; do
  if ! declare -f "$_fn" > /dev/null 2>&1; then
    echo "ERROR: Provider '$_ISSUE_TRACKER' does not implement $_fn()" >&2
    return 1
  fi
done

unset _TRACKER_DIR _ISSUE_TRACKER _fn
