#!/usr/bin/env bash
# harness/lib/config.sh — 設定の単一ホーム。
#
# 導入先ごとの設定は1ファイル `.claude/yosage-dev-harness.local.json`(git 追跡しない)にまとめる。
# 既定値の唯一の置き場は `harness/config/defaults.json`。環境変数 `YOSAGE_*` は読まない
# (設定ファイルには利用者が変えた項目だけを書き、ハーネスが既定値を書き足すと後で既定値を
# 変えても届かなくなるため)。
#
# source して使う(CLI エントリポイントは持たない。git-outermost-root.sh と同じ位置づけ)。
#
# 提供する関数:
#   ydh_config_path <repo-root>              → 設定ファイルの絶対パスを1行出力
#   ydh_config_get  <repo-root> <dotted.key>  → 値を1行出力(ファイルの値 > defaults.json の値)。
#     真偽値は true/false、未定義は空文字。
#     戻り値: 0=成功 / 2=引数不正 / 3=jq も python3 も無い / 4=設定ファイルが壊れた JSON
#   ydh_config_is_secret <dotted.key>        → スキーマで writeOnly:true が付いていれば 0、
#     無ければ(不明なキーも含め) 1
#   ydh_repo_root                             → cwd の git の「元のチェックアウト」のルートを出力
#     (dirname "$(git rev-parse --path-format=absolute --git-common-dir)"。worktree の中や
#     サブディレクトリから呼んでも、作業ツリーではなく元のチェックアウトのルートを指す)。
#     git の外なら非ゼロ。
set -uo pipefail

_ydh_lib_dir() { cd "$(dirname "${BASH_SOURCE[0]}")" && pwd; }

# harness/config/ の実体を見つける(BASH_SOURCE[0] 基点で解決 → install 先でも dogfood
# worktree でも正しく動く。git-outermost-root.sh 冒頭コメントと同じ流儀)。
_ydh_config_dir() {
  local d
  d="$(_ydh_lib_dir)"
  (cd "$d/../config" 2>/dev/null && pwd)
}

ydh_defaults_path() { printf '%s/defaults.json' "$(_ydh_config_dir)"; }
ydh_schema_path()   { printf '%s/yosage-dev-harness.schema.json' "$(_ydh_config_dir)"; }

ydh_config_path() {  # <repo-root>
  local root="${1:-}"
  [ -n "$root" ] || return 2
  printf '%s/.claude/yosage-dev-harness.local.json' "$root"
}

ydh_repo_root() {
  local gcd
  gcd="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -n "$gcd" ] || return 1
  dirname "$gcd"
}

# <file> の JSON を dotted key で1値取り出す(jq 優先 → python3 フォールバック)。
# ファイルが無ければ空。呼び出し前提: <file> は妥当な JSON であること(壊れた JSON の検出は
# ydh_config_get 側が担う。ここでは呼ばれた時点で「読めるなら読む」だけ)。
_ydh_json_dotted_get() {  # <file> <dotted.key>
  local f="$1" k="$2"
  [ -f "$f" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$k" '
      . as $root
      | ($k | split(".")) as $parts
      | reduce $parts[] as $p ($root; if . == null then null else .[$p] end)
      | if . == null then empty
        elif type == "boolean" then (if . then "true" else "false" end)
        else tostring end
    ' "$f" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
v = d
for p in sys.argv[2].split("."):
    if not isinstance(v, dict) or p not in v:
        v = None
        break
    v = v[p]
if v is None:
    print("")
elif isinstance(v, bool):
    print("true" if v else "false")
else:
    print(v)
' "$f" "$k" 2>/dev/null
  fi
}

# <file> の dotted key が存在するか(値が明示的に空文字列/false/0でも「存在する」とみなす。
# キー自体が無い・途中のオブジェクトが無い・値が null の場合だけ「存在しない」)。
# ydh_config_get がヘッダの約束(「ファイルの値 > defaults.json の値」)を守るために使う——
# キーが存在する場合は値がどうであれ defaults.json へフォールバックしない(空文字列を明示的に
# 書いた場合に既定値へ戻ってしまう欠陥の回帰防止)。
_ydh_json_dotted_has() {  # <file> <dotted.key>
  local f="$1" k="$2"
  [ -f "$f" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    local r
    r="$(jq -r --arg k "$k" '
      . as $root
      | ($k | split(".")) as $parts
      | reduce $parts[] as $p ($root; if . == null then null else .[$p] end)
      | if . == null then "false" else "true" end
    ' "$f" 2>/dev/null)"
    [ "$r" = "true" ]
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
v = d
for p in sys.argv[2].split("."):
    if not isinstance(v, dict) or p not in v:
        sys.exit(1)
    v = v[p]
sys.exit(0 if v is not None else 1)
' "$f" "$k"
  else
    return 1
  fi
}

# <file> が妥当な JSON かどうかだけを判定する(値の中身は見ない)。0=妥当 / 1=壊れている。
_ydh_json_is_valid() {  # <file>
  local f="$1"
  if command -v jq >/dev/null 2>&1; then
    jq empty "$f" >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys
json.load(open(sys.argv[1], encoding="utf-8"))' "$f" >/dev/null 2>&1
  else
    return 1
  fi
}

ydh_config_get() {  # <repo-root> <dotted.key>
  local root="${1:-}" key="${2:-}"
  [ -n "$root" ] && [ -n "$key" ] || return 2
  command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || return 3

  local cfg defaults val
  cfg="$(ydh_config_path "$root")" || return 2
  defaults="$(ydh_defaults_path)"

  if [ -f "$cfg" ]; then
    _ydh_json_is_valid "$cfg" || return 4
    # キーがファイルに存在するなら、値がどうであれ(空文字列を含め)ファイルの値を返す。
    # ここで「値が空文字列なら defaults へフォールバック」に倒すと、利用者が明示的に空文字列を
    # 書いた場合でも既定値へ戻ってしまい、ヘッダの約束(ファイルの値 > defaults.json の値)に反する。
    if _ydh_json_dotted_has "$cfg" "$key"; then
      val="$(_ydh_json_dotted_get "$cfg" "$key")"
      printf '%s' "$val"
      return 0
    fi
  fi
  val="$(_ydh_json_dotted_get "$defaults" "$key")"
  printf '%s' "$val"
  return 0
}

# スキーマの properties を dotted key でたどり、writeOnly:true かどうかを判定する。
# 0=秘密(writeOnly:true) / 1=秘密でない(不明なキーを含む)。
ydh_config_is_secret() {  # <dotted.key>
  local key="${1:-}"
  [ -n "$key" ] || return 1
  local schema
  schema="$(ydh_schema_path)"
  [ -f "$schema" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    local v
    v="$(jq -r --arg k "$key" '
      ($k | split(".")) as $parts
      | reduce $parts[] as $p (.; if . == null then null else (.properties // {})[$p] end)
      | if . == null then "false" else (.writeOnly // false | tostring) end
    ' "$schema" 2>/dev/null)"
    [ "$v" = "true" ]
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c '
import json, sys
try:
    s = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
node = s
for p in sys.argv[2].split("."):
    if not isinstance(node, dict):
        sys.exit(1)
    node = node.get("properties", {}).get(p)
    if node is None:
        sys.exit(1)
sys.exit(0 if node.get("writeOnly") is True else 1)
' "$schema" "$key"
  else
    return 1
  fi
}
