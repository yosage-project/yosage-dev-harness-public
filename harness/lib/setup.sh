#!/usr/bin/env bash
# harness/lib/setup.sh — setup/update/status が使う関数群。
#
# 導入先に守りに必要な最小のものだけを書き込む(ydh_gitignore_apply・ydh_worktrees_ignore_ensure・
# ydh_recommended_settings_put)。「対象を判定するだけ・書き込まない」関数(ydh_gitignore_plan・
# ydh_config_unknown_keys・ydh_recommended_settings_render)は status からも使う。
#
# source して使う(git-outermost-root.sh・config.sh と同じ位置づけ。CLI エントリポイントは持たない)。
#
# 提供する関数:
#   ydh_gitignore_plan <repo-root>            → 各行の判定を「<状態>\t<行>」で1行ずつ出力
#     (状態: covered / negated / missing)
#   ydh_gitignore_apply <repo-root>           → missing の行を .gitignore へ足し、
#     「added\t<行>」「negated\t<行>」を出力(negated は報告のみ・書き込まない)
#   ydh_worktrees_ignore_ensure <repo-root>   → .claude/worktrees/.gitignore を確認/作成/書き換え、
#     行った操作があれば「<created|rewritten|tracked>\t.claude/worktrees/.gitignore」を出力
#   ydh_workspace_members <root>              → 直下の子ディレクトリのうち .git を持つものを1行ずつ
#   ydh_config_unknown_keys <repo-root>       → 設定ファイルのキーのうちスキーマに無いもの(dotted)を1行ずつ
#   ydh_recommended_settings_render           → 推奨設定の見本の JSON を標準出力に出す
#   ydh_recommended_settings_put <repo-root>  → render の結果を推奨設定の見本ファイルへ丸ごと書く
#   ydh_config_init <repo-root> <schema-url> [workspace-bool]
#     → 設定ファイルが無い場合に限り {"$schema": <url>[, "workspace": <bool>]} を新規作成する
#   ydh_config_set_workspace <repo-root> <true|false>
#     → 既存の設定ファイルの workspace キーだけを書き換える(他のキーは変えない)
#   ydh_config_schema_keys                    → スキーマが持つ既知の dotted key を1行ずつ出力(表示順)
set -uo pipefail

# 設定ファイルの $schema 参照先(公開用リポジトリの既定ブランチの raw URL)。プラグインの実体の
# 置き場(版ごとに変わりホームディレクトリ名を含む)ではなく、公開リポジトリの既定ブランチを指す形で
# 固定する(決定: 導入先固有ではなく参照専用の URL であり、公開リポジトリが private のままの期間が
# 長ければ見直す)。
YDH_SCHEMA_URL="https://raw.githubusercontent.com/yosage-project/yosage-dev-harness-public/main/harness/config/yosage-dev-harness.schema.json"

_ydh_setup_lib_dir() { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }
_ydh_setup_dir="$(_ydh_setup_lib_dir)"
# shellcheck source=./config.sh
. "$_ydh_setup_dir/config.sh"
# shellcheck source=./secret-patterns.sh
. "$_ydh_setup_dir/secret-patterns.sh"

_ydh_gitignore_lines_path() { printf '%s/gitignore-lines.txt' "$(_ydh_config_dir)"; }

ydh_worktrees_ignore_path() { printf '%s/.claude/worktrees/.gitignore' "${1:-}"; }
ydh_recommended_settings_path() { printf '%s/.claude/yosage-dev-harness.recommended-settings.json' "${1:-}"; }

# 秘密ファイル以外の deny(旧 settings.base.json の permissions.deny 由来)。
_YDH_EXTRA_DENY=(
  # PR マージ操作の deny(逐語では書かない。配布 payload に実行する記述をそのまま残さない
  # 不変のため、隣接する文字列リテラルの連結に分ける。実行時は連結され通常どおり動く)。
  "Bash(gh pr me""rge:*)"
  "Bash(git commit -a:*)"
  "Bash(git commit --all:*)"
)

# ydh_gitignore_plan <repo-root>
#   gitignore-lines.txt の各行を判定し「<状態>\t<行>」を1行ずつ出す。
#   判定: git -C <repo-root> -c core.excludesFile= check-ignore --no-index -v -- <path>
#     (path は行の先頭 / を外し、末尾 / はそのまま、* は 'X' に置き換えた検査用パス)
#   - 出力が空(未一致) → 対象リポジトリの .gitignore に「!<行>」(打ち消し)が既にあれば negated、
#     無ければ missing。
#   - 出力あり、出どころが <repo-root>/.git/info/exclude → missing(info/exclude には頼らない)。
#   - 出力あり、パターン(<source>:<line>:<pattern> の <pattern> 部分)が "!" で始まる → negated。
#     (git の実測での既知の癖: 対象の行の後に同じ行を打ち消す行があると、check-ignore -v は
#     ファイル対象では最後に一致した打ち消しパターンを表示しつつ exit 0 を返す──「出力が空でない
#     ＝ covered」だけで判定すると、この打ち消し済みの状態を誤って足りていると判定してしまう。
#     ディレクトリ対象では同じ状況でも出力が空・exit 1 になり上の「出力が空」の枝で正しく処理される
#     ため、両方の枝を通して判定できるよう、ここでも明示的にパターンの "!" 接頭辞を見る)。
#   - 出力あり、それ以外 → covered。
ydh_gitignore_plan() {  # <repo-root>
  local root="${1:-}"
  [ -n "$root" ] && [ -d "$root" ] || return 2
  local lines_file
  lines_file="$(_ydh_gitignore_lines_path)"
  [ -f "$lines_file" ] || return 2

  local root_gi="$root/.gitignore"
  local line path out src pattern head1 state
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -n "$line" ] || continue
    path="${line#/}"
    path="${path//\*/X}"
    out="$(git -C "$root" -c core.excludesFile= check-ignore --no-index -v -- "$path" 2>/dev/null)"
    if [ -z "$out" ]; then
      if [ -f "$root_gi" ] && _ydh_gitignore_has_negation "$root_gi" "$line"; then
        state="negated"
      else
        state="missing"
      fi
    else
      src="${out%%:*}"
      case "$src" in
        "$root"/.git/info/exclude|.git/info/exclude) state="missing" ;;
        *)
          head1="${out%%$'\t'*}"
          pattern="${head1#*:}"
          pattern="${pattern#*:}"
          case "$pattern" in
            '!'*) state="negated" ;;
            *) state="covered" ;;
          esac
          ;;
      esac
    fi
    printf '%s\t%s\n' "$state" "$line"
  done < "$lines_file"
}

# _ydh_gitignore_has_negation <gitignore-file> <line>
#   <gitignore-file> に、先頭の "!" を外すと <line> と一致する行(CRLF を許容)があるか。
_ydh_gitignore_has_negation() {
  local f="$1" line="$2" l
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%$'\r'}"
    case "$l" in
      "!$line") return 0 ;;
    esac
  done < "$f"
  return 1
}

# ydh_gitignore_apply <repo-root>
#   ydh_gitignore_plan の missing を .gitignore の末尾に足す(ファイルが無ければ作る)。
#   既存の改行が CRLF ならその流儀を保つ。末尾に改行が無ければ先に1つ足す。
#   足した行(added)と negated の行(報告のみ)を「<状態>\t<行>」で出力する。
ydh_gitignore_apply() {  # <repo-root>
  local root="${1:-}"
  [ -n "$root" ] && [ -d "$root" ] || return 2
  local gi="$root/.gitignore"
  local plan state text
  plan="$(ydh_gitignore_plan "$root")" || return $?

  local -a missing=() negated=()
  while IFS=$'\t' read -r state text; do
    [ -n "$state" ] || continue
    case "$state" in
      missing) missing+=("$text") ;;
      negated) negated+=("$text") ;;
    esac
  done <<< "$plan"

  if [ "${#missing[@]}" -gt 0 ]; then
    local crlf="" need_nl="" last_byte
    if [ -f "$gi" ]; then
      LC_ALL=C grep -q $'\r' "$gi" 2>/dev/null && crlf=1
      if [ -s "$gi" ]; then
        last_byte="$(tail -c1 "$gi" | od -An -tx1 2>/dev/null | tr -d ' \n')"
        [ "$last_byte" = "0a" ] || need_nl=1
      fi
    fi
    {
      [ -n "$need_nl" ] && { [ -n "$crlf" ] && printf '\r\n' || printf '\n'; }
      for text in "${missing[@]+"${missing[@]}"}"; do
        if [ -n "$crlf" ]; then printf '%s\r\n' "$text"; else printf '%s\n' "$text"; fi
      done
    } >> "$gi"
  fi

  for text in "${missing[@]+"${missing[@]}"}"; do printf 'added\t%s\n' "$text"; done
  for text in "${negated[@]+"${negated[@]}"}"; do printf 'negated\t%s\n' "$text"; done
  return 0
}

# ydh_worktrees_ignore_ensure <repo-root>
#   .claude/worktrees/.gitignore を確認/作成/書き換える。行った操作があれば
#   「<created|rewritten|tracked>\t.claude/worktrees/.gitignore」を1行出す(何もしなければ無出力)。
ydh_worktrees_ignore_ensure() {  # <repo-root>
  local root="${1:-}"
  [ -n "$root" ] && [ -d "$root" ] || return 2
  local wt_gi
  wt_gi="$(ydh_worktrees_ignore_path "$root")"

  if [ ! -f "$wt_gi" ]; then
    mkdir -p "$(dirname "$wt_gi")" || return 1
    printf '*\n' > "$wt_gi"
    printf 'created\t.claude/worktrees/.gitignore\n'
    return 0
  fi

  local content stripped
  content="$(cat "$wt_gi")"
  stripped="${content%$'\r'}"
  if [ "$stripped" = "*" ]; then
    return 0
  fi

  if git -C "$root" ls-files --error-unmatch .claude/worktrees/.gitignore >/dev/null 2>&1; then
    printf 'tracked\t.claude/worktrees/.gitignore\n'
    return 0
  fi

  printf '*\n' > "$wt_gi"
  printf 'rewritten\t.claude/worktrees/.gitignore\n'
  return 0
}

# ydh_workspace_members <root>
#   <root> 直下の子ディレクトリのうち .git を持つもの(ディレクトリ/ファイルいずれの型でも)を
#   絶対パスで1行ずつ出す(promote-collect.sh 等と同じ member 判定基準)。
ydh_workspace_members() {  # <root>
  local root="${1:-}"
  [ -n "$root" ] && [ -d "$root" ] || return 2
  local d
  for d in "$root"/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    [ -e "$d/.git" ] && printf '%s\n' "$d"
  done
  return 0
}

# ydh_config_unknown_keys <repo-root>
#   設定ファイル(.claude/yosage-dev-harness.local.json)のキーのうち、スキーマに定義が無いもの
#   (親が既知のオブジェクトなら "親.子" のドット区切り、親自体が未知ならそこで止める)を1行ずつ出す。
#   設定ファイルが無ければ何も出さない(exit 0)。
ydh_config_unknown_keys() {  # <repo-root>
  local root="${1:-}"
  [ -n "$root" ] || return 2
  local cfg schema
  cfg="$(ydh_config_path "$root")" || return 2
  [ -f "$cfg" ] || return 0
  schema="$(ydh_schema_path)"
  [ -f "$schema" ] || return 0
  command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || return 3
  _ydh_json_is_valid "$cfg" || return 4

  if command -v jq >/dev/null 2>&1; then
    jq -r --slurpfile s "$schema" '
      def walk_unknown(obj; props; prefix):
        obj | to_entries[] | . as $e |
        (props[$e.key]) as $node |
        if $e.key == "$schema" and prefix == "" then
          empty
        elif $node == null then
          (prefix + $e.key)
        elif (($e.value|type) == "object") and ($node.properties != null) then
          ($e.value | walk_unknown(.; $node.properties; prefix + $e.key + "."))
        else
          empty
        end;
      . as $cfg
      | $cfg | walk_unknown(.; $s[0].properties; "")
    ' "$cfg" 2>/dev/null
  else
    python3 -c '
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
schema = json.load(open(sys.argv[2], encoding="utf-8"))

def walk(obj, props, prefix, out):
    for k, v in obj.items():
        if prefix == "" and k == "$schema":
            continue
        node = (props or {}).get(k)
        if node is None:
            out.append(prefix + k)
        elif isinstance(v, dict) and isinstance(node.get("properties"), dict):
            walk(v, node["properties"], prefix + k + ".", out)

out = []
walk(cfg, schema.get("properties", {}), "", out)
for k in out:
    print(k)
' "$cfg" "$schema" 2>/dev/null
  fi
}

# ydh_recommended_settings_render
#   推奨設定の見本(Claude Code は読まない。利用者が採るものを自分で settings.json へ移す)の
#   JSON を標準出力に出す。permissions.deny は秘密ファイル以外の3件(_YDH_EXTRA_DENY)+
#   秘密ファイルの一覧(secret-patterns.sh の sf_deny_rules。唯一の置き場、書き写さない)。
ydh_recommended_settings_render() {
  command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || return 3
  local deny_lines
  deny_lines="$( { for d in "${_YDH_EXTRA_DENY[@]}"; do printf '%s\n' "$d"; done; sf_deny_rules; } )"
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$deny_lines" | jq -R . | jq -s '{
      "$comment": "yosage-dev-harness の推奨設定の見本。Claude Code はこのファイルを読まない。採るものを自分で .claude/settings.json へ移す。",
      "permissions": { "deny": . }
    }'
  else
    printf '%s\n' "$deny_lines" | python3 -c '
import json, sys
deny = [l for l in sys.stdin.read().splitlines() if l]
print(json.dumps({
    "$comment": "yosage-dev-harness の推奨設定の見本。Claude Code はこのファイルを読まない。採るものを自分で .claude/settings.json へ移す。",
    "permissions": {"deny": deny}
}, ensure_ascii=False, indent=2))
'
  fi
}

# ydh_recommended_settings_put <repo-root>
#   ydh_recommended_settings_render の結果を推奨設定の見本ファイルへ丸ごと書く(置き換え)。
ydh_recommended_settings_put() {  # <repo-root>
  local root="${1:-}"
  [ -n "$root" ] && [ -d "$root" ] || return 2
  local dest
  dest="$(ydh_recommended_settings_path "$root")"
  mkdir -p "$(dirname "$dest")" || return 1
  ydh_recommended_settings_render > "$dest" || return $?
  return 0
}

# ydh_config_init <repo-root> <schema-url> [workspace-bool]
#   設定ファイルが無い場合に限り作成する({"$schema": <url>}。workspace-bool が渡されれば
#   "workspace" キーも足す)。既にファイルがあれば何もしない(呼び出し側が存在確認する想定だが、
#   ここでも二重に安全側へ倒す)。
ydh_config_init() {  # <repo-root> <schema-url> [workspace-bool]
  local root="${1:-}" schema_url="${2:-}" ws="${3:-}"
  [ -n "$root" ] && [ -n "$schema_url" ] || return 2
  local cfg
  cfg="$(ydh_config_path "$root")" || return 2
  [ -f "$cfg" ] && return 0
  mkdir -p "$(dirname "$cfg")" || return 1
  if command -v jq >/dev/null 2>&1; then
    if [ -n "$ws" ]; then
      jq -n --arg schema "$schema_url" --argjson ws "$ws" '{"$schema": $schema, "workspace": $ws}' > "$cfg" || return 1
    else
      jq -n --arg schema "$schema_url" '{"$schema": $schema}' > "$cfg" || return 1
    fi
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
d = {"$schema": sys.argv[1]}
if len(sys.argv) > 2 and sys.argv[2]:
    d["workspace"] = (sys.argv[2] == "true")
print(json.dumps(d, ensure_ascii=False))
' "$schema_url" "$ws" > "$cfg" || return 1
  else
    return 3
  fi
  return 0
}

# ydh_config_set_workspace <repo-root> <true|false>
#   既存の設定ファイルの "workspace" キーだけを書き換える(他のキー・不明なキーはそのまま保つ)。
#   設定ファイルが無ければ何もしない(呼び出し側で ydh_config_init を先に通す想定)。
ydh_config_set_workspace() {  # <repo-root> <true|false>
  local root="${1:-}" ws="${2:-}"
  [ -n "$root" ] && { [ "$ws" = "true" ] || [ "$ws" = "false" ]; } || return 2
  local cfg
  cfg="$(ydh_config_path "$root")" || return 2
  [ -f "$cfg" ] || return 0
  _ydh_json_is_valid "$cfg" || return 4
  local tmp
  tmp="$(mktemp "${cfg}.XXXXXX")" || return 1
  if command -v jq >/dev/null 2>&1; then
    jq --argjson ws "$ws" '.workspace = $ws' "$cfg" > "$tmp" || { rm -f "$tmp"; return 1; }
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["workspace"] = (sys.argv[2] == "true")
print(json.dumps(d, ensure_ascii=False))
' "$cfg" "$ws" > "$tmp" || { rm -f "$tmp"; return 1; }
  else
    rm -f "$tmp"
    return 3
  fi
  mv "$tmp" "$cfg"
}

# ydh_config_schema_keys
#   スキーマ(yosage-dev-harness.schema.json)が持つ既知の dotted key を、スキーマの宣言順で
#   1行ずつ出す(status が既定値/今の値を並べて出すのに使う)。
ydh_config_schema_keys() {
  local schema
  schema="$(ydh_schema_path)"
  [ -f "$schema" ] || return 0
  command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || return 3
  if command -v jq >/dev/null 2>&1; then
    jq -r '
      def leaf_keys(props; prefix):
        props | to_entries[] | . as $e |
        if ($e.value.properties != null) then
          ($e.value.properties | leaf_keys(.; prefix + $e.key + "."))
        else
          (prefix + $e.key)
        end;
      .properties | leaf_keys(.; "")
    ' "$schema" 2>/dev/null
  else
    python3 -c '
import json, sys
schema = json.load(open(sys.argv[1], encoding="utf-8"))

def walk(props, prefix, out):
    for k, v in props.items():
        if isinstance(v.get("properties"), dict):
            walk(v["properties"], prefix + k + ".", out)
        else:
            out.append(prefix + k)

out = []
walk(schema.get("properties", {}), "", out)
for k in out:
    print(k)
' "$schema" 2>/dev/null
  fi
}
