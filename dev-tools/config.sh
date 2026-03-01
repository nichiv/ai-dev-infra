#!/usr/bin/env bash
# config.sh - .config/*.yml から設定値を読み込むヘルパー
#
# Usage:
#   source dev-tools/config.sh
#   REPO=$(config_get '.repository.full_name')
#   CLAUDE_MODEL=$(ai_model_get '.claude.primary')
#
# 環境変数:
#   CONFIG_DIR  - 設定ファイルのディレクトリ（デフォルト: <repo_root>/.config）

_CONFIG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# CONFIG_DIR が未設定の場合、リポジトリルートの .config を使用
if [ -z "${CONFIG_DIR:-}" ]; then
  _REPO_ROOT="$(cd "$_CONFIG_SCRIPT_DIR" && git rev-parse --show-toplevel 2>/dev/null || echo "$_CONFIG_SCRIPT_DIR/..")"
  CONFIG_DIR="${_REPO_ROOT}/.config"
fi

PROJECT_CONFIG="${CONFIG_DIR}/project.yml"
AI_MODELS_CONFIG="${CONFIG_DIR}/ai-models.yml"

_yaml_get() {
  local file="$1" path="$2"
  python3 -c "
import sys

def parse(filepath):
    result, stack, indents = {}, [{}], [-1]
    with open(filepath) as f:
        for line in f:
            s = line.rstrip()
            if not s or s.lstrip().startswith('#'):
                continue
            indent = len(line) - len(line.lstrip())
            parts = s.strip().split(':', 1)
            if len(parts) != 2:
                continue
            key, val = parts[0].strip(), parts[1].strip()
            while indent <= indents[-1]:
                stack.pop(); indents.pop()
            if val:
                stack[-1][key] = val
            else:
                d = {}
                stack[-1][key] = d
                stack.append(d)
                indents.append(indent)
    return stack[0]

path = sys.argv[1].lstrip('.').split('.')
data = parse(sys.argv[2])
for p in path:
    data = data[p]
print(data)
" "$path" "$file"
}

config_get() {
  local value
  value=$(_yaml_get "$PROJECT_CONFIG" "$1") || {
    echo "ERROR: Failed to read '$1' from $PROJECT_CONFIG" >&2
    return 1
  }
  echo "$value"
}

ai_model_get() {
  local value
  value=$(_yaml_get "$AI_MODELS_CONFIG" "$1") || {
    echo "ERROR: Failed to read '$1' from $AI_MODELS_CONFIG" >&2
    return 1
  }
  echo "$value"
}
