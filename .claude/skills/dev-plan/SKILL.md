---
description: 計画作成 - Issue調査と作業計画の作成、Status変更
user-invocable: true
disable-model-invocation: true
name: dev-plan
---

# 計画作成

Issue情報とコードベースを調査し、作業計画を作成してGH Issueに記録する。
Status を In Progress に変更し、作業開始を示す。

---

## 使用方法

```
/dev-plan [Issue ID]
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

ブランチ名から Issue ID を抽出:
- `project-123` → GH Issueを検索（タイトルに含まれるもの）
- その他 → ユーザーに確認

### Step 2: Issue情報取得

```bash
gh issue view {issue_number} --repo {REPO} --json number,title,body,url
```

※ 外部サービス情報が必要な場合は、GH Issue body内の外部サービスセクションを参照

### Step 3: 既存コード調査

Issue内容に基づいて、関連コードを調査:
- Glob/Grep で関連ファイルを検索
- 既存の実装パターンを把握
- 影響範囲を特定

### Step 4: 計画ファイル作成

ローカルに計画ファイルを作成:

```bash
Write: ./tmp/plan-{issue_id}.md
```

**計画ファイルフォーマット:**

```markdown
# {Issue Title} 計画

## 概要

{Issueの目的・背景}

## 調査結果

### 関連ファイル

- `path/to/file1.ts` - 説明
- `path/to/file2.ts` - 説明

### 既存パターン

{既存の実装パターンの説明}

## 実装方針

{どのようなアプローチで実装するか}

## タスク分解

1. [ ] タスク1の詳細
2. [ ] タスク2の詳細
3. [ ] タスク3の詳細

## リスク・注意点

- リスク1
- リスク2

## 参考資料

- {関連ドキュメント}
- {参考実装}
```

### Step 5: ユーザー承認

計画内容を表示し、ユーザーの承認を求める:

```
📋 作業計画を作成しました

---

{計画ファイルの内容}

---

この計画でよろしいですか？
- 「OK」/ 「承認」: GH Issueに記録、Statusを In Progress に変更
- 修正指示: 計画を修正
```

### Step 6: GH Issue更新

承認後、作業計画セクションを更新:

**6-1: 現在のIssueボディ取得**

```bash
gh issue view {issue_number} --repo {REPO} --json body --jq '.body'
```

**6-2: 作業計画セクションを更新**

```markdown
## 作業計画

（/dev-plan で記録: {date}）

### 方針

{実装方針}

### タスク

- [ ] タスク1
- [ ] タスク2
- [ ] タスク3
```

**6-3: ボディを更新**

```bash
Write: /tmp/issue-{issue_number}-body.md

gh issue edit {issue_number} --repo {REPO} --body-file /tmp/issue-{issue_number}-body.md
```

### Step 7: GP Status更新: In Progress

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

### Step 8: 完了報告

```
✅ 作業計画をIssueに記録しました

📋 Issue: #{issue_number} {title}
🔗 https://github.com/{REPO}/issues/{issue_number}

📌 Status: In Progress
📄 計画ファイル: ./tmp/plan-{issue_id}.md

---

💡 次のステップ: タスクに従って実装を開始
```

---

## 注意事項

- 計画ファイルはローカルに保存（`./tmp/plan-{issue_id}.md`）
- GH Issue の作業計画セクションにも反映
- ユーザー承認なしにIssue更新しない
- **Status を In Progress に変更**（作業開始を示す）
- 直接 gh CLI でIssue取得（外部サービスに依存しない）
- 外部サービス情報は外部サービスセクションに埋め込み済み
- 調査結果は詳細に記録し、後で参照できるようにする
