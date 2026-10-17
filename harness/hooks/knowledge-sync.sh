#!/usr/bin/env bash
# SessionStart フック: グローバル知識ストアを best-effort で取得・反映する。
# セッション開始を遅らせないよう既定では **非ブロッキング**(バックグラウンド)で lib を回して
# 即 exit 0 を返す。`--foreground` を渡すと、lib の完了を待ってから exit する(前景実行)。
# 手動でキャッシュ状態を確認・再同期したい場合や、結果を待ってから次の処理へ進みたい場合に使う
# (例: このスクリプト自身のテスト。test/suites/35-knowledge.sh は `.sync-log` 等の同期結果を
# 直後に検証するため、非同期のポーリング待ちを避けてこのオプションで呼ぶ)。
# opt-in/オフライン/失敗の判定は lib 側(無効なら何もしない)。
#
# 同期ライブラリは自分自身の位置から見つける(target のインストール済みディレクトリ配下の
# lib を読みに行かない — プラグイン内の hooks/knowledge-sync.sh から見て `../lib/knowledge-sync.sh`
# がプラグイン内の lib/knowledge-sync.sh に一致する、という相対関係だけに依存する)。
target="${CLAUDE_PROJECT_DIR:-$PWD}"
lib="$(dirname "${BASH_SOURCE[0]}")/../lib/knowledge-sync.sh"
# クローンのキャッシュはプラグインごとの保存場所(${CLAUDE_PLUGIN_DATA})に置く(アンインストールで
# 消える。旧版(XDG キャッシュ)と置き場を共有しない)。lib 自身は環境変数を読まないので、ここで
# 引数として渡す。CLAUDE_PLUGIN_DATA が空(未対応の実行環境)なら lib 側が skip する(no-cache-dir)。
cache_dir=""
[ -n "${CLAUDE_PLUGIN_DATA:-}" ] && cache_dir="$CLAUDE_PLUGIN_DATA/knowledge"
if [ ! -f "$lib" ]; then
  exit 0
fi
cmd=(bash "$lib" "$target" "$cache_dir")
if [ "${1:-}" = "--foreground" ]; then
  "${cmd[@]}" >/dev/null 2>&1
else
  nohup "${cmd[@]}" >/dev/null 2>&1 &
fi
exit 0
