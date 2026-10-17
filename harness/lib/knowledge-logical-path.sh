#!/usr/bin/env bash
# knowledge-logical-path.sh — 配布物の論理パス(`yosage-dev-harness:<harness/ からの相対パス>`)の
#   判定・解決。ナレッジのエントリは導入先の `lib/<name>.sh` 等(`.claude` 配下)のパスではなく、この論理パスで
#   配布物のファイルを参照する(プラグイン形では導入先にそうしたディレクトリが存在しないため)。
#   `.` の直後が `/` を含まないトークン(`yosage-dev-harness:implementer` のようなエージェント名/
#   スキル名の名前空間つき参照)は論理パスではない(決定: 必ず `/` を含む。ルール `knowledge`)。
#
# 使い方(source して使う。他スクリプトから `bash -c` で単発呼び出しする用途は想定しない):
#   source ".../lib/knowledge-logical-path.sh"
#   ydh_lp_is_logical "<token>"        # 論理パスの形(接頭辞 + /区切りの相対パス)なら 0、でなければ 1
#   ydh_lp_resolve "<logical-path>"    # 使用中の版のプラグインの中の絶対パスを stdout に出す。
#                                       # 接頭辞違い/`..`を含む → 2、実在しない → 1、成功 → 0
set -uo pipefail

YDH_LP_PREFIX='yosage-dev-harness:'

ydh_lp_is_logical() {  # <token>
  local token="${1:-}"
  case "$token" in
    "$YDH_LP_PREFIX"*)
      local rest="${token#"$YDH_LP_PREFIX"}"
      case "$rest" in
        */*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

ydh_lp_resolve() {  # <logical-path>
  local token="${1:-}"
  case "$token" in
    "$YDH_LP_PREFIX"*) : ;;
    *) return 2 ;;
  esac
  local rel="${token#"$YDH_LP_PREFIX"}"
  case "$rel" in
    *..*) return 2 ;;
  esac
  # プラグインのルート: このスクリプト自身の位置(`$(dirname BASH_SOURCE)/..`)から自己解決する
  # (knowledge-audit.sh の plugin_root 解決と同じ考え方。呼び出し元の base-dir には依存しない)。
  local plugin_root
  plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local target="$plugin_root/$rel"
  [ -f "$target" ] || return 1
  printf '%s\n' "$target"
}
