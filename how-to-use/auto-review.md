# 自動レビュー

`git push` をトリガーに、複数の AI エージェントが並列でコードレビューを実行し、結果を Issue にコメントする。

デフォルトは Claude + Gemini の2エージェント。Codex はオプションで追加可能。

## 仕組み

```
git push
  │
  ▼
lefthook pre-push hook
  │
  ▼
ブランチ名から issue 番号を抽出
（例: feature-123 → #123）
  │
  ▼
review.sh re-review 123
  │
  ├──→ Claude (primary/fallback)  ─┐
  ├──→ Gemini (primary/fallback)  ─┤ 並列実行
  └──→ Codex  (primary/fallback)  ─┘ ← --with-codex 時のみ
                                    │
                                    ▼
                              結果を統合
                                    │
                                    ▼
                          Issue #123 にコメント
                                    │
                                    ▼
                            LGTM → push 成功
                            要修正 → push ブロック
```

### ポイント

- デフォルトは Claude + Gemini の2エージェント。Codex はオプション
- 各エージェントは primary モデル → fallback モデルの順で試行する
- 1エージェントでも成功すればレビュー結果を出力する（全失敗時のみエラー）
- re-review は前回指摘の対応状況を追跡し、全指摘対応済みなら LGTM で push を通す
- タイムアウト: デフォルト5分、Codex 込みの場合15分（`AGENT_TIMEOUT` 環境変数で上書き可能）

## セットアップ

### 1. ファイルを配置

プロジェクトルートに以下のファイルをコピーする。

```
your-project/
├── .config/
│   ├── project.yml
│   └── ai-models.yml
├── dev-tools/
│   ├── review.sh
│   ├── config.sh
│   ├── perspectives.md           # 省略可（デフォルト観点を使用）
│   └── issue-tracker/
│       ├── loader.sh             # プロバイダー解決・読み込み
│       ├── github.sh             # GitHub プロバイダー
│       └── youtrack.sh           # YouTrack プロバイダー
└── lefthook.yml
```

### 2. `.config/project.yml` を編集

```yaml
repository:
  owner: your-org
  name: your-repo
  full_name: your-org/your-repo
  base_branch: main          # diff の基準ブランチ
```

`full_name` は GitHub プロバイダーで Issue の取得・コメント投稿に使用される。

### 3. `.config/ai-models.yml` を編集

```yaml
claude:
  primary: opus
  fallback: sonnet

gemini:
  primary: gemini-3.1-pro-preview
  fallback: gemini-3-flash-preview

codex:
  primary: gpt-5.3-codex
  fallback: gpt-5.2
```

各エージェントは primary → fallback の順で試行する。インストールしていない CLI のモデルはダミー値でよい（実行時にスキップされる）。

### 4. `lefthook.yml` のブランチパターンを設定

```yaml
pre-push:
  commands:
    review:
      run: |
        BRANCH=$(git rev-parse --abbrev-ref HEAD)
        BRANCH_PATTERN='^feature-([0-9]+)$'
        if [[ "$BRANCH" =~ $BRANCH_PATTERN ]]; then
          ISSUE_NUMBER="${BASH_REMATCH[1]}"
          ./dev-tools/review.sh re-review "$ISSUE_NUMBER"
        fi
```

`BRANCH_PATTERN` をプロジェクトのブランチ命名規約に合わせて変更する。

| ブランチ命名例 | BRANCH_PATTERN |
|-------------|----------------|
| `feature-123` | `'^feature-([0-9]+)$'` |
| `issue-123` | `'^issue-([0-9]+)$'` |
| `app-123` | `'^app-([0-9]+)$'` |
| `fix/123-description` | `'^fix/([0-9]+)'` |

パターンにマッチしないブランチ（`main`, `develop` 等）では自動レビューは実行されない。

### 5. Lefthook をインストール・有効化

```bash
brew install lefthook
lefthook install
```

### 6. `.gitignore` に追加

```
tmp/
```

レビュー結果は `./tmp/review/` に出力される。

## 使い方

### 初回レビュー（手動実行）

PR 作成前に手動で実行する。

```bash
# Claude + Gemini でレビュー（デフォルト）
./dev-tools/review.sh review 123

# Codex も含めてレビュー
./dev-tools/review.sh review 123 --with-codex
```

- `base_branch...HEAD` の差分を取得
- Issue #123 の要件と照合してレビュー
- 結果を Issue #123 にコメント

### 再レビュー（自動実行）

`git push` 時に lefthook が自動実行する。

```bash
git push  # → lefthook → review.sh re-review 123
```

- 前回のレビュー指摘に対する修正状況を判定
- 全指摘対応済み＋新規指摘なし → LGTM（exit 0、push 成功）
- 未対応あり or 新規指摘あり → 要修正（exit 1、push ブロック）

### Codex の有効化

Codex はデフォルトでは実行されない。有効化する方法は2つ:

**方法1: CLI フラグ（一回限り）**

```bash
./dev-tools/review.sh review 123 --with-codex
```

**方法2: 設定ファイル（永続的）**

`.config/project.yml` に以下を追加:

```yaml
review:
  with_codex: true
```

CLI フラグが設定ファイルより優先される。

Codex を有効にするとタイムアウトが5分→15分に延長される。Codex は思考が深く、大きな差分では10分以上かかることがある。

### 出力ファイル

```
tmp/review/
├── claude-review.md              # Claude の個別結果
├── gemini-review.md              # Gemini の個別結果
├── codex-review.md               # Codex の個別結果（--with-codex 時のみ）
├── codex-review_progress.jsonl   # Codex の実行トレース（JSONL）
├── combined-review.md            # 統合結果（review）
├── claude-re-review.md           # Claude の再レビュー結果
├── gemini-re-review.md           # Gemini の再レビュー結果
├── codex-re-review.md            # Codex の再レビュー結果
├── codex-re-review_progress.jsonl # Codex の実行トレース（JSONL）
├── re-review-result.md           # 統合結果（re-review）
└── *.err                         # 各エージェントのエラーログ
```

Codex の `_progress.jsonl` には WebSocket 接続状況、思考過程、コマンド実行、トークン使用量などが記録される。実行が遅い場合の診断に使用する。

## Issue Tracker 設定

`.config/project.yml` の `issue_tracker` で使用するプロバイダーを設定する。未設定時は `github` がデフォルト。

### GitHub（デフォルト）

```yaml
issue_tracker: github
```

`gh` CLI が認証済みであること。

### YouTrack

```yaml
issue_tracker: youtrack

youtrack:
  base_url: https://your-instance.youtrack.cloud
```

環境変数 `YOUTRACK_TOKEN` に API トークンを設定すること。

```bash
export YOUTRACK_TOKEN="perm:xxx..."
```

プロジェクトルートの `.env` ファイルからも読み込み可能（既存の環境変数を上書きしない）。

```
# .env
YOUTRACK_TOKEN=perm:xxx...
```

### プロバイダーの追加

全プロバイダーは以下の3関数を実装する:

| 関数 | 説明 |
|------|------|
| `tracker_get_issue $issue_number $repo` | Issue のタイトルと本文を取得 |
| `tracker_get_comments $issue_number $repo` | Issue のコメント一覧を取得 |
| `tracker_post_comment $issue_number $repo $body_file` | Issue にコメントを投稿 |

新しいプロバイダーを追加する手順:

1. `dev-tools/issue-tracker/<provider>.sh` を作成し、上記3関数を実装
2. `dev-tools/issue-tracker/loader.sh` の `case` 文にプロバイダーを追加
3. `.config/project.yml` に `issue_tracker: <provider>` を設定

## カスタマイズ

### レビュー観点

`dev-tools/perspectives.md` を配置すると、デフォルトのレビュー観点を上書きできる。

```markdown
### 観点1: 要件充足 🔴
Issue で定義された要件を全て満たしているか。

### 観点2: セキュリティ 🔴
SQLインジェクション、XSS、認証バイパス...

### 観点3: テスト 🟡
新機能にテストがあるか...
```

深刻度アイコンの意味:

| アイコン | 深刻度 | 説明 |
|---------|--------|------|
| 🔴 | Critical | 必ず修正が必要 |
| 🟠 | High | 原則修正が必要 |
| 🟡 | Medium | 修正を推奨 |
| 🟢 | Low | 改善提案 |

`perspectives.md` を配置しない場合、以下のデフォルト8観点が使用される。

1. 要件充足 🔴
2. 不適切な変更 🔴
3. セキュリティ 🔴
4. 破壊的変更 🟠
5. アーキテクチャ準拠 🟠
6. テストカバレッジ 🟡
7. 命名規約 🟡
8. コード品質 🟢

### 設定ディレクトリの変更

`CONFIG_DIR` 環境変数で `.config/` 以外の場所を指定できる。

```bash
CONFIG_DIR=./settings ./dev-tools/review.sh review 123
```

## トラブルシューティング

### Claude Code のネスト禁止エラー

Claude Code セッション内から `git push` すると、`CLAUDECODE` 環境変数が子プロセスに継承されてネスト禁止になる。`review.sh` は `CLAUDECODE=` で明示的に unset しているため、通常は発生しない。

手動実行で発生する場合:

```bash
CLAUDECODE= ./dev-tools/review.sh review 123
```

### 特定のエージェントだけ失敗する

CLI がインストールされていない、または認証が切れている可能性がある。`tmp/review/*.err` でエラー内容を確認する。

```bash
cat tmp/review/gemini-review.err
```

1エージェントでも成功すればレビュー結果は出力されるため、全エージェントのインストールは必須ではない。

### push が毎回ブロックされる

re-review の結果に `❌` または `⚠️` が含まれていると push がブロックされる。`tmp/review/re-review-result.md` で具体的な指摘内容を確認し、対応してから再度 push する。

レビューをスキップして push したい場合:

```bash
git push --no-verify
```
