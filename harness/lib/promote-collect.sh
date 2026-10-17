#!/usr/bin/env bash
# promote-collect.sh — promote-knowledge SKILL の動的コンテキスト収集ロジック。
#
# 経緯: 収集ロジックを SKILL.md の動的コンテキスト行にインラインのブレースグループ `{ …; }`＋クォートで
# 直書きすると、ホスト側の permission チェック（ブレース+クォートの組み合わせを難読化コマンドとみなす
# ヒューリスティック）に弾かれ、SKILL 起動自体が失敗する。収集ロジックは複雑なので lib スクリプトへ出し、
# SKILL 側は `yosage-dev-harness-promote-collect <mode>` という単純呼び出しにする。
#
# 使い方:
#   yosage-dev-harness-promote-collect entries    … staged な生層候補(scope: global かつ status: active の local entry)を列挙
#   yosage-dev-harness-promote-collect criteria   … staged な蒸留層候補(criteria.global-proposed.md)を列挙
#
# 呼び出し元(SKILL)の cwd を対象にする(スクリプト自身の場所ではない)。
# workspace かどうか(設定の `workspace` が true か)で自ストアのみ/自ストア+member を切り替える。
# member 判定: workspace 直下の子ディレクトリで `.git` を持つもの(ディレクトリ/ファイルいずれの型でも判定)。
# best-effort な収集コマンドなので -e は付けない(失敗を個別に握って空扱いにする)。
#
# ストア位置は capture-learning 側と同じ固定置き場(.claude/knowledge)を使う(置き場を変える機能は
# 撤去済み。正本ルール `knowledge`)。
set -uo pipefail
KNOWLEDGE_DIR=".claude/knowledge"

pc_log() { printf 'promote-collect: %s\n' "$1" >&2; }

# workspace 判定・同期 source の要約(設定ファイルを丸ごと開かず1項目ずつ取り出す。秘密の値
# writeOnly の項目は出さない)。config.sh が無い(古い install 等)場合は空扱いで進める。
_pc_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
[ -f "$_pc_lib" ] && . "$_pc_lib"
# 戻り値は3値: 0=true(workspace) / 1=false(単一リポジトリ) / 2=判定不能
# (設定ファイルが壊れた JSON・jq/python3 が無い等)。判定不能は「単一リポジトリ」とはみなさない。
pc_is_workspace() {
  command -v ydh_config_get >/dev/null 2>&1 || return 2
  local root val rc
  root="$(ydh_repo_root 2>/dev/null)" || root="$PWD"
  val="$(ydh_config_get "$root" workspace 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] || return 2
  [ "$val" = "true" ] && return 0
  return 1
}
pc_header() {
  local ws="false" src="(未設定)" root v
  if command -v ydh_config_get >/dev/null 2>&1; then
    root="$(ydh_repo_root 2>/dev/null)" || root="$PWD"
    [ "$(ydh_config_get "$root" workspace 2>/dev/null)" = "true" ] && ws="true"
    v="$(ydh_config_get "$root" knowledge.source 2>/dev/null)"
    [ -n "$v" ] && src="$v"
  fi
  printf 'workspace: %s\n' "$ws"
  printf 'knowledge.source: %s\n' "$src"
}

# 生層(staged entry)を1repoぶん収集する。origin_label は出力の由来タグ(自ストア=".", member="<dir名>")。
pc_entries_for() {  # <knowledge-dir> <origin-label>
  local dir="$1" label="$2"
  [ -d "$dir" ] || return 0
  grep -rl '^scope: global' "$dir" --include='*.md' 2>/dev/null \
    | grep -v '/global/' \
    | grep -v '_entry-template' \
    | while IFS= read -r f; do
        grep -q '^status: active' "$f" 2>/dev/null && printf '%s: %s\n' "$label" "$f"
      done
  return 0
}

# 生層候補を集約する(単一 repo モード: 自ストアのみ / workspace モード: 自ストア+各 member)。
pc_collect_entries() {
  {
    pc_entries_for "$KNOWLEDGE_DIR" "."
    if pc_is_workspace; then
      for d in */; do
        [ -e "${d}.git" ] || continue
        pc_entries_for "${d}${KNOWLEDGE_DIR}" "${d%/}"
      done
    fi
  } 2>/dev/null | sort
}

# 蒸留層(criteria.global-proposed.md)を集約する(単一 repo モード: 自ストアのみ / workspace モード: 自ストア+各 member)。
pc_collect_criteria() {
  local out
  out=$({
    [ -f .claude/review/criteria.global-proposed.md ] \
      && printf '=== . ===\n%s\n' "$(cat .claude/review/criteria.global-proposed.md)"
    if pc_is_workspace; then
      for d in */; do
        [ -e "${d}.git" ] || continue
        [ -f "${d}.claude/review/criteria.global-proposed.md" ] \
          && printf '=== %s ===\n%s\n' "${d%/}" "$(cat "${d}.claude/review/criteria.global-proposed.md")"
      done
    fi
  } 2>/dev/null)
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}

promote_collect() {  # <mode>
  local mode="${1:-}" out _pc_ws_rc
  pc_is_workspace; _pc_ws_rc=$?
  if [ "$_pc_ws_rc" = 2 ]; then
    pc_log "ワークスペース判定に失敗しました(設定ファイルが壊れた JSON、または jq/python3 が無い)。単一リポジトリとはみなさず停止します。"
    return 1
  fi
  case "$mode" in
    entries)
      pc_header
      out="$(pc_collect_entries)"
      if [ -n "$out" ]; then printf '%s\n' "$out"; else echo "(該当なし)"; fi
      ;;
    criteria)
      out="$(pc_collect_criteria)"
      if [ -n "$out" ]; then printf '%s\n' "$out"; else echo "(criteria.global-proposed.md 無し)"; fi
      ;;
    *)
      pc_log "不明な mode: ${mode:-(空)}(entries か criteria を指定)"
      return 1
      ;;
  esac
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then promote_collect "${1:-}"; fi
