echo "== notify.sh (Discord/Slack webhook 通知) =="
ntbin="$(mktemp -d)"; ntlog="$(mktemp -d)/curl.log"
cat > "$ntbin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$NOTIFY_CURL_LOG"
EOF
chmod +x "$ntbin/curl"

ntproj="$(mktemp -d)"; mkdir -p "$ntproj/.claude"
ntcfg="$ntproj/.claude/yosage-dev-harness.local.json"

# CLAUDE_PROJECT_DIR 未設定 → 無音 exit 0(curl は呼ばれない)
: > "$ntlog"
json_notify Stop sess12345678 /tmp/some-repo | NOTIFY_CURL_LOG="$ntlog" PATH="$ntbin:$PATH" bash "$H/hooks/notify.sh" >/dev/null 2>&1
exit_is "CLAUDE_PROJECT_DIR未設定は exit 0" 0 "$?"
if [ -s "$ntlog" ]; then ng "CLAUDE_PROJECT_DIR未設定は curl を呼ばない"; else ok "CLAUDE_PROJECT_DIR未設定は curl を呼ばない"; fi

# 設定ファイル無し(CLAUDE_PROJECT_DIR はあるが .claude/yosage-dev-harness.local.json 無し) → 無音 exit 0
: > "$ntlog"
ntproj_empty="$(mktemp -d)"; mkdir -p "$ntproj_empty/.claude"
json_notify Stop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj_empty" NOTIFY_CURL_LOG="$ntlog" PATH="$ntbin:$PATH" bash "$H/hooks/notify.sh" >/dev/null 2>&1
exit_is "設定ファイル無しは exit 0" 0 "$?"
if [ -s "$ntlog" ]; then ng "設定ファイル無しは curl を呼ばない"; else ok "設定ファイル無しは curl を呼ばない"; fi
rm -rf "$ntproj_empty"

# on/off: 対象イベントを無効化すると curl を呼ばない(既定は全イベント有効)
: > "$ntlog"
printf '{ "notify": { "url": "https://hooks.slack.com/services/T000/B000/xxxx", "on_stop": false } }\n' > "$ntcfg"
json_notify Stop sess12345678 /tmp/some-repo \
  | CLAUDE_PROJECT_DIR="$ntproj" NOTIFY_CURL_LOG="$ntlog" PATH="$ntbin:$PATH" bash "$H/hooks/notify.sh" >/dev/null 2>&1
exit_is "Stop 無効化は exit 0" 0 "$?"
if [ -s "$ntlog" ]; then ng "on/off: 無効化イベントは curl を呼ばない"; else ok "on/off: 無効化イベントは curl を呼ばない"; fi

# Slack URL → {"text": ...} で POST。メッセージに event/repo/session を含む。
: > "$ntlog"
printf '{ "notify": { "url": "https://hooks.slack.com/services/T000/B000/xxxx" } }\n' > "$ntcfg"
json_notify Stop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj" NOTIFY_CURL_LOG="$ntlog" PATH="$ntbin:$PATH" \
    bash "$H/hooks/notify.sh" >/dev/null 2>&1
exit_is "Slack URL は exit 0" 0 "$?"
nto="$(cat "$ntlog" 2>/dev/null)"
out_has   "Slack: text キーで POST"          '"text"'              "$nto"
out_has   "Slack: repo(cwd basename)を含む"  "repo=yosage-dev-harness" "$nto"
out_has   "Slack: session を短縮して含む"    "session=sess1234"    "$nto"
out_has   "Slack: event を含む"              "[Stop]"              "$nto"

# Discord URL → {"content": ...} で POST
: > "$ntlog"
printf '{ "notify": { "url": "https://discord.com/api/webhooks/123/token" } }\n' > "$ntcfg"
json_notify SubagentStop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj" NOTIFY_CURL_LOG="$ntlog" PATH="$ntbin:$PATH" \
    bash "$H/hooks/notify.sh" >/dev/null 2>&1
nto="$(cat "$ntlog" 2>/dev/null)"
out_has   "Discord: content キーで POST" '"content"' "$nto"
out_hasnt "Discord: text キーは使わない" '"text"'    "$nto"

# Notification イベントは notification_type を添える
: > "$ntlog"
printf '{ "notify": { "url": "https://hooks.slack.com/services/T000/B000/xxxx" } }\n' > "$ntcfg"
json_notify Notification sess12345678 /tmp/yosage-dev-harness permission_prompt \
  | CLAUDE_PROJECT_DIR="$ntproj" NOTIFY_CURL_LOG="$ntlog" PATH="$ntbin:$PATH" \
    bash "$H/hooks/notify.sh" >/dev/null 2>&1
out_has "Notification: notification_type を含む" "type=permission_prompt" "$(cat "$ntlog" 2>/dev/null)"

# provider 明示指定(設定ファイルの notify.provider)が URL ホスト名判別より優先される
: > "$ntlog"
printf '{ "notify": { "url": "https://example.invalid/webhook", "provider": "discord" } }\n' > "$ntcfg"
json_notify Stop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj" NOTIFY_CURL_LOG="$ntlog" PATH="$ntbin:$PATH" \
    bash "$H/hooks/notify.sh" >/dev/null 2>&1
out_has "provider 明示指定(discord)が優先" '"content"' "$(cat "$ntlog" 2>/dev/null)"

# 環境変数 YOSAGE_NOTIFY_* を export しても挙動は変わらない(読まない・回帰防止)
: > "$ntlog"
printf '{ "notify": { "url": "https://hooks.slack.com/services/T000/B000/xxxx", "on_stop": false } }\n' > "$ntcfg"
json_notify Stop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj" YOSAGE_NOTIFY_URL="https://discord.com/api/webhooks/999/abc" YOSAGE_NOTIFY_ON_STOP=1 \
    NOTIFY_CURL_LOG="$ntlog" PATH="$ntbin:$PATH" bash "$H/hooks/notify.sh" >/dev/null 2>&1
if [ -s "$ntlog" ]; then ng "YOSAGE_NOTIFY_* を export しても on_stop=false のまま(env は読まない)"; else ok "YOSAGE_NOTIFY_* を export しても on_stop=false のまま(env は読まない)"; fi

# jq 非在(python3 フォールバック)でも同じ payload が組み立つ(pyenv shim 回避で実体を解決。knowledge-sync.sh と同型の手法)
nojq="$(mktemp -d)"
realpy="$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null)"
for t in bash cat cut basename curl dirname; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$nojq/$t"; done
ln -sf "$ntbin/curl" "$nojq/curl"   # stub curl(ログ採取用)で上書き
[ -n "$realpy" ] && ln -sf "$realpy" "$nojq/python3"
: > "$ntlog"
printf '{ "notify": { "url": "https://hooks.slack.com/services/T000/B000/xxxx" } }\n' > "$ntcfg"
json_notify Stop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj" NOTIFY_CURL_LOG="$ntlog" PATH="$nojq" \
    bash "$H/hooks/notify.sh" >/dev/null 2>&1
out_has "jq非在(python3): text キーで POST"         '"text"'              "$(cat "$ntlog" 2>/dev/null)"
out_has "jq非在(python3): repo/session を含む"       "repo=yosage-dev-harness" "$(cat "$ntlog" 2>/dev/null)"
: > "$ntlog"
printf '{ "notify": { "url": "https://discord.com/api/webhooks/123/token" } }\n' > "$ntcfg"
json_notify SubagentStop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj" NOTIFY_CURL_LOG="$ntlog" PATH="$nojq" \
    bash "$H/hooks/notify.sh" >/dev/null 2>&1
out_has "jq非在(python3): content キーで POST" '"content"' "$(cat "$ntlog" 2>/dev/null)"
rm -rf "$nojq"

# curl 非在でも hook を落とさない(依存欠如でもベストエフォートで exit 0)
nocurl="$(mktemp -d)"
for t in bash cat cut basename dirname; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$nocurl/$t"; done
command -v jq >/dev/null 2>&1 && ln -sf "$(command -v jq)" "$nocurl/jq"
printf '{ "notify": { "url": "https://hooks.slack.com/services/T000/B000/xxxx" } }\n' > "$ntcfg"
json_notify Stop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj" PATH="$nocurl" bash "$H/hooks/notify.sh" >/dev/null 2>&1
exit_is "curl 非在でも exit 0(依存欠如でも hook を落とさない)" 0 "$?"
rm -rf "$nocurl"

# 壊れた設定ファイル(構文エラー / トップレベル非object)でもクラッシュせず既定(無音)へフォールバックする(回帰防止)。
# jq/python3 どちらの読み経路でも exit 0(hook を落とさない。ydh_config_get の rc=4 を best-effort で無視)。
: > "$ntlog"
printf '{ "notify": { "url": "https://hooks.slack.com/services/T000/B000/xxxx", invalid syntax here' > "$ntcfg"
json_notify Stop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj" NOTIFY_CURL_LOG="$ntlog" PATH="$ntbin:$PATH" bash "$H/hooks/notify.sh" >/dev/null 2>&1
exit_is "壊れたJSON(構文エラー,jq経路)は既定へフォールバックし exit 0" 0 "$?"
if [ -s "$ntlog" ]; then ng "壊れたJSON(jq経路)は url 無しとして curl を呼ばない"; else ok "壊れたJSON(jq経路)は url 無しとして curl を呼ばない"; fi

nojq2="$(mktemp -d)"
realpy2="$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null)"
for t in bash cat cut basename curl dirname; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$nojq2/$t"; done
ln -sf "$ntbin/curl" "$nojq2/curl"   # stub curl(ログ採取用)で上書き
[ -n "$realpy2" ] && ln -sf "$realpy2" "$nojq2/python3"
: > "$ntlog"
json_notify Stop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj" NOTIFY_CURL_LOG="$ntlog" PATH="$nojq2" bash "$H/hooks/notify.sh" >/dev/null 2>&1
exit_is "壊れたJSON(構文エラー,python3経路)は既定へフォールバックし exit 0" 0 "$?"
if [ -s "$ntlog" ]; then ng "壊れたJSON(python3経路)は url 無しとして curl を呼ばない"; else ok "壊れたJSON(python3経路)は url 無しとして curl を呼ばない"; fi

: > "$ntlog"
printf '["not", "an", "object"]\n' > "$ntcfg"
json_notify Stop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj" NOTIFY_CURL_LOG="$ntlog" PATH="$ntbin:$PATH" bash "$H/hooks/notify.sh" >/dev/null 2>&1
exit_is "トップレベル非object(配列,jq経路)は既定へフォールバックし exit 0" 0 "$?"
if [ -s "$ntlog" ]; then ng "トップレベル非object(jq経路)は url 無しとして curl を呼ばない"; else ok "トップレベル非object(jq経路)は url 無しとして curl を呼ばない"; fi

: > "$ntlog"
json_notify Stop sess12345678 /tmp/yosage-dev-harness \
  | CLAUDE_PROJECT_DIR="$ntproj" NOTIFY_CURL_LOG="$ntlog" PATH="$nojq2" bash "$H/hooks/notify.sh" >/dev/null 2>&1
exit_is "トップレベル非object(配列,python3経路)は既定へフォールバックし exit 0" 0 "$?"
if [ -s "$ntlog" ]; then ng "トップレベル非object(python3経路)は url 無しとして curl を呼ばない"; else ok "トップレベル非object(python3経路)は url 無しとして curl を呼ばない"; fi
rm -rf "$nojq2"

rm -rf "$ntproj"

rm -rf "$ntbin" "$(dirname "$ntlog")"
