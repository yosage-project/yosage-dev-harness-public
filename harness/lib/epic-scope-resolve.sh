#!/usr/bin/env bash
# epic-scope-resolve.sh — epic-implement / epic-create-docs / epic-create-issues が参照する
# Epic 計画ドキュメント(`.epic_docs/`)の置き場所を解決する共有ロジック。
#
# 背景: 複数リポジトリが同居するワークスペースでは、計画ドキュメント(`.epic_docs/`)を実装先
# リポジトリの外(ワークスペース側リポジトリ)に置く運用がある。`.epic_docs/` を cwd 相対で
# 固定すると、実装先とワークスペースが別リポジトリの構成でフェーズ定義を見失い、依存ウェーブへ
# 黙ってフォールバックしてしまう(スコープの絞りが黙って外れる)。
#
# 解決順: 現在地(cwd)から `git rev-parse --show-toplevel` で自分のリポジトリ最上位を取り、
# そこから上へ辿って見つかる最も外側の git リポジトリ(自分自身を候補に含める。上に他の
# リポジトリが無ければ自分自身が最も外側)の直下にある `.epic_docs/` を見る。
# 探索ロジック自体はハーネスの `lib/git-outermost-root.sh` の `git_outermost_root()` を source して
# 使う(`yosage-dev-harness-gh-review` の自組織識別子導出も同じ関数を使う共有実装)。単一リポジトリの
# 導入先では「自分自身が最も外側」になるため、従来の cwd 直下 `.epic_docs/` と同じ場所になる(後方互換)。
#
# 使い方:
#   yosage-dev-harness-epic-scope-resolve outermost-root
#     … 最も外側の git リポジトリの絶対パスを表示する。git リポジトリの外なら非ゼロ終了。
#   yosage-dev-harness-epic-scope-resolve locate-docs <epic-name>
#     … 最も外側のリポジトリ直下の `.epic_docs/<epic-name>` の絶対パスを表示する。
#       作業ツリーに無いときは、自分のリポジトリの `refs/remotes/origin/epic/<epic-name>`、
#       続いて `refs/heads/epic/<epic-name>` の中を探し、あれば `<ref>:.epic_docs/<epic-name>` を
#       表示して終了コード4で終わる(`git show <その値>/<ファイル>` で読める。中身を作業ツリーへ
#       展開しない)。どこにも無ければ非ゼロ終了+理由を stderr へ(「そもそも計画が無い」可能性)。
#   yosage-dev-harness-epic-scope-resolve locate-phase <epic-name> <phaseN>
#     … 上に加えて `<epic_docs_dir>/<phaseN>` の絶対パスを表示する。
#       `.epic_docs/<epic-name>` 自体は見つかるが phaseN サブディレクトリが無い場合は、
#       locate-docs の失敗(そもそも計画が無い)とは別の理由(計画はあるがこのフェーズが
#       見つからない)を stderr へ出し、両者を区別できるようにする。計画がブランチの上にあるときは、
#       フェーズがあれば `<ref>:.epic_docs/<epic-name>/<phaseN>` を表示して終了コード4、無ければ3。
#   yosage-dev-harness-epic-scope-resolve list-phases <epic-name>
#     … `<epic_docs_dir>/` 直下に存在する `phase<N>` サブディレクトリ名を番号の昇順で
#       1行1件、標準出力へ列挙する(`phase1` 始まりとは限らない前提。`phase0` から始まる
#       計画・番号が飛ぶ計画のどちらでも、実在するディレクトリだけを昇順で返す)。
#       フェーズ分割していない Epic(`phase*` ディレクトリが1つも無い)は異常ではないため、
#       計画ドキュメント自体は見つかった場合は終了コード0・出力は空という形で区別する
#       (「そもそも計画が無い」= locate-docs 失敗とは別。呼び出し側は空出力を「フェーズ無し
#       →依存ウェーブ完走へフォールバック」として扱ってよい)。計画がブランチの上にあるときも
#       同じ列挙(ref の中のサブディレクトリだけ)を返し、終了コードだけ0の代わりに4にする
#       (0件でも4。「ブランチの上で見つけた」という意味を保つ)。
#
# 終了コード:
#   0 … 発見(list-phases は0件でも発見=計画ドキュメントはある、という意味で0を返す)。
#   1 … 対象そのものが無い(「そもそも計画が無い」= locate-docs で `.epic_docs/<epic-name>` が
#       見つからない)。
#   2 … 引数不足・git リポジトリの外など、解決を試みる前提が欠けている。
#   3 … 計画ディレクトリ自体は見つかったが、指定フェーズのサブディレクトリが無い
#       (「あるのに見つけられない」= locate-phase 固有)。
#   4 … 作業ツリーには無いが、Epic ブランチの上にある(stdout は `<ref>:<path>`。読む側は
#       `git show` / `git ls-tree` を使う)。
set -uo pipefail

# 最も外側の git リポジトリを探す共有ロジック(git_outermost_root)を source する。
# shellcheck source=./git-outermost-root.sh
source "$(dirname "${BASH_SOURCE[0]}")/git-outermost-root.sh"

esr_log() { printf 'epic-scope-resolve: %s\n' "$1" >&2; }

esr_locate_docs() {  # <epic-name>
  local epic="${1:-}" root dir
  if [ -z "$epic" ]; then
    esr_log "epic-name を指定してください"
    return 2
  fi
  root="$(git_outermost_root)" || { esr_log "git リポジトリの外です(cwd を確認してください)"; return 2; }
  dir="$root/.epic_docs/$epic"
  if [ -d "$dir" ]; then
    printf '%s\n' "$dir"
    return 0
  fi
  # 作業ツリーに無ければ、自分のリポジトリ(cwd の toplevel)の Epic ブランチの中を探す。
  # 単一リポジトリの導入先では計画の正本は Epic ブランチにあり、メインは既定ブランチにいることが多い。
  local ref
  for ref in "refs/remotes/origin/epic/${epic}" "refs/heads/epic/${epic}"; do
    # ディレクトリ(tree)のときだけ採る(作業ツリー側の `[ -d ]` と同じ。ファイル(blob)は計画ではない)。
    if [ "$(git cat-file -t "${ref}:.epic_docs/${epic}" 2>/dev/null)" = "tree" ]; then
      printf '%s:.epic_docs/%s\n' "$ref" "$epic"
      esr_log "計画ドキュメントは作業ツリーに無く、ブランチ ${ref} の上にあります。\`git show ${ref}:.epic_docs/${epic}/<ファイル>\` で読んでください。"
      return 4
    fi
  done
  esr_log "計画ドキュメント(.epic_docs/${epic}/)が見つかりません(最も外側のリポジトリ ${root} の作業ツリーと、Epic ブランチ(origin/epic/${epic}・epic/${epic})を探索済み)。そもそも計画ドキュメントが存在しない可能性があります(Epic ブランチが最新でなければ git fetch origin してから再実行してください)。"
  return 1
}

# ref の中の計画ディレクトリ直下にあるサブディレクトリ名を1行1件で返す。
# $1 = `<ref>:.epic_docs/<epic>` (esr_locate_docs が exit 4 で出す値)
esr_ref_subdirs() {
  git ls-tree "${1}/" 2>/dev/null | awk -F'\t' '{ split($1, m, " "); if (m[2] == "tree") print $2 }'
}

esr_locate_phase() {  # <epic-name> <phaseN>
  local epic="${1:-}" phase="${2:-}" dir rc phase_dir
  if [ -z "$epic" ] || [ -z "$phase" ]; then
    esr_log "epic-name と phaseN を指定してください"
    return 2
  fi
  dir="$(esr_locate_docs "$epic" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 4 ]; then
    if esr_ref_subdirs "$dir" | grep -qxF -- "$phase"; then
      printf '%s/%s\n' "$dir" "$phase"
      esr_log "フェーズ(${phase})はブランチの上にあります。\`git show ${dir}/${phase}/<ファイル>\` で読んでください。"
      return 4
    fi
    esr_log "計画ドキュメント自体は ${dir} (ブランチの上)に見つかりましたが、フェーズ(${phase})のサブディレクトリが見つかりません。計画が無いのではなく、あるのに見つけられていない状態です(フェーズ名の誤り・未作成の可能性)。"
    return 3
  fi
  if [ "$rc" -ne 0 ]; then
    esr_locate_docs "$epic" >/dev/null   # 失敗理由を stderr へ出す
    return "$rc"
  fi

  phase_dir="$dir/$phase"
  if [ -d "$phase_dir" ]; then
    printf '%s\n' "$phase_dir"
    return 0
  fi
  esr_log "計画ドキュメント自体は ${dir} に見つかりましたが、フェーズ(${phase})のサブディレクトリが見つかりません。計画が無いのではなく、あるのに見つけられていない状態です(フェーズ名の誤り・未作成の可能性)。"
  return 3
}

esr_list_phases() {  # <epic-name>
  local epic="${1:-}" dir rc d name num pairs
  if [ -z "$epic" ]; then
    esr_log "epic-name を指定してください"
    return 2
  fi
  dir="$(esr_locate_docs "$epic" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 4 ]; then
    # ブランチの上: ref の中のサブディレクトリから同じ規則(phase<数字>のみ・数値昇順)で列挙する。
    pairs=""
    for name in $(esr_ref_subdirs "$dir"); do
      num="${name#phase}"
      case "$name" in phase*) ;; *) continue ;; esac
      case "$num" in
        ''|*[!0-9]*) continue ;;
      esac
      pairs="${pairs}${num} ${name}
"
    done
    [ -z "$pairs" ] || printf '%s' "$pairs" | sort -n -k1,1 | awk '{print $2}'
    return 4
  fi
  if [ "$rc" -ne 0 ]; then
    esr_locate_docs "$epic" >/dev/null   # 失敗理由を stderr へ出す
    return "$rc"
  fi

  # `phase*` サブディレクトリを走査し、「phase」に続く部分が純粋な数字のものだけを対象にする
  # (phase1 始まりとは限らない・番号が飛んでいてもよい前提。phaseX のような非数値サフィックスは
  # 対象外とし、誤って別名のディレクトリを拾わない)。pairs は "<数値> <ディレクトリ名>" を
  # 改行区切りで積んだ文字列(sort -n で数値昇順に並べ替えるための一時形式)。
  pairs=""
  for d in "$dir"/phase*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    num="${name#phase}"
    case "$num" in
      ''|*[!0-9]*) continue ;;
    esac
    pairs="${pairs}${num} ${name}
"
  done
  if [ -z "$pairs" ]; then
    return 0
  fi
  printf '%s' "$pairs" | sort -n -k1,1 | awk '{print $2}'
}

epic_scope_resolve() {  # <mode> <args...>
  local mode="${1:-}"
  shift || true
  case "$mode" in
    outermost-root) git_outermost_root ;;
    locate-docs)    esr_locate_docs "${1:-}" ;;
    locate-phase)   esr_locate_phase "${1:-}" "${2:-}" ;;
    list-phases)    esr_list_phases "${1:-}" ;;
    *)
      esr_log "不明な mode: ${mode:-(空)}(outermost-root / locate-docs / locate-phase / list-phases を指定)"
      return 1
      ;;
  esac
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then epic_scope_resolve "$@"; fi
