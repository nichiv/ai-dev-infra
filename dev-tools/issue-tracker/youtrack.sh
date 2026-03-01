#!/usr/bin/env bash
# youtrack.sh - YouTrack issue tracker provider
#
# Required:
#   - YOUTRACK_TOKEN environment variable
#   - youtrack.base_url in .config/project.yml

_YT_BASE_URL=$(config_get '.youtrack.base_url')

if [ -z "${YOUTRACK_TOKEN:-}" ]; then
  echo "ERROR: YOUTRACK_TOKEN environment variable is not set" >&2
  exit 1
fi

if [ -z "$_YT_BASE_URL" ]; then
  echo "ERROR: youtrack.base_url is not configured in .config/project.yml" >&2
  exit 1
fi

_yt_api() {
  local endpoint="$1"
  shift
  curl -sS -H "Authorization: Bearer ${YOUTRACK_TOKEN}" \
    -H "Accept: application/json" \
    "$@" \
    "${_YT_BASE_URL}/api${endpoint}"
}

tracker_get_issue() {
  local issue_number="$1"
  # $2 (repo) is unused for YouTrack
  local response
  response=$(_yt_api "/issues/$issue_number?fields=summary,description")
  python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print('# ' + d.get('summary', ''))
print()
print(d.get('description', '') or '')
" <<< "$response"
}

tracker_get_comments() {
  local issue_number="$1"
  # $2 (repo) is unused for YouTrack
  local response
  response=$(_yt_api "/issues/$issue_number/comments?fields=author(login),text&\$top=10")
  python3 -c "
import json, sys
comments = json.loads(sys.stdin.read())
for c in comments:
    author = c.get('author', {}).get('login', 'unknown')
    body = c.get('text', '')
    print('### ' + author)
    print(body)
    print('---')
" <<< "$response"
}

tracker_post_comment() {
  local issue_number="$1"
  # $2 (repo) is unused for YouTrack
  local body_file="$3"
  local text
  text=$(cat "$body_file")
  _yt_api "/issues/$issue_number/comments" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json,sys; print(json.dumps({'text': sys.stdin.read()}))" <<< "$text")"
}
