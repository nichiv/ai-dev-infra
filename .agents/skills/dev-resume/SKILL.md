---
description: 開発再開 - 中断した作業の再開
user-invocable: true
disable-model-invocation: true
name: dev-resume
---

# Resume - 中断した作業の再開

中断された issue の作業を再開します。計画・チェックリスト・引き継ぎ情報を読み込み、状況を把握してから実装を続行します。

---

## 使用方法

```
/dev-resume <issue_number>
```

引数: $ARGUMENTS

---

## 処理フロー

### Step 1: ブランチの確認・チェックアウト

```bash
git branch --list <branch_prefix>-<N>
```

- ブランチが存在する → `git checkout <branch_prefix>-<N>`
- ブランチが存在しない → ユーザーに報告して停止

ブランチ命名規約はプロジェクトの CLAUDE.md または `.config/project.yml` の `branch_prefix` を参照する。

### Step 2: Issue body の取得・確認

```bash
gh issue view <N> --json body --jq .body
```

Issue body から以下のセクションを確認:

- **計画書セクション** → 計画コメント URL を取得
- **やることセクション** → 完了/未完了のタスクを把握
- **引き継ぎセクション** → 引き継ぎコメント URL を取得

### Step 3: 計画・引き継ぎ情報の読み込み

1. **計画コメント:** 計画書セクションのコメント URL から計画内容を読む

   ```bash
   gh issue view <N> --json comments --jq '.comments[] | select(.body | startswith("# Issue #<N>")) | .body'
   ```

   または URL からコメント ID を抽出して取得。

2. **計画ファイル:** `./tmp/plan-<N>.md` を読む（なければ計画コメントの内容で復元して保存）

3. **引き継ぎコメント:** 引き継ぎセクションのコメント URL から引き継ぎ内容を読む

   ```bash
   gh issue view <N> --json comments --jq '.comments[] | select(.body | startswith("# 引き継ぎ事項")) | .body'
   ```

### Step 4: サマリーの表示

ユーザーに以下を表示:

- **完了済みの作業:** やることチェックリストの `[x]` 項目
- **未着手の作業:** やることチェックリストの `[ ]` 項目
- **引き継ぎ事項:** 注意点、ブロッカー、進行中の作業状況
- **次にやるべきこと:** 未完了タスクの中で次に取り組むべき項目

### Step 5: 実装の再開

`/dev-execute <N>` と同じフローで実装を再開する。

- 完了済みの手順はスキップ
- 未完了の手順から順に実装
- フェーズ完了時に issue body のチェックリストを更新（dev-execute と同様）

---

## 重要ルール

- **状況把握が最優先:** 計画・引き継ぎを十分に読み込んでから実装に入る
- **計画に忠実:** 計画に書かれていない機能を追加しない
- **引き継ぎの注意事項を尊重:** ブロッカーや判断保留事項がある場合はユーザーに確認
- **完了済みタスクを再実行しない:** チェックリストで完了済みの手順はスキップ
