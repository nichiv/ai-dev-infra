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

### Step 3: 計画ファイル確認

```bash
ls ./tmp/plan-{issue_id}.md 2>/dev/null
```

- 存在する場合 → 計画を読み込み
- 存在しない場合 → Issueの作業計画セクションを参照

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

- 計画ファイル（./tmp/plan-{issue_id}.md）があれば読み込み
- GH Issueの作業状況セクションからコンテキストを復元
- Status は自動で In Progress に変更
- 直接 gh CLI でIssue取得（外部サービスに依存しない）
- 外部同期が必要な場合は /task-sync-external を使用
