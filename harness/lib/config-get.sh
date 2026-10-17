#!/usr/bin/env bash
# harness/lib/config-get.sh — 設定から1項目だけを取り出す入口(エージェント・スキルが使う)。
#
# エージェント・スキルは設定ファイル(`.claude/yosage-dev-harness.local.json`)を Read/cat で
# 丸ごと開かない — 秘密の値(今は notify.url)が入りうるため、必要な1項目だけをここで取り出す。
#
# 使い方: yosage-dev-harness-config-get <dotted.key>
#   → ydh_config_get "$(ydh_repo_root)" <dotted.key> の値を1行出力する。
#   スキーマで writeOnly:true の項目(秘密)は値を出さず exit 5
#   (「秘密の項目は取り出せません。設定の有無は状態表示で確かめてください」)。
#
# `harness/bin/yosage-dev-harness-config-get` から名前で呼ぶ(パスを書かない)。
set -uo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./config.sh
. "$_dir/config.sh"

key="${1:-}"
if [ -z "$key" ]; then
  echo "使い方: yosage-dev-harness-config-get <dotted.key>" >&2
  exit 2
fi

if ydh_config_is_secret "$key"; then
  echo "秘密の項目は取り出せません。設定の有無は状態表示で確かめてください。" >&2
  exit 5
fi

root="$(ydh_repo_root)" || { echo "config-get: git リポジトリの外です" >&2; exit 1; }
ydh_config_get "$root" "$key"
exit $?
