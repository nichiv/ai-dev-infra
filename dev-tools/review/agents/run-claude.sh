#!/usr/bin/env bash
# Claude AI レビュー実行スクリプト
# Usage: run-claude.sh <primary_model> <fallback_model> <prompt> <output_file> <timeout>
# Exit codes: 0=成功, 1=失敗

set -euo pipefail

PRIMARY="$1"
FALLBACK="$2"
PROMPT="$3"
OUTPUT="$4"
TIMEOUT="${5:-600}"
ERRLOG="${OUTPUT%.md}.err"

_run_with_timeout() {
  perl -e 'alarm shift @ARGV; exec @ARGV' "$TIMEOUT" "$@"
}

# pre-push hook から呼ばれた場合、CLAUDECODE が継承されてネスト禁止になるため unset
if CLAUDECODE= _run_with_timeout claude --print --model "$PRIMARY" "$PROMPT" > "$OUTPUT" 2>"$ERRLOG"; then
  exit 0
fi

echo "[Claude] Primary ($PRIMARY) failed. Trying fallback ($FALLBACK)..." >&2
if CLAUDECODE= _run_with_timeout claude --print --model "$FALLBACK" "$PROMPT" > "$OUTPUT" 2>"$ERRLOG"; then
  exit 0
fi

echo "[Claude] Fallback ($FALLBACK) also failed." >&2
exit 1
