#!/usr/bin/env bash
# inject-rule.sh — 常時オンのルール1本を SessionStart/SubagentStart フックで注入する。
#
# 背景: プラグインは CLAUDE.md を配れない(プラグイン直下の CLAUDE.md は読まれず、常時オンの
# 規律を配る正規の手段が無い)。ルール `knowledge` の判断どおり、導入先へファイルを写さず
# SessionStart(メイン)・SubagentStart(サブエージェント)のフックで注入する。1ルールにつき1フック
# (1フックの出力の上限は1万字だが、フックごとに別計上され複数フックの出力はすべて届く。同じ
# イベントのフックは並行に走り届く順序が保証されないため、1つのルールを途中で切らない)。
#
# 使い方(hooks.json の args から): bash inject-rule.sh <SessionStart|SubagentStart> <rule-name>
#   標準入力(フックの入力 JSON)は使わないが、読み切ってから終了する(パイプの詰まりを避ける)。
set -uo pipefail
cat >/dev/null

event="${1:-}"
name="${2:-}"
rule="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/rules/${name}.md"

if [ -z "$name" ] || [ ! -r "$rule" ]; then
  printf 'yosage-dev-harness: ルール「%s」が見つからず、注入できませんでした\n' "$name" >&2
  exit 1
fi

# 前置き: 注入する文を「システムからの命令」の形で書くと、Claude のプロンプトインジェクション
# 防御に引っかかりうる(出典: Claude Code の hooks リファレンス「Add context for Claude」)。
# そのため命令形ではなく取り決めを述べる書き方にし、出どころの前置きを付ける
# (ルール本文側の文面は既に取り決めを述べる書き方へ書き直し済み。ここでは前置きだけを付ける)。
PREFACE="以下は、このリポジトリで利用者が有効にしたプラグイン yosage-dev-harness の取り決めです（ルール: ${name}）。"

body() {
  printf '%s\n\n' "$PREFACE"
  cat "$rule"
}

case "$event" in
  SessionStart)
    # プレーンな標準出力がそのまま文脈に入る(JSON は不要)。
    body
    exit 0
    ;;
  SubagentStart)
    : # 下で JSON を組み立てる
    ;;
  *)
    printf 'yosage-dev-harness: 未知のイベント「%s」のため注入できませんでした\n' "$event" >&2
    exit 1
    ;;
esac

if command -v jq >/dev/null 2>&1; then
  body | jq -Rs '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:.}}'
elif command -v python3 >/dev/null 2>&1; then
  body | python3 -c 'import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":sys.stdin.read()}}))'
else
  printf 'yosage-dev-harness: jq も python3 も無いため、サブエージェントへルール「%s」を注入できませんでした\n' "$name" >&2
  exit 1
fi
