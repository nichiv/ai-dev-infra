#!/usr/bin/env bash
# Codex AI レビュー実行スクリプト
# Usage: run-codex.sh <primary_model> <fallback_model> <prompt> <output_file> <timeout>
# Exit codes: 0=成功, 1=失敗

set -euo pipefail

PRIMARY="$1"
FALLBACK="$2"
PROMPT="$3"
OUTPUT="$4"
TIMEOUT="${5:-600}"
PROGRESS="${OUTPUT%.md}_progress.jsonl"

_run_with_timeout() {
  perl -e 'alarm shift @ARGV; exec @ARGV' "$TIMEOUT" "$@"
}

if _run_with_timeout codex exec -m "$PRIMARY" --json -o "$OUTPUT" "$PROMPT" > "$PROGRESS" 2>&1; then
  exit 0
fi

echo "[Codex] Primary ($PRIMARY) failed. Trying fallback ($FALLBACK)..." >&2
if _run_with_timeout codex exec -m "$FALLBACK" --json -o "$OUTPUT" "$PROMPT" > "$PROGRESS" 2>&1; then
  exit 0
fi

echo "[Codex] Fallback ($FALLBACK) also failed." >&2
exit 1
