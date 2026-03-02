# ai-dev-infra

AI駆動開発のインフラツール群。Git hooks と複数AIエージェントを組み合わせて、開発ワークフローを自動化する。

## 機能

| 機能 | 説明 | ドキュメント |
|------|------|-------------|
| 自動レビュー | `git push` 時に3エージェント並列でコードレビュー | [how-to-use/auto-review.md](how-to-use/auto-review.md) |
| 開発スキル | Issue 駆動の計画→実装→中断→再開ワークフロー | [how-to-use/dev-skills.md](how-to-use/dev-skills.md) |

## ディレクトリ構成

```
.claude/skills/                # Claude Code スキル
  dev-plan/SKILL.md            #   計画作成
  dev-execute/SKILL.md         #   実装実行
  dev-pause/SKILL.md           #   作業中断・引き継ぎ
  dev-resume/SKILL.md          #   作業再開
.agents/skills/                # エージェント共通スキル（同内容）
.config/
  project.yml                  # リポジトリ情報（プロジェクトごとに編集）
  ai-models.yml                # AIモデル設定
dev-tools/
  review.sh                    # 3エージェント並列レビュー
  config.sh                    # YAML設定リーダー
  perspectives.md              # レビュー観点（カスタマイズ用）
lefthook.yml                   # Git hooks 設定
```

## 前提条件

- [Lefthook](https://github.com/evilmartians/lefthook)
- [GitHub CLI](https://cli.github.com/) (`gh`)
- Python 3（YAML パーサーとして使用）
- 以下のAI CLIツールのうち1つ以上:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`)
  - [Codex CLI](https://github.com/openai/codex) (`codex`)
