---
description: 作業再開 - コンテキスト復元とステータス更新
user-invocable: true
disable-model-invocation: true
name: dev-resume
---

# 作業再開

中断していた作業を再開し、コンテキストを復元する。

---

## 使用方法

```
/dev-resume [Issue ID]
```

引数: $ARGUMENTS

- `#5` → GH Issue番号
- 省略 → 現在のブランチ名から自動判定

---

## 設定ファイル

**パス**: `.config/project.yml`

処理開始時に設定ファイルを読み込み、以下の値を取得：

```yaml
# 使用する設定項目
github_project.project_id        # PROJECT_ID
github_project.project_number    # PROJECT_NUMBER
github_project.repository        # REPO

github_project.fields.status.id                       # STATUS_FIELD_ID
github_project.fields.status.options.in_progress      # STATUS_IN_PROGRESS
```

**読み込み方法**:
```bash
# yqコマンドで読み込み
PROJECT_ID=$(yq '.github_project.project_id' .config/project.yml)
PROJECT_NUMBER=$(yq '.github_project.project_number' .config/project.yml)
REPO=$(yq '.github_project.repository' .config/project.yml)
STATUS_FIELD_ID=$(yq '.github_project.fields.status.id' .config/project.yml)
STATUS_IN_PROGRESS=$(yq '.github_project.fields.status.options.in_progress' .config/project.yml)
```

---

## 処理フロー

### Step 1: Issue特定

**引数なしの場合:**

```bash
git branch --show-current
```

ブランチ名から Issue ID を抽出し、GH Issue を検索。

### Step 2: Issue情報取得

```bash
gh issue view {issue_number} --repo {REPO} --json number,title,body,url
```

### Step 3: 計画ファイル確認（必須）

**作業開始前に必ず計画書を確認すること。このステップを省略してはならない。**

**3-1: 計画ファイルの存在確認**

```bash
ls ./tmp/plan-*.md 2>/dev/null
```

**3-2: 計画ファイルの読み込み**

計画ファイルが存在する場合は必ず内容を読み込む:

```bash
Read: ./tmp/plan-{issue_id}.md
```

読み込んだ内容から以下を確認:
- 実装方針
- タスク分解（完了/未完了の状態）
- リスク・注意点
- 参考資料

**3-3: 計画ファイルが存在しない場合**

計画ファイルがない場合は、GH Issueの作業計画セクションを参照:

```bash
gh issue view {issue_number} --repo {REPO} --json body --jq '.body'
```

`## 作業計画` セクションから方針とタスクを抽出。

**注意:** 計画内容を把握せずに作業を開始してはならない。

### Step 4: GP Status更新: In Progress

```bash
ITEM_ID=$(gh project item-list {PROJECT_NUMBER} --owner @me --limit 100 --format json | jq -r '.items[] | select(.content.number == {issue_number}) | .id')

gh api graphql -f query='
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "{PROJECT_ID}"
    itemId: "{ITEM_ID}"
    fieldId: "{STATUS_FIELD_ID}"
    value: { singleSelectOptionId: "{STATUS_IN_PROGRESS}" }
  }) { projectV2Item { id } }
}'
```

### Step 5: コンテキスト出力

```
✅ 作業再開

📋 Issue: #{issue_number} {title}
🔗 https://github.com/{REPO}/issues/{issue_number}

📌 Status: In Progress

---

## Issue概要

{Issue概要セクション}

---

## 作業計画

### 方針

{作業計画の方針}

### タスク

{タスクリスト（チェック状態含む）}

---

## 前回の作業状況

### 最終更新: {最終更新日時}

**進捗**:
{進捗リスト}

**ブロッカー**:
{ブロッカー}

**次のアクション**:
{次のアクション}

---

💡 次のアクション: {Issue記載の次のアクション}
```

---

## 注意事項

- **計画ファイル（./tmp/plan-{issue_id}.md）の確認は必須**（Step 3を省略しない）
- 計画ファイルがある場合は必ず内容を読み込んでから作業開始
- 計画ファイルがない場合はGH Issueの作業計画セクションを確認
- GH Issueの作業状況セクションからコンテキストを復元
- Status は自動で In Progress に変更
- 直接 gh CLI でIssue取得（外部サービスに依存しない）
- 外部同期が必要な場合は /task-sync-external を使用
