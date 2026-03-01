#!/usr/bin/env bash
# review.sh - Claude CLI + Gemini CLI + Codex CLI による並列コードレビュー
#
# Usage:
#   ./dev-tools/review.sh review <issue_number>              # 初回レビュー（Claude + Gemini）
#   ./dev-tools/review.sh review <issue_number> --with-codex # Codex も含めて実行
#   ./dev-tools/review.sh re-review <issue_number>           # 再レビュー
#   ./dev-tools/review.sh re-review <issue_number> --with-codex
#
# 終了コード (re-review):
#   0 = LGTM（全指摘対応済み、新規指摘なし）
#   1 = 追加指摘あり
#
# 設定ファイル:
#   .config/project.yml     - リポジトリ情報
#   .config/ai-models.yml   - AIモデル設定
#
# カスタマイズ:
#   dev-tools/perspectives.md  - レビュー観点（存在する場合に使用）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/issue-tracker/loader.sh"

# --- 引数チェック ---
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "Usage: $0 <review|re-review> <issue_number> [--with-codex]"
  exit 1
fi

SUBCOMMAND="$1"
ISSUE_NUMBER="$2"

# レビュー有効/無効: 設定ファイル > デフォルト(true)
_REVIEW_ENABLED=$(config_get '.review.enabled' 2>/dev/null) || _REVIEW_ENABLED="true"
if [ "$_REVIEW_ENABLED" != "true" ]; then
  echo "⏭️ AIレビューは無効です（review.enabled: false）"
  exit 0
fi
unset _REVIEW_ENABLED

# Codex 実行: CLI フラグ > 設定ファイル > デフォルト(false)
_CONFIG_WITH_CODEX=$(config_get '.review.with_codex' 2>/dev/null) || _CONFIG_WITH_CODEX="false"
WITH_CODEX="$_CONFIG_WITH_CODEX"
unset _CONFIG_WITH_CODEX

if [ "${3:-}" = "--with-codex" ]; then
  WITH_CODEX=true
fi

if [ "$SUBCOMMAND" != "review" ] && [ "$SUBCOMMAND" != "re-review" ]; then
  echo "Unknown subcommand: $SUBCOMMAND"
  echo "Usage: $0 <review|re-review> <issue_number> [--with-codex]"
  exit 1
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

# --- レビュー観点の読み込み ---
PERSPECTIVES_FILE="${SCRIPT_DIR}/perspectives.md"
if [ -f "$PERSPECTIVES_FILE" ]; then
  PERSPECTIVES=$(cat "$PERSPECTIVES_FILE")
else
  # デフォルトのレビュー観点
  PERSPECTIVES='### 観点1: 要件充足 🔴
Issue で定義された要件を全て満たしているか。各要件に対応する実装があるか。

### 観点2: 不適切な変更 🔴
- テストのアサーションをバグに合わせて変更していないか
- @ts-ignore / eslint-disable でエラーを不正に抑制していないか
- 型安全性の低下（any の多用、不要な型アサーション as）
- 認証・認可チェックの削除や弱体化
- バリデーションの削除・無効化
- テストの skip / xtest / .only の放置
- デバッグコード（console.log, debug: true）の混入
- コメントアウトされたコードの放置
- 環境変数やシークレットのハードコーディング

### 観点3: セキュリティ 🔴
SQLインジェクション、XSS、CSRF、認証バイパス、権限昇格、シークレットの露出、未検証の外部入力

### 観点4: 破壊的変更 🟠
公開APIの引数・戻り値の型変更、DBスキーマ変更の影響、既存テストの不必要な変更

### 観点5: アーキテクチャ準拠 🟠
プロジェクト固有のアーキテクチャルールに違反していないか

### 観点6: テストカバレッジ 🟡
新機能に正常系テストがあるか、バリデーションの異常系テストがあるか、認可エラーのテストがあるか

### 観点7: 命名規約 🟡
プロジェクトの命名規約に準拠しているか

### 観点8: コード品質 🟢
可読性、命名の適切さ、不要な複雑さ、重複コード、エラーハンドリングの不足'
fi

# --- 出力ディレクトリの初期化 ---
rm -rf "$REVIEW_DIR"
mkdir -p "$REVIEW_DIR"

# --- 要件の取得 ---
echo "📝 要件を取得中..."

DIFF_NAMES=$(git diff "${BASE_BRANCH}...HEAD" --name-only)

if [ -z "$DIFF_NAMES" ]; then
  echo "❌ ${BASE_BRANCH}...HEAD に差分がありません。"
  exit 1
fi

ISSUE_BODY=$(tracker_get_issue "$ISSUE_NUMBER" "$REPO")

# --- タイムアウト付きコマンド実行 ---
# macOS には timeout コマンドがないため perl で代替
if [ "$WITH_CODEX" = true ]; then
  AGENT_TIMEOUT="${AGENT_TIMEOUT:-900}"   # Codex 込み: 15分
else
  AGENT_TIMEOUT="${AGENT_TIMEOUT:-300}"   # デフォルト: 5分
fi

_run_with_timeout() {
  perl -e 'alarm shift @ARGV; exec @ARGV' "$AGENT_TIMEOUT" "$@"
}

# --- エージェント実行ヘルパー ---
# run_agent <name> <primary_model> <fallback_model> <prompt> <output_file>
run_agent() {
  local name="$1" primary="$2" fallback="$3" prompt="$4" output="$5"
  local errlog="${output%.md}.err"

  case "$name" in
    claude)
      # pre-push hook から呼ばれた場合、CLAUDECODE が継承されてネスト禁止になるため unset
      if CLAUDECODE= _run_with_timeout claude --print --model "$primary" "$prompt" > "$output" 2>"$errlog"; then
        return 0
      fi
      echo "⚠️ Claude (${primary}) 失敗。fallback (${fallback}) でリトライ..."
      if CLAUDECODE= _run_with_timeout claude --print --model "$fallback" "$prompt" > "$output" 2>"$errlog"; then
        return 0
      fi
      return 1
      ;;
    gemini)
      if _run_with_timeout gemini -m "$primary" -p "$prompt" > "$output" 2>"$errlog"; then
        return 0
      fi
      echo "⚠️ Gemini (${primary}) 失敗。fallback (${fallback}) でリトライ..."
      if _run_with_timeout gemini -m "$fallback" -p "$prompt" > "$output" 2>"$errlog"; then
        return 0
      fi
      return 1
      ;;
    codex)
      local progress="${output%.md}_progress.jsonl"
      if _run_with_timeout codex exec -m "$primary" --json -o "$output" "$prompt" > "$progress" 2>&1; then
        return 0
      fi
      echo "⚠️ Codex (${primary}) 失敗。fallback (${fallback}) でリトライ..."
      if _run_with_timeout codex exec -m "$fallback" --json -o "$output" "$prompt" > "$progress" 2>&1; then
        return 0
      fi
      return 1
      ;;
  esac
}

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

# ==========================================
# review サブコマンド
# ==========================================
do_review() {
  # --- レビュープロンプト ---
  REVIEW_PROMPT='あなたはシニアソフトウェアエンジニアのコードレビュアーです。
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

---

## Issue 要件

'"$ISSUE_BODY"'

## 変更ファイル一覧

'"$DIFF_NAMES"'
'

  # --- エージェントを並列実行 ---
  if [ "$WITH_CODEX" = true ]; then
    echo "🔍 Claude + Gemini + Codex でレビュー中...（タイムアウト: ${AGENT_TIMEOUT}秒）"
  else
    echo "🔍 Claude + Gemini でレビュー中...（タイムアウト: ${AGENT_TIMEOUT}秒）"
  fi

  run_agent claude "$CLAUDE_PRIMARY" "$CLAUDE_FALLBACK" "$REVIEW_PROMPT" "$REVIEW_DIR/claude-review.md" &
  CLAUDE_PID=$!

  run_agent gemini "$GEMINI_PRIMARY" "$GEMINI_FALLBACK" "$REVIEW_PROMPT" "$REVIEW_DIR/gemini-review.md" &
  GEMINI_PID=$!

  CODEX_PID=""
  if [ "$WITH_CODEX" = true ]; then
    run_agent codex "$CODEX_PRIMARY" "$CODEX_FALLBACK" "$REVIEW_PROMPT" "$REVIEW_DIR/codex-review.md" &
    CODEX_PID=$!
  fi

  CLAUDE_EXIT=0; GEMINI_EXIT=0; CODEX_EXIT=0
  wait $CLAUDE_PID || CLAUDE_EXIT=$?
  wait $GEMINI_PID || GEMINI_EXIT=$?
  if [ -n "$CODEX_PID" ]; then
    wait $CODEX_PID || CODEX_EXIT=$?
  fi

  # 成功したエージェントの結果を収集
  RESULTS=()
  RESULT_LABELS=()
  if [ $CLAUDE_EXIT -eq 0 ] && [ -s "$REVIEW_DIR/claude-review.md" ]; then
    RESULTS+=("$(cat "$REVIEW_DIR/claude-review.md")")
    RESULT_LABELS+=("Claude")
  else
    echo "⚠️ Claude CLI が失敗しました。"
  fi
  if [ $GEMINI_EXIT -eq 0 ] && [ -s "$REVIEW_DIR/gemini-review.md" ]; then
    RESULTS+=("$(cat "$REVIEW_DIR/gemini-review.md")")
    RESULT_LABELS+=("Gemini")
  else
    echo "⚠️ Gemini CLI が失敗しました。"
  fi
  if [ "$WITH_CODEX" = true ]; then
    if [ $CODEX_EXIT -eq 0 ] && [ -s "$REVIEW_DIR/codex-review.md" ]; then
      RESULTS+=("$(cat "$REVIEW_DIR/codex-review.md")")
      RESULT_LABELS+=("Codex")
    else
      echo "⚠️ Codex CLI が失敗しました。"
    fi
  fi

  if [ ${#RESULTS[@]} -eq 0 ]; then
    echo "❌ 全エージェントが失敗しました。"
    exit 1
  fi

  if [ ${#RESULTS[@]} -eq 1 ]; then
    echo "📊 ${RESULT_LABELS[0]} の結果のみ使用します。"
    echo "${RESULTS[0]}" > "$REVIEW_DIR/combined-review.md"
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

## 出力フォーマット

```
# コードレビュー結果（統合）

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

    CLAUDECODE= claude --print --model "$CLAUDE_PRIMARY" "$MERGE_PROMPT" > "$REVIEW_DIR/combined-review.md" 2>/dev/null || \
      CLAUDECODE= claude --print --model "$CLAUDE_FALLBACK" "$MERGE_PROMPT" > "$REVIEW_DIR/combined-review.md" 2>/dev/null
  fi

  # --- issue にコメント ---
  echo "💬 Issue #$ISSUE_NUMBER にコメント中..."
  tracker_post_comment "$ISSUE_NUMBER" "$REPO" "$REVIEW_DIR/combined-review.md"

  echo "✅ レビュー完了: $REVIEW_DIR/combined-review.md"
}

# ==========================================
# re-review サブコマンド
# ==========================================
do_re_review() {
  # --- 追加情報の取得 ---
  COMMENTS=$(tracker_get_comments "$ISSUE_NUMBER" "$REPO")

  # --- 再レビュープロンプト ---
  RE_REVIEW_PROMPT='あなたはシニアソフトウェアエンジニアのコードレビュアーです。
前回のレビュー指摘に対する修正対応を確認し、再レビューを行ってください。

## 手順

1. `git diff '"${BASE_BRANCH}"'...HEAD` を実行して、最新の差分を取得してください。
2. 必要に応じて `read_file` 等を使用して各ファイルのコード品質を確認してください。

## タスク

1. 前回の指摘事項に対して、以下を判定:
   - ✅ 対応済み: 指摘が正しく修正されている
   - ⚠️ 部分対応: 一部修正されているが不十分
   - ❌ 未対応: 修正されていない

2. 新たに発見した問題があれば追加指摘

## 出力フォーマット

```
# 再レビュー結果

## 前回指摘の対応状況

| # | 指摘 | 状態 | コメント |
|---|------|------|---------|
| C1 | (指摘内容) | ✅/⚠️/❌ | (確認結果) |
| H1 | (指摘内容) | ✅/⚠️/❌ | (確認結果) |

## 新規指摘

(なければ「新規指摘なし」)

### [N1] (指摘タイトル)
- **ファイル**: `path/to/file.tsx:行番号`
- **観点**: (該当する観点名)
- **深刻度**: 🔴/🟠/🟡/🟢
- **内容**: (具体的な問題の説明)
- **修正案**: (修正方法)

## 判定

LGTM / 要修正
```

---

## Issue 要件

'"$ISSUE_BODY"'

## Issue コメント（レビュー指摘・対応内容）

'"$COMMENTS"'

## 変更ファイル一覧

'"$DIFF_NAMES"'
'

  # --- エージェントを並列実行 ---
  if [ "$WITH_CODEX" = true ]; then
    echo "🔍 Claude + Gemini + Codex で再レビュー中...（タイムアウト: ${AGENT_TIMEOUT}秒）"
  else
    echo "🔍 Claude + Gemini で再レビュー中...（タイムアウト: ${AGENT_TIMEOUT}秒）"
  fi

  run_agent claude "$CLAUDE_PRIMARY" "$CLAUDE_FALLBACK" "$RE_REVIEW_PROMPT" "$REVIEW_DIR/claude-re-review.md" &
  CLAUDE_PID=$!

  run_agent gemini "$GEMINI_PRIMARY" "$GEMINI_FALLBACK" "$RE_REVIEW_PROMPT" "$REVIEW_DIR/gemini-re-review.md" &
  GEMINI_PID=$!

  CODEX_PID=""
  if [ "$WITH_CODEX" = true ]; then
    run_agent codex "$CODEX_PRIMARY" "$CODEX_FALLBACK" "$RE_REVIEW_PROMPT" "$REVIEW_DIR/codex-re-review.md" &
    CODEX_PID=$!
  fi

  CLAUDE_EXIT=0; GEMINI_EXIT=0; CODEX_EXIT=0
  wait $CLAUDE_PID || CLAUDE_EXIT=$?
  wait $GEMINI_PID || GEMINI_EXIT=$?
  if [ -n "$CODEX_PID" ]; then
    wait $CODEX_PID || CODEX_EXIT=$?
  fi

  # 成功したエージェントの結果を収集
  RESULTS=()
  RESULT_LABELS=()
  if [ $CLAUDE_EXIT -eq 0 ] && [ -s "$REVIEW_DIR/claude-re-review.md" ]; then
    RESULTS+=("$(cat "$REVIEW_DIR/claude-re-review.md")")
    RESULT_LABELS+=("Claude")
  else
    echo "⚠️ Claude CLI が失敗しました。"
  fi
  if [ $GEMINI_EXIT -eq 0 ] && [ -s "$REVIEW_DIR/gemini-re-review.md" ]; then
    RESULTS+=("$(cat "$REVIEW_DIR/gemini-re-review.md")")
    RESULT_LABELS+=("Gemini")
  else
    echo "⚠️ Gemini CLI が失敗しました。"
  fi
  if [ "$WITH_CODEX" = true ]; then
    if [ $CODEX_EXIT -eq 0 ] && [ -s "$REVIEW_DIR/codex-re-review.md" ]; then
      RESULTS+=("$(cat "$REVIEW_DIR/codex-re-review.md")")
      RESULT_LABELS+=("Codex")
    else
      echo "⚠️ Codex CLI が失敗しました。"
    fi
  fi

  if [ ${#RESULTS[@]} -eq 0 ]; then
    echo "❌ 全エージェントが失敗しました。"
    exit 1
  fi

  if [ ${#RESULTS[@]} -eq 1 ]; then
    echo "📊 ${RESULT_LABELS[0]} の結果のみ使用します。"
    echo "${RESULTS[0]}" > "$REVIEW_DIR/re-review-result.md"
  else
    echo "📊 再レビュー結果を統合中（${RESULT_LABELS[*]}）..."

    MERGE_PROMPT='あなたはシニアソフトウェアエンジニアです。
複数の再レビュー結果を統合してください。

## ルール

1. 前回指摘の対応状況は、全レビュアーの判定を考慮して最終判定する
   - 全員 ✅ → ✅
   - 1人でも ⚠️ → ⚠️（理由を確認）
   - 1人でも ❌ → ❌
2. 新規指摘は重複を排除して統合
3. LGTM 判定: 全指摘が ✅ かつ新規指摘（🔴/🟠）なし → LGTM

## 出力フォーマット

```
# 再レビュー結果（統合）

## 前回指摘の対応状況

| # | 指摘 | 状態 | コメント |
|---|------|------|---------|
| C1 | (指摘内容) | ✅/⚠️/❌ | (確認結果) |

## 新規指摘

(なければ「新規指摘なし」)

## 判定

LGTM / 要修正
```

---
'

    for i in "${!RESULTS[@]}"; do
      MERGE_PROMPT+="
## ${RESULT_LABELS[$i]} の再レビュー結果

${RESULTS[$i]}
"
    done

    CLAUDECODE= claude --print --model "$CLAUDE_PRIMARY" "$MERGE_PROMPT" > "$REVIEW_DIR/re-review-result.md" 2>/dev/null || \
      CLAUDECODE= claude --print --model "$CLAUDE_FALLBACK" "$MERGE_PROMPT" > "$REVIEW_DIR/re-review-result.md" 2>/dev/null
  fi

  # --- issue にコメント ---
  echo "💬 Issue #$ISSUE_NUMBER にコメント中..."
  tracker_post_comment "$ISSUE_NUMBER" "$REPO" "$REVIEW_DIR/re-review-result.md"

  # --- LGTM 判定 ---
  RESULT=$(cat "$REVIEW_DIR/re-review-result.md")

  if echo "$RESULT" | grep -qi "LGTM"; then
    if ! echo "$RESULT" | grep -qE '❌|⚠️'; then
      echo "✅ LGTM — 全指摘対応済み"
      exit 0
    fi
  fi

  echo "⚠️ 追加対応が必要です。詳細: $REVIEW_DIR/re-review-result.md"
  exit 1
}

# --- サブコマンド実行 ---
case "$SUBCOMMAND" in
  review)     do_review ;;
  re-review)  do_re_review ;;
esac
