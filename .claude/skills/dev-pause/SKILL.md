---
description: 作業中断 - 進捗記録とステータス更新
user-invocable: true
disable-model-invocation: true
name: dev-pause
---

# 作業中断

現在の作業状況を記録し、GH IssueとGitHub Projectsのステータスを更新する。

---

## 使用方法

```
/dev-pause [Issue ID]
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
github_project.fields.status.options.paused        # STATUS_PAUSED
```

**読み込み方法**:
```bash
# yqコマンドで読み込み
PROJECT_ID=$(yq '.github_project.project_id' .config/project.yml)
PROJECT_NUMBER=$(yq '.github_project.project_number' .config/project.yml)
REPO=$(yq '.github_project.repository' .config/project.yml)
STATUS_FIELD_ID=$(yq '.github_project.fields.status.id' .config/project.yml)
STATUS_PAUSED=$(yq '.github_project.fields.status.options.paused' .config/project.yml)
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

### Step 3: 作業サマリ自動生成

セッション中の作業内容から、サマリを自動生成:

- 直近の作業内容（コミット、ファイル編集、コマンド実行等）から要約
- 完了したタスク、残タスクを整理
- ブロッカーがあれば記録

### Step 4: Issue更新

**4-1: 現在のIssueボディ取得**

```bash
gh issue view {issue_number} --repo {REPO} --json body --jq '.body'
```

**4-2: 作業状況セクションを更新**

```markdown
## 作業状況

### 最終更新: {YYYY-MM-DD HH:MM}

**進捗**:
- [x] 完了したタスク1
- [x] 完了したタスク2
- [ ] 残タスク1
- [ ] 残タスク2

**ブロッカー**:
- (なし) または ブロッカーの内容

**次のアクション**:
- 再開時に最初にやること
```

**4-3: ボディを更新**

```bash
Write: /tmp/issue-{issue_number}-body.md

gh issue edit {issue_number} --repo {REPO} --body-file /tmp/issue-{issue_number}-body.md
```

### Step 5: GP Status更新: Paused

```bash
ITEM_ID=$(gh project item-list {PROJECT_NUMBER} --owner @me --limit 100 --format json | jq -r '.items[] | select(.content.number == {issue_number}) | .id')

gh api graphql -f query='
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: "{PROJECT_ID}"
    itemId: "{ITEM_ID}"
    fieldId: "{STATUS_FIELD_ID}"
    value: { singleSelectOptionId: "{STATUS_PAUSED}" }
  }) { projectV2Item { id } }
}'
```

### Step 6: 完了報告

```
✅ 作業中断を記録しました

📋 Issue: #{issue_number} {title}
🔗 https://github.com/{REPO}/issues/{issue_number}

📌 Status: Paused

---

## 作業状況サマリ

**進捗**:
{進捗リスト}

**ブロッカー**:
{ブロッカー}

**次のアクション**:
{次のアクション}

---

💡 再開時: /dev-resume #{issue_number}
```

---

## 注意事項

- 直接 gh CLI でIssue取得（外部サービスに依存しない）
- 作業サマリは自動生成（セッション内容から判断）
- ブロッカーがある場合は Status を Blocked に変更することも検討
- 外部同期が必要な場合は /task-sync-external を使用
