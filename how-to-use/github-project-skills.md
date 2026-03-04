# GitHub Project Skills

GitHub Projects と連携したタスク管理スキル群。Issue の作成、ステータス管理、外部サービス連携を Claude Code から実行できる。

## スキル一覧

| スキル | 用途 |
|--------|------|
| `/task-create` | GitHub Issue 作成 + Projects 追加 |
| `/task-export-external` | GH Issue → 外部サービス（YouTrack等）にエクスポート |
| `/task-import-external` | 外部サービス → GH Issue にインポート |
| `/task-sync-external` | GH Issue ↔ 外部サービス 双方向同期 |
| `/dev-plan` | 作業計画作成 + Status → In Progress |
| `/dev-pause` | 作業中断 + Status → Paused |
| `/dev-resume` | 作業再開 + Status → In Progress |
| `/dev-done` | 作業完了 + Status → Done |

## セットアップ

### 方式1: プロジェクト設定（推奨）

プロジェクトごとに設定を持つ。チームで共有しやすい。

```
your-project/
├── .claude/
│   └── skills/
│       ├── task-create/
│       │   └── SKILL.md
│       ├── task-export-external/
│       │   └── SKILL.md
│       ├── dev-plan/
│       │   └── SKILL.md
│       └── ...
└── .config/
    └── project.yml          # 設定ファイル
```

**手順:**

1. ai-dev-infra から `.claude/skills/` をコピー

```bash
cp -r ai-dev-infra/.claude/skills/ your-project/.claude/skills/
```

2. `.config/project.yml` を作成・編集

```bash
mkdir -p your-project/.config
cp ai-dev-infra/.config/project.yml your-project/.config/project.yml
```

3. 設定値を自分の環境に合わせて編集（後述）

### 方式2: グローバル設定

全プロジェクトで共通のスキルを使う。個人の開発環境向け。

```
~/
├── .claude/
│   └── skills/
│       ├── task-create/
│       │   └── SKILL.md
│       ├── dev-plan/
│       │   └── SKILL.md
│       └── ...
└── .config/
    └── project.yml          # グローバル設定ファイル
```

**手順:**

1. ai-dev-infra から `~/.claude/skills/` にコピー

```bash
cp -r ai-dev-infra/.claude/skills/* ~/.claude/skills/
```

2. `~/.config/project.yml` を作成

```bash
mkdir -p ~/.config
cp ai-dev-infra/.config/project.yml ~/.config/project.yml
```

3. スキル内の設定ファイルパスを修正

各スキルの SKILL.md 内で設定ファイルパスを変更:

```bash
# 変更前
PROJECT_ID=$(yq '.github_project.project_id' .config/project.yml)

# 変更後
PROJECT_ID=$(yq '.github_project.project_id' ~/.config/project.yml)
```

または、スキル冒頭で設定ファイルパスを変数化:

```bash
CONFIG_FILE="${CONFIG_FILE:-~/.config/project.yml}"
PROJECT_ID=$(yq '.github_project.project_id' "$CONFIG_FILE")
```

## 設定ファイル

### project.yml の構造

```yaml
# GitHub Projects 設定
github_project:
  # プロジェクト識別子
  project_id: "PVT_kwDOABCDEF..."           # GraphQL の Project ID
  project_number: 1                          # プロジェクト番号（URLに表示される）
  repository: "your-org/your-repo"           # リポジトリ

  # フィールド定義
  fields:
    # Status フィールド
    status:
      id: "PVTSSF_lADOABCDEF..."             # Status フィールドの ID
      options:
        todo: "abc123..."                    # Todo オプションの ID
        in_progress: "def456..."             # In Progress オプションの ID
        paused: "ghi789..."                  # Paused オプションの ID
        done: "jkl012..."                    # Done オプションの ID

    # Project フィールド（カスタム）
    project:
      id: "PVTSSF_lADOXYZ..."
      options:
        personal: "opt_personal..."
        project_a: "opt_project_a..."
        project_b: "opt_project_b..."

    # Priority フィールド（カスタム）
    priority:
      id: "PVTSSF_lADOPRI..."
      options:
        p0_urgent: "opt_p0..."
        p1_high: "opt_p1..."
        p2_normal: "opt_p2..."
        p3_low: "opt_p3..."

    # Sprint フィールド（Iteration）
    sprint:
      id: "PVTIF_lADOSPR..."

# 外部サービス連携（YouTrack等）
external:
  service: "youtrack"                        # サービス種別
  base_url: "https://your-instance.youtrack.cloud"
  projects:
    - project_a                              # 連携対象プロジェクト
    - project_b
```

### 設定値の取得方法

#### 1. Project ID と Project Number

GitHub Projects のURLから確認:

```
https://github.com/users/YOUR_NAME/projects/1
                                          ↑ Project Number
```

Project ID は GraphQL で取得:

```bash
gh api graphql -f query='
query {
  user(login: "YOUR_NAME") {
    projectV2(number: 1) {
      id
    }
  }
}'
```

Organization の場合:

```bash
gh api graphql -f query='
query {
  organization(login: "YOUR_ORG") {
    projectV2(number: 1) {
      id
    }
  }
}'
```

#### 2. フィールド ID とオプション ID

```bash
gh api graphql -f query='
query {
  node(id: "PROJECT_ID_HERE") {
    ... on ProjectV2 {
      fields(first: 20) {
        nodes {
          ... on ProjectV2Field {
            id
            name
          }
          ... on ProjectV2SingleSelectField {
            id
            name
            options {
              id
              name
            }
          }
          ... on ProjectV2IterationField {
            id
            name
          }
        }
      }
    }
  }
}'
```

出力例:

```json
{
  "data": {
    "node": {
      "fields": {
        "nodes": [
          {
            "id": "PVTSSF_lADO...",
            "name": "Status",
            "options": [
              { "id": "abc123", "name": "Todo" },
              { "id": "def456", "name": "In Progress" },
              { "id": "ghi789", "name": "Done" }
            ]
          }
        ]
      }
    }
  }
}
```

## 使用例

### 新規タスク作成

```
/task-create APIのレスポンス改善 --source https://slack.com/...
```

→ Issue 作成 → Projects に追加 → フィールド設定

### 作業開始

```
/dev-plan #123
```

→ Issue 調査 → 計画作成 → ユーザー承認 → Status を In Progress に

### 作業中断

```
/dev-pause #123
```

→ 進捗記録 → Status を Paused に

### 作業再開

```
/dev-resume #123
```

→ 状況確認 → Status を In Progress に

### 作業完了

```
/dev-done #123
```

→ 完了記録 → Status を Done に

### 外部サービス連携

```
# GH Issue を YouTrack にエクスポート
/task-export-external #123

# YouTrack Issue を GH にインポート
/task-import-external PROJECT-456

# 双方向同期
/task-sync-external #123
```

## 依存ツール

| ツール | 用途 | インストール |
|--------|------|-------------|
| `gh` | GitHub CLI | `brew install gh` |
| `yq` | YAML パーサー | `brew install yq` |
| `jq` | JSON パーサー | `brew install jq` |

## トラブルシューティング

### "yq: command not found"

```bash
brew install yq
```

### "gh: command not found"

```bash
brew install gh
gh auth login
```

### GraphQL エラー: "Could not resolve to a node"

Project ID が間違っている可能性。上記の「設定値の取得方法」で再取得。

### "Item not found in project"

Issue がまだ Projects に追加されていない。手動で追加するか、`/task-create` で作成。

```bash
gh project item-add PROJECT_NUMBER --owner @me --url ISSUE_URL
```

### 設定ファイルが見つからない

プロジェクト設定の場合:
- `.config/project.yml` がプロジェクトルートにあるか確認

グローバル設定の場合:
- `~/.config/project.yml` が存在するか確認
- スキル内のパスが `~/.config/project.yml` になっているか確認
