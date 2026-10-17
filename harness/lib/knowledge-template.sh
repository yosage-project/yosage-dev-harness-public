#!/usr/bin/env bash
# knowledge-template.sh — knowledge エントリの雛形(harness/knowledge/_entry-template.md)の中身を
#   標準出力に出す。導入先に雛形ファイルを置かない(プラグイン形では `.claude/knowledge/` は
#   consumer 所有の生層だけを持ち、雛形はプラグインの中から取り出す)。
#
# 使い方: yosage-dev-harness-knowledge-template
set -uo pipefail

kt_log() { printf 'knowledge-template: %s\n' "$1" >&2; }

knowledge_template() {
  local plugin_root
  plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local tmpl="$plugin_root/knowledge/_entry-template.md"
  [ -f "$tmpl" ] || { kt_log "雛形が見つからない: $tmpl"; return 1; }
  cat "$tmpl"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then knowledge_template "$@"; fi
