---
description: 外部出力 - GitHub Issueを外部Issue管理システムにエクスポート
user-invocable: true
disable-model-invocation: true
name: task-export-external
---

# 外部出力

GitHub Issueを外部Issue管理システム（YouTrack等）にエクスポートする。

---

## 使用方法

```
/task-export-external #番号 --project 外部プロジェクト名
```

引数: $ARGUMENTS

- `#番号`: GitHub Issue番号（必須）
- `--project`: 外部サービスのプロジェクト名（必須）

---

## 設定ファイル

**パス**: `.config/project.yml`

処理開始時に設定ファイルを読み込み、以下の値を取得：

```yaml
# 使用する設定項目
github_project.project_id        # PROJECT_ID
github_project.project_number    # プロジェクト番号
github_project.repository        # REPO

github_project.fields.project.id                   # PROJECT_FIELD_ID
github_project.fields.project.options.<project>    # PROJECT_OPTION_ID

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

### Step 1: 引数検証

- `--project` が必須
- `personal` は指定不可（エクスポート対象外）

### Step 2: GH Issue情報取得

```bash
gh issue view {issue_number} --repo {REPO} --json number,title,body,url
```

### Step 3: 外部Issue作成

MCP または API を使用:

```
# YouTrackの場合
mcp__youtrack__create_issue:
  project: {外部プロジェクト名}
  summary: {GH Issueタイトル}
  description: |
    ## 概要

    {GH Issue概要セクション}

    ## 関連

    - GitHub Issue: {GH Issue URL}
```

### Step 4: GH Issue更新

**4-1: YAML Front Matter追加（または更新）**

```markdown
---
external:
  {service}: {EXTERNAL_BASE_URL}/issue/{EXTERNAL_ISSUE_ID}
---
```

**4-2: タイトル変更**

```bash
gh issue edit {issue_number} --repo {REPO} \
  --title "{EXTERNAL_ISSUE_ID}: {元のタイトル}"
```

**4-3: 外部サービスセクション追加**

外部Issueのdescriptionを取得し、GH Issueに埋め込む:

```markdown
## 外部サービス

外部サービスから取得したissueの関連情報

### {service}

<!-- {service}-body-start
{External Issue Description の内容をそのまま埋め込み}
{service}-body-end -->
```

**4-4: ボディ更新**

YAML Front Matter + 外部サービスセクションを追加:

```bash
Write: /tmp/issue-{issue_number}-body.md

gh issue edit {issue_number} --repo {REPO} --body-file /tmp/issue-{issue_number}-body.md
```

### Step 5: GP Projectフィールド更新

```bash
# アイテムID取得
ITEM_ID=$(gh project item-list {PROJECT_NUMBER} --owner @me --limit 100 --format json | jq -r '.items[] | select(.content.number == {issue_number}) | .id')

# Project フィールドを更新
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

### Step 6: 完了報告

```
✅ 外部出力完了

📋 GitHub Issue: #{issue_number} {new_title}
🔗 https://github.com/{REPO}/issues/{issue_number}

📋 External Issue: {EXTERNAL_ISSUE_ID}
🔗 {EXTERNAL_BASE_URL}/issue/{EXTERNAL_ISSUE_ID}

📂 Project: {project} (updated)
```

---

## 注意事項

- GH Issue → 外部 の一方向同期
- 外部Issue作成後は、GH Issueでステータス管理を継続
- 外部への同期は手動（このスキルで明示的に実行）
- personal タスクはエクスポート不可
- YAML Front Matterでexternal linkを管理
- **外部サービスセクションに description を非表示で埋め込み**
- 埋め込んだbodyは task-sync-external で差分検出に使用
