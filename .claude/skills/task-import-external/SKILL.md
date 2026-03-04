---
description: 外部入力 - 外部Issue管理システムからGitHub Issueにインポート
user-invocable: true
disable-model-invocation: true
name: task-import-external
---

# 外部入力

外部Issue管理システム（YouTrack等）からGitHub Issueにインポートする。
外部Issue の description は外部サービスセクションに非表示で埋め込む。

---

## 使用方法

```
/task-import-external <EXTERNAL_ISSUE_ID>
```

引数: $ARGUMENTS

- `project-123` / `issue-456` 等（外部サービスのIssue ID）

---

## 設定ファイル

**パス**: `.config/project.yml`

処理開始時に設定ファイルを読み込み、以下の値を取得：

```yaml
# 使用する設定項目
github_project.project_id        # PROJECT_ID
github_project.project_number    # プロジェクト番号
github_project.repository        # REPO

github_project.fields.status.id                    # STATUS_FIELD_ID
github_project.fields.status.options.todo          # STATUS_TODO

github_project.fields.project.id                   # PROJECT_FIELD_ID
github_project.fields.project.options.<project>    # PROJECT_OPTION_ID

github_project.fields.sprint.id                    # SPRINT_FIELD_ID

external.base_url   # EXTERNAL_BASE_URL
external.service    # EXTERNAL_SERVICE (youtrack等)
```

**読み込み方法**:
```bash
# yqコマンドで読み込み
PROJECT_ID=$(yq '.github_project.project_id' .config/project.yml)
REPO=$(yq '.github_project.repository' .config/project.yml)
EXTERNAL_BASE_URL=$(yq '.external.base_url' .config/project.yml)
# ... 以下同様
```

---

## 処理フロー

### Step 1: 外部Issue情報取得

MCP または API を使用:

```
# YouTrackの場合
mcp__youtrack__get_issue:
  issueId: {EXTERNAL_ISSUE_ID}
```

取得項目:
- summary: タイトル
- description: Issue本文（外部サービスセクションに埋め込む）

### Step 2: 既存GH Issue検索

```bash
gh issue list --repo {REPO} --search "in:title {EXTERNAL_ISSUE_ID}" --json number,title
```

- 見つかった場合 → そのIssueを使用（スキップ通知）
- 見つからない場合 → 新規作成

### Step 3: GH Issue作成（新規の場合）

```bash
gh issue create --repo {REPO} \
  --title "{EXTERNAL_ISSUE_ID}: {External Issue Summary}" \
  --body-file /tmp/issue-body.md
```

**Issueボディフォーマット:**

```markdown
---
external:
  {service}: {EXTERNAL_BASE_URL}/issue/{EXTERNAL_ISSUE_ID}
---

## 概要

{External Issue Description から概要を抽出}

## 関連

- 依頼元: （あれば）

## 外部サービス

外部サービスから取得したissueの関連情報

### {service}

<!-- {service}-body-start
{External Issue Description の内容をそのまま埋め込み}
{service}-body-end -->

## 作業計画

（/dev-plan で記録）

### 方針

[実装方針・設計概要]

### タスク

- [ ] タスク1
- [ ] タスク2
- [ ] タスク3

## 作業状況

### 最終更新: -

**進捗**:
- (なし)

**ブロッカー**:
- (なし)

**次のアクション**:
- 作業計画を立てる
```

### Step 4: プロジェクト追加・フィールド設定

```bash
gh project item-add {PROJECT_NUMBER} --owner @me --url {issue_url}
ITEM_ID=$(gh project item-list {PROJECT_NUMBER} --owner @me --limit 100 --format json | jq -r '.items[] | select(.content.number == {issue_number}) | .id')
```

**Project フィールド（EXTERNAL_ISSUE_IDのプレフィックスから判定）:**
- `project_a-*` → PROJECT_OPTION_A
- `project_b-*` → PROJECT_OPTION_B

**Status: Todo**

```bash
gh api graphql -f query='
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "{PROJECT_ID}"
    itemId: "{ITEM_ID}"
    fieldId: "{STATUS_FIELD_ID}"
    value: { singleSelectOptionId: "{STATUS_TODO}" }
  }) { projectV2Item { id } }
}'
```

### Step 5: Sprint設定（現在週）

```bash
MONDAY=$(date -v-$(date +%u)d+1d +%Y-%m-%d)

gh api graphql -f query='
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "{PROJECT_ID}"
    itemId: "{ITEM_ID}"
    fieldId: "{SPRINT_FIELD_ID}"
    value: { iterationId: "{SPRINT_ITERATION_ID}" }
  }) { projectV2Item { id } }
}'
```

### Step 6: 完了報告

```
✅ 外部入力完了

📋 Issue: #{issue_number} {title}
🔗 https://github.com/{REPO}/issues/{issue_number}

📌 Status: Todo
📂 Project: {project}
📅 Sprint: {sprint}

---

## Issue概要

{Issue概要}

## 作業計画

（/dev-plan で計画を作成してください）

---

💡 次のステップ: /dev-plan で作業計画を作成
```

---

## 注意事項

- 外部 → GH の一方向インポート
- 既存のGH Issueがある場合は再利用（重複作成しない）
- Status は Todo で作成（作業開始は /dev-plan で行う）
- YAML Front Matterでexternal linkを管理
- **外部サービスセクションに description を非表示で埋め込み**
- GH IssueのタイトルにはExternal Issue IDを含める
- 埋め込んだbodyは task-sync-external で差分検出に使用
