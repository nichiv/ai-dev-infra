---
description: 作業完了 - Issueクローズとステータス更新
user-invocable: true
disable-model-invocation: true
name: dev-done
---

# 作業完了

作業を完了し、GH IssueをクローズしてGitHub ProjectsのステータスをDoneに変更する。

---

## 使用方法

```
/dev-done [Issue ID]
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

github_project.fields.status.id                    # STATUS_FIELD_ID
github_project.fields.status.options.done          # STATUS_DONE
```

**読み込み方法**:
```bash
# yqコマンドで読み込み
PROJECT_ID=$(yq '.github_project.project_id' .config/project.yml)
PROJECT_NUMBER=$(yq '.github_project.project_number' .config/project.yml)
REPO=$(yq '.github_project.repository' .config/project.yml)
STATUS_FIELD_ID=$(yq '.github_project.fields.status.id' .config/project.yml)
STATUS_DONE=$(yq '.github_project.fields.status.options.done' .config/project.yml)
```

---

## 処理フロー

### Step 1: Issue特定

**引数なしの場合:**

```bash
git branch --show-current
```

ブランチ名から Issue ID を抽出し、GH Issue を検索。

### Step 2: 完了サマリ生成

セッション中の作業内容から、完了サマリを自動生成:

- 実施した作業の要約
- 作成したPR（あれば）
- 主な成果物

### Step 3: Issue情報取得・更新

**3-1: 現在のIssueボディ取得**

```bash
gh issue view {issue_number} --repo {REPO} --json body --jq '.body'
```

**3-2: 作業状況セクションを更新（完了）**

```markdown
## 作業状況

### 最終更新: {YYYY-MM-DD HH:MM} ✅ 完了

**成果**:
- 完了した作業1
- 完了した作業2
- PR: {owner}/{repo}#{pr_number}

**ブロッカー**:
- (なし)

**備考**:
- 追加情報など
```

**3-3: ボディを更新**

```bash
Write: /tmp/issue-{issue_number}-body.md

gh issue edit {issue_number} --repo {REPO} --body-file /tmp/issue-{issue_number}-body.md
```

### Step 4: GH Issue クローズ

```bash
gh issue close {issue_number} --repo {REPO}
```

### Step 5: GP Status更新: Done

```bash
ITEM_ID=$(gh project item-list {PROJECT_NUMBER} --owner @me --limit 100 --format json | jq -r '.items[] | select(.content.number == {issue_number}) | .id')

gh api graphql -f query='
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "{PROJECT_ID}"
    itemId: "{ITEM_ID}"
    fieldId: "{STATUS_FIELD_ID}"
    value: { singleSelectOptionId: "{STATUS_DONE}" }
  }) { projectV2Item { id } }
}'
```

### Step 6: 完了報告

```
✅ 作業完了

📋 Issue: #{issue_number} {title}
🔗 https://github.com/{REPO}/issues/{issue_number}

📌 Status: Done (Closed)

---

## 完了サマリ

{完了サマリ}

---

🎉 お疲れさまでした！
```

---

## PR作成時の注意（クロスリポジトリ参照）

PRを別リポジトリで作成する場合、Issue参照には完全修飾名が必要:

### 構成例

```
GitHub Projects / Issue: user/tasks (個人)
PR作成先: org/project (Organization)
```

### PR から Issue を参照する場合

```markdown
# ❌ 同一リポジトリ形式（動作しない）
Fixes #47

# ✅ 完全修飾名（必須）
Fixes user/tasks#47
Closes user/tasks#47
Related to user/tasks#47
```

### Issue から PR を参照する場合

```markdown
## 関連

- PR: org/project#123
- または PR URL をそのまま記載
```

---

## 注意事項

- 直接 gh CLI でIssue取得（外部サービスに依存しない）
- Issue は自動でクローズ
- 計画ファイル（./tmp/plan-{issue_id}.md）は残す（ローカル参照用）
- PRとIssueのクロスリポジトリ参照に注意
- 外部同期が必要な場合は完了前に /task-sync-external を使用
