#!/usr/bin/env bash
# Notification / Stop / SubagentStop フック: Discord/Slack へフラット通知を webhook POST する。
#   設定は単一ファイル `.claude/yosage-dev-harness.local.json`(harness/lib/config.sh 経由)。
#   設定用の環境変数は読まない(利用者が変えた項目だけを設定ファイルに書く運用にするため)。
#   webhook URL 未設定なら無音 exit 0(opt-in by URL。base に既定配線しても無影響)。
#   POST 失敗・依存欠如でも hook 全体を落とさない(通知はベストエフォート。常に exit 0)。
#   ydh_config_get の戻り値が 3(jq/python3 無し)・4(設定ファイルが壊れた JSON)でも同様に
#   何もせず exit 0(best-effort。セッションを止めない)。
#   provider 差は payload キーで吸収(Slack: text / Discord: content)。判別は URL ホスト名
#   (プロキシ等で崩れる場合は provider 明示指定で上書き)。
set -uo pipefail

input="$(cat)"   # stdin は無条件で読み切る(early exit で読まずに終えると呼び出し元に SIGPIPE が飛ぶ)

root="${CLAUDE_PROJECT_DIR:-}"
[ -n "$root" ] || exit 0
lib="$(dirname "${BASH_SOURCE[0]}")/../lib/config.sh"
[ -f "$lib" ] || exit 0
# shellcheck source=../lib/config.sh
. "$lib"

# config-get.sh(秘密を返さない入口)ではなく ydh_config_get を直接呼ぶ — notify.sh 自身が
# webhook URL(秘密)を必要とする数少ない呼び出し元のため。
cfg_get() { ydh_config_get "$root" "$1" 2>/dev/null; }  # <dotted.key> — rc 3/4 は呼び出し側で無視

url="$(cfg_get notify.url)"
[ -n "$url" ] || exit 0

jqget() { command -v jq >/dev/null 2>&1 && printf '%s' "$input" | jq -r "$1" 2>/dev/null; }
pyget() {  # <key>
  command -v python3 >/dev/null 2>&1 || return 0
  printf '%s' "$input" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
v = d.get(sys.argv[1])
print(v if isinstance(v, str) else "")
' "$1" 2>/dev/null
}
get() {  # <key> — jq 優先 → python3 フォールバック
  local v
  v="$(jqget ".$1 // empty")"
  [ -n "$v" ] || v="$(pyget "$1")"
  printf '%s' "$v"
}

event="$(get hook_event_name)"
[ -n "$event" ] || event="unknown"

# イベント別 on/off(既定: URL があれば全イベント有効。明示的に false で無効化)
case "$event" in
  Notification) on="$(cfg_get notify.on_notification)" ;;
  Stop)         on="$(cfg_get notify.on_stop)" ;;
  SubagentStop) on="$(cfg_get notify.on_subagent_stop)" ;;
  *)            on=true ;;
esac
case "$on" in 0|false|False|FALSE) exit 0 ;; esac

session_id="$(get session_id)"
short_session="$(printf '%s' "$session_id" | cut -c1-8)"
[ -n "$short_session" ] || short_session="unknown"

cwd="$(get cwd)"
[ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
repo="$(basename "$cwd")"

msg="Claude Code [$event] repo=$repo session=$short_session"
if [ "$event" = "Notification" ]; then
  ntype="$(get notification_type)"
  [ -n "$ntype" ] && msg="$msg type=$ntype"
fi

# provider 判別: 設定ファイル > URL ホスト名(不明なら Slack 形式にフォールバック)
provider="$(cfg_get notify.provider)"
if [ -z "$provider" ]; then
  case "$url" in
    *discord.com/api/webhooks*|*discordapp.com/api/webhooks*) provider=discord ;;
    *) provider=slack ;;
  esac
fi
key="text"
[ "$provider" = "discord" ] && key="content"

payload=""
if command -v jq >/dev/null 2>&1; then
  payload="$(jq -n --arg k "$key" --arg v "$msg" '{($k): $v}')"
elif command -v python3 >/dev/null 2>&1; then
  payload="$(python3 -c 'import json,sys;print(json.dumps({sys.argv[1]: sys.argv[2]}))' "$key" "$msg")"
fi
[ -n "$payload" ] || exit 0

command -v curl >/dev/null 2>&1 || exit 0
# 短い timeout でベストエフォート POST。失敗しても hook は落とさない(常に exit 0)。
curl -fsS -m 3 -X POST -H 'Content-Type: application/json' -d "$payload" "$url" >/dev/null 2>&1 || true
exit 0
