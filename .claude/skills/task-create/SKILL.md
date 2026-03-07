---
description: タスク作成 - GitHub Issue作成とProjects追加
user-invocable: true
disable-model-invocation: true
name: task-create
---

# タスク作成

GitHub Issueを作成し、GitHub Projectsに追加する。

---

## 使用方法

```
/task-create タスク内容 [--source URL]
```

引数: $ARGUMENTS

- `--source`: 依頼元URL（Slack, Kibela等）

---

## 設定ファイル

**パス**: `.config/project.yml`

処理開始時に設定ファイルを読み込み、以下の値を取得：

```yaml
# 使用する設定項目
github_project.project_id        # PROJECT_ID
github_project.project_number    # PROJECT_NUMBER
github_project.repository        # REPO

github_project.fields.status.id                    # STATUS_FIELD_ID
github_project.fields.status.options.todo          # STATUS_TODO

github_project.fields.project.id                   # PROJECT_FIELD_ID
github_project.fields.project.options.<project>    # PROJECT_OPTION_ID

github_project.fields.priority.id                  # PRIORITY_FIELD_ID
github_project.fields.priority.options.<priority>  # PRIORITY_OPTION_ID

github_project.fields.sprint.id                    # SPRINT_FIELD_ID
```

**読み込み方法**:
```bash
# yqコマンドで読み込み
PROJECT_ID=$(yq '.github_project.project_id' .config/project.yml)
PROJECT_NUMBER=$(yq '.github_project.project_number' .config/project.yml)
REPO=$(yq '.github_project.repository' .config/project.yml)
# ... 以下同様
```

---

## 処理フロー

### Step 1: 引数パース

入力からタスク内容とオプションを抽出：
- タイトル: オプション以外の部分
- source: `--source` の値（省略時: なし）

### Step 2: ユーザーへフィールド確認

AskUserQuestion でフィールドを確認:

**質問1: Project**
```
header: "Project"
question: "どのプロジェクトに関連しますか？"
options:
  - label: "personal"
    description: "個人タスク（デフォルト）"
  - label: "project_a"
    description: "プロジェクトA"
  - label: "project_b"
    description: "プロジェクトB"
```

**質問2: Sprint**
```
header: "Sprint"
question: "いつまでに対応しますか？"
options:
  - label: "今週 (YYYY-MM-DD)"
    description: "現在のSprint"
  - label: "来週 (YYYY-MM-DD)"
    description: "次のSprint"
  - label: "再来週 (YYYY-MM-DD)"
    description: "2週間後"
  - label: "バックログ"
    description: "Sprint未設定"
```

**質問3: Priority**
```
header: "Priority"
question: "優先度は？"
options:
  - label: "P2 (Normal)"
    description: "今Sprint内（通常タスク）"
  - label: "P0 (Urgent)"
    description: "即対応（ブロッカー、障害）"
  - label: "P1 (High)"
    description: "今週中（期限あり、依頼タスク）"
  - label: "P3 (Low)"
    description: "いつでも（改善、調査）"
```

### Step 3: タイトル生成

```
フォーマット: "{タスク内容}"

例:
  - "開発環境のDocker化調査"
  - "検索APIのパフォーマンス改善"

※ 外部サービス紐付けは /task-export-external で後から追加
```

### Step 4: Milestone計算

```bash
MONTH=$(date +%m)
YEAR=$(date +%Y)
if [ $MONTH -lt 4 ]; then
  FY=$((YEAR - 1))
  HALF="H2"
elif [ $MONTH -lt 10 ]; then
  FY=$YEAR
  HALF="H1"
else
  FY=$YEAR
  HALF="H2"
fi
MILESTONE="FY${FY}-${HALF}"
```

### Step 5: Issue作成

```bash
gh issue create --repo {REPO} \
  --title "{タイトル}" \
  --body-file /tmp/issue-body.md
```

**Issueボディフォーマット:**

```markdown
## 概要

{タスクの目的・内容}

## 関連

- 依頼元: {source URL}（ある場合）

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

### Step 6: プロジェクトに追加

```bash
gh project item-add {PROJECT_NUMBER} --owner @me --url {issue_url}
```

### Step 7: フィールド設定

**7-1: アイテムID取得**

```bash
ITEM_ID=$(gh project item-list {PROJECT_NUMBER} --owner @me --limit 100 --format json | jq -r '.items[] | select(.content.number == {issue_number}) | .id')
```

**7-2: Status = Todo**

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

**7-3: Project フィールド設定**

```bash
gh api graphql -f query='
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "{PROJECT_ID}"
    itemId: "{ITEM_ID}"
    fieldId: "{PROJECT_FIELD_ID}"
    value: { singleSelectOptionId: "{PROJECT_OPTION_ID}" }
  }) { projectV2Item { id } }
}'
```

**7-4: Priority フィールド設定**

```bash
gh api graphql -f query='
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "{PROJECT_ID}"
    itemId: "{ITEM_ID}"
    fieldId: "{PRIORITY_FIELD_ID}"
    value: { singleSelectOptionId: "{PRIORITY_OPTION_ID}" }
  }) { projectV2Item { id } }
}'
```

**7-5: Sprint フィールド設定**（バックログ以外）

```bash
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

**7-6: Milestone設定（GH Issue側）**

```bash
gh api repos/{REPO}/milestones --jq '.[] | select(.title == "{MILESTONE}") | .number'

# 存在しない場合
gh api repos/{REPO}/milestones -f title="{MILESTONE}"

gh issue edit {issue_number} --repo {REPO} --milestone "{MILESTONE}"
```

### Step 8: 完了報告

```
✅ タスク作成完了

📋 Issue: #{issue_number} {title}
🔗 https://github.com/{REPO}/issues/{issue_number}

📌 Status: Todo
📂 Project: {project}
🎯 Priority: {priority}
📅 Sprint: {sprint}
🏁 Milestone: {milestone}
```

---

## 注意事項

- 外部サービス連携は行わない（/task-export-external で明示的に実行）
- Milestoneは GH Issue のビルトイン機能を使用
- Sprint は Iteration フィールドで管理
- フィールド（Project, Sprint, Priority）は必ずユーザーに確認
