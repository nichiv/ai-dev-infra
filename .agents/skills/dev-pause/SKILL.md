---
description: 開発中断 - 作業中断・引き継ぎ
user-invocable: true
disable-model-invocation: true
name: dev-pause
---

# Pause - 作業中断・引き継ぎ

現在の作業を中断し、進捗をまとめて issue に引き継ぎ情報を投稿します。

---

## 使用方法

```
/dev-pause
```

---

## 処理フロー

### Step 1: Issue 番号の取得

ブランチ名から issue 番号を取得する:

```bash
git branch --show-current
# → <branch_prefix>-<N> から N を抽出
```

ブランチ命名規約はプロジェクトの CLAUDE.md または `.config/project.yml` の `branch_prefix` を参照する。

### Step 2: 計画ファイルの読み込み

`./tmp/plan-<N>.md` を読み込み、全体の実装計画を把握する。

### Step 3: 現在の進捗確認

```bash
git diff --stat
git status
```

### Step 4: Issue body の「やること」チェックリスト確認

```bash
gh issue view <N> --json body --jq .body
```

「やること」セクションのチェックリストから、完了/未完了を把握する。

### Step 5: 引き継ぎ事項の作成

以下の内容を整理して `/tmp/handoff-<N>.md` に保存:

```markdown
# 引き継ぎ事項 — YYYY-MM-DD

## 完了済みの作業
- （チェックリストの完了済み項目）

## 進行中の作業と現在地
- （現在取り組んでいるタスクと進捗状況）

## 未着手の作業
- （チェックリストの未完了項目）

## 注意事項・ブロッカー
- （実装中に気づいた注意点、判断保留事項、ブロッカー等）

## 未コミットの変更
- （`git status` / `git diff --stat` の結果から、未コミットの変更の有無と内容）
```

### Step 6: 引き継ぎコメントの投稿

```bash
gh issue comment <N> --body-file /tmp/handoff-<N>.md
```

投稿後、コメント URL を控える。

### Step 7: Issue body の更新

1. `gh issue view <N> --json body --jq .body` で現在の body を取得
2. 以下を更新:
   - **やること**: チェックリストを最新状態に更新
   - **引き継ぎ**: セクションを追加（または追記）し、コメント URL を記載
3. `/tmp/issue-body-<N>.md` に保存
4. `gh issue edit <N> --body-file /tmp/issue-body-<N>.md` で更新

**引き継ぎセクションの形式:**

```markdown
## 引き継ぎ
- [引き継ぎ事項](コメントURL) — YYYY-MM-DD
```

既に引き継ぎセクションがある場合は、新しいエントリを追記する。

### Step 8: 完了報告

ユーザーに以下を報告:
- 引き継ぎコメントの URL
- 進捗サマリー（完了/未完了の概要）

---

## 重要ルール

- **コードの変更はしない:** このスキルは状況整理と記録のみ
- **コミットはしない:** 未コミットの変更はそのまま残す
- **正確に記録する:** 推測ではなく、実際の差分・ステータスに基づいて記録する
