# Permission 自動許可

Claude Code の Permission リクエストを自動許可する hook。安全なコマンドを毎回確認せずに実行できる。

## 仕組み

```
Claude Code がツール実行を要求
  │
  ▼
PermissionRequest hook
  │
  ▼
auto-allow.sh
  │
  ├── パターンにマッチ → 自動許可
  │
  └── マッチしない → ユーザーに確認
```

## デフォルト許可パターン

| パターン | 用途 |
|---------|------|
| `^ITEM_ID=` | GitHub Project操作用変数 |
| `gh project` | GitHub Project操作 |
| `gh api` | GitHub API呼び出し |
| `gh issue` | GitHub Issue操作 |
| `gh pr` | GitHub PR操作 |
| `^ls` | ディレクトリ一覧 |
| `^cat` | ファイル内容表示 |
| `^find` | ファイル検索 |
| `^npm run` | npm スクリプト実行 |
| `^git fetch` | リモート取得 |
| `^yq` | YAML操作 |

## セットアップ

### 1. ファイルを配置

```
your-project/
└── .claude/
    └── hooks/
        └── auto-allow.sh
```

### 2. `~/.claude/settings.json` に追加

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/your-project/.claude/hooks/auto-allow.sh"
          }
        ]
      }
    ]
  }
}
```

**注意**: `command` は絶対パスで指定する。

### 3. 実行権限を付与

```bash
chmod +x .claude/hooks/auto-allow.sh
```

## パターン追加

`hooks/auto-allow.sh` の `should_allow()` 関数に直接追記する。

```bash
should_allow() {
    local cmd="$1"

    # 既存パターン...

    # --- 追加パターンはここに記述 ---
    [[ "$cmd" =~ ^npx\ eslint ]] && return 0
    [[ "$cmd" =~ ^docker ]] && return 0

    return 1
}
```

MCPツールは `should_allow_mcp()` 関数に追記:

```bash
should_allow_mcp() {
    local tool="$1"

    # --- MCPパターンはここに記述 ---
    [[ "$tool" =~ ^mcp__youtrack__ ]] && return 0
    [[ "$tool" =~ ^mcp__kibela__ ]] && return 0

    return 1
}
```

## デバッグ

`--debug` オプションでログを出力:

```json
{
  "command": "/path/to/hooks/auto-allow.sh --debug"
}
```

ログは `.claude/hooks/auto-allow-debug.log` に出力される。
