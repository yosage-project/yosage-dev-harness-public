#!/usr/bin/env bash
# scratch.sh — 使い捨てコンテナで一時コマンドを実行する(ホストを汚さない)。
#   ローカル(Windows/Mac)に uv/python/node 等が無くてもよい。**Docker を基本ランタイム**にする方針。
#   --rm で実行後に破棄、カレントを /work に rw マウント、ホストには何も残さない。
#
#   使い方:
#     yosage-dev-harness-scratch [--image IMG] [--net none|bridge] -- <command...>
#   例:
#     scratch.sh --image python:3.12-slim -- sh -lc "pip install -q pandas && python analyze.py"
#     scratch.sh --image node:24-alpine   -- npx prettier --check .
#   既定: image=python:3.12-slim, network=docker既定(--net none で遮断可)。
set -euo pipefail

img="python:3.12-slim"; net=""
while [ $# -gt 0 ]; do
  case "$1" in
    --image) img="${2:?--image にイメージ名}"; shift 2 ;;
    --net)   net="${2:?--net に none|bridge}"; shift 2 ;;
    --)      shift; break ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "usage: scratch.sh [--image IMG] [--net none|bridge] -- <command...>" >&2; exit 2 ;;
  esac
done

[ $# -gt 0 ] || { echo "実行コマンドがありません(-- の後に指定してください)" >&2; exit 2; }
command -v docker >/dev/null 2>&1 || {
  echo "docker が見つかりません。ローカルにツールを入れず使い捨てコンテナで実行する方針です。Docker を用意してください。" >&2
  exit 1
}

netarg=""; [ -n "$net" ] && netarg="--network $net"
# shellcheck disable=SC2086
exec docker run --rm -v "$PWD":/work -w /work $netarg "$img" "$@"
