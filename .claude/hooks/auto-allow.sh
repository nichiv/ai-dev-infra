#!/bin/bash
# Auto-allow hook for Claude Code
# Permission自動許可フック
#
# 使用方法:
#   ~/.claude/settings.json の hooks.PermissionRequest に追加
#   詳細は how-to-use/auto-allow.md を参照
#
# パターン追加:
#   should_allow() 関数内に直接追記

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ログ設定（--debug オプションで有効化）
DEBUG_MODE=false
LOG_FILE=""
for arg in "$@"; do
    [[ "$arg" == "--debug" ]] && DEBUG_MODE=true && LOG_FILE="$SCRIPT_DIR/auto-allow-debug.log"
done

log_debug() {
    [[ "$DEBUG_MODE" == "true" ]] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

log_debug "tool=$TOOL_NAME cmd=${COMMAND:0:80}"

output_allow() {
    log_debug "ALLOWING: $1"
    jq -n '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
}

# 許可パターン定義
# 追加する場合はここに追記
should_allow() {
    local cmd="$1"

    # GitHub CLI
    [[ "$cmd" =~ ^ITEM_ID= ]] && return 0
    [[ "$cmd" =~ gh\ project ]] && return 0
    [[ "$cmd" =~ gh\ api ]] && return 0
    [[ "$cmd" =~ gh\ issue ]] && return 0
    [[ "$cmd" =~ gh\ pr ]] && return 0

    # 読み取り系
    [[ "$cmd" =~ ^ls ]] && return 0
    [[ "$cmd" =~ ^cat ]] && return 0
    [[ "$cmd" =~ ^find ]] && return 0

    # 開発ツール
    [[ "$cmd" =~ ^npm\ run ]] && return 0
    [[ "$cmd" =~ ^git\ fetch ]] && return 0
    [[ "$cmd" =~ ^yq ]] && return 0

    # --- 追加パターンはここに記述 ---
    # [[ "$cmd" =~ ^npx\ eslint ]] && return 0
    # [[ "$cmd" =~ ^docker ]] && return 0

    return 1
}

# MCPツール許可パターン
# 追加する場合はここに追記
should_allow_mcp() {
    local tool="$1"

    # --- MCPパターンはここに記述 ---
    # [[ "$tool" =~ ^mcp__youtrack__ ]] && return 0
    # [[ "$tool" =~ ^mcp__kibela__ ]] && return 0

    return 1
}

# メイン処理
if [[ "$TOOL_NAME" =~ ^mcp__ ]] && should_allow_mcp "$TOOL_NAME"; then
    output_allow "MCP: $TOOL_NAME"
    exit 0
fi

if [[ "$TOOL_NAME" == "Bash" ]] && should_allow "$COMMAND"; then
    output_allow "Bash: $COMMAND"
    exit 0
fi

log_debug "NOT ALLOWED: tool=$TOOL_NAME"
exit 0
