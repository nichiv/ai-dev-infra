#!/usr/bin/env bash
# Gemini AI レビュー実行スクリプト（rate limit 検知付き）
# Usage: run-gemini.sh <primary_model> <fallback_model> <prompt> <output_file> <timeout>
# Exit codes: 0=成功, 1=失敗, 2=rate limit（primary/fallback両方）

set -uo pipefail

PRIMARY="$1"
FALLBACK="$2"
PROMPT="$3"
OUTPUT="$4"
TIMEOUT="${5:-600}"
ERRLOG="${OUTPUT%.md}.err"

# --- Gemini 実行（rate limit 監視付き）---
# Returns: 0=成功, 2=rate limit, 1=その他エラー
run_gemini() {
  local model="$1"

  # gemini をバックグラウンドで実行
  gemini -m "$model" -p "$PROMPT" > "$OUTPUT" 2>"$ERRLOG" &
  local pid=$!
  echo "[Gemini] Started: pid=$pid, model=$model" >&2

  # タイムアウト用のバックグラウンドプロセス
  ( sleep "$TIMEOUT"; kill -9 $pid 2>/dev/null ) &
  local timeout_pid=$!

  # rate limit 監視ループ
  while kill -0 $pid 2>/dev/null; do
    if grep -q "429\|rateLimitExceeded\|RESOURCE_EXHAUSTED" "$ERRLOG" 2>/dev/null; then
      echo "[Gemini] Rate limit detected. Killing pid=$pid" >&2
      kill -9 $pid 2>/dev/null || true
      kill $timeout_pid 2>/dev/null || true
      wait $pid 2>/dev/null || true
      echo "[Gemini] Process killed." >&2
      return 2
    fi
    sleep 0.5
  done

  # タイムアウトプロセスを停止
  kill $timeout_pid 2>/dev/null || true
  wait $pid 2>/dev/null
  return $?
}

# --- メイン処理 ---

echo "[Gemini] Running primary model: $PRIMARY" >&2
run_gemini "$PRIMARY"
exit_code=$?
echo "[Gemini] Primary exit_code=$exit_code" >&2

if [ $exit_code -eq 0 ]; then
  exit 0
elif [ $exit_code -eq 2 ]; then
  echo "[Gemini] Primary ($PRIMARY) hit rate limit. Trying fallback ($FALLBACK)..." >&2
else
  echo "[Gemini] Primary ($PRIMARY) failed. Trying fallback ($FALLBACK)..." >&2
fi

echo "[Gemini] Running fallback model: $FALLBACK" >&2
run_gemini "$FALLBACK"
exit_code=$?
echo "[Gemini] Fallback exit_code=$exit_code" >&2

if [ $exit_code -eq 0 ]; then
  exit 0
elif [ $exit_code -eq 2 ]; then
  echo "[Gemini] Fallback ($FALLBACK) also hit rate limit." >&2
  exit 2
else
  echo "[Gemini] Fallback ($FALLBACK) also failed." >&2
  exit 1
fi
