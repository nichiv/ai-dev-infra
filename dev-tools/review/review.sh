#!/usr/bin/env bash
# review.sh - Claude CLI + Gemini CLI + Codex CLI による並列コードレビュー
#
# Usage:
#   ./dev-tools/review/review.sh review <issue_number>              # レビュー実行
#   ./dev-tools/review/review.sh review <issue_number> --with-codex # Codex も含めて実行
#
# 動作:
#   - tmp/review/combined-review-N.md が存在する場合: 前回指摘の修正確認も実施
#   - 存在しない場合: 初回レビューとして実行
#
# 終了コード:
#   0 = LGTM（ブロック対象の指摘なし）
#   1 = 指摘あり
#
# 設定ファイル:
#   .config/project.yml     - リポジトリ情報
#   .config/review.yml      - レビュー設定
#   .config/ai-models.yml   - AIモデル設定
#
# 必須ファイル:
#   dev-tools/review/perspectives.md           - レビュー観点（必須）
#
# オプション:
#   dev-tools/review/additional_perspectives/  - 追加観点（*.md を自動読み込み）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../config.sh"
source "${SCRIPT_DIR}/../issue-tracker/loader.sh"

# --- 引数チェック ---
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 review <issue_number> [--with-codex]"
  exit 1
fi

SUBCOMMAND="$1"
ISSUE_NUMBER="$2"

if [ "$SUBCOMMAND" != "review" ]; then
  echo "Unknown subcommand: $SUBCOMMAND"
  echo "Usage: $0 review <issue_number> [--with-codex]"
  exit 1
fi

# レビュー有効/無効: 設定ファイル > デフォルト(true)
_REVIEW_ENABLED=$(review_get '.enabled' 2>/dev/null) || _REVIEW_ENABLED="true"
if [ "$_REVIEW_ENABLED" != "true" ]; then
  echo "⏭️ AIレビューは無効です（enabled: false）"
  exit 0
fi
unset _REVIEW_ENABLED

# エージェント有効/無効: 設定ファイル > デフォルト
WITH_CLAUDE=$(review_get '.agents.claude' 2>/dev/null) || WITH_CLAUDE="true"
WITH_GEMINI=$(review_get '.agents.gemini' 2>/dev/null) || WITH_GEMINI="true"
WITH_CODEX=$(review_get '.agents.codex' 2>/dev/null) || WITH_CODEX="false"

# CLI フラグで上書き
if [ "${3:-}" = "--with-codex" ]; then
  WITH_CODEX=true
fi

# --- 設定ファイルから読み込み ---
REPO=$(config_get '.repository.full_name')
BASE_BRANCH=$(config_get '.repository.base_branch')

CLAUDE_PRIMARY=$(ai_model_get '.claude.primary')
CLAUDE_FALLBACK=$(ai_model_get '.claude.fallback')
GEMINI_PRIMARY=$(ai_model_get '.gemini.primary')
GEMINI_FALLBACK=$(ai_model_get '.gemini.fallback')
CODEX_PRIMARY=$(ai_model_get '.codex.primary')
CODEX_FALLBACK=$(ai_model_get '.codex.fallback')

REVIEW_DIR="./tmp/review"

# --- レビュー回数の計算 ---
# combined-review-N.md の最大Nを取得
get_latest_review_number() {
  local max=0
  local files
  files=$(ls "$REVIEW_DIR"/combined-review-*.md 2>/dev/null || true)
  for f in $files; do
    if [ -f "$f" ]; then
      local num=$(basename "$f" | sed 's/combined-review-\([0-9]*\)\.md/\1/')
      if [ "$num" -gt "$max" ] 2>/dev/null; then
        max=$num
      fi
    fi
  done
  echo $max
}

LATEST_REVIEW_NUM=$(get_latest_review_number)
CURRENT_REVIEW_NUM=$((LATEST_REVIEW_NUM + 1))
CURRENT_REVIEW_FILE="$REVIEW_DIR/combined-review-${CURRENT_REVIEW_NUM}.md"

# --- 前回レビュー結果の存在チェック ---
HAS_PREVIOUS_REVIEW=false
PREVIOUS_REVIEW=""
PREVIOUS_REVIEW_FILE="$REVIEW_DIR/combined-review-${LATEST_REVIEW_NUM}.md"
if [ "$LATEST_REVIEW_NUM" -gt 0 ] && [ -f "$PREVIOUS_REVIEW_FILE" ]; then
  HAS_PREVIOUS_REVIEW=true
  PREVIOUS_REVIEW=$(cat "$PREVIOUS_REVIEW_FILE")
  echo "📋 前回のレビュー結果（${LATEST_REVIEW_NUM}回目）を検出しました。修正確認も実施します。"
  echo "📝 今回は${CURRENT_REVIEW_NUM}回目のレビューです。"
fi

# --- レビュー観点の読み込み（必須） ---
PERSPECTIVES_FILE="${SCRIPT_DIR}/perspectives.md"
if [ ! -f "$PERSPECTIVES_FILE" ]; then
  echo "❌ レビュー観点ファイルが見つかりません: $PERSPECTIVES_FILE" >&2
  exit 1
fi
PERSPECTIVES=$(cat "$PERSPECTIVES_FILE")

# --- 追加観点の読み込み ---
ADDITIONAL_PERSPECTIVES_DIR="${SCRIPT_DIR}/additional_perspectives"
ADDITIONAL_PERSPECTIVES=""
if [ -d "$ADDITIONAL_PERSPECTIVES_DIR" ]; then
  for f in "$ADDITIONAL_PERSPECTIVES_DIR"/*.md; do
    if [ -f "$f" ]; then
      ADDITIONAL_PERSPECTIVES+="
---
# $(basename "$f" .md)
$(cat "$f")
"
    fi
  done
  if [ -n "$ADDITIONAL_PERSPECTIVES" ]; then
    PERSPECTIVES+="

## 追加観点
$ADDITIONAL_PERSPECTIVES"
  fi
fi

# --- 出力ディレクトリの初期化（前回結果は保持） ---
mkdir -p "$REVIEW_DIR"

# --- 要件の取得 ---
echo "📝 要件を取得中..."

echo "[DEBUG] git diff 開始" >&2
DIFF_NAMES=$(git diff "${BASE_BRANCH}...HEAD" --name-only)
echo "[DEBUG] git diff 完了" >&2

if [ -z "$DIFF_NAMES" ]; then
  echo "❌ ${BASE_BRANCH}...HEAD に差分がありません。"
  exit 1
fi

echo "[DEBUG] tracker_get_issue 開始" >&2
ISSUE_BODY=$(tracker_get_issue "$ISSUE_NUMBER" "$REPO")
echo "[DEBUG] tracker_get_issue 完了" >&2

# 前回レビューありの場合、コメントも取得
COMMENTS=""
if [ "$HAS_PREVIOUS_REVIEW" = true ]; then
  echo "[DEBUG] tracker_get_comments 開始" >&2
  COMMENTS=$(tracker_get_comments "$ISSUE_NUMBER" "$REPO")
  echo "[DEBUG] tracker_get_comments 完了" >&2
fi

# --- タイムアウト付きコマンド実行 ---
# タイムアウト設定: 環境変数 > 設定ファイル > デフォルト
if [ "$WITH_CODEX" = true ]; then
  _DEFAULT_TIMEOUT=$(review_get '.timeout_with_codex' 2>/dev/null) || _DEFAULT_TIMEOUT="900"
else
  _DEFAULT_TIMEOUT=$(review_get '.timeout' 2>/dev/null) || _DEFAULT_TIMEOUT="600"
fi
AGENT_TIMEOUT="${AGENT_TIMEOUT:-$_DEFAULT_TIMEOUT}"
unset _DEFAULT_TIMEOUT

# --- エージェントスクリプトのパス ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_DIR="$SCRIPT_DIR/agents"

# --- 共通の出力フォーマット ---
OUTPUT_FORMAT='```
# レビュー指摘事項

## 🔴 Critical

### [C1] (指摘タイトル)
- **ファイル**: `path/to/file.tsx:行番号`
- **観点**: (該当する観点名)
- **内容**: (具体的な問題の説明)
- **修正案**: (修正方法の説明またはコード)

## 🟠 High

### [H1] (指摘タイトル)
...

## 🟡 Medium

### [M1] (指摘タイトル)
...

## 🟢 Low

### [L1] (指摘タイトル)
...
```'

# --- レビュープロンプト生成 ---
generate_review_prompt() {
  local prompt='あなたはシニアソフトウェアエンジニアのコードレビュアーです。
以下の手順で差分を取得し、Issue の要件と照らし合わせてレビューしてください。

## 手順

1. `git diff '"${BASE_BRANCH}"'...HEAD` を実行して、レビュー対象の差分を取得してください。
2. 必要に応じて `read_file` 等を使用して各ファイルのコード品質を確認してください。

## レビュー観点

'"${PERSPECTIVES}"'

## 出力フォーマット

以下のフォーマットで出力してください。指摘がない場合は「指摘なし」と記載。

'"${OUTPUT_FORMAT}"'

事実ベースの指摘のみ。コードの動作を単に説明するだけの指摘は禁止。
変更された行のみを対象とする（既存コードへの指摘は禁止）。
'

  # 前回レビューがある場合、修正確認タスクを追加
  if [ "$HAS_PREVIOUS_REVIEW" = true ]; then
    prompt+='

## 追加タスク: 前回指摘の修正確認

前回のレビューで以下の指摘がありました。各指摘について修正状況を確認し、出力の冒頭に以下の形式で記載してください。

### 前回指摘の対応状況

| # | 指摘 | 状態 | コメント |
|---|------|------|---------|
| C1 | (指摘内容) | ✅/⚠️/❌ | (確認結果) |

- ✅ 対応済み: 指摘が正しく修正されている
- ⚠️ 部分対応: 一部修正されているが不十分
- ❌ 未対応: 修正されていない

### 前回のレビュー結果

'"${PREVIOUS_REVIEW}"'

### Issue コメント（対応内容）

'"${COMMENTS}"'
'
  fi

  prompt+='
---

## Issue 要件

'"$ISSUE_BODY"'

## 変更ファイル一覧

'"$DIFF_NAMES"'
'

  echo "$prompt"
}

# --- メイン処理 ---
do_review() {
  REVIEW_PROMPT=$(generate_review_prompt)

  # --- エージェントを並列実行 ---
  _AGENTS=()
  [ "$WITH_CLAUDE" = "true" ] && _AGENTS+=("Claude")
  [ "$WITH_GEMINI" = "true" ] && _AGENTS+=("Gemini")
  [ "$WITH_CODEX" = "true" ] && _AGENTS+=("Codex")
  echo "🔍 ${_AGENTS[*]} でレビュー中...（タイムアウト: ${AGENT_TIMEOUT}秒）"

  CLAUDE_PID=""
  GEMINI_PID=""
  CODEX_PID=""

  if [ "$WITH_CLAUDE" = "true" ]; then
    "$AGENTS_DIR/run-claude.sh" "$CLAUDE_PRIMARY" "$CLAUDE_FALLBACK" "$REVIEW_PROMPT" "$REVIEW_DIR/claude-review.md" "$AGENT_TIMEOUT" &
    CLAUDE_PID=$!
  fi

  if [ "$WITH_GEMINI" = "true" ]; then
    "$AGENTS_DIR/run-gemini.sh" "$GEMINI_PRIMARY" "$GEMINI_FALLBACK" "$REVIEW_PROMPT" "$REVIEW_DIR/gemini-review.md" "$AGENT_TIMEOUT" &
    GEMINI_PID=$!
  fi

  if [ "$WITH_CODEX" = "true" ]; then
    "$AGENTS_DIR/run-codex.sh" "$CODEX_PRIMARY" "$CODEX_FALLBACK" "$REVIEW_PROMPT" "$REVIEW_DIR/codex-review.md" "$AGENT_TIMEOUT" &
    CODEX_PID=$!
  fi

  CLAUDE_EXIT=0; GEMINI_EXIT=0; CODEX_EXIT=0
  [ -n "$CLAUDE_PID" ] && { wait $CLAUDE_PID || CLAUDE_EXIT=$?; }
  [ -n "$GEMINI_PID" ] && { wait $GEMINI_PID || GEMINI_EXIT=$?; }
  [ -n "$CODEX_PID" ] && { wait $CODEX_PID || CODEX_EXIT=$?; }

  # 成功したエージェントの結果を収集
  RESULTS=()
  RESULT_LABELS=()
  if [ "$WITH_CLAUDE" = "true" ]; then
    if [ $CLAUDE_EXIT -eq 0 ] && [ -s "$REVIEW_DIR/claude-review.md" ]; then
      RESULTS+=("$(cat "$REVIEW_DIR/claude-review.md")")
      RESULT_LABELS+=("Claude")
    else
      echo "⚠️ Claude CLI が失敗しました。"
    fi
  fi
  if [ "$WITH_GEMINI" = "true" ]; then
    if [ $GEMINI_EXIT -eq 0 ] && [ -s "$REVIEW_DIR/gemini-review.md" ]; then
      RESULTS+=("$(cat "$REVIEW_DIR/gemini-review.md")")
      RESULT_LABELS+=("Gemini")
    else
      echo "⚠️ Gemini CLI が失敗しました。"
    fi
  fi
  if [ "$WITH_CODEX" = "true" ]; then
    if [ $CODEX_EXIT -eq 0 ] && [ -s "$REVIEW_DIR/codex-review.md" ]; then
      RESULTS+=("$(cat "$REVIEW_DIR/codex-review.md")")
      RESULT_LABELS+=("Codex")
    else
      echo "⚠️ Codex CLI が失敗しました。"
    fi
  fi

  if [ ${#RESULTS[@]} -eq 0 ]; then
    echo "❌ review FAILED: 全エージェントが失敗しました。エラーログ: $REVIEW_DIR/*.err" >&2
    exit 1
  fi

  if [ ${#RESULTS[@]} -eq 1 ]; then
    echo "📊 ${RESULT_LABELS[0]} の結果のみ使用します。"
    echo "${RESULTS[0]}" > "$CURRENT_REVIEW_FILE"
  else
    echo "📊 レビュー結果を統合中（${RESULT_LABELS[*]}）..."

    MERGE_PROMPT='あなたはシニアソフトウェアエンジニアです。
複数のレビュー結果を統合してください。

## ルール

1. 重複する指摘は1つにまとめる
2. 深刻度が異なる場合はより高い方を採用
3. 出力フォーマットは以下の形式で統一する
4. 指摘IDは通し番号にする（C1, C2, H1, H2, M1, ...）
5. 指摘がない場合は「指摘なし — LGTM 🎉」と記載
'

    # 前回レビューがある場合、修正確認の統合ルールを追加
    if [ "$HAS_PREVIOUS_REVIEW" = true ]; then
      MERGE_PROMPT+='
6. 前回指摘の対応状況は、全レビュアーの判定を考慮して最終判定する
   - 全員 ✅ → ✅
   - 1人でも ⚠️ → ⚠️（理由を確認）
   - 1人でも ❌ → ❌
7. 出力の冒頭に「## 前回指摘の対応状況」テーブルを含める
'
    fi

    MERGE_PROMPT+='
## 出力フォーマット

```
# コードレビュー結果（統合）
'

    if [ "$HAS_PREVIOUS_REVIEW" = true ]; then
      MERGE_PROMPT+='
## 前回指摘の対応状況

| # | 指摘 | 状態 | コメント |
|---|------|------|---------|
| C1 | (指摘内容) | ✅/⚠️/❌ | (確認結果) |

'
    fi

    MERGE_PROMPT+='
## 🔴 Critical

### [C1] (指摘タイトル)
- **ファイル**: `path/to/file.tsx:行番号`
- **観点**: (該当する観点名)
- **内容**: (具体的な問題の説明)
- **修正案**: (修正方法の説明またはコード)

## 🟠 High
...

## 🟡 Medium
...

## 🟢 Low
...
```

---
'

    for i in "${!RESULTS[@]}"; do
      MERGE_PROMPT+="
## ${RESULT_LABELS[$i]} のレビュー結果

${RESULTS[$i]}
"
    done

    CLAUDECODE= claude --print --model "$CLAUDE_PRIMARY" "$MERGE_PROMPT" > "$CURRENT_REVIEW_FILE" 2>/dev/null || \
      CLAUDECODE= claude --print --model "$CLAUDE_FALLBACK" "$MERGE_PROMPT" > "$CURRENT_REVIEW_FILE" 2>/dev/null
  fi

  # --- issue にコメント ---
  _COMMENT_ENABLED=$(review_get '.comment' 2>/dev/null) || _COMMENT_ENABLED="true"
  if [ "$_COMMENT_ENABLED" = "true" ]; then
    echo "💬 Issue #$ISSUE_NUMBER にコメント中..."
    tracker_post_comment "$ISSUE_NUMBER" "$REPO" "$CURRENT_REVIEW_FILE"
  else
    echo "⏭️ Issueコメントは無効です（comment: false）"
  fi
  unset _COMMENT_ENABLED

  # --- 判定 ---
  RESULT=$(cat "$CURRENT_REVIEW_FILE")

  # ブロック設定を読み込み
  _BLOCK_CRITICAL=$(review_get '.block.critical' 2>/dev/null) || _BLOCK_CRITICAL="true"
  _BLOCK_HIGH=$(review_get '.block.high' 2>/dev/null) || _BLOCK_HIGH="true"
  _BLOCK_MEDIUM=$(review_get '.block.medium' 2>/dev/null) || _BLOCK_MEDIUM="true"
  _BLOCK_LOW=$(review_get '.block.low' 2>/dev/null) || _BLOCK_LOW="false"

  # 前回指摘に ❌/⚠️ があればブロック
  if [ "$HAS_PREVIOUS_REVIEW" = true ]; then
    if echo "$RESULT" | grep -qE '❌|⚠️'; then
      echo ""
      echo "========================================" >&2
      echo "❌ review FAILED: 前回指摘への対応が不十分です" >&2
      echo "========================================" >&2
      echo "" >&2
      echo "レビュー結果:" >&2
      cat "$CURRENT_REVIEW_FILE" >&2
      echo "" >&2
      echo "ファイル: $CURRENT_REVIEW_FILE" >&2
      echo "========================================" >&2
      exit 1
    fi
  fi

  # ブロック設定に基づいて判定
  _BLOCK_PATTERN=""
  [ "$_BLOCK_CRITICAL" = "true" ] && _BLOCK_PATTERN+='\[C[0-9]+\]|'
  [ "$_BLOCK_HIGH" = "true" ] && _BLOCK_PATTERN+='\[H[0-9]+\]|'
  [ "$_BLOCK_MEDIUM" = "true" ] && _BLOCK_PATTERN+='\[M[0-9]+\]|'
  [ "$_BLOCK_LOW" = "true" ] && _BLOCK_PATTERN+='\[L[0-9]+\]|'
  _BLOCK_PATTERN="${_BLOCK_PATTERN%|}"  # 末尾の | を削除

  if [ -n "$_BLOCK_PATTERN" ] && echo "$RESULT" | grep -qE "$_BLOCK_PATTERN"; then
    echo ""
    echo "========================================" >&2
    echo "❌ review FAILED: ブロック対象の指摘があります" >&2
    echo "========================================" >&2
    echo "" >&2
    echo "レビュー結果:" >&2
    cat "$CURRENT_REVIEW_FILE" >&2
    echo "" >&2
    echo "ファイル: $CURRENT_REVIEW_FILE" >&2
    echo "========================================" >&2
    exit 1
  fi

  echo ""
  echo "========================================" >&2
  echo "✅ review 完了: ブロック対象の指摘なし" >&2
  echo "========================================" >&2
  echo "" >&2
  echo "レビュー結果:" >&2
  cat "$CURRENT_REVIEW_FILE" >&2
  echo "" >&2
  echo "ファイル: $CURRENT_REVIEW_FILE" >&2
  echo "========================================" >&2
}

# --- サブコマンド実行 ---
do_review
