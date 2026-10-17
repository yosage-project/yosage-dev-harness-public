echo "== 公開面: identity 指紋(裸 #N・word#N)が無い(regression ラチェット) =="
# knowledge.md の「書き方不変: travel 面の自己完結」(番号・repo名・org identity を load-bearing にしない)を
# 機械的に強制する指紋ブロック。ファイル内容スキャンなので、コマンド文字列 scan 専用の guard.sh でなく
# 既存の横断ルール指紋ブロック(上の fp_fail ループ)と同型で実装する。ストア側 entry のガードは別 repo(対象外)。
#
# スキャン対象は公開面全体(harness/ 配下の配布ロジックに加え、bin/・test/・README.md・リポジトリ直下の
# マーケットプレイス定義 `.claude-plugin/` も含む。`harness/.claude-plugin` は $H 配下なので既存の
# 対象に既に含まれている)。
# harness/knowledge/ は _entry-template.md 等の template のみを配布し実 entry は配布しないため、
# ここに混入すれば即 template 自体が識別子を焼いていることになる(誤検知源ではなく本来の検知対象)。
id_scan_paths="$H $ROOT/scripts $ROOT/test $ROOT/README.md $ROOT/.claude-plugin"
# 走査本体は関数に切り出す(引数=走査対象のパス一覧)。結果は行ごとに標準出力へ返す:
# 「NG:<メッセージ>」の行が1つでもあれば失敗、無ければ空。スイート内の回帰テスト(下の
# 「identity 指紋スキャン: 走査関数の回帰テスト」節)が、この関数に fixture を渡して判定を確かめる。
_id_patterns='(^|[^0-9A-Za-z_])#[0-9]+([^0-9A-Za-z_]|$)
[A-Za-z0-9_.-]+#[0-9]+'
_id_scan() {  # <パス>...
  local _p _pat _hits _h _rc _exist=()
  # 走査の前に対象の各パスが存在することを確かめる。存在しない対象は grep の「該当なし」と
  # 区別がつかず黙って緑になるため、ここで失敗にする。
  for _p in "$@"; do
    if [ -e "$_p" ]; then _exist+=("$_p"); else echo "NG:identity 指紋の走査対象が存在しません: $_p"; fi
  done
  while IFS= read -r _pat; do
    [ -n "$_pat" ] || continue
    _hits=""
    for _p in ${_exist[@]+"${_exist[@]}"}; do
      # grep の終了コード 1(該当なし)だけを吸収する。2 以上(読み取りの失敗)は、失敗したパスを添えて失敗にする。
      _h="$(grep -rlE "$_pat" "$_p" 2>/dev/null)" && _rc=0 || _rc=$?
      if [ "$_rc" -gt 1 ]; then echo "NG:identity 指紋の走査が読み取りに失敗しました(終了コード $_rc): $_p"; fi
      [ -z "$_h" ] || _hits="$_hits$_h"$'\n'
    done
    if [ -n "$_hits" ]; then echo "NG:identity 指紋が公開面に混入: [$_pat] → $(printf '%s' "$_hits" | tr '\n' ' ')"; fi
  done <<< "$_id_patterns"
}
_id_scan_out="$(_id_scan $id_scan_paths)"
if [ -n "$_id_scan_out" ]; then
  while IFS= read -r _l; do ng "${_l#NG:}"; done <<< "$_id_scan_out"
  id_fp_fail=1
else
  ok "identity 指紋の走査対象はすべて存在し、読み取りに成功した"
fi
# 誤検知させない(FP 回避、設計時に実測済み): shebang(#!)・数字を伴わない色コード(#fff)・見出しアンカー
# (#section-name)・`#<issue>` プレースホルダは digit が # の直後に無い/`<...>` 内なので自然に非該当。
# 数字のみの hex 色コード(等)は本パターンでも該当しうるが、本 payload は CSS を含まず現状ヒットしない
# (narrowing-guard-pattern-can-open-bypass の教訓どおり、絞り込みで FN=バイパスを開かないことを優先し、
# あえて除外条件を足さない)。
# FN は既知の対象外として明示(前提が崩れ次第で再検討): 空白を挟む `# 123` 形・全角 `＃１２３` は GitHub が
# 自動リンクしない(=実際の identity 漏洩として機能しない)ため、本チェックの「裸 #N ＋ word#N 形式」の
# 対象外(段階導入)としてあえて非検知のまま。
#
# 2本目のパターン([A-Za-z0-9_.-]+#[0-9]+)は owner/repo#N 形式・repo 名単体#N 形式・PR#N 形式のいずれも
# 拾う(「あなたの repo に置き換えてください」という例示文へ具体名のまま埋め込む誤りを含め、word 直後に
# #N が続く shape 全般が対象)。
[ "${id_fp_fail:-0}" = "0" ] && ok "公開面に裸 #N・word#N の identity 指紋は無し"

echo "== identity 指紋スキャン: 走査関数の回帰テスト(存在しないパス・読めないファイル・正常・混入) =="
# 存在確認と grep 終了コード 2 以上の失敗が、将来 `2>/dev/null || true` の形へ黙って戻らないことを常設で守る。
_idr_dir="$(mktemp -d)"
printf 'clean file\n' > "$_idr_dir/clean.md"
_idr_out="$(_id_scan "$_idr_dir")"
out_is_empty "走査関数: 存在し読めて混入の無いパスだけなら出力は空(正常)" "$_idr_out"
_idr_out="$(_id_scan "$_idr_dir" "$_idr_dir/no-such-path")"
out_has "走査関数: 存在しないパスを渡すと NG が出る" "NG:identity 指紋の走査対象が存在しません: $_idr_dir/no-such-path" "$_idr_out"
mkdir "$_idr_dir/unreadable"
printf 'secret\n' > "$_idr_dir/unreadable/f.md"
chmod 000 "$_idr_dir/unreadable/f.md"
if [ -r "$_idr_dir/unreadable/f.md" ]; then
  # root 等で chmod 000 でも読めてしまう環境では、読み取り失敗を作れない。
  # 合格に数えない(件数に出さない)。省略をログにだけ残す。
  echo "  - 省略: 走査関数の読み取り失敗の検査(権限を無視できる実行者のため chmod 000 の fixture が読めてしまう)"
else
  _idr_out="$(_id_scan "$_idr_dir/unreadable")"
  out_has "走査関数: 読めないファイルがあると NG が出て、失敗したパスがメッセージに含まれる" "NG:identity 指紋の走査が読み取りに失敗しました(終了コード 2): $_idr_dir/unreadable" "$_idr_out"
fi
chmod 600 "$_idr_dir/unreadable/f.md"
printf 'see %s42 here\n' "$HSH" > "$_idr_dir/hit.md"
_idr_out="$(_id_scan "$_idr_dir/hit.md")"
out_has "走査関数: 裸の番号が混入していると NG が出る" "NG:identity 指紋が公開面に混入" "$_idr_out"
rm -rf "$_idr_dir"

echo "== identity 指紋スキャン: negative control(仕込んだ違反で実際に赤になること) =="
# スキャン自体が空振りしていないか(パターン・スキャン対象のどちらかが崩れて常に0件のまま
# 緑になっていないか)を、意図的に違反を仕込んで確認する。仕込む値もソース上に裸 #N を
# 残さないため実行時に組み立てる(このテストファイル自身も上のスキャン対象に含まれるため)。
idfp_probe() {
  # $1=対象ディレクトリ $2=検査するパターン(1本のみ)
  grep -rlE "$2" "$1" 2>/dev/null
}
_idfp_nc_dir="$(mktemp -d)"
# ケースA: 裸の #N。
printf 'plain issue %s42 reference\n' "$HSH" > "$_idfp_nc_dir/bare.md"
if [ -n "$(idfp_probe "$_idfp_nc_dir" '(^|[^0-9A-Za-z_])#[0-9]+([^0-9A-Za-z_]|$)')" ]; then
  ok "negative control: 仕込んだ裸 #N は1本目のパターンで検知される"
else
  ng "negative control: 仕込んだ裸 #N は1本目のパターンで検知される"
fi
rm -f "$_idfp_nc_dir"/*.md
# ケースB: owner/repo#N 形式。
printf 'see acme/target%s42\n' "$HSH" > "$_idfp_nc_dir/scoped.md"
if [ -n "$(idfp_probe "$_idfp_nc_dir" '[A-Za-z0-9_.-]+#[0-9]+')" ]; then
  ok "negative control: 仕込んだ owner/repo#N は2本目のパターンで検知される"
else
  ng "negative control: 仕込んだ owner/repo#N は2本目のパターンで検知される"
fi
rm -f "$_idfp_nc_dir"/*.md
# ケースC: PR#N 形式(2本目のパターンが repo 名別の3本を置き換えたことで新たに拾えるようになった形)。
printf 'merged in PR%s581\n' "$HSH" > "$_idfp_nc_dir/pr.md"
if [ -n "$(idfp_probe "$_idfp_nc_dir" '[A-Za-z0-9_.-]+#[0-9]+')" ]; then
  ok "negative control: 仕込んだ PR#N は2本目のパターンで検知される"
else
  ng "negative control: 仕込んだ PR#N は2本目のパターンで検知される"
fi
rm -rf "$_idfp_nc_dir"

echo "== test/run.sh: テスト名・echo見出しに HSH による disguised issue 参照が無い(regression ラチェット) =="
# HSH(='#')は epic-implement-probe・gh-issue-resolve・knowledge-audit の check1/check2 fixture・
# knowledge-index フックと監査の fixture でのみ、被検査コードへの入力・期待値として正当に使われる。
# 上記のテストデータ用途は needle/haystack・cmd 引数・printf/ヒアドキュメント内の文字列リテラルの
# 位置にしか出現しない(テスト名・見出しは、いま HSH+数字を必要としない——テストデータの数字を
# 説明する場合も番号なしの実体(bare digit)で書く。一次レビュー指摘で、テスト名にテストデータの
# 番号を書く場合だけ例外的に許す区間除外を設けていたが、区間全体(約1000行)を丸ごと除外しており、
# 同じ区間内の見出し・テスト名に real citation が混入しても検知できなかった。区間除外をやめ、
# テストデータを必要とする既存のテスト名はすべて bare digit へ書き換えたので、区間除外は不要になった)。
# したがってテスト名・echo見出しに HSH+数字が1つでも現れたら、番号を消したはずが変数で組み立てる
# 形に置き換えられて残っている(disguised citation)とみなし、区間を問わず全行を検査する。
#
# テスト名を受け取るヘルパーは、既知の名前を列挙するだけでは「新しいラッパーヘルパーを足したのに
# 列挙の更新を忘れる」再発(一次レビュー指摘: ag364 のような既存のローカル定義ヘルパーが列挙から
# 漏れていた)を防げない。このため、列挙(LABEL1/LABEL2/LABEL3)とは別に、ファイル内の関数定義から
# 「ラベルを生成するヘルパー」の集合を導出し、列挙が漏れていないかを自己検証する
# (_hsh_disguise_completeness_check)。
_hsh_disguise_scan() {
  # $1=走査対象ファイル。見つけた行を1行1件で標準出力へ出す(0件なら無出力・exit 0)。
  python3 - "$1" <<'PYEOF'
import re, sys
path = sys.argv[1]
pat = re.compile(r'\$\{?HSH\}?[0-9]')
# ラベル位置がヘルパーごとに違う(第何引数目に来るか)ため、位置ごとに3系統のヘルパー名を持つ。
LABEL1 = ('ok', 'ng', 'exit_is', 'out_has', 'out_hasnt', 'file_is', 'file_isnt', 'out_is_empty', '_wt_prop_check')
LABEL2 = ('ag', 'ag364', '_threshold_invariant', '_threshold_invariant_esc')
LABEL3 = ('wg', 'wf')
# ラベル引数は二重引用符・単一引用符のどちらでも書ける(実際に test/run.sh 内には
# exit_is '...' の形で単一引用符のラベルが複数存在する。二重引用符しか拾わないと、
# これらの行に disguised citation が混入しても検知できない、という関数定義検出と
# 同型の穴になる)。両方を1つの選択群として持ち、マッチした側の内容を使う。
_label = r'(?:"([^"]*)"|\'([^\']*)\')'
_arg = r'(?:\'[^\']*\'|"[^"]*"|\S+)'
label1_re = re.compile(r'\b(?:' + '|'.join(LABEL1) + r')\s+' + _label)
label2_re = re.compile(r'\b(?:' + '|'.join(LABEL2) + r')\s+' + _arg + r'\s+' + _label)
label3_re = re.compile(r'\b(?:' + '|'.join(LABEL3) + r')\s+' + _arg + r'\s+' + _arg + r'\s+' + _label)
# echo見出しも同様に二重引用符・単一引用符の両方を拾う。printf での見出し(printf "%s\n"
# "== ... =="形)は本ファイル内に現在1件も存在しない(確認済み)ため、任意の printf 書式を
# 相手にする一般化は過剰実装と判断し見送る。将来 printf 形の見出しが実際に使われ始めたら、
# その時点で同じ考え方(構造で判定・自己一致しないパターン)で追加する。
echo_re = re.compile(r'^\s*echo\s+(?:"==.*=="|\'==.*==\')\s*$')

with open(path, encoding='utf-8') as f:
    lines = f.readlines()

hits = []
for i, line in enumerate(lines):
    lineno = i + 1
    if echo_re.match(line) and pat.search(line):
        hits.append(f"{lineno}:heading:{line.rstrip()}")
        continue
    for regex in (label1_re, label2_re, label3_re):
        for m in regex.finditer(line):
            label_content = m.group(1) if m.group(1) is not None else m.group(2)
            if pat.search(label_content):
                hits.append(f"{lineno}:label:{line.rstrip()}")
for h in hits:
    print(h)
sys.exit(1 if hits else 0)
PYEOF
}
_hsh_disguise_completeness_check() {
  # $1=走査対象ファイル。ファイル内の関数定義から「ラベル(第N引数)を ok/ng/exit_is/out_has/
  # out_hasnt/file_is/out_is_empty(=末端のレポート関数)へ渡すヘルパー」の集合を、呼び出しグラフの
  # 到達可能性で導出し、_hsh_disguise_scan の LABEL1/LABEL2/LABEL3 列挙がこれを網羅しているかを
  # 検証する。未知のヘルパーが見つかったら1行1件で標準出力へ出す(0件なら無出力・exit 0)。
  # このスキャナ自身(_hsh_disguise_scan/_hsh_disguise_completeness_check)は、python ソース中に
  # "ok"/"ng" 等の語をヘルパー名の列挙として含むため、呼び出しグラフ判定の対象から除く。
  python3 - "$1" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    lines = f.readlines()

# bash の関数定義は複数の書き方が有効(POSIX形 `name() {`・`name ()`(空白入り)、
# bash拡張の `function name {`・`function name() {`・`function name () {`)、かつ
# `{` が同じ行にも次の行にも来うる。網羅するため、まず「関数ヘッダらしい行」を緩く
# 判定してから、name/parens有無/function有無/brace位置を個別に読む。
func_head_re = re.compile(r'^\s*(function\s+)?(\w+)\s*(\(\s*\))?\s*(\{(.*))?$')
# 上のヘッダ判定にすら掛からなかったが、明らかに関数定義を書こうとしている行
# (`function` キーワードで始まる)を検出するための安全網。ヘッダ判定で処理できた行は
# このパターンにも一致するが、その場合は下の本ループで既に処理済みなので二重報告しない。
func_looks_like_re = re.compile(r'^\s*function\b')
heredoc_start_re = re.compile(r'<<-?\s*\'?([A-Za-z_][A-Za-z0-9_]*)\'?')

# ヒアドキュメントの中身は fixture 生成用の"例文"であり、実際の関数定義ではない
# (例: このファイル自身のネガティブコントロールが `cat > file <<'X' ... my_wrapper() { ... } ... X`
# のように、テスト用ヘルパー定義をヒアドキュメントとして書き出している)。中身をスキップしないと、
# それを実在の関数定義と誤認してしまう。
in_heredoc = set()
i = 0
n = len(lines)
while i < n:
    hm = heredoc_start_re.search(lines[i])
    if hm:
        delim = hm.group(1)
        j = i + 1
        while j < n and lines[j].rstrip('\n') != delim:
            in_heredoc.add(j)
            j += 1
        in_heredoc.add(j) if j < n else None
        i = j + 1
        continue
    i += 1

funcs = {}
unparsed = []  # 関数定義らしいのに解析しきれなかった行(取りこぼしの可視化)
i, n = 0, len(lines)
while i < n:
    if i in in_heredoc:
        i += 1
        continue
    raw = lines[i].rstrip('\n')
    m = func_head_re.match(raw)
    is_def_head = bool(m) and (m.group(1) is not None or m.group(3) is not None)
    if is_def_head:
        name = m.group(2)
        brace_group = m.group(4)
        if brace_group is not None:
            rest = m.group(5)
            if rest.rstrip().endswith('}'):
                funcs[name] = rest
                i += 1
                continue
            body_lines = [rest]
            i += 1
            # 閉じ括弧行の判定は末尾の改行だけでなく行末の空白も除去して比較する
            # (`}` の後ろに末尾空白が付いた行を見逃すと、閉じ括弧が見つからないまま
            # ファイル末尾まで読み進めてしまい、直後の関数定義も巻き込んで消える)。
            while i < n and lines[i].rstrip() != '}':
                body_lines.append(lines[i])
                i += 1
            funcs[name] = '\n'.join(body_lines)
            i += 1
            continue
        # `{` がこの行に無い場合、次の非空行が単独の `{` かどうかを見る
        # (bash の一般的な複数行関数定義の書き方)。行末の空白も除去して比較する
        # (上と同じ注意: 末尾空白付きの `{`/`}` 行を見逃さない)。
        j = i + 1
        while j < n and lines[j].strip() == '':
            j += 1
        if j < n and lines[j].rstrip() == '{':
            body_lines = []
            k = j + 1
            while k < n and lines[k].rstrip() != '}':
                body_lines.append(lines[k])
                k += 1
            funcs[name] = '\n'.join(body_lines)
            i = k + 1
            continue
        # ヘッダらしき行だったが `{` を見つけられなかった → 取りこぼしとして報告する
        # (黙ってスキップしない)。
        unparsed.append((i + 1, raw))
        i += 1
        continue
    if func_looks_like_re.match(raw):
        # `function` キーワードで始まるのにヘッダ判定にも掛からなかった行
        # (例: 識別子が続かない壊れた記法)。同様に取りこぼしとして報告する。
        unparsed.append((i + 1, raw))
    i += 1

TERMINALS = {'ok', 'ng', 'exit_is', 'out_has', 'out_hasnt', 'file_is', 'file_isnt', 'out_is_empty'}
SELF = {'_hsh_disguise_scan', '_hsh_disguise_completeness_check'}
KNOWN = TERMINALS | {'ag', 'ag364', '_threshold_invariant', '_threshold_invariant_esc', 'wg', 'wf', '_wt_prop_check'}

producers = set(TERMINALS)
changed = True
while changed:
    changed = False
    for name, body in funcs.items():
        if name in producers or name in SELF:
            continue
        for p in producers:
            if re.search(r'\b' + re.escape(p) + r'\b', body):
                producers.add(name)
                changed = True
                break

unknown = sorted(producers - KNOWN)
for u in unknown:
    print(f"未知のラベル生成ヘルパー: {u}(LABEL1/LABEL2/LABEL3 のいずれにも列挙されていません)")
for lineno, raw in unparsed:
    print(f"{lineno}:未解析の関数定義らしい行(ラベル生成ヘルパーかどうか判定できません): {raw}")
sys.exit(1 if (unknown or unparsed) else 0)
PYEOF
}
# 分割前は test/run.sh 単体が走査対象だった。分割後も1件の走査として扱うため、
# test/run.sh・test/lib/*.sh・test/suites/*.sh を連結した一時ファイルを走査する(_all_test_src)。
_hsh_allsrc="$(_all_test_src)"
_hsh_disguise_out="$(_hsh_disguise_scan "$_hsh_allsrc")"; _hsh_disguise_rc=$?
if [ "$_hsh_disguise_rc" = "0" ]; then
  ok "test/run.sh: テスト名・echo見出しに disguised issue 参照(HSH+数字)が無い"
else
  ng "test/run.sh: テスト名・echo見出しに disguised issue 参照(HSH+数字)が無い → $(printf '%s' "$_hsh_disguise_out" | tr '\n' ' ')"
fi
_hsh_completeness_out="$(_hsh_disguise_completeness_check "$_hsh_allsrc")"; _hsh_completeness_rc=$?
if [ "$_hsh_completeness_rc" = "0" ]; then
  ok "test/run.sh: ラベル生成ヘルパーの列挙(LABEL1/LABEL2/LABEL3)に漏れが無い"
else
  ng "test/run.sh: ラベル生成ヘルパーの列挙(LABEL1/LABEL2/LABEL3)に漏れが無い → $(printf '%s' "$_hsh_completeness_out" | tr '\n' ' ')"
fi

echo "== HSHディスガイズ検査: negative control(仕込んだ echo見出し/テスト名で実際に赤になること) =="
# 仕込む値はソース上に disguised パターンをそのまま書かない(このテストファイル自身も上の
# 走査対象に含まれるため、素朴に書くと自己一致してしまう)。'$' と '{HSH}<N>' を別々の変数へ
# 分けて実行時に連結し、ソース上は隣接しない形にする(IDFP のネガティブコントロールと同じ注意)。
_hsh_nc_dollar='$'
_hsh_nc_dir="$(mktemp -d "$ROOT/test/scratch.XXXXXXXX")"

# ケースA: echo見出しへの混入。
printf 'echo "== sample heading(%s{HSH}999) =="\n' "$_hsh_nc_dollar" > "$_hsh_nc_dir/case_a.sh"
if grep -qF '${HSH}999' "$_hsh_nc_dir/case_a.sh"; then
  ok "negative control: 仕込みが実際に適用された(echo見出しにdisguisedパターンが書き込まれている)"
else
  ng "negative control: 仕込みが実際に適用された(echo見出しにdisguisedパターンが書き込まれている)"
fi
_hsh_nc_out_a="$(_hsh_disguise_scan "$_hsh_nc_dir/case_a.sh")"; _hsh_nc_rc_a=$?
if [ "$_hsh_nc_rc_a" != "0" ]; then
  ok "negative control: 仕込んだ echo見出し(disguised)は検知される"
else
  ng "negative control: 仕込んだ echo見出し(disguised)は検知される"
fi
out_has "negative control: echo見出しの検知はheading種別で報告される" ":heading:" "$_hsh_nc_out_a"

# ケースB: テスト名(LABEL1の第1引数)への混入。
printf 'out_has "sample test name(%s{HSH}888)" "needle" "haystack"\n' "$_hsh_nc_dollar" > "$_hsh_nc_dir/case_b.sh"
_hsh_nc_out_b="$(_hsh_disguise_scan "$_hsh_nc_dir/case_b.sh")"; _hsh_nc_rc_b=$?
if [ "$_hsh_nc_rc_b" != "0" ]; then
  ok "negative control: 仕込んだテスト名(LABEL1第1引数・disguised)は検知される"
else
  ng "negative control: 仕込んだテスト名(LABEL1第1引数・disguised)は検知される"
fi
out_has "negative control: テスト名の検知はlabel種別で報告される" ":label:" "$_hsh_nc_out_b"

# 陽性対照(対になる正しい振る舞い): テストデータ位置(needle/haystack)にHSH+数字があっても検知しない
# (labelとdataを引数位置で区別できていることの確認・落ちたのが意図した検査だけであることの裏付け)。
printf 'out_has "clean test name" "acme/target%s{HSH}42" "haystack"\n' "$_hsh_nc_dollar" > "$_hsh_nc_dir/case_c.sh"
_hsh_nc_rc_c="$(_hsh_disguise_scan "$_hsh_nc_dir/case_c.sh" >/dev/null; echo $?)"
if [ "$_hsh_nc_rc_c" = "0" ]; then
  ok "negative control: needle/haystack位置のHSH+数字(テストデータ)は誤検知しない"
else
  ng "negative control: needle/haystack位置のHSH+数字(テストデータ)は誤検知しない"
fi

# ケースD: LABEL2(ag、既知の共通ヘルパー)の第2引数への混入。
printf 'ag "cmd" "sample label(%s{HSH}777)" 2\n' "$_hsh_nc_dollar" > "$_hsh_nc_dir/case_d.sh"
_hsh_nc_rc_d="$(_hsh_disguise_scan "$_hsh_nc_dir/case_d.sh" >/dev/null; echo $?)"
if [ "$_hsh_nc_rc_d" != "0" ]; then
  ok "negative control: 仕込んだ ag 呼び出し(LABEL2第2引数・disguised)は検知される"
else
  ng "negative control: 仕込んだ ag 呼び出し(LABEL2第2引数・disguised)は検知される"
fi

# ケースE(一次レビュー指摘1の回帰): ag364 のような、ファイル内でローカルに定義された
# ヘルパー経由のテスト名も検知されること。ag364 は既に LABEL2 に列挙済みなので通常運転では
# 検知されるが、ここでは「その仕組みが実際に効いている」ことを個別に固定する。
printf 'ag364 '"'"'cmd'"'"' "sample label(%s{HSH}666)"\n' "$_hsh_nc_dollar" > "$_hsh_nc_dir/case_e.sh"
_hsh_nc_rc_e="$(_hsh_disguise_scan "$_hsh_nc_dir/case_e.sh" >/dev/null; echo $?)"
if [ "$_hsh_nc_rc_e" != "0" ]; then
  ok "negative control: 仕込んだ ag364(ローカル定義ヘルパー)呼び出しは検知される"
else
  ng "negative control: 仕込んだ ag364(ローカル定義ヘルパー)呼び出しは検知される"
fi

# ケースF: 列挙(LABEL1/LABEL2/LABEL3)に無い新規ヘルパーを完全性チェックが検知すること
# (このヘルパー自体は disguised citation を含まないが、それでも「未列挙」として報告される)。
cat > "$_hsh_nc_dir/case_f.sh" <<'CASEF'
my_new_wrapper() { exit_is "$1" "$2" "$3"; }
CASEF
_hsh_nc_out_f="$(_hsh_disguise_completeness_check "$_hsh_nc_dir/case_f.sh")"; _hsh_nc_rc_f=$?
if [ "$_hsh_nc_rc_f" != "0" ]; then
  ok "negative control: 列挙に無い新規ラッパーヘルパーは完全性チェックで検知される"
else
  ng "negative control: 列挙に無い新規ラッパーヘルパーは完全性チェックで検知される"
fi
out_has "negative control: 完全性チェックの報告に未知ヘルパー名が含まれる" "my_new_wrapper" "$_hsh_nc_out_f"

# ケースG(一次レビュー指摘2の回帰): 実ファイルの再現。以前は epic-implement-probe の fixture
# 区間全体(約700行)を丸ごと除外していたため、区間の内側に混入した disguised citation は
# 検知できなかった(一次レビューで実際に確認された欠陥)。区間除外を撤廃した今、実ファイルの
# コピー(連結済み全テストソース。_eipbin="$(mktemp -d)" の直後は test/suites/70-epic.sh 由来)へ
# 同じ位置へ見出しを1行だけ仕込んで検知されることを固定する。
_hsh_nc_realcopy="$_hsh_nc_dir/run_copy.sh"
cp "$_hsh_allsrc" "$_hsh_nc_realcopy"
_hsh_nc_poison="$(printf 'echo "== poisoned heading(%s{HSH}999) =="' "$_hsh_nc_dollar")"
python3 - "$_hsh_nc_realcopy" "$_hsh_nc_poison" <<'PYEOF'
import sys
path, poison = sys.argv[1], sys.argv[2]
with open(path, encoding='utf-8') as f:
    lines = f.readlines()
idx = next(i for i, l in enumerate(lines) if l.rstrip('\n') == '_eipbin="$(mktemp -d)"')
lines.insert(idx + 1, poison + '\n')
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(lines)
PYEOF
if grep -qF '${HSH}999' "$_hsh_nc_realcopy"; then
  ok "negative control: 仕込みが実際に適用された(epic-implement-probe区間の内側に見出しを挿入)"
else
  ng "negative control: 仕込みが実際に適用された(epic-implement-probe区間の内側に見出しを挿入)"
fi
_hsh_nc_rc_g="$(_hsh_disguise_scan "$_hsh_nc_realcopy" >/dev/null; echo $?)"
if [ "$_hsh_nc_rc_g" != "0" ]; then
  ok "negative control: 旧epic-implement-probe区間の内側に仕込んだ見出しも検知される(区間除外の撤廃回帰)"
else
  ng "negative control: 旧epic-implement-probe区間の内側に仕込んだ見出しも検知される(区間除外の撤廃回帰)"
fi

# ケースH(二次レビュー指摘の回帰): 完全性チェックの関数定義パーサが `name() {` 形にしか
# 一致せず、bash で有効な他の書き方(空白入り・function キーワード・{ が次行)のヘルパーを
# 静かに見逃していた。各書き方について、列挙に無いヘルパーを実際に検知することを固定する。
cat > "$_hsh_nc_dir/case_h.sh" <<'CASEH'
paren_space_helper () { exit_is "$1" "$2" "$3"; }
function noparens_helper { exit_is "$1" "$2" "$3"; }
function_kw_paren_helper() { exit_is "$1" "$2" "$3"; }
brace_next_line_helper()
{
  exit_is "$1" "$2" "$3"
}
CASEH
_hsh_nc_out_h="$(_hsh_disguise_completeness_check "$_hsh_nc_dir/case_h.sh")"; _hsh_nc_rc_h=$?
if [ "$_hsh_nc_rc_h" != "0" ]; then
  ok "negative control: 空白入り・functionキーワード・{が次行、いずれの書き方のヘルパーも完全性チェックで検知される"
else
  ng "negative control: 空白入り・functionキーワード・{が次行、いずれの書き方のヘルパーも完全性チェックで検知される"
fi
for _hsh_nc_h_name in paren_space_helper noparens_helper function_kw_paren_helper brace_next_line_helper; do
  out_has "negative control: 完全性チェックの報告に ${_hsh_nc_h_name} が含まれる" "$_hsh_nc_h_name" "$_hsh_nc_out_h"
done

# ケースH': `function` キーワードで始まるが解析できない壊れた行(取りこぼしの可視化)。
cat > "$_hsh_nc_dir/case_h2.sh" <<'CASEH2'
function
echo "not a valid function definition"
CASEH2
_hsh_nc_out_h2="$(_hsh_disguise_completeness_check "$_hsh_nc_dir/case_h2.sh")"; _hsh_nc_rc_h2=$?
if [ "$_hsh_nc_rc_h2" != "0" ]; then
  ok "negative control: 解析できない関数定義らしい行(function単独)は黙って飛ばさず検知される"
else
  ng "negative control: 解析できない関数定義らしい行(function単独)は黙って飛ばさず検知される"
fi
out_has "negative control: 未解析行の報告に該当行の内容が含まれる" "未解析の関数定義らしい行" "$_hsh_nc_out_h2"

# ケースI(二次レビュー指摘4の回帰確認: 対になる箇所の再走査): echo見出し・テスト名の検出が
# 二重引用符にしか一致せず、単一引用符の見出し・ラベルを見逃していた
# (test/run.sh 内には exit_is '...' 形の単一引用符ラベルが実在する)。両方とも検知されることを固定する。
printf "echo '== sample heading(%s{HSH}444) =='\n" "$_hsh_nc_dollar" > "$_hsh_nc_dir/case_i_heading.sh"
_hsh_nc_rc_i1="$(_hsh_disguise_scan "$_hsh_nc_dir/case_i_heading.sh" >/dev/null; echo $?)"
if [ "$_hsh_nc_rc_i1" != "0" ]; then
  ok "negative control: 単一引用符のecho見出しも検知される"
else
  ng "negative control: 単一引用符のecho見出しも検知される"
fi
printf 'exit_is '"'"'sample label(%s{HSH}333)'"'"' 0 0\n' "$_hsh_nc_dollar" > "$_hsh_nc_dir/case_i_label.sh"
_hsh_nc_rc_i2="$(_hsh_disguise_scan "$_hsh_nc_dir/case_i_label.sh" >/dev/null; echo $?)"
if [ "$_hsh_nc_rc_i2" != "0" ]; then
  ok "negative control: 単一引用符のLABEL1(exit_is)テスト名も検知される"
else
  ng "negative control: 単一引用符のLABEL1(exit_is)テスト名も検知される"
fi

# ケースJ(三次レビュー指摘の回帰): 閉じ括弧の判定が改行だけ除去(.rstrip('\n'))で行末の空白を
# 見ていなかったため、末尾空白付きの `}` 行を「まだ本体の途中」と誤認し、その直後にある
# 別の関数定義を丸ごと本体へ取り込んで(=黙って消して)いた。`}` の行末に空白を仕込み、
# 直後の未列挙ヘルパーが funcs/unparsed のどちらにも現れず欠落しないことを固定する。
printf 'first_trailing_ws_helper()\n{\n  exit_is "$1" "$2" "$3"\n}   \nsecond_trailing_ws_helper() { exit_is "$1" "$2" "$3"; }\n' > "$_hsh_nc_dir/case_j.sh"
if grep -qE '^}[[:space:]]+$' "$_hsh_nc_dir/case_j.sh"; then
  ok "negative control: 仕込みが実際に適用された(末尾空白付きの}行が書き込まれている)"
else
  ng "negative control: 仕込みが実際に適用された(末尾空白付きの}行が書き込まれている)"
fi
_hsh_nc_out_j="$(_hsh_disguise_completeness_check "$_hsh_nc_dir/case_j.sh")"; _hsh_nc_rc_j=$?
if [ "$_hsh_nc_rc_j" != "0" ]; then
  ok "negative control: 末尾空白付き}行の直後にある未列挙ヘルパーも完全性チェックで検知される"
else
  ng "negative control: 末尾空白付き}行の直後にある未列挙ヘルパーも完全性チェックで検知される"
fi
out_has "negative control: 完全性チェックの報告にfirst_trailing_ws_helperが含まれる" "first_trailing_ws_helper" "$_hsh_nc_out_j"
out_has "negative control: 完全性チェックの報告にsecond_trailing_ws_helperが含まれる(直後の定義が消えていない)" "second_trailing_ws_helper" "$_hsh_nc_out_j"

rm -rf "$_hsh_nc_dir"
rm -rf "$(dirname "$_hsh_allsrc")"

