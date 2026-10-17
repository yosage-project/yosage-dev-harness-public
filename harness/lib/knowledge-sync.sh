#!/usr/bin/env bash
# knowledge-sync.sh — グローバル知識ストア(設定した source の独立リポ)を プロジェクトの .claude/ へ同期する。
#
# 単一ソース: SessionStart フック(harness/hooks/knowledge-sync.sh)から呼ばれる。
# best-effort: 無効 / オフライン / 取得失敗 でも常に exit 0（セッションを止めない）。
# 設定は単一ファイル `<target>/.claude/yosage-dev-harness.local.json` の `knowledge.*`
# (既定は無効。設定用の環境変数は読まない。設定ファイルは利用者が変えた項目だけを持つ運用にするため)。
#
# クローンのキャッシュ置き場(KS_CACHE)は呼び出し元が引数で渡す(このライブラリ自身は環境変数を
# 読まない)。呼び出し元(SessionStart フック)は `${CLAUDE_PLUGIN_DATA}/knowledge` を渡す
# (プラグインごとの保存場所。アンインストールで消える)。
#
# 使い方:
#   knowledge-sync.sh <target> <cache-dir>            … 同期(cache-dir 省略/空なら skip)
#   knowledge-sync.sh --status <target> [<cache-dir>] … status 用に enabled/source/ref/cache最終取得/このミラー最終反映 を表示
#     (cache は複数 target 間で共有されうるため、cache 側の fetch 状態と target 側の反映状態は別物として区別する)
set -uo pipefail   # -e は付けない(best-effort で個別に握る)

ks_log() { printf 'knowledge-sync: %s\n' "$1" >&2; }

# atomic 入替(global ⇔ .global.old ⇔ tmp)専用の rename。シェルの `mv` コマンドは「宛先が既存
# ディレクトリなら置換ではなく入れ子移動」という利便のためのフォールバックを持ち、その場合でも
# exit 0 を返すため、呼ぶ前に宛先の非存在を確認しても、確認と実行の間の短い隙(TOCTOU)で
# 他プロセスが宛先を作ってしまえば静かに入れ子化しうる(並行 sync の実測で再現・確認済み)。
# rename(2) 自体にはその入れ子フォールバックが無く、宛先が非空ディレクトリなら失敗するだけ
# なので、python3 経由で rename(2) を直接呼び、真に「置換に成功したか失敗したか」の二値にする。
# python3 が無い環境では、宛先の非存在を確認してから mv を呼ぶ形にフォールバックする
# (確認と実行の間の隙は残るが、常に入れ子にしていた旧実装よりは狭い)。
ks_atomic_rename() {  # <src> <dst>
  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import os, sys
try:
    os.rename(sys.argv[1], sys.argv[2])
except OSError:
    sys.exit(1)
' "$1" "$2" 2>/dev/null
  else
    [ -e "$2" ] && return 1
    mv "$1" "$2" 2>/dev/null
  fi
}

# 同期の並行実行が「安全だが前進しない」ラウンドを生むことがあり、しかもそれが
# nohup(標準出力・標準エラー両方を捨てて背景実行)により利用者から完全に不可視だった。
# 前進性そのもの(排他/再試行)は討議で見送り、可視化のみを入れる: 各ラウンドの結果を
# target 側(`.claude/knowledge/.sync-log`)に記録し、後から(`--status` 経由で)確認できるようにする。
#
# 書き込みは O_APPEND の単純追記のみ(read-modify-write をしない)。一次レビュー実測: 固定名の
# 一時ファイル(旧実装の `$logf.next`)への read-modify-write は、並行呼び出し下で lost-update が
# 深刻に起きる(80並列の直接呼び出しで直近20件保持のはずが2行のみ・8並列の end-to-end でも
# 期待9行のところ2行のみ、という規模で記録そのものが失われた)。まさに並行実行時の無進捗を
# 見せるための機能が、並行実行下で最も壊れるという逆説的な結果になっていた。追記のみに
# すれば read → 書き換え → 置換、という区間そのものが無くなるため lost-update は原理的に
# 起きない(1回の write(2) が短い1行を書くだけであり、POSIX の追記モードでの短い write は
# 複数プロセスからの同時書き込みでも内容が混ざらないことが一般に期待される。同じ target への
# 並行実行を直接想定した設計として、`ks_tmp`(下記 mktemp によるプロセスごとに一意な一時名)と
# 同じ「固定名の共有可変状態を作らない」という教訓に合わせた)。
# トリムは書き込み時ではなく読み取り時(`knowledge_status` 側)で行う(直近何件を見るかは
# 表示側の関心であり、書き込み側に持たせると再び read-modify-write が要る)。
ks_record_outcome() {  # <dest> <outcome> <detail>
  local dest="$1" outcome="$2" detail="$3" ts
  mkdir -p "$dest/knowledge" 2>/dev/null || return 0
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
  printf '%s outcome=%s detail=%s\n' "$ts" "$outcome" "$detail" >> "$dest/knowledge/.sync-log" 2>/dev/null || true
}

# 設定は単一ファイル `<repo-root>/.claude/yosage-dev-harness.local.json` から harness/lib/config.sh
# 経由で読む(設定用の環境変数は読まない。設定ファイルは利用者が変えた項目だけを持つ運用にするため)。
_ks_lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
if [ -f "$_ks_lib" ]; then
  # shellcheck source=./config.sh
  . "$_ks_lib"
fi

# 設定を解決して enabled/source/ref をグローバルに入れる。<root> はリポジトリのルート
# (呼び出し元は `<root>/.claude` を dest として渡すため、ここでは dirname して復元する)。
# <cache-dir> は呼び出し元(hooks/knowledge-sync.sh)が引数で渡すクローンの置き場(環境変数は読まない)。
ks_resolve() {  # <dest> <cache-dir>
  local dest="$1"
  KS_ROOT="$(dirname "$dest")"
  KS_ENABLED="" KS_SOURCE="" KS_REF="" KS_CONFIG_BROKEN=0
  if command -v ydh_config_get >/dev/null 2>&1; then
    KS_ENABLED="$(ydh_config_get "$KS_ROOT" knowledge.enabled 2>/dev/null)"; [ "$?" = 4 ] && KS_CONFIG_BROKEN=1
    KS_SOURCE="$(ydh_config_get "$KS_ROOT" knowledge.source 2>/dev/null)"; [ "$?" = 4 ] && KS_CONFIG_BROKEN=1
    KS_REF="$(ydh_config_get "$KS_ROOT" knowledge.ref 2>/dev/null)"; [ "$?" = 4 ] && KS_CONFIG_BROKEN=1
  fi
  [ -n "$KS_REF" ] || KS_REF="main"
  KS_CACHE="${2:-}"
}

knowledge_sync() {  # <target> <cache-dir>
  local target dest cache_dir
  target="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  cache_dir="${2:-}"
  dest="$target/.claude"
  [ -d "$dest" ] || { ks_log "未インストール($dest なし) → skip"; return 0; }
  ks_resolve "$dest" "$cache_dir"

  if [ -z "$KS_CACHE" ]; then
    ks_log "cache-dir 未指定(CLAUDE_PLUGIN_DATA 未設定?) → skip"
    ks_record_outcome "$dest" "no-cache-dir" "呼び出し元がキャッシュの置き場を渡さなかった"
    return 0
  fi
  if [ "$KS_CONFIG_BROKEN" = 1 ]; then
    ks_log "設定ファイルが壊れている($KS_ROOT/.claude/yosage-dev-harness.local.json が壊れた JSON) → skip"
    ks_record_outcome "$dest" "config-broken" "設定ファイルが壊れた JSON"
    return 0
  fi
  if [ "$KS_ENABLED" != "true" ] || [ -z "$KS_SOURCE" ]; then
    ks_log "無効(opt-in 未設定) → skip。有効化は $KS_ROOT/.claude/yosage-dev-harness.local.json の knowledge.enabled/knowledge.source。"
    return 0
  fi
  command -v git >/dev/null 2>&1 || { ks_log "git が無い → skip"; return 0; }

  # このラウンドが進捗したかを後で判定するための基準点(直前にこのミラーが反映していた
  # store コミット)。clone/fetch より前(=このラウンドの試行が実際に始まる前)に固定する。
  local ks_prev_target_stamp
  ks_prev_target_stamp="$(cat "$dest/knowledge/.global-sync" 2>/dev/null || true)"

  # cache を最新化(破棄前提のキャッシュ。ローカル改変は捨てて ref に追従)
  if [ -d "$KS_CACHE/.git" ]; then
    if ! ( git -C "$KS_CACHE" fetch --depth 1 origin "$KS_REF" >/dev/null 2>&1 \
           && git -C "$KS_CACHE" reset --hard FETCH_HEAD >/dev/null 2>&1 ); then
      ks_log "fetch 失敗(オフライン?) → 既存 cache をそのまま使用"
    fi
  else
    [ -n "$KS_CACHE" ] && rm -rf "$KS_CACHE"   # .git なし残骸を除去(中断クローン等で再取得不能になるのを防ぐ)
    mkdir -p "$(dirname "$KS_CACHE")"
    if ! git clone --depth 1 --branch "$KS_REF" "$KS_SOURCE" "$KS_CACHE" >/dev/null 2>&1; then
      [ -n "$KS_CACHE" ] && rm -rf "$KS_CACHE"   # 中途半端な残骸を残さない
      ks_log "clone 失敗(オフライン/権限/URL?) → skip"
      ks_record_outcome "$dest" "clone-failed" "source 取得不能(オフライン/権限/URL?)"
      return 0
    fi
  fi

  # 蒸留層: review/criteria.md(あれば上書き)
  if [ -f "$KS_CACHE/review/criteria.md" ]; then
    mkdir -p "$dest/review"
    cp "$KS_CACHE/review/criteria.md" "$dest/review/criteria.md" 2>/dev/null || true
  fi
  # 反映する store コミットを一度だけ確定(cache 側「最終取得」と target 側「最終反映」を同一値で揃える)
  local sync_stamp
  sync_stamp="$(git -C "$KS_CACHE" log -1 --format='%H %cI' 2>/dev/null || true)"
  # 生層: knowledge/ → .claude/knowledge/global/(atomic 入替。
  # 旧実装は「先に rm -rf で wipe → cp -R で複製」の直列処理だったため、中断のタイミングによって
  # 「空」(wipe 直後)にも「一部だけ複製された」(cp -R 途中)にもなりえた。どちらも監査側からは
  # 「エントリが1件以上ある」と誤認され、未着のエントリを指す `[[...]]` 参照が偽の dangling-link
  # として検出される(「空」は先に対処済み。「一部」の対処が本変更)。
  # ここでは "global" という名前は常に「入替前の旧内容」か「入替後の新内容」のどちらかにしかならない
  # ようにする: 実体は同一ファイルシステム上の一時ディレクトリへ完成させてから、rename(mv) で
  # 一気に差し替える。同一ファイルシステム上の rename は単一のディレクトリエントリ更新であり、
  # 「複製の途中」という中間状態を経由しない。中断できるのは (1) tmp の構築中(まだ "global" という
  # 名前には一切影響しない) と (2) 2回の mv の間(ごく短時間、"global" が不在になるだけ＝既存の
  # 「不在/空」判定と同じ安全な扱い) の2箇所だけになる。
  # 2回の入替はいずれも ks_atomic_rename(上記)で行う。真の rename(2) は宛先が非空ディレクトリ
  # なら黙って入れ子にせず失敗するため、成否だけで正しく分岐できる。また .global.old は、直前の
  # 実行が中断して残った正当なミラーでありうるため、無条件には消さない(次回の実行の先頭で
  # 復元を試みてから掃除する)。
  if [ -d "$KS_CACHE/knowledge" ]; then
    mkdir -p "$dest/knowledge"
    local ks_old="$dest/knowledge/.global.old"
    # このラウンドで実際に retire/swap を試みて失敗したか(下記の進捗判定で使う)。
    # 一次レビュー実測: target が既にラウンド開始時点で sync_stamp に追いついていた(定常状態)場合、
    # このラウンドで実際に swap を試みて競合により失敗しても、.global-sync の値自体は変化しない
    # (試行前後どちらも sync_stamp のまま)ため、下記の「前後の値を比較するだけ」の判定では
    # 「何もしなかった」場合と区別できず、outcome=up-to-date と誤記録される(実際にはこのラウンドで
    # 「global ミラーの退避に失敗...」というログが出ているにも関わらず)。値の比較に加えて、この
    # ラウンドで失敗が実際に起きたかどうかを独立にここで記録し、下記の判定で優先させる。
    local ks_swap_failed=0
    # 前回の中断からの回復: 直前の実行が「旧内容の退避(1回目の入替)は完了したが、新内容への
    # 入替(2回目)は完了しなかった」場合、global は不在のまま .global.old に最後の正当な
    # ミラーが残る。今回 cp -R 自体が失敗した場合に「既存ミラーを維持」を成立させるには、この
    # 復元を新しい試行の前に済ませておく必要がある(そうしないと、正当な旧ミラーを無条件の
    # 掃除で失ったまま複製にも失敗し、「維持」と称して実際には何も残らない状態になる)。
    # 復元に失敗したら .global.old は消さずに次回へ持ち越す(下の掃除は global が実在する
    # 場合に限る)。
    if [ ! -e "$dest/knowledge/global" ] && [ -e "$ks_old" ]; then
      if ks_atomic_rename "$ks_old" "$dest/knowledge/global"; then
        ks_log "前回の入替が中断していたため旧内容を復元"
      else
        ks_log "前回の退避(.global.old)の復元に失敗 → 次回の同期で再試行"
      fi
    fi
    # tmp は固定名にしない: 同一 target への並行実行(SessionStart フックは複数セッションで
    # 同時に起動しうる)では、固定名だと複数プロセスが同じパスへ同時に cp -R / rm -rf することに
    # なり、cp -R も mv と同じく「宛先が既存ディレクトリだと置換ではなく入れ子移動」になるため、
    # 一方の複製がもう一方の tmp の中へ入れ子で混入しうる(実測で再現・確認済み)。プロセスごとに
    # 一意な名前(mktemp)を使えば、複製の段階では他プロセスと衝突しようがない。
    rm -rf "$dest"/knowledge/.global.tmp.* 2>/dev/null   # 前回中断で残った旧 tmp の掃除(グロブ)
    local ks_tmp
    ks_tmp="$(mktemp -d "$dest/knowledge/.global.tmp.XXXXXX" 2>/dev/null)" || ks_tmp=""
    # old は「global が実在する(＝復元済み、または元から正当)」場合に限って掃除する。global が
    # 依然として不在(＝復元にも失敗した)なら、old を消すと直前まで在った正当なミラーが完全に
    # 失われるため、次回の復元の芽を残す。
    [ -e "$dest/knowledge/global" ] && rm -rf "$ks_old"
    if [ -z "$ks_tmp" ]; then
      ks_log "一時ディレクトリの作成に失敗 → 既存ミラーを維持"
      ks_swap_failed=1
    elif cp -R "$KS_CACHE/knowledge/." "$ks_tmp/" 2>/dev/null; then
      # global INDEX は手編集せず frontmatter から生成（ストア側は INDEX を持たなくてよい＝衝突源が無い）。
      # swap 前(tmp に対して)行う: swap 後に生成すると「global は入れ替わったが INDEX だけ古い/欠ける」
      # という新たな中間状態を作ってしまう。
      _ki="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/knowledge-index.sh"
      [ -f "$_ki" ] && bash "$_ki" "$ks_tmp" >/dev/null 2>&1 || true
      local ks_swap_ready=1
      if [ -e "$dest/knowledge/global" ]; then
        if ! ks_atomic_rename "$dest/knowledge/global" "$ks_old"; then
          ks_swap_ready=0
          ks_log "global ミラーの退避に失敗(既に使用中/並行実行等) → 旧内容を維持"
        fi
      fi
      if [ "$ks_swap_ready" = 1 ]; then
        if ks_atomic_rename "$ks_tmp" "$dest/knowledge/global"; then
          rm -rf "$ks_old"
          # target 側マーカー: このミラーが反映した store コミットを記録(target ごと=このミラー自体の
          # 鮮度。global/ は上の swap で丸ごと置き換わる対象なので、その外(knowledge/直下)に置く)
          [ -n "$sync_stamp" ] && printf '%s\n' "$sync_stamp" > "$dest/knowledge/.global-sync" 2>/dev/null || true
        else
          ks_swap_ready=0
          ks_log "global ミラーの入替に失敗(想定外に global が復活等) → 現在の内容を維持"
        fi
      fi
      # 退避はできたが入替に進めなかった場合(上のどちらかで ks_swap_ready=0 になった場合)は、
      # global が不在のまま old だけが残っていないかを確認し、あれば戻す(global を不在のまま
      # 放置しない。想定外に global が復活していた場合は old 側を戻す必要が無いので何もしない)。
      if [ "$ks_swap_ready" = 0 ] && [ ! -e "$dest/knowledge/global" ] && [ -e "$ks_old" ]; then
        ks_atomic_rename "$ks_old" "$dest/knowledge/global" || true
      fi
      [ "$ks_swap_ready" = 0 ] && ks_swap_failed=1
      rm -rf "$ks_tmp"
    else
      rm -rf "$ks_tmp"
      ks_log "cache → tmp のコピーに失敗 → 既存ミラーを維持"
      ks_swap_failed=1
    fi
  fi
  # 最終取得(cache 側の fetch 状態。target 横断で共有される cache のため target ツリーとは別物)
  [ -n "$sync_stamp" ] && printf '%s\n' "$sync_stamp" > "$KS_CACHE/.last-sync" 2>/dev/null || true

  # このラウンドの進捗を判定して記録する(可視化のみ・前進性そのものは変えない)。
  # 判定は理由を問わず一様に行う(退避の競合・コピー失敗・一時ディレクトリ作成失敗のいずれでも、
  # 「試みたが今回は反映されなかった」ことだけを見る)。
  # $KS_CACHE/knowledge が無い(store 側に生層が無い)場合は target マーカーがそもそも書かれる
  # 経路が無いため、恒久的に no-progress と誤判定しないよう判定自体を行わない。
  #
  # まず ks_swap_failed(このラウンドで実際に retire/swap を試みて失敗したか)を見る。これは
  # このラウンドの成否そのものを表す独立したフラグであり、成功時は必ず .global-sync が
  # sync_stamp へ書き換わる(上のブロックの構造上、ks_swap_failed=0 のまま抜けられるのは
  # 「.global-sync への書き込みまで到達した」場合に限られるため)。したがって
  # 「今回 sync_stamp に到達したか」を .global-sync の値を読み直して再確認する必要は無く、
  # このフラグ1つで「今回追いついたか」を判定できる。
  #
  # 一次レビュー実測: 旧実装は .global-sync の前後比較だけで判定しており、target がラウンド
  # 開始時点で既に sync_stamp に追いついていた(定常状態)場合、「何もしなかった」場合と
  # 「試みて失敗した」場合を比較だけでは区別できず、後者を outcome=up-to-date と誤記録して
  # いた(実際には「global ミラーの退避に失敗...」というログが出ている)。ks_swap_failed は
  # この区別を独立に持つため、この誤分類が起きない。
  if [ -d "$KS_CACHE/knowledge" ] && [ -n "$sync_stamp" ]; then
    if [ "$ks_swap_failed" = 1 ]; then
      ks_record_outcome "$dest" "no-progress" "他プロセスとの競合/コピー失敗等で今回は反映されず"
    elif [ "$ks_prev_target_stamp" = "$sync_stamp" ]; then
      ks_record_outcome "$dest" "up-to-date" "変更なし"
    else
      ks_record_outcome "$dest" "progressed" "反映完了"
    fi
  fi

  ks_log "同期完了: $KS_SOURCE ($KS_REF)"
  return 0
}

knowledge_status() {  # <target> <cache-dir>
  local target dest cache_last target_last
  target="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
  dest="$target/.claude"
  ks_resolve "$dest" "${2:-}"
  if [ "$KS_ENABLED" = "true" ] && [ -n "$KS_SOURCE" ]; then
    printf 'knowledge   : 有効 source=%s ref=%s\n' "$KS_SOURCE" "$KS_REF"
    # cache 側(fetch 状態。他 target と共有されうる)と target 側(このミラーへの反映状態)を区別して表示する。
    # 複数 repo が同じ cache を共有する運用では、他 repo の sync でこの cache だけ先に進むことがあるため、
    # 「cache が最新」≠「このミラーが最新」。target 側マーカーが無い/古ければそれを可視化する。
    cache_last="$(cat "$KS_CACHE/.last-sync" 2>/dev/null || true)"
    target_last="$(cat "$dest/knowledge/.global-sync" 2>/dev/null || true)"
    [ -n "$cache_last" ] && printf '              cache 最終取得   : %s\n' "$cache_last" \
      || printf '              cache 最終取得   : (未取得)\n'
    [ -n "$target_last" ] && printf '              このミラー最終反映: %s\n' "$target_last" \
      || printf '              このミラー最終反映: (未反映)\n'
    if [ -n "$cache_last" ] && [ -n "$target_last" ] && [ "$cache_last" != "$target_last" ]; then
      printf '              ⚠ このミラーは cache の最新取得より古い可能性があります(他 target の sync で cache だけ進んだ等) → 再度 sync してください\n'
    fi
    # 直近の同期試行が前進したかを表示する(並行実行で「安全だが前進しない」ラウンドが
    # 起きても、SessionStart フックは出力を捨てて背景実行するため、これまで確認する手段が
    # 無かった。無進捗は自己修復しうるが、追いついたかどうかはここで確認できる)。
    # .sync-log は書き込み時に一切トリムしない(単純追記。ks_record_outcome のコメント参照)ため、
    # 「直近20件」への絞り込みは読み取り側であるここで行う(tail -n 20)。
    local sync_log last_line streak line
    sync_log="$dest/knowledge/.sync-log"
    if [ -f "$sync_log" ]; then
      last_line="$(tail -n1 "$sync_log" 2>/dev/null || true)"
      [ -n "$last_line" ] && printf '              直近の同期試行   : %s\n' "$last_line"
      streak=0
      while IFS= read -r line; do
        case "$line" in
          *'outcome=progressed '*|*'outcome=up-to-date '*) streak=0 ;;
          *'outcome=no-progress '*|*'outcome=clone-failed '*) streak=$((streak+1)) ;;
        esac
      done < <(tail -n 20 "$sync_log" 2>/dev/null)
      if [ "$streak" -ge 1 ] 2>/dev/null; then
        printf '              ⚠ 直近 %s 回連続で同期が前進していません(安全ですが停滞中。自己修復を待つか再度 sync してください)\n' "$streak"
      fi
    fi
  else
    printf 'knowledge   : 無効(opt-in 未設定。%s の knowledge.enabled/knowledge.source で有効化)\n' "$(dirname "$dest")/.claude/yosage-dev-harness.local.json"
  fi
}

# 直接実行(hook から)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  if [ "${1:-}" = "--status" ]; then knowledge_status "${2:-}" "${3:-}"; else knowledge_sync "${1:-}" "${2:-}"; fi
fi
