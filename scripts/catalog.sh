#!/usr/bin/env bash
# scripts/catalog.sh — 開発者向けの道具: このリポジトリ自身の README.md「機能カタログ」区間を
#   harness/(プラグイン本体)の内容から再生成する。プラグインには含まれない(プラグインの外・
#   scripts/ に置く開発時専用ツール)。
#
# 使い方:
#   scripts/catalog.sh --write   README.md の機能カタログ区間を再生成して書き戻す
#   scripts/catalog.sh --check   再生成した内容と README.md の区間を比較し、不一致なら exit 1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PAYLOAD_DIR="$ROOT_DIR/harness"
README="$ROOT_DIR/README.md"

# catalog マーカー: このリポジトリ自身の README.md「機能カタログ」区間を機械管理する(write_managed_block
# を再利用。BEGIN/END の2マーカーで範囲を区切り、範囲外の手書き解説はそのまま保存する)。
# 過去に存在した単一行マーカー形式は無い(新規追加)ため、CATALOG_LEGACY_MARKER は「境界不明時の
# メッセージ分岐」用のダミー(実ファイルに出現しない文字列)を渡す(空文字は grep -F が全行に
# マッチしうるため避ける)。
CATALOG_LEGACY_MARKER='<!-- yosage-dev-harness catalog: no legacy format -->'
CATALOG_BEGIN_MARKER='<!-- BEGIN yosage-dev-harness catalog (generated) -->'
CATALOG_END_MARKER='<!-- END yosage-dev-harness catalog (generated) -->'

die() { printf 'error: %s\n' "$1" >&2; exit 1; }

# shellcheck disable=SC1091
. "$SCRIPT_DIR/catalog-gen.sh"

# managed-block マーカー: dest に <begin>...<end> で囲った body を注入/更新する(CLI 撤去前の
# install/update ツールから移設。挙動は変えない)。
#   - dest が無い                                    → 新規生成(block のみのファイルを作る)
#   - dest に begin/end がそれぞれ「ちょうど1個」あり、
#     かつ begin が end より前(well-formed な block) → block の中身だけ差し替え、block外の
#     利用者記述(block の前後にある行)はそのまま保存する
#   - 上記以外の全て(legacy 単一行マーカーのみ/マーカー無し/begin・end の個数不一致/出現順序不正)
#     → 境界が不明な既存内容につき、部分的に救おうとせず丸ごと退避してから新形式で新規生成する
#       (存在有無だけの判定は END欠落・複数組・利用者記述内の偶然一致行で境界を誤認し、
#       間の利用者記述を無警告で消しうる)
write_managed_block() {  # <dest> <legacy_marker> <begin_marker> <end_marker> <body>
  local dest="$1" legacy="$2" begin="$3" end="$4" body="$5"
  local block tmp bodyfile
  local begin_n end_n begin_line end_line well_formed
  local backup latest slot n

  block="$(printf '%s\n%s\n%s\n' "$begin" "$body" "$end")"

  if [ ! -f "$dest" ]; then
    printf '%s\n' "$block" > "$dest"
    return 0
  fi

  begin_n="$(grep -cFx "$begin" "$dest" 2>/dev/null)" || begin_n=0
  end_n="$(grep -cFx "$end" "$dest" 2>/dev/null)" || end_n=0
  well_formed=0
  if [ "$begin_n" -eq 1 ] && [ "$end_n" -eq 1 ]; then
    begin_line="$(grep -nFx "$begin" "$dest" 2>/dev/null | head -1 | cut -d: -f1)"
    end_line="$(grep -nFx "$end" "$dest" 2>/dev/null | head -1 | cut -d: -f1)"
    if [ -n "$begin_line" ] && [ -n "$end_line" ] && [ "$begin_line" -lt "$end_line" ]; then
      well_formed=1
    fi
  fi

  if [ "$well_formed" -eq 1 ]; then
    if tmp=$(mktemp); then :; else die "一時ファイルを作成できません(mktemp)"; fi
    if bodyfile=$(mktemp); then :; else die "一時ファイルを作成できません(mktemp)"; fi
    printf '%s\n' "$body" > "$bodyfile"
    awk -v begin="$begin" -v end="$end" -v bodyfile="$bodyfile" '
      $0 == begin { print; while ((getline line < bodyfile) > 0) print line; skip=1; next }
      $0 == end   { skip=0; print; next }
      skip == 1   { next }
      { print }
    ' "$dest" > "$tmp"
    mv "$tmp" "$dest"
    rm -f "$bodyfile"
    return 0
  fi

  backup="${dest}.pre-yosage"
  latest=""; slot="$backup"; n=1
  while [ -f "$slot" ]; do
    latest="$slot"
    n=$((n+1))
    slot="${backup}.${n}"
  done
  if [ -n "$latest" ] && cmp -s "$dest" "$latest"; then
    : # 直近の退避済み内容と同一 → 追加退避しない(重複抑止)
  else
    cp "$dest" "$slot"
    if [ "$slot" = "$backup" ]; then
      if grep -qF "$legacy" "$dest" 2>/dev/null; then
        info "  ⚠ $(basename "$dest"): 旧形式(単一行)マーカーから managed-block 構造へ初回移行(旧内容を $(basename "$backup") へ退避)"
      else
        info "  ⚠ $(basename "$dest"): managed-block 構造へ初回移行(既存内容を $(basename "$backup") へ退避)"
      fi
    else
      info "  ⚠ $(basename "$dest"): 境界不明の状態を検知し再移行(既存内容が退避済み版と異なるため $(basename "$slot") へ追加退避)"
    fi
  fi
  printf '%s\n' "$block" > "$dest"
  return 0
}

info() { printf '%s\n' "$1"; }

cmd_check() {
  local body current
  body="$(catalog_gen "$PAYLOAD_DIR")" || die "catalog-gen.sh の実行に失敗しました"
  current="$(awk -v b="$CATALOG_BEGIN_MARKER" -v e="$CATALOG_END_MARKER" '
    $0==b {f=1; next} $0==e {f=0} f' "$README" 2>/dev/null || true)"
  if [ "$current" = "$body" ]; then
    exit 0
  fi
  printf 'README.md の機能カタログ区間が生成物と乖離しています(要 scripts/catalog.sh --write)\n' >&2
  exit 1
}

cmd_write() {
  local body
  body="$(catalog_gen "$PAYLOAD_DIR")" || die "catalog-gen.sh の実行に失敗しました"
  write_managed_block "$README" "$CATALOG_LEGACY_MARKER" "$CATALOG_BEGIN_MARKER" "$CATALOG_END_MARKER" "$body"
  info "README.md の機能カタログ区間を再生成しました: $README"
}

case "${1:-}" in
  --write) cmd_write ;;
  --check) cmd_check ;;
  *) die "使い方: scripts/catalog.sh --write|--check" ;;
esac
