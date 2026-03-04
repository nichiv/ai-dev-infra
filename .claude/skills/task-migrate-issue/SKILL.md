---
description: Issue移行 - 既存Issueを現行フォーマットに変換
user-invocable: true
disable-model-invocation: true
name: task-migrate-issue
---

# Issue移行

既存のGitHub Issueを現行の運用ルール（YAML Front Matter + 外部サービスセクション + 統一フォーマット）に変換する。

---

## 使用方法

```
/task-migrate-issue [オプション]
```

引数: $ARGUMENTS

- `#5` → 単一Issue移行
- `--all` → 全オープンIssue移行
- `--dry-run` → 変更を適用せずプレビュー

---

## 設定ファイル

**パス**: `.config/project.yml`

処理開始時に設定ファイルを読み込み、以下の値を取得：

```yaml
# 使用する設定項目
github_project.repository  # REPO

external.base_url   # EXTERNAL_BASE_URL
external.service    # EXTERNAL_SERVICE (youtrack等)
external.projects   # EXTERNAL_PROJECTS (プロジェクトプレフィックス一覧)
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

### Step 1: Issue取得

```bash
gh issue view {issue_number} --repo {REPO} --json number,title,body
```

### Step 2: 外部Issue ID抽出

タイトルからパターンマッチ:
```regex
^(project_a|project_b)-[0-9]+
```

**注**: `external.projects` に定義されたプロジェクトプレフィックスを使用

### Step 3: 外部body取得（外部連携の場合）

MCP または API を使用:

```
# YouTrackの場合
mcp__youtrack__get_issue:
  issueId: {EXTERNAL_ID}
```

### Step 4: 既存bodyからセクション抽出

既存Issueから以下のセクションを抽出:

| 既存セクション | 抽出内容 |
|--------------|---------|
| ## 概要 | 概要テキスト |
| ## 関連 | 関連リンク |
| ## 依存関係 | 依存情報（関連に統合） |
| ## 調査結果 | 調査内容（作業計画に統合） |
| ## 対応方針 | 方針内容（作業計画に統合） |
| ## タスク | タスクリスト（作業計画に統合） |
| ## 進捗状況 | 進捗内容（作業状況に統合） |
| ## 次のアクション | 次アクション（作業状況に統合） |
| ## セッション | **削除** |

### Step 5: 新しいbody構築

**目標フォーマット:**

```markdown
---
external:
  {service}: {EXTERNAL_BASE_URL}/issue/{EXTERNAL_ID}
---

## 概要

{既存の概要セクション内容}

## 関連

{既存の関連セクション内容}
{既存の依存関係があれば追記}

## 外部サービス

外部サービスから取得したissueの関連情報

### {service}

<!-- {service}-body-start
{外部MCPで取得したdescription}
{service}-body-end -->

## 作業計画

{既存の調査結果があれば記載}

### 方針

{既存の対応方針があれば記載、なければ「[実装方針・設計概要]」}

### タスク

{既存のタスクリスト、なければ初期値}
- [ ] タスク1
- [ ] タスク2

## 作業状況

### 最終更新: {既存の最終更新 or "-"}

**進捗**:
{既存の進捗状況、なければ「- (なし)」}

**ブロッカー**:
{既存のブロッカー、なければ「- (なし)」}

**次のアクション**:
{既存の次のアクション、なければ「- 作業計画を立てる」}
```

**非外部連携の場合:**

```markdown
---
external: {}
---

{上記と同じ構造、外部サービスセクションは空}
```

### Step 6: Issue更新

```bash
Write: /tmp/issue-{issue_number}-body.md

gh issue edit {issue_number} --repo {REPO} --body-file /tmp/issue-{issue_number}-body.md
```

### Step 7: 完了報告

```
✅ Issue移行完了

📋 Issue: #{issue_number} {title}
🔗 https://github.com/{REPO}/issues/{issue_number}

変更内容:
- YAML Front Matter追加
- 外部サービスセクション追加（外部body埋め込み）
- セクション構造を統一フォーマットに変換
```

---

## 注意事項

- 既存の内容は可能な限り保持し、新しいセクションに当てはめる
- YAML Front Matterが既にある場合はスキップ
- セッションセクションは削除
- 調査結果・対応方針は作業計画に統合
- 依存関係は関連に統合
- `--dry-run` で事前確認を推奨
