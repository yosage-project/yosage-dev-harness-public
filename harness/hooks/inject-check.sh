#!/usr/bin/env bash
# inject-check.sh — SessionStart(matcher なし)で1回、ルール注入の前提を確認する。
#
# 背景: SubagentStart での注入が失敗しても、利用者からは見えない(サブエージェント自身の会話記録
# にしか出ない)。セッション開始時にメインで前提を確認し、問題があれば利用者に見える形(標準エラー
# 出力の "hook error")で知らせる。
#
# 確認すること:
#   (a) jq か python3 のどちらかがある(無いと inject-rule.sh は SubagentStart への注入ができない)。
#   (b) harness/rules/*.md がすべて読める(1本でも読めなければ、そのルールは注入できない)。
# 「hooks.json に載っている全ルール」は hooks.json 自身を読まずに harness/rules/*.md の一覧で
# 代える(jq が無い環境でも本チェック自体が動くように)。hooks.json とルール一覧の一致は
# test/suites/91-inject.sh の静的テストで別途保証する。
#
# 利用者に見えるのは標準エラー出力の1行目だけ(hook error の表示は先頭行しか出ないため)。
# 1行目だけで意味が通る文にする。問題が無ければ何も出さず exit 0。
set -uo pipefail
cat >/dev/null

harness_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  printf 'yosage-dev-harness: jq も python3 も無いため、サブエージェントにハーネスの取り決めが届きません（jq か python3 を入れてください）\n' >&2
  exit 1
fi

unreadable=""
for rule in "$harness_root"/rules/*.md; do
  [ -e "$rule" ] || continue
  if [ ! -r "$rule" ]; then
    unreadable="${unreadable}${unreadable:+, }$(basename "$rule")"
  fi
done

if [ -n "$unreadable" ]; then
  printf 'yosage-dev-harness: ルールの一部が読めないため、注入できません（対象: %s）\n' "$unreadable" >&2
  exit 1
fi

exit 0
