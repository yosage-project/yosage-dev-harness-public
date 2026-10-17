echo "== 決め打ちの再発防止: harness/・README.md・scripts/ にベースブランチの直書きが無い =="
# ベース(作業ブランチの起点・PR の向け先)は導入先の既定ブランチから解決する(ルール pr-loop の「ベースブランチ / クローズ / マージ」節)。
# 特定のブランチ名を payload・README・scripts に直書きすると、導入先によっては存在しないブランチを
# 前提にした手順が配られる。検出語はリテラルで決める(語境界つきの develop・origin/<名前>・--base <名前>・
# checkout の対象)。epic/<name>・$base・<…> の形は直書きと見なさない。除外は使わない(0件にする。
# 行番号で除外すると、別の変更が同じファイルを触ったときにずれて壊れるため)。
# 判定の本体(_nfb_scan)は、実ツリーと、壊した写し(negative control)の両方から同じコードで呼ぶ。

# _nfb_scan <root>: <root>/harness・<root>/README.md・<root>/scripts を走査する。
#   stdout に当たった行(file:line:text)。戻り値 0=1件も無い / 1=当たりがある / 2=走査できなかった
#   (走査対象が無い・grep のエラー)。2 を「0件」と同じに扱わない(fail-closed)。
_nfb_scan() {
  local root="$1" t out rc
  local targets=()
  for t in harness README.md scripts; do
    [ -e "$root/$t" ] && targets+=("$root/$t")
  done
  [ "${#targets[@]}" -eq 3 ] || { echo "_nfb_scan: 走査対象が揃っていない($root)" >&2; return 2; }
  # 語境界は [[:alnum:]_] の外側で表す(BSD grep の -E は \b が使えない)。
  # 名前の右側の境界: 英数字・_・/・- が続くときは別の名前(mainline・main-x・main/x)なので当たらない。
  local B='([^[:alnum:]_/-]|$)'
  out="$(grep -rInE \
    -e '(^|[^[:alnum:]_])develop([^[:alnum:]_]|$)' \
    -e "origin/(main|master|develop)$B" \
    -e "--base[ =](main|master|develop)$B" \
    -e "checkout (-b [^ ]+ )?(origin/)?(main|master|develop)$B" \
    -e "switch (-c [^ ]+ )?(origin/)?(main|master|develop)$B" \
    -e "git (push|pull)( -[^ ]+)* origin (main|master|develop)$B" \
    "${targets[@]}" 2>&1)"; rc=$?
  case "$rc" in
    0) printf '%s\n' "$out"; return 1 ;;
    1) return 0 ;;
    *) printf '%s\n' "$out" >&2; return 2 ;;
  esac
}

# --- 実ツリー: 0件 ---
_nfb_out="$(_nfb_scan "$ROOT" 2>&1)"; _nfb_rc=$?
exit_is "ベースの決め打ちが harness/・README.md・scripts/ に無い" 0 "$_nfb_rc"
[ "$_nfb_rc" -eq 0 ] || printf '%s\n' "$_nfb_out" | sed 's/^/    /'

# --- 検出語そのものの検査(写しの上で): 当たらないもの・当たるもの ---
# 「当たらない」ことは、足した行の前後で出力が変わらないこと(足した行が1件も増やさないこと)で確かめる
# (実ツリーの0件に依存させない。実ツリーの状態は上の検査が受け持つ)。
_nfb_src="$(_src_copy)"
_nfb_sk="$_nfb_src/harness/skills/epic-implement/SKILL.md"
_nfb_base="$(_nfb_scan "$_nfb_src" 2>&1)"
printf '\n%s\n' 'NODE_ENV の設定は .env.development に書く' >> "$_nfb_sk"
[ "$(_nfb_scan "$_nfb_src" 2>&1)" = "$_nfb_base" ] && ok "検出語: .env.development を含む行は当たらない" || ng "検出語: .env.development を含む行は当たらない"
printf '\n%s\n' 'gh pr create --base epic/<name> --head feat/x --base "$base" --base <ref>' >> "$_nfb_sk"
[ "$(_nfb_scan "$_nfb_src" 2>&1)" = "$_nfb_base" ] && ok "検出語: --base epic/<name>・\$base・<ref> は当たらない" || ng "検出語: --base epic/<name>・\$base・<ref> は当たらない"
printf '\n%s\n' 'KS_REF="main" と "ref": "main" は既定値であってベースの直書きではない' >> "$_nfb_sk"
[ "$(_nfb_scan "$_nfb_src" 2>&1)" = "$_nfb_base" ] && ok "検出語: knowledge.ref の既定値 main は当たらない" || ng "検出語: knowledge.ref の既定値 main は当たらない"
printf '\n%s\n' 'gh pr create --base develop --head feat/x' >> "$_nfb_sk"
_nfb_out="$(_nfb_scan "$_nfb_src" 2>&1)"; exit_is "検出語: --base develop は当たる" 1 "$?"
[ "$_nfb_out" != "$_nfb_base" ] && ok "検出語: --base develop で当たりが増える" || ng "検出語: --base develop で当たりが増える"
out_has "検出語: 当たりの出力に壊した行が含まれる(どこが当たったか分かる)" "--base develop" "$_nfb_out"
rm -rf "$_nfb_src"

_nfb_src="$(_src_copy)"
printf '\n%s\n' 'git log origin/main --oneline' >> "$_nfb_src/harness/skills/epic-implement/SKILL.md"
_nfb_scan "$_nfb_src" >/dev/null 2>&1; exit_is "検出語: origin/main は当たる" 1 "$?"
rm -rf "$_nfb_src"

_nfb_src="$(_src_copy)"
printf '\n%s\n' 'git checkout -b feat/x origin/develop' >> "$_nfb_src/scripts/catalog.sh"
_nfb_scan "$_nfb_src" >/dev/null 2>&1; exit_is "検出語: checkout -b <名前> origin/develop は当たる(scripts/ も走査する)" 1 "$?"
rm -rf "$_nfb_src"

_nfb_src="$(_src_copy)"
printf '\n%s\n' 'Sub-issue PR の既定は develop（独立に取り込める形）' >> "$_nfb_src/README.md"
_nfb_scan "$_nfb_src" >/dev/null 2>&1; exit_is "検出語: 地の文の develop(語境界つき)は当たる(README.md も走査する)" 1 "$?"
rm -rf "$_nfb_src"

_nfb_src="$(_src_copy)"
printf '\n%s\n' 'git checkout master' >> "$_nfb_src/harness/hooks/guard.sh"
_nfb_scan "$_nfb_src" >/dev/null 2>&1; exit_is "検出語: checkout master は当たる(hooks も走査する)" 1 "$?"
rm -rf "$_nfb_src"

# 右側の境界(別の名前は当たらない)と、追加した検出語(当たる)
_nfb_src="$(_src_copy)"
_nfb_sk="$_nfb_src/harness/skills/epic-implement/SKILL.md"
_nfb_base="$(_nfb_scan "$_nfb_src" 2>&1)"
printf '\n%s\n' 'git checkout mainline と --base mainline と origin/main-x と origin/main/x と git switch masterpiece' >> "$_nfb_sk"
[ "$(_nfb_scan "$_nfb_src" 2>&1)" = "$_nfb_base" ] && ok "検出語: 別の名前(mainline・main-x・main/x・masterpiece)は当たらない(右側の境界)" || ng "検出語: 別の名前(mainline・main-x・main/x・masterpiece)は当たらない(右側の境界)"
rm -rf "$_nfb_src"
for _nfb_c in 'git push origin main' 'git push -u origin develop' 'git pull origin master' 'git switch main' 'git switch -c x develop' 'gh pr create --base=main'; do
  _nfb_src="$(_src_copy)"
  _nfb_base="$(_nfb_scan "$_nfb_src" 2>&1)"
  printf '\n%s\n' "$_nfb_c" >> "$_nfb_src/harness/skills/epic-implement/SKILL.md"
  _nfb_out="$(_nfb_scan "$_nfb_src" 2>&1)"; _nfb_rc=$?
  if [ "$_nfb_rc" -eq 1 ] && [ "$_nfb_out" != "$_nfb_base" ]; then ok "検出語: '$_nfb_c' は当たる"; else ng "検出語: '$_nfb_c' は当たる(rc=$_nfb_rc)"; fi
  rm -rf "$_nfb_src"
done

# --- 失敗するべきときに失敗する: 走査できなければ 0件にしない ---
_nfb_src="$(_src_copy)"
rm -rf "$_nfb_src/scripts"
_nfb_scan "$_nfb_src" >/dev/null 2>&1; exit_is "走査対象が無いときは失敗(2)になる(0件と同じに扱わない)" 2 "$?"
rm -rf "$_nfb_src"
_nfb_empty="$(mktemp -d)"
_nfb_scan "$_nfb_empty" >/dev/null 2>&1; exit_is "空のディレクトリを渡すと失敗(2)になる" 2 "$?"
rm -rf "$_nfb_empty"
if [ "$(id -u)" != "0" ]; then
  _nfb_src="$(_src_copy)"
  chmod 000 "$_nfb_src/harness/hooks/guard.sh"
  _nfb_scan "$_nfb_src" >/dev/null 2>&1; exit_is "grep が読めないファイルに当たったら失敗(2)になる(0件と同じに扱わない)" 2 "$?"
  chmod 644 "$_nfb_src/harness/hooks/guard.sh"
  rm -rf "$_nfb_src"
fi
