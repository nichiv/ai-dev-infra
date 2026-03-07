---
description: 外部同期 - GitHub Issueと外部Issue管理システムの双方向同期
user-invocable: true
disable-model-invocation: true
name: task-sync-external
---

# 外部同期

GitHub Issue内の埋め込み外部bodyと、外部Issue管理システムの最新descriptionを比較し、双方向同期を行う。

---

## 使用方法

```
/task-sync-external [Issue ID]
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
github_project.repository  # REPO

external.base_url   # EXTERNAL_BASE_URL
external.service    # EXTERNAL_SERVICE (youtrack等)
```

**読み込み方法**:
```bash
# yqコマンドで読み込み
REPO=$(yq '.github_project.repository' .config/project.yml)
EXTERNAL_BASE_URL=$(yq '.external.base_url' .config/project.yml)
EXTERNAL_SERVICE=$(yq '.external.service' .config/project.yml)
```

---

## 処理フロー

### Step 1: Issue特定

**引数なしの場合:**

```bash
git branch --show-current
```

ブランチ名から Issue ID を抽出し、GH Issue を検索:

```bash
gh issue list --repo {REPO} --search "in:title {branch_name}" --json number,title
```

### Step 2: GH Issue情報取得

```bash
gh issue view {issue_number} --repo {REPO} --json number,title,body,url
```

### Step 3: YAML Front Matterから外部サービス情報取得

```yaml
---
external:
  {service}: {external_issue_url}
---
```

- 外部サービス情報が存在しない場合 → エラー終了「外部連携が設定されていません」

### Step 4: 埋め込み外部body抽出

GH Issue bodyから外部サービスセクションを抽出:

```markdown
## 外部サービス

外部サービスから取得したissueの関連情報

### {service}

<!-- {service}-body-start
{埋め込まれている外部body}
{service}-body-end -->
```

正規表現で抽出:
```
<!-- {service}-body-start\n(.*?)\n{service}-body-end -->
```

### Step 5: 外部最新body取得

MCP または API を使用:

```
# YouTrackの場合
mcp__youtrack__get_issue:
  issueId: {EXTERNAL_ISSUE_ID}
```

取得項目:
- description: 外部Issueの最新body

### Step 6: 差分比較

埋め込み外部body（GH側）と最新外部body（外部側）を比較:

**差分なし:**
```
✅ 同期済み

📋 Issue: #{issue_number} {title}
🔗 GH: {gh_url}
🔗 External: {external_url}

GH埋め込みbodyと外部最新bodyは同一です。
```
→ 処理終了

**差分あり:**
差分を表示してStep 7へ進む

### Step 7: ユーザーにマージ方法確認

AskUserQuestion を使用:

```
📋 Issue: #{issue_number} {title}

GH埋め込みbodyと外部最新bodyに差分があります。

---
### GH側（埋め込みbody）
{gh_embedded_body}

---
### 外部側（最新body）
{external_latest_body}

---

どの方向に同期しますか？
```

選択肢:
- **GH → External**: GH埋め込みの内容を外部に反映
- **External → GH**: 外部最新の内容をGHに反映
- **キャンセル**: 何もしない

### Step 8: 同期実行

**GH → External の場合:**

MCP または API を使用:

```
# YouTrackの場合
mcp__youtrack__update_issue:
  issueId: {EXTERNAL_ISSUE_ID}
  description: {gh_embedded_body}
```

**External → GH の場合:**

1. GH Issue bodyの外部サービスセクションを更新:

```markdown
### {service}

<!-- {service}-body-start
{external_latest_body}
{service}-body-end -->
```

2. ボディを更新:

```bash
Write: /tmp/issue-{issue_number}-body.md

gh issue edit {issue_number} --repo {REPO} --body-file /tmp/issue-{issue_number}-body.md
```

### Step 9: 完了報告

```
✅ 外部同期完了

📋 Issue: #{issue_number} {title}
🔗 GH: https://github.com/{REPO}/issues/{issue_number}
🔗 External: {EXTERNAL_BASE_URL}/issue/{EXTERNAL_ISSUE_ID}

🔄 同期方向: {GH → External / External → GH}

---

同期が完了しました。両方のIssueが最新状態です。
```

---

## 注意事項

- YAML Front Matterに外部サービスリンクが必須
- 差分がない場合は何も更新しない
- ユーザー確認なしに同期は実行しない
- HTMLコメント内の body を抽出・更新
- 外部サービスセクションが存在しない場合は新規作成
