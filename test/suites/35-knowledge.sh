# mk_consumer は .claude/knowledge しか作らない(CLI install には頼らない)。knowledge-index
# フック($H/hooks/knowledge-index.sh)は自分の位置から生成器/監査本体を見つける
# (`resolve_lib()`。`$(dirname "${BASH_SOURCE[0]}")/../lib/$1`)ので、consumer 側に
# `.claude/lib/<name>` を用意しなくても常に `$H/lib/<name>` が使われる。生成器そのものを
# 壊れた版に差し替えて失敗を模す検査だけは、フック本体と lib を別のスクラッチ位置へコピーして
# 相対関係を保ったまま行う(下記 `_mk_ki_scratch_hooks()`。実体である `$H/hooks/knowledge-index.sh`
# を書き換えるわけにはいかないため)。
_mk_ki_scratch_hooks() {  # <scratch-dir> -> echo する必要は無く $1/hooks/knowledge-index.sh を叩けばよい
  mkdir -p "$1/hooks" "$1/lib"
  cp "$H/hooks/knowledge-index.sh" "$1/hooks/knowledge-index.sh"
  cp "$H/lib/knowledge-index.sh" "$1/lib/knowledge-index.sh"
  cp "$H/lib/knowledge-audit.sh" "$1/lib/knowledge-audit.sh"
}

echo "== knowledge-sync (opt-in, ローカル source) =="
out_has "config/defaults.json に knowledge.enabled:false を明記" '"enabled": false' "$(python3 -c "import json;print(json.dumps(json.load(open('$H/config/defaults.json')).get('knowledge', {})))" 2>/dev/null)"
ks="$(mktemp -d)"; src="$ks/src"; cache_home="$ks/cache"; cache="${cache_home}/yosage-dev-harness/knowledge"; proj="$ks/proj"
mkdir -p "$src/review" "$src/knowledge/api" "$proj"
printf '# global criteria\n' > "$src/review/criteria.md"
printf '# INDEX\n'          > "$src/knowledge/INDEX.md"
printf '# entry\n'          > "$src/knowledge/api/x.md"
( cd "$src" && git init -q && git checkout -q -b main && gitc add -A && gitc commit -qm init )
mk_consumer "$proj"
# 既定(無効): sync 物は来ない・落ちない
bash "$H/lib/knowledge-sync.sh" "$proj" "$cache" >/dev/null 2>&1
exit_is "disabled: sync は exit 0" 0 "$?"
if [ -f "$proj/.claude/review/criteria.md" ]; then ng "disabled: criteria.md 来ない"; else ok "disabled: criteria.md 来ない"; fi
# 有効化(ローカル source)
printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$src" > "$proj/.claude/yosage-dev-harness.local.json"
bash "$H/lib/knowledge-sync.sh" "$proj" "$cache" >/dev/null 2>&1
file_is "enabled: review/criteria.md 生成"          "$proj/.claude/review/criteria.md"
file_is "enabled: knowledge/global/INDEX.md 生成"   "$proj/.claude/knowledge/global/INDEX.md"
out_has "global INDEX は生成物(sync が再生成)" "生成物" "$(cat "$proj/.claude/knowledge/global/INDEX.md" 2>/dev/null)"
file_is "enabled: knowledge/global/INDEX.archive.md も生成される" "$proj/.claude/knowledge/global/INDEX.archive.md"
out_has "status に source 表示" "$src" "$(bash "$H/lib/knowledge-sync.sh" --status "$proj" "$cache" 2>&1)"
# sync 物は gitignore で管理外。プラグイン形では配布 payload に review/.gitignore・
# knowledge/.gitignore が無いため、導入先自身の .gitignore にこの行があれば管理外になることを
# 確かめる(setup の段が実際に書く行の先取り)。
printf 'review/criteria.md\nknowledge/global/\nknowledge/.global-sync\nknowledge/.sync-log\n' > "$proj/.claude/.gitignore"
( cd "$proj" && git init -q && git checkout -q -b main && gitc add -A 2>/dev/null )
kst="$(cd "$proj" && git status --porcelain 2>/dev/null)"
out_hasnt "sync 物(criteria.md)は git 管理外" "review/criteria.md" "$kst"
out_hasnt "sync 物(global)は git 管理外"      "knowledge/global"   "$kst"
# jq 非在(python3 フォールバック)で bool が小文字 'true' で返る(enabled 判定の回帰防止)。
# git を使わず ydh_config_get を直接検証(設定の読み取りは harness/lib/config.sh に一本化済み)。
# PATH に実 python3・dirname 等の最小ツールだけ置いて jq を隠す(pyenv shim 回避で実体を解決)。
njq="$ks/nojq"; mkdir -p "$njq"
realpy="$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null)"
for t in bash cat dirname basename; do p="$(command -v "$t" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$njq/$t"; done
[ -n "$realpy" ] && ln -sf "$realpy" "$njq/python3"
mkdir -p "$ks/proj_nojq/.claude"
printf '{ "knowledge": { "enabled": true } }\n' > "$ks/proj_nojq/.claude/yosage-dev-harness.local.json"
got="$(bash -c 'export PATH="$1"; source "$2"; ydh_config_get "$3" knowledge.enabled' _ "$njq" "$ROOT/harness/lib/config.sh" "$ks/proj_nojq" 2>/dev/null)"
out_has "jq非在(python3)で bool が 'true'" "true" "$got"
# 取得失敗(到達不可 source)でも exit 0・残骸を残さない(best-effort)
printf '{ "knowledge": { "enabled": true, "source": "%s/does-not-exist.git", "ref": "main" } }\n' "$ks" > "$proj/.claude/yosage-dev-harness.local.json"
cache_fail_home="$ks/cache_fail_home"; cache_fail="${cache_fail_home}/yosage-dev-harness/knowledge"
bash "$H/lib/knowledge-sync.sh" "$proj" "$cache_fail" >/dev/null 2>&1
exit_is "取得失敗でも exit 0(best-effort)" 0 "$?"
if [ -d "$cache_fail" ]; then ng "失敗時 cache 残骸を残さない"; else ok "失敗時 cache 残骸を残さない"; fi
# SessionStart フックは非ブロッキングで exit 0(opt-in 無効化してから=bg ジョブの後始末レース回避)
rm -f "$proj/.claude/yosage-dev-harness.local.json"
CLAUDE_PROJECT_DIR="$proj" bash "$H/hooks/knowledge-sync.sh" >/dev/null 2>&1
exit_is "SessionStart hook は exit 0" 0 "$?"
rm -rf "$ks"

echo "== SessionStart hook: CLAUDE_PLUGIN_DATA を読み、<CLAUDE_PLUGIN_DATA>/knowledge をキャッシュの置き場として lib へ引数で渡す =="
# hook は既定(引数無し)では非ブロッキング(nohup ... &)で lib を回してすぐ exit 0 を返す
# (直前の節で確認済み)。ここから先は lib の実行結果そのものを検査したいので、`--foreground`
# (lib の完了を待ってから exit する。手動でキャッシュを再同期したい場合にも使える運用上の
# 切り替え口。本番の呼び出し経路である hooks.json は引数無しで呼ぶため、この引数を渡さない
# 呼び出しの非ブロッキング挙動には影響しない)で同期実行させ、待ち合わせを排除する(負荷が
# 高いと既定のポーリング時間を超えてたまたま失敗しうるため)。
kss="$(mktemp -d)"; kss_src="$kss/src"; kss_proj="$kss/proj"
mkdir -p "$kss_src/knowledge/api" "$kss_proj"
printf '# INDEX\n' > "$kss_src/knowledge/INDEX.md"
printf -- '---\nid: plugdata-1\ndate: 2026-01-01\ndomain: api\nscope: global\nstatus: active\nsummary: s\n---\nbody\n' \
  > "$kss_src/knowledge/api/2026-01-01-plugdata-1.md"
( cd "$kss_src" && git init -q && git checkout -q -b main && gitc add -A && gitc commit -qm init )
mk_consumer "$kss_proj"
printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$kss_src" > "$kss_proj/.claude/yosage-dev-harness.local.json"

# (a) CLAUDE_PLUGIN_DATA を設定 → <CLAUDE_PLUGIN_DATA>/knowledge にキャッシュができ、
#     既定の置き場(XDG_CACHE_HOME。一時ディレクトリにして観測)には何も増えない。
kss_pd_root="$(mktemp -d)"; kss_pd="$kss_pd_root/plugin-data"
kss_xdg_root="$(mktemp -d)"; kss_xdg="$kss_xdg_root/xdg-cache"
CLAUDE_PROJECT_DIR="$kss_proj" CLAUDE_PLUGIN_DATA="$kss_pd" XDG_CACHE_HOME="$kss_xdg" bash "$H/hooks/knowledge-sync.sh" --foreground >/dev/null 2>&1
file_is "(a) CLAUDE_PLUGIN_DATA設定時: <CLAUDE_PLUGIN_DATA>/knowledge にキャッシュができる" "$kss_pd/knowledge/.last-sync"
file_is "(a) CLAUDE_PLUGIN_DATA設定時: 導入先側にも反映される(global/ ミラー)" "$kss_proj/.claude/knowledge/global/api/2026-01-01-plugdata-1.md"
if [ -e "$kss_xdg" ]; then ng "(a) 既定の置き場(XDG_CACHE_HOME)には何も作られない(ライブラリが環境変数を読まないことの確認)"; else ok "(a) 既定の置き場(XDG_CACHE_HOME)には何も作られない(ライブラリが環境変数を読まないことの確認)"; fi

# (c) XDG_CACHE_HOME を変えても (a) の置き場(<CLAUDE_PLUGIN_DATA>/knowledge)は変わらない。
rm -rf "$kss_proj/.claude/knowledge/global" "$kss_proj/.claude/knowledge/.global-sync" "$kss_proj/.claude/knowledge/.sync-log"
kss_xdg2_root="$(mktemp -d)"; kss_xdg2="$kss_xdg2_root/xdg-cache-2"
CLAUDE_PROJECT_DIR="$kss_proj" CLAUDE_PLUGIN_DATA="$kss_pd" XDG_CACHE_HOME="$kss_xdg2" bash "$H/hooks/knowledge-sync.sh" --foreground >/dev/null 2>&1
out_has "(c) XDG_CACHE_HOME を変えても置き場(CLAUDE_PLUGIN_DATA)は変わらない(同期は引き続き成功)" "plugdata-1" \
  "$(cat "$kss_proj/.claude/knowledge/global/api/2026-01-01-plugdata-1.md" 2>/dev/null)"
if [ -e "$kss_xdg2" ]; then ng "(c) 変えた先の XDG_CACHE_HOME も使われない"; else ok "(c) 変えた先の XDG_CACHE_HOME も使われない"; fi

# (b) CLAUDE_PLUGIN_DATA が空/未設定 → 同期しない。.sync-log に理由が残り exit 0。
rm -f "$kss_proj/.claude/knowledge/.sync-log"
kss_b_rc="$(CLAUDE_PROJECT_DIR="$kss_proj" bash "$H/hooks/knowledge-sync.sh" --foreground >/dev/null 2>&1; echo $?)"
exit_is "(b) CLAUDE_PLUGIN_DATA 未設定でも hook 自体は exit 0" 0 "$kss_b_rc"
out_has "(b) CLAUDE_PLUGIN_DATA 未設定: .sync-log に no-cache-dir の理由が残る" "outcome=no-cache-dir" \
  "$(cat "$kss_proj/.claude/knowledge/.sync-log" 2>/dev/null)"

# 破壊試験: hook が CLAUDE_PLUGIN_DATA を lib へ渡さない形に変えると、(a) と同じ入力でもキャッシュが
# 作られなくなる(検証が実際に効いていることの確認)。実体(harness/hooks/knowledge-sync.sh)は
# 書き換えられないため、hook・lib 一式を相対関係を保ったままスクラッチへコピーしてそちらだけ壊す。
kss_scratch="$(mktemp -d)"; mkdir -p "$kss_scratch/hooks" "$kss_scratch/lib"
cp "$H/hooks/knowledge-sync.sh" "$kss_scratch/hooks/knowledge-sync.sh"
cp "$H/lib/knowledge-sync.sh" "$kss_scratch/lib/knowledge-sync.sh"
cp "$H/lib/config.sh" "$kss_scratch/lib/config.sh"
python3 - "$kss_scratch/hooks/knowledge-sync.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = 'cache_dir=""\n[ -n "${CLAUDE_PLUGIN_DATA:-}" ] && cache_dir="$CLAUDE_PLUGIN_DATA/knowledge"\n'
new = 'cache_dir=""  # MUTATED: CLAUDE_PLUGIN_DATA を無視する\n'
assert s.count(old) == 1
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
if grep -qF 'MUTATED' "$kss_scratch/hooks/knowledge-sync.sh"; then
  ok "破壊試験: CLAUDE_PLUGIN_DATA を無視する編集が実際に入った"
else
  ng "破壊試験: CLAUDE_PLUGIN_DATA を無視する編集が実際に入った"
fi
rm -rf "$kss_proj/.claude/knowledge/global" "$kss_proj/.claude/knowledge/.global-sync" "$kss_proj/.claude/knowledge/.sync-log"
kss_pd2_root="$(mktemp -d)"; kss_pd2="$kss_pd2_root/plugin-data-broken"
CLAUDE_PROJECT_DIR="$kss_proj" CLAUDE_PLUGIN_DATA="$kss_pd2" bash "$kss_scratch/hooks/knowledge-sync.sh" --foreground >/dev/null 2>&1
if [ -f "$kss_pd2/knowledge/.last-sync" ]; then
  ng "破壊試験: CLAUDE_PLUGIN_DATA を渡さなくすると (a) は本来赤になるはず(検証が実際に効いている確認)"
else
  ok "破壊試験: CLAUDE_PLUGIN_DATA を渡さなくすると (a) は本来赤になる(キャッシュが作られない。検証が実際に効いている確認)"
fi
out_has "破壊試験: no-cache-dir として記録される(渡さない=未設定と同じ経路になる)" "outcome=no-cache-dir" \
  "$(cat "$kss_proj/.claude/knowledge/.sync-log" 2>/dev/null)"

rm -rf "$kss_scratch" "$kss_pd_root" "$kss_xdg_root" "$kss_xdg2_root" "$kss_pd2_root" "$kss"

echo "== knowledge-sync: グローバルミラーの入替を atomic 化(中断で「一部だけ」を残さない) =="
# 背景: 旧実装は「rm -rf で wipe → cp -R で複製」の直列処理で、中断のタイミングによって
# 「空」(PR で対処済み)にも「一部だけ複製された」(本 issue)にもなりえた。
# knowledge-audit.sh 側は「エントリが1件でもあれば利用可能」としか判定できない(どんな部分集合でも
# 同じ非空ディレクトリに見えるため、audit 単体では「一部」と「同期済み」を区別する手段がない)。
# したがって修正は sync 側の atomicity で行う: live な "global" という名前が、複製の途中を
# 一切経由しないことを保証する(実体は一時ディレクトリへ完成させてから rename で差し替える)。
# 4状態(不在/空/一部/同期済み)のうち、"空" と "一部" は audit からは exactly 同じ「中間状態」
# として扱われる(どちらも sync が中断したときに生じうる非本来的な状態)。このブロックでは
# 「不在」「同期済み」を実際に作って確認し、「一部」は sync 側の欠陥がなければ構造的に発生
# しえないことを、意図的にコピーを失敗させて確認する(発生したら live な内容が変化するはず)。
#
# 変数名は本ブロック専用に `ks501_` を接頭辞にする(一次レビュー指摘: 短い連番だけの変数名は
# 後方の別セクションが偶然同じ名前を使う可能性があり、実害が出ていなくても将来まぎれて発見が
# 遅れる型のため)。
ks501_ws="$(mktemp -d)"; ks501_src="$ks501_ws/src"; ks501_cache_home="$ks501_ws/cache"; ks501_cache="${ks501_cache_home}/yosage-dev-harness/knowledge"; ks501_proj="$ks501_ws/proj"
mkdir -p "$ks501_src/knowledge/api" "$ks501_proj"
printf '# INDEX\n' > "$ks501_src/knowledge/INDEX.md"
printf -- '---\nid: gid-1\ndate: 2026-01-01\ndomain: api\nscope: global\nstatus: active\nsummary: v1\n---\nbody v1\n' \
  > "$ks501_src/knowledge/api/2026-01-01-gid-1.md"
( cd "$ks501_src" && git init -q && git checkout -q -b main && gitc add -A && gitc commit -qm v1 )
mk_consumer "$ks501_proj"
printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ks501_src" > "$ks501_proj/.claude/yosage-dev-harness.local.json"

# 状態: 不在(未 sync)
if [ -d "$ks501_proj/.claude/knowledge/global" ]; then ng "atomic入替: 未sync時点では global/ が存在しない(状態: 不在)"; else ok "atomic入替: 未sync時点では global/ が存在しない(状態: 不在)"; fi

# 状態: 同期済み(1回目の正常な sync)。tmp/old の残骸を残さないことも併せて確認する。
# tmp は並行実行下での衝突を避けるため mktemp でプロセスごとに一意な名前(.global.tmp.XXXXXX)を
# 振るので、存在確認は固定名の -d ではなくワイルドカードで行う(一次レビュー で判明した
# 別の並行実行時の穴への対処に伴う変更)。この穴自体の再現・修正確認は複数プロセスの実際の
# 並行実行(&/wait)による手動のストレステストで行ったもので、本ファイルには自動テストとしては
# 含めていない(タイミング依存で決定論的なテストにしづらいため)。実測内容は
# .claude/knowledge/harness-dev/2026-08-13-mv-cp-into-existing-directory-nests-silently-use-
# rename2-for-true-atomic-replace.md に記録している。ここでは、その穴のうち「宛先が既に
# 埋まっている」という前提条件だけを決定論的に再現できる下の「== knowledge-sync: 入替は
# rename(2) 直呼びで行い、宛先が既に埋まっていても静かに入れ子化しない(一次レビュー 🔴1)
# ==」ブロックで、実際のガードが正しく機能することを固定している。
bash "$H/lib/knowledge-sync.sh" "$ks501_proj" "$ks501_cache" >/dev/null 2>&1
file_is "atomic入替: 初回同期後 global/api/*.md が実在(状態: 同期済み)" "$ks501_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md"
if ls -d "$ks501_proj"/.claude/knowledge/.global.tmp.* >/dev/null 2>&1 || [ -d "$ks501_proj/.claude/knowledge/.global.old" ]; then
  ng "atomic入替: 正常終了後に tmp/old の残骸を残さない"
else
  ok "atomic入替: 正常終了後に tmp/old の残骸を残さない"
fi

# store を更新(v2)し、atomic swap でも既存の「同期済み」内容が入替わることを確認する。
printf -- '---\nid: gid-1\ndate: 2026-01-01\ndomain: api\nscope: global\nstatus: active\nsummary: v2\n---\nbody v2\n' \
  > "$ks501_src/knowledge/api/2026-01-01-gid-1.md"
( cd "$ks501_src" && gitc add -A && gitc commit -qm v2 )
bash "$H/lib/knowledge-sync.sh" "$ks501_proj" "$ks501_cache" >/dev/null 2>&1
out_has "atomic入替: 2回目の同期で新内容(v2)に置き換わる" "body v2" \
  "$(cat "$ks501_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md" 2>/dev/null)"

# 状態: 「一部だけ複製された」を live な global/ に一切作らないことの確認(の核心)。
# cache → tmp のコピーを確実に失敗させる: 読み取り不能なファイルを cache 側へ直接(git を経由せず)
# 混入する。cache は git 管理下だが、この混入ファイルは commit されていないため fetch/reset で
# 消えたり上書きされたりしない。
ks501_before_snapshot="$(find "$ks501_proj/.claude/knowledge/global" -type f | sort)"
ks501_before_body="$(cat "$ks501_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md" 2>/dev/null)"
mkdir -p "$ks501_cache/knowledge/api"
printf 'secret\n' > "$ks501_cache/knowledge/api/unreadable.md"
chmod 000 "$ks501_cache/knowledge/api/unreadable.md"
ks501_sync_out="$(bash "$H/lib/knowledge-sync.sh" "$ks501_proj" "$ks501_cache" 2>&1)"
ks501_after_snapshot="$(find "$ks501_proj/.claude/knowledge/global" -type f | sort)"
ks501_after_body="$(cat "$ks501_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md" 2>/dev/null)"
chmod 644 "$ks501_cache/knowledge/api/unreadable.md"   # 後始末(rm -rf できるよう権限を戻す)
out_has "atomic入替: コピー失敗を報告する" "コピーに失敗" "$ks501_sync_out"
if [ "$ks501_before_snapshot" = "$ks501_after_snapshot" ] && [ "$ks501_before_body" = "$ks501_after_body" ]; then
  ok "atomic入替: コピー失敗時も live な global/ は変化しない(旧内容=v2を維持。一部だけの中間状態を晒さない)"
else
  ng "atomic入替: コピー失敗時も live な global/ は変化しない(旧内容=v2を維持。一部だけの中間状態を晒さない)"
fi
if ls -d "$ks501_proj"/.claude/knowledge/.global.tmp.* >/dev/null 2>&1; then ng "atomic入替: コピー失敗後 tmp を掃除する"; else ok "atomic入替: コピー失敗後 tmp を掃除する"; fi
if [ -d "$ks501_proj/.claude/knowledge/.global.old" ]; then ng "atomic入替: コピー失敗時は old を作らない(swapまで到達しない)"; else ok "atomic入替: コピー失敗時は old を作らない(swapまで到達しない)"; fi

# 状態: 前回中断の残骸(tmp/old)が残っていても、次の正常な sync が自己回復することを確認する。
# tmp 側は実運用のグロブ掃除(.global.tmp.*)が拾える名前で残骸を模す(プロセス固有のランダム
# suffix を模した固定文字列)。
mkdir -p "$ks501_proj/.claude/knowledge/.global.tmp.stalefixture/stale" "$ks501_proj/.claude/knowledge/.global.old/stale"
printf 'leftover\n' > "$ks501_proj/.claude/knowledge/.global.tmp.stalefixture/stale/x.md"
bash "$H/lib/knowledge-sync.sh" "$ks501_proj" "$ks501_cache" >/dev/null 2>&1
out_has "atomic入替: 前回中断の残骸が残っていても次の同期は正常完了する" "body v2" \
  "$(cat "$ks501_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md" 2>/dev/null)"
out_hasnt "atomic入替: 残骸(leftover)は次の同期後の global/ に混入しない" "leftover" \
  "$(cat "$ks501_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md" 2>/dev/null; ls "$ks501_proj/.claude/knowledge/global" 2>/dev/null)"
if ls -d "$ks501_proj"/.claude/knowledge/.global.tmp.* >/dev/null 2>&1 || [ -d "$ks501_proj/.claude/knowledge/.global.old" ]; then
  ng "atomic入替: 前回の残骸(tmp/old)は次の同期で掃除される"
else
  ok "atomic入替: 前回の残骸(tmp/old)は次の同期で掃除される"
fi
rm -rf "$ks501_ws"

# 破壊試験: 上の「コピー失敗時も live な global/ は変化しない」検証が実際に効いていることを確認する。
# atomic swap の失敗ゲート(cp -R の成否チェック)を無効化し、cp が失敗しても tmp の内容(不完全な
# ままの一部だけの複製)を無条件で live な global/ へ swap してしまう旧来の穴を再現する。壊す対象は
# 呼び出し側ではなく検証対象のロジックそのもの(cp -R の成否判定)であり、値の埋め込みではない。
# 実 repo の追跡ファイルは書き換えず、payload を _src_copy() で一時コピーしてそちら側だけを壊す。
ks501_mut_target='    elif cp -R "$KS_CACHE/knowledge/." "$ks_tmp/" 2>/dev/null; then'
ks501_mut_count="$(grep -Fc "$ks501_mut_target" "$ROOT/harness/lib/knowledge-sync.sh")"
if [ "$ks501_mut_count" = "1" ]; then
  ks501_payload="$(_src_copy)"
  python3 - "$ks501_payload/harness/lib/knowledge-sync.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = '    elif cp -R "$KS_CACHE/knowledge/." "$ks_tmp/" 2>/dev/null; then\n'
new = '    cp -R "$KS_CACHE/knowledge/." "$ks_tmp/" 2>/dev/null\n    elif true; then\n'
assert s.count(old) == 1
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
  # 未 sync(状態: 不在)から、読み取り不能な1件を混ぜた cache でいきなり sync する。
  # 修正済みの実装なら cp -R が失敗して swap まで到達せず global/ は不在のまま(不在 → 不在)だが、
  # ゲートを外した壊れた実装は cp -R の成否を無視して tmp を無条件に swap する。この mutation の
  # 具体的な壊れ方(実測で確認: elif の条件式だけを true に固定するため cp -R 自体が呼ばれず、
  # 空のままの tmp が swap される)では global/ は「一部」ではなく「空」になるが、いずれの形でも
  # 「本来 fail して欲しいのに global/ が出来てしまう」という検証したい性質は同じである。
  ks501_mut_ws="$(mktemp -d)"; ks501_mut_cache_home="$ks501_mut_ws/cache"; ks501_mut_cache="${ks501_mut_cache_home}/yosage-dev-harness/knowledge"; ks501_mut_proj="$ks501_mut_ws/proj"
  mkdir -p "$ks501_mut_cache/knowledge/api" "$ks501_mut_proj"
  mk_consumer "$ks501_mut_proj"
  printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ks501_mut_ws/does-not-matter" > "$ks501_mut_proj/.claude/yosage-dev-harness.local.json"
  printf -- '---\nid: gid-1\ndate: 2026-01-01\ndomain: api\nscope: global\nstatus: active\nsummary: v1\n---\nbody v1\n' \
    > "$ks501_mut_cache/knowledge/api/2026-01-01-gid-1.md"
  printf 'secret\n' > "$ks501_mut_cache/knowledge/api/unreadable.md"
  chmod 000 "$ks501_mut_cache/knowledge/api/unreadable.md"
  # KS_CACHE に .git が無いと sync は「clone を試みる」経路に入り既存 cache を消してしまうため、
  # 空の .git を置いて「fetch → 失敗 → 既存 cache をそのまま使う」経路(オフライン相当)を通す。
  ( cd "$ks501_mut_cache" && git init -q ) >/dev/null 2>&1
  bash "$ks501_payload/harness/lib/knowledge-sync.sh" "$ks501_mut_proj" "$ks501_mut_cache" >/dev/null 2>&1
  chmod 644 "$ks501_mut_cache/knowledge/api/unreadable.md"
  if [ -d "$ks501_mut_proj/.claude/knowledge/global" ]; then
    ok "atomic入替(破壊試験): 失敗ゲートを外すとコピー失敗にも関わらず global/ が作られてしまう(検証が実際に効いている確認)"
  else
    ng "atomic入替(破壊試験): 想定した壊れ方が再現しない(検証の前提が崩れている疑い。global/ が作られなかった)"
  fi
  rm -rf "$ks501_mut_ws" "$ks501_payload"
else
  ng "atomic入替(破壊試験): 壊す対象のパターンが本体に見つからない(件数=$ks501_mut_count。事前確認に失敗)"
fi

echo "== knowledge-sync: 入替は rename(2) 直呼びで行い、宛先が既に埋まっていても静かに入れ子化しない(一次レビュー 🔴1) =="
# 背景: シェルの `mv <dir> <既存dir>` は置換ではなく入れ子移動になり、exit 0 を返す(mv の一般的な
# 仕様)。したがって「呼ぶ前に宛先の非存在を確認する」だけでは、確認と実行の間の短い隙(TOCTOU)で
# 他プロセスが宛先を作った場合に静かな入れ子化を防げない(実測: 8並列で knowledge-sync.sh を
# 同一 target に対して繰り返し実行し、global/ の中に別プロセスの .global.tmp.<random> が入れ子で
# 残留する事例を再現した)。この PR では mv の代わりに ks_atomic_rename()(python3 経由で
# rename(2) を直接呼ぶヘルパー。python3 が無い環境では宛先の非存在確認+mv にフォールバック)を
# 使う。rename(2) 自体には入れ子フォールバックが無く、宛先が非空ディレクトリなら黙って失敗する
# だけなので、成否だけで正しく分岐できる。
#
# ここでは1回目の入替(global → .global.old)の宛先が想定外に既に埋まっている状態を作り、
# 実際の(改変していない)本体コードがそれを検知して入替を見送り、live な global/ の中身と
# .global.old に退避されていたはずの旧内容が、どちらも変化しないことを確認する。
#
# 「宛先が既に埋まっている」状態は、通常の実行では sync の先頭処理が毎回掃除するため単体の
# sync 呼び出しだけでは作れない(並行実行でしか自然発生しない)。ここでは検証対象のロジック
# (ks_atomic_rename とその呼び出し)には一切触れず、その手前の掃除処理(1行)だけを一時コピー上で
# 無効化して、この前提条件を確定的に再現する。
ks501_guard_cleanup_target='    [ -e "$dest/knowledge/global" ] && rm -rf "$ks_old"'
ks501_guard_cleanup_count="$(grep -Fc "$ks501_guard_cleanup_target" "$ROOT/harness/lib/knowledge-sync.sh")"
if [ "$ks501_guard_cleanup_count" = "1" ]; then
  # (a) 前提条件だけを再現する版(検証対象の ks_atomic_rename には触れない・実際の実装で確認する)。
  ks501_guard_fixture_payload="$(_src_copy)"
  python3 - "$ks501_guard_fixture_payload/harness/lib/knowledge-sync.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = '    [ -e "$dest/knowledge/global" ] && rm -rf "$ks_old"\n'
new = '    : # FIXTURE: skip pre-swap old cleanup so a pre-seeded .global.old survives to swap-time\n'
assert s.count(old) == 1
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
  ks501_guard_ws="$(mktemp -d)"; ks501_guard_proj="$ks501_guard_ws/proj"; ks501_guard_cache_home="$ks501_guard_ws/cache"; ks501_guard_cache="${ks501_guard_cache_home}/yosage-dev-harness/knowledge"
  mkdir -p "$ks501_guard_proj/.claude/knowledge/global/api" "$ks501_guard_cache/knowledge/api"
  printf -- '---\nid: gid-1\ndomain: api\nsummary: current\n---\nbody current\n' > "$ks501_guard_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md"
  mkdir -p "$ks501_guard_proj/.claude/knowledge/.global.old/marker-dir"
  printf 'PRE-EXISTING-OLD-MARKER\n' > "$ks501_guard_proj/.claude/knowledge/.global.old/marker-dir/x.txt"
  printf -- '---\nid: gid-1\ndomain: api\nsummary: incoming\n---\nbody incoming\n' > "$ks501_guard_cache/knowledge/api/2026-01-01-gid-1.md"
  ( cd "$ks501_guard_cache" && git init -q ) >/dev/null 2>&1
  printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ks501_guard_cache" > "$ks501_guard_proj/.claude/yosage-dev-harness.local.json"
  ks501_guard_out="$(bash "$ks501_guard_fixture_payload/harness/lib/knowledge-sync.sh" "$ks501_guard_proj" "$ks501_guard_cache" 2>&1)"
  out_has "入替ガード: 退避先が既に使用中である旨を報告する" "既に使用中" "$ks501_guard_out"
  out_has "入替ガード: live な global/ の中身は変化しない(入替を見送る)" "body current" \
    "$(cat "$ks501_guard_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md" 2>/dev/null)"
  file_is "入替ガード: 退避されていたはずの旧内容(.global.old)も無事なまま残る" "$ks501_guard_proj/.claude/knowledge/.global.old/marker-dir/x.txt"
  if ls -d "$ks501_guard_proj"/.claude/knowledge/.global.tmp.* >/dev/null 2>&1; then ng "入替ガード: 見送り後に tmp を掃除する"; else ok "入替ガード: 見送り後に tmp を掃除する"; fi
  rm -rf "$ks501_guard_ws" "$ks501_guard_fixture_payload"

  # (b) 破壊試験: 前提条件の再現(上と同じ1行)に加えて、検証対象のロジックそのもの
  # (ks_atomic_rename)も無効化し、「入れ子移動なのに exit 0 を返す」旧来の mv 相当の挙動に
  # 差し戻す。退避されていたはずの旧内容(marker-dir)が実際に失われる(=どこからも見えなく
  # なる)ことを確認する。
  ks501_guard_break_payload="$(_src_copy)"
  python3 - "$ks501_guard_break_payload/harness/lib/knowledge-sync.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old1 = '    [ -e "$dest/knowledge/global" ] && rm -rf "$ks_old"\n'
new1 = '    : # FIXTURE: skip pre-swap old cleanup so a pre-seeded .global.old survives to swap-time\n'
assert s.count(old1) == 1
s = s.replace(old1, new1, 1)
old2 = '''ks_atomic_rename() {  # <src> <dst>
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
'''
new2 = '''ks_atomic_rename() {  # <src> <dst> — MUTATED: unconditional mv(旧来の入れ子化しうる挙動)
  mv "$1" "$2" 2>/dev/null
}
'''
assert s.count(old2) == 1
s = s.replace(old2, new2, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
  ks501_guard_break_ws="$(mktemp -d)"; ks501_guard_break_proj="$ks501_guard_break_ws/proj"; ks501_guard_break_cache_home="$ks501_guard_break_ws/cache"; ks501_guard_break_cache="${ks501_guard_break_cache_home}/yosage-dev-harness/knowledge"
  mkdir -p "$ks501_guard_break_proj/.claude/knowledge/global/api" "$ks501_guard_break_cache/knowledge/api"
  printf -- '---\nid: gid-1\ndomain: api\nsummary: current\n---\nbody current\n' > "$ks501_guard_break_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md"
  mkdir -p "$ks501_guard_break_proj/.claude/knowledge/.global.old/marker-dir"
  printf 'PRE-EXISTING-OLD-MARKER\n' > "$ks501_guard_break_proj/.claude/knowledge/.global.old/marker-dir/x.txt"
  printf -- '---\nid: gid-1\ndomain: api\nsummary: incoming\n---\nbody incoming\n' > "$ks501_guard_break_cache/knowledge/api/2026-01-01-gid-1.md"
  ( cd "$ks501_guard_break_cache" && git init -q ) >/dev/null 2>&1
  printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ks501_guard_break_cache" > "$ks501_guard_break_proj/.claude/yosage-dev-harness.local.json"
  bash "$ks501_guard_break_payload/harness/lib/knowledge-sync.sh" "$ks501_guard_break_proj" "$ks501_guard_break_cache" >/dev/null 2>&1
  ks501_guard_break_marker_found="$(find "$ks501_guard_break_proj" -iname 'marker-dir' 2>/dev/null)"
  if [ -z "$ks501_guard_break_marker_found" ]; then
    ok "入替ガード(破壊試験): ks_atomic_rename を旧来の mv 相当に戻すと退避されていたはずの旧内容が実際にどこからも見えなくなる(検証が実際に効いている確認)"
  else
    ng "入替ガード(破壊試験): 想定した壊れ方が再現しない(検証の前提が崩れている疑い。marker-dir が $ks501_guard_break_marker_found に残っている)"
  fi
  rm -rf "$ks501_guard_break_ws" "$ks501_guard_break_payload"
else
  ng "入替ガード: 壊す対象のパターンが本体に見つからない(cleanup=$ks501_guard_cleanup_count。事前確認に失敗)"
fi

echo "== knowledge-sync: 中断で残った .global.old は次回の同期で復元してから使う(一次レビュー 🔴1・付随の失敗系) =="
# 背景: 直前の実行が「旧内容の退避(1回目の mv)は完了したが、新内容への入替(2回目の mv)は
# 完了しなかった」場合、global は不在のまま .global.old に最後の正当なミラーが残る。この状態を
# 実際に作り、cp -R 自体が失敗する回では「既存ミラーを維持」という報告が実際に真であること
# (=.global.old の内容が global/ へ復元され、失われないこと)を確認する。
ks501_recover_ws="$(mktemp -d)"; ks501_recover_proj="$ks501_recover_ws/proj"; ks501_recover_cache_home="$ks501_recover_ws/cache"; ks501_recover_cache="${ks501_recover_cache_home}/yosage-dev-harness/knowledge"
mkdir -p "$ks501_recover_proj/.claude/knowledge/.global.old/api" "$ks501_recover_cache/knowledge/api"
printf -- '---\nid: gid-1\ndomain: api\nsummary: restored\n---\nbody restored\n' > "$ks501_recover_proj/.claude/knowledge/.global.old/api/2026-01-01-gid-1.md"
printf 'secret\n' > "$ks501_recover_cache/knowledge/api/unreadable.md"
chmod 000 "$ks501_recover_cache/knowledge/api/unreadable.md"
( cd "$ks501_recover_cache" && git init -q ) >/dev/null 2>&1
printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ks501_recover_cache" > "$ks501_recover_proj/.claude/yosage-dev-harness.local.json"
ks501_recover_out="$(bash "$ROOT/harness/lib/knowledge-sync.sh" "$ks501_recover_proj" "$ks501_recover_cache" 2>&1)"
chmod 644 "$ks501_recover_cache/knowledge/api/unreadable.md"
out_has "中断復元: 復元した旨を報告する" "旧内容を復元" "$ks501_recover_out"
out_has "中断復元: cp -R 失敗後も「既存ミラーを維持」が実際に真になる(復元済みの内容が読める)" "body restored" \
  "$(cat "$ks501_recover_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md" 2>/dev/null)"
if [ -d "$ks501_recover_proj/.claude/knowledge/.global.old" ]; then ng "中断復元: 復元後に .global.old の残骸を残さない"; else ok "中断復元: 復元後に .global.old の残骸を残さない"; fi

# 破壊試験: 上の「中断復元」検証が実際に効いていることを確認する。復元ロジック自体を無効化する
# (呼び出し側ではなく検証対象のロジックそのもの)と、cp -R 失敗時に「既存ミラーを維持」という
# 報告が出るにも関わらず global/ が不在のまま(=報告と実態が食い違う)になることを確認する。
ks501_recover_mut_target='    if [ ! -e "$dest/knowledge/global" ] && [ -e "$ks_old" ]; then'
ks501_recover_mut_count="$(grep -Fc "$ks501_recover_mut_target" "$ROOT/harness/lib/knowledge-sync.sh")"
if [ "$ks501_recover_mut_count" = "1" ]; then
  ks501_recover_payload="$(_src_copy)"
  python3 - "$ks501_recover_payload/harness/lib/knowledge-sync.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = '    if [ ! -e "$dest/knowledge/global" ] && [ -e "$ks_old" ]; then\n'
new = '    if false; then # MUTATED: disable recovery-from-interruption\n'
assert s.count(old) == 1
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
  ks501_recover_break_ws="$(mktemp -d)"; ks501_recover_break_proj="$ks501_recover_break_ws/proj"; ks501_recover_break_cache_home="$ks501_recover_break_ws/cache"; ks501_recover_break_cache="${ks501_recover_break_cache_home}/yosage-dev-harness/knowledge"
  mkdir -p "$ks501_recover_break_proj/.claude/knowledge/.global.old/api" "$ks501_recover_break_cache/knowledge/api"
  printf -- '---\nid: gid-1\ndomain: api\nsummary: restored\n---\nbody restored\n' > "$ks501_recover_break_proj/.claude/knowledge/.global.old/api/2026-01-01-gid-1.md"
  printf 'secret\n' > "$ks501_recover_break_cache/knowledge/api/unreadable.md"
  chmod 000 "$ks501_recover_break_cache/knowledge/api/unreadable.md"
  ( cd "$ks501_recover_break_cache" && git init -q ) >/dev/null 2>&1
  printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ks501_recover_break_cache" > "$ks501_recover_break_proj/.claude/yosage-dev-harness.local.json"
  ks501_recover_break_out="$(bash "$ks501_recover_payload/harness/lib/knowledge-sync.sh" "$ks501_recover_break_proj" "$ks501_recover_break_cache" 2>&1)"
  chmod 644 "$ks501_recover_break_cache/knowledge/api/unreadable.md"
  if printf '%s' "$ks501_recover_break_out" | grep -q "既存ミラーを維持" && [ ! -e "$ks501_recover_break_proj/.claude/knowledge/global" ]; then
    ok "中断復元(破壊試験): 復元ロジックを外すと「既存ミラーを維持」と報告しつつ実際は global/ が不在のままになる(検証が実際に効いている確認)"
  else
    ng "中断復元(破壊試験): 想定した壊れ方が再現しない(検証の前提が崩れている疑い)"
  fi
  rm -rf "$ks501_recover_break_ws" "$ks501_recover_payload"
else
  ng "中断復元(破壊試験): 壊す対象のパターンが本体に見つからない(件数=$ks501_recover_mut_count。事前確認に失敗)"
fi
rm -rf "$ks501_recover_ws"

echo "== knowledge-sync: --status がミラー鮮度を target 別に反映(cache 共有下の乖離検知) =="
ks2="$(mktemp -d)"; src2="$ks2/src"; cache2_home="$ks2/cache"; cache2="${cache2_home}/yosage-dev-harness/knowledge"; proj1="$ks2/proj1"; proj2="$ks2/proj2"
mkdir -p "$src2/knowledge/api" "$proj1" "$proj2"
printf '# INDEX\n'    > "$src2/knowledge/INDEX.md"
printf '# entry v1\n' > "$src2/knowledge/api/x.md"
( cd "$src2" && git init -q && git checkout -q -b main && gitc add -A && gitc commit -qm v1 )
mk_consumer "$proj1"
mk_consumer "$proj2"
printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$src2" > "$proj1/.claude/yosage-dev-harness.local.json"
printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$src2" > "$proj2/.claude/yosage-dev-harness.local.json"
# proj1 が単独 sync(v1) → status は cache/ミラー区別を表示しつつ乖離なし
bash "$H/lib/knowledge-sync.sh" "$proj1" "$cache2" >/dev/null 2>&1
st1_before="$(bash "$H/lib/knowledge-sync.sh" --status "$proj1" "$cache2" 2>&1)"
out_has   "単一repoモード: cache最終取得を表示"      "cache 最終取得"     "$st1_before"
out_has   "単一repoモード: このミラー最終反映を表示" "このミラー最終反映" "$st1_before"
out_hasnt "単一repoモード(乖離なし)は警告なし"       "古い可能性"        "$st1_before"
# store を進める(v2)。proj2 が同じ cache で sync → cache は v2、proj2 ミラーも v2 に反映
printf '# entry v2\n' > "$src2/knowledge/api/x.md"
( cd "$src2" && gitc add -A && gitc commit -qm v2 )
bash "$H/lib/knowledge-sync.sh" "$proj2" "$cache2" >/dev/null 2>&1
# proj1 は sync していないのに(他 target の sync で)cache だけ v2 へ進んだ → proj1 の status は要 sync を警告
st1_after="$(bash "$H/lib/knowledge-sync.sh" --status "$proj1" "$cache2" 2>&1)"
out_has "他targetのsyncでcacheだけ進んだ後: proj1(未sync)は古い可能性を警告" "古い可能性" "$st1_after"
st2_after="$(bash "$H/lib/knowledge-sync.sh" --status "$proj2" "$cache2" 2>&1)"
out_hasnt "同状況でも proj2(sync済み)は警告なし" "古い可能性" "$st2_after"
# per-target マーカー(.global-sync)は global/ 同様 pull 物 → git 管理外(導入先自身の
# .gitignore にこの行があれば、の形で確かめる。上と同じ理由)。
printf 'knowledge/.global-sync
' > "$proj1/.claude/.gitignore"
( cd "$proj1" && git init -q && git checkout -q -b main && gitc add -A 2>/dev/null )
kst1="$(cd "$proj1" && git status --porcelain 2>/dev/null)"
out_hasnt "target マーカー(.global-sync)は git 管理外" ".global-sync" "$kst1"

# エッジケース1: 未 sync(cache dir も target マーカーも無い状態)で --status → クラッシュせず・誤警告なし
proj3="$ks2/proj3"; cache3_home="$ks2/cache3_never"; cache3="${cache3_home}/yosage-dev-harness/knowledge"
mkdir -p "$proj3"
mk_consumer "$proj3"
printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$src2" > "$proj3/.claude/yosage-dev-harness.local.json"
st3_never="$(bash "$H/lib/knowledge-sync.sh" --status "$proj3" "$cache3" 2>&1)"; rc3_never=$?
exit_is "未sync: --status はクラッシュせず exit 0"        0             "$rc3_never"
out_has   "未sync: cache最終取得は(未取得)"                "cache 最終取得   : (未取得)"  "$st3_never"
out_has   "未sync: このミラー最終反映は(未反映)"           "このミラー最終反映: (未反映)" "$st3_never"
out_hasnt "未sync: 誤警告が出ない"                          "古い可能性"                   "$st3_never"

# エッジケース2: 旧consumer相当(cache側 .last-sync は在るが target側 .global-sync が無い)で --status
#   → クラッシュせず、片方欠如を「古い」と誤断定した警告を出さない(現行実装: 両方揃わないと比較しない安全側)
bash "$H/lib/knowledge-sync.sh" "$proj3" "$cache3" >/dev/null 2>&1
rm -f "$proj3/.claude/knowledge/.global-sync"   # target マーカーだけ無い旧consumerを模す
st3_missing="$(bash "$H/lib/knowledge-sync.sh" --status "$proj3" "$cache3" 2>&1)"; rc3_missing=$?
exit_is "旧consumer(マーカー欠如): --status はクラッシュせず exit 0" 0                 "$rc3_missing"
out_has   "旧consumer: cache最終取得は表示される"                     "cache 最終取得   :"        "$st3_missing"
out_has   "旧consumer: このミラー最終反映は(未反映)"                 "このミラー最終反映: (未反映)" "$st3_missing"
out_hasnt "旧consumer: 片方欠如を古いと誤断定した警告は出さない"     "古い可能性"                   "$st3_missing"
rm -rf "$ks2"

echo "== knowledge-sync: 無進捗の可視化(.sync-log と --status への反映) =="
# 背景: 同期の並行実行は「安全だが前進しない」ラウンドを生むことがあり(の atomic 入替が
# 検知して安全に見送る経路そのものは既に確認済み)、しかも SessionStart フックが nohup で
# 標準出力・標準エラーの両方を捨てて背景実行するため、その無進捗が利用者から完全に不可視だった。
# 討議の結論(前進性=排他/再試行は見送り・可視化のみを入れる)に従い、各ラウンドの結果を
# target 側(.claude/knowledge/.sync-log)に記録し、--status 経由で後から
# 確認できることを確認する。
ks506_ws="$(mktemp -d)"; ks506_src="$ks506_ws/src"; ks506_cache_home="$ks506_ws/cache"; ks506_cache="${ks506_cache_home}/yosage-dev-harness/knowledge"; ks506_proj="$ks506_ws/proj"
mkdir -p "$ks506_src/knowledge/api" "$ks506_proj"
printf '# INDEX\n' > "$ks506_src/knowledge/INDEX.md"
printf -- '---\nid: gid-1\ndate: 2026-01-01\ndomain: api\nscope: global\nstatus: active\nsummary: v1\n---\nbody v1\n' \
  > "$ks506_src/knowledge/api/2026-01-01-gid-1.md"
( cd "$ks506_src" && git init -q && git checkout -q -b main && gitc add -A && gitc commit -qm v1 )
mk_consumer "$ks506_proj"
printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ks506_src" > "$ks506_proj/.claude/yosage-dev-harness.local.json"

# 初回同期: outcome=progressed が1行だけ記録される。
bash "$H/lib/knowledge-sync.sh" "$ks506_proj" "$ks506_cache" >/dev/null 2>&1
ks506_log1="$(cat "$ks506_proj/.claude/knowledge/.sync-log" 2>/dev/null)"
out_has "無進捗可視化: 初回同期は outcome=progressed を記録" "outcome=progressed" "$ks506_log1"
if [ "$(printf '%s\n' "$ks506_log1" | wc -l | tr -d ' ')" = "1" ]; then
  ok "無進捗可視化: 初回同期の記録は1行"
else
  ng "無進捗可視化: 初回同期の記録は1行(実際: $(printf '%s\n' "$ks506_log1" | wc -l | tr -d ' ')行)"
fi

# 2回目(変更なし): outcome=up-to-date が追記される。
bash "$H/lib/knowledge-sync.sh" "$ks506_proj" "$ks506_cache" >/dev/null 2>&1
ks506_log2_last="$(tail -n1 "$ks506_proj/.claude/knowledge/.sync-log" 2>/dev/null)"
out_has "無進捗可視化: 変更なしの2回目は outcome=up-to-date" "outcome=up-to-date" "$ks506_log2_last"

# .sync-log は他の sync 由来生成物と同じく git 管理外(導入先自身の .gitignore にこの行が
# あれば、の形で確かめる。上と同じ理由)。
printf 'knowledge/.sync-log
' > "$ks506_proj/.claude/.gitignore"
( cd "$ks506_proj" && git init -q && git checkout -q -b main && gitc add -A 2>/dev/null )
ks506_gitst="$(cd "$ks506_proj" && git status --porcelain 2>/dev/null)"
out_hasnt "無進捗可視化: .sync-log は git 管理外" ".sync-log" "$ks506_gitst"

# 退避先(.global.old)が既に使用中である状況(の入替ガードと同じ前提再現。検証対象の
# ks_atomic_rename やこの PR の判定ロジックには一切触れず、その手前の掃除処理(1行)だけを
# 一時コピー上で無効化して、通常の単発呼び出しでは自然発生しない「退避先が埋まっている」
# 状態を確定的に作る)を経て、この PR の判定ロジック(実際の・改変していない箇所)が
# outcome=no-progress を記録することを確認する。
ks506_cleanup_target='    [ -e "$dest/knowledge/global" ] && rm -rf "$ks_old"'
ks506_cleanup_count="$(grep -Fc "$ks506_cleanup_target" "$ROOT/harness/lib/knowledge-sync.sh")"
if [ "$ks506_cleanup_count" = "1" ]; then
  ks506_fixture_payload="$(_src_copy)"
  python3 - "$ks506_fixture_payload/harness/lib/knowledge-sync.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = '    [ -e "$dest/knowledge/global" ] && rm -rf "$ks_old"\n'
new = '    : # FIXTURE: skip pre-swap old cleanup so a pre-seeded .global.old survives to swap-time\n'
assert s.count(old) == 1
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
  ks506_contend_ws="$(mktemp -d)"; ks506_contend_proj="$ks506_contend_ws/proj"; ks506_contend_cache_home="$ks506_contend_ws/cache"; ks506_contend_cache="${ks506_contend_cache_home}/yosage-dev-harness/knowledge"
  mkdir -p "$ks506_contend_proj/.claude/knowledge/global/api" "$ks506_contend_cache/knowledge/api"
  printf -- '---\nid: gid-1\ndomain: api\nsummary: current\n---\nbody current\n' > "$ks506_contend_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md"
  mkdir -p "$ks506_contend_proj/.claude/knowledge/.global.old/marker-dir"
  printf 'PRE-EXISTING-OLD-MARKER\n' > "$ks506_contend_proj/.claude/knowledge/.global.old/marker-dir/x.txt"
  printf -- '---\nid: gid-1\ndomain: api\nsummary: incoming\n---\nbody incoming\n' > "$ks506_contend_cache/knowledge/api/2026-01-01-gid-1.md"
  # cache 側に実コミットを作る(sync_stamp は `git log -1` の結果なので、コミットが無い
  # と空になり、この PR の進捗判定〈$sync_stamp が空でないことが前提〉が丸ごと skip
  # される。既存の入替ガード fixture は判定を持たないため commit 無しでも成立するが、
  # 本ブロックはそのままでは成立しない)。
  ( cd "$ks506_contend_cache" && git init -q && gitc add -A && gitc commit -qm incoming ) >/dev/null 2>&1
  printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ks506_contend_cache" > "$ks506_contend_proj/.claude/yosage-dev-harness.local.json"
  bash "$ks506_fixture_payload/harness/lib/knowledge-sync.sh" "$ks506_contend_proj" "$ks506_contend_cache" >/dev/null 2>&1
  out_has "無進捗可視化: 退避競合ラウンドは outcome=no-progress を記録" "outcome=no-progress" \
    "$(cat "$ks506_contend_proj/.claude/knowledge/.sync-log" 2>/dev/null)"
  ks506_contend_status="$(bash "$ks506_fixture_payload/harness/lib/knowledge-sync.sh" --status "$ks506_contend_proj" "$ks506_contend_cache" 2>&1)"
  out_has "無進捗可視化: --status に直近の同期試行を表示" "直近の同期試行" "$ks506_contend_status"
  out_has "無進捗可視化: --status が連続無進捗を警告" "連続で同期が前進していません" "$ks506_contend_status"

  # 自己修復: 同じ target/cache に対して(今度は無改変の本体で)通常どおり同期すると追いつき、
  # 警告が消える(次のラウンドが安全に前進できることは既に確認済み。ここでは
  # その前進が「可視化ログの側にも」正しく反映されることを確認する)。
  bash "$ROOT/harness/lib/knowledge-sync.sh" "$ks506_contend_proj" "$ks506_contend_cache" >/dev/null 2>&1
  out_has "無進捗可視化(自己修復): 追いついた後は outcome=progressed" "outcome=progressed" \
    "$(tail -n1 "$ks506_contend_proj/.claude/knowledge/.sync-log" 2>/dev/null)"
  ks506_healed_status="$(bash "$ROOT/harness/lib/knowledge-sync.sh" --status "$ks506_contend_proj" "$ks506_contend_cache" 2>&1)"
  out_hasnt "無進捗可視化(自己修復): 追いついた後は警告が消える" "連続で同期が前進していません" "$ks506_healed_status"

  # 破壊試験: この PR が足した判定ロジック(このラウンドで実際に retire/swap を試みて
  # 失敗したかを表す独立フラグ ks_swap_failed による優先判定)そのものを無効化し、
  # 常に「進捗した」と誤判定させる。上と同じ退避競合の前提(fixture の掃除無効化のみ)を
  # 再現しつつ、判定ロジックだけ追加で壊した版で走らせ、live な global/ の中身は変化して
  # いない(=実際には前進していない)のに outcome=progressed と記録されてしまう
  # (検証が実際に効いていることの確認: 正しい実装ならここで no-progress と記録される)。
  ks506_mut_target='    if [ "$ks_swap_failed" = 1 ]; then'
  ks506_mut_count="$(grep -Fc "$ks506_mut_target" "$ROOT/harness/lib/knowledge-sync.sh")"
  if [ "$ks506_mut_count" = "1" ]; then
    ks506_mut_payload="$(_src_copy)"
    python3 - "$ks506_mut_payload/harness/lib/knowledge-sync.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old1 = '    [ -e "$dest/knowledge/global" ] && rm -rf "$ks_old"\n'
new1 = '    : # FIXTURE: skip pre-swap old cleanup so a pre-seeded .global.old survives to swap-time\n'
assert s.count(old1) == 1
s = s.replace(old1, new1, 1)
old2 = '    if [ "$ks_swap_failed" = 1 ]; then\n'
new2 = '    if false; then # MUTATED: disable the swap-failure override, fall back to stamp-only comparison\n'
assert s.count(old2) == 1
s = s.replace(old2, new2, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
    ks506_mut_ws="$(mktemp -d)"; ks506_mut_proj="$ks506_mut_ws/proj"; ks506_mut_cache_home="$ks506_mut_ws/cache"; ks506_mut_cache="${ks506_mut_cache_home}/yosage-dev-harness/knowledge"
    mkdir -p "$ks506_mut_proj/.claude/knowledge/global/api" "$ks506_mut_cache/knowledge/api"
    printf -- '---\nid: gid-1\ndomain: api\nsummary: current\n---\nbody current\n' > "$ks506_mut_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md"
    mkdir -p "$ks506_mut_proj/.claude/knowledge/.global.old/marker-dir"
    printf 'PRE-EXISTING-OLD-MARKER\n' > "$ks506_mut_proj/.claude/knowledge/.global.old/marker-dir/x.txt"
    printf -- '---\nid: gid-1\ndomain: api\nsummary: incoming\n---\nbody incoming\n' > "$ks506_mut_cache/knowledge/api/2026-01-01-gid-1.md"
    ( cd "$ks506_mut_cache" && git init -q && gitc add -A && gitc commit -qm incoming ) >/dev/null 2>&1
    printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ks506_mut_cache" > "$ks506_mut_proj/.claude/yosage-dev-harness.local.json"
    bash "$ks506_mut_payload/harness/lib/knowledge-sync.sh" "$ks506_mut_proj" "$ks506_mut_cache" >/dev/null 2>&1
    ks506_mut_live="$(cat "$ks506_mut_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md" 2>/dev/null)"
    ks506_mut_log="$(cat "$ks506_mut_proj/.claude/knowledge/.sync-log" 2>/dev/null)"
    if printf '%s' "$ks506_mut_log" | grep -q "outcome=progressed" && printf '%s' "$ks506_mut_live" | grep -q "body current"; then
      ok "無進捗可視化(破壊試験): 判定ロジックを外すと実際は前進していないのに outcome=progressed と誤記録される(検証が実際に効いている確認)"
    else
      ng "無進捗可視化(破壊試験): 想定した壊れ方が再現しない(検証の前提が崩れている疑い)"
    fi
    rm -rf "$ks506_mut_ws" "$ks506_mut_payload"
  else
    ng "無進捗可視化(破壊試験): 壊す対象のパターンが本体に見つからない(件数=$ks506_mut_count。事前確認に失敗)"
  fi

  # 定常状態での退避競合(一次レビュー指摘2件目の再現): target がラウンド開始時点で既に
  # sync_stamp に追いついていた(.global-sync が既に sync_stamp と一致)状態でも、このラウンドで
  # 実際に retire/swap を試み、競合により失敗した場合は outcome=up-to-date ではなく
  # outcome=no-progress と記録されなければならない(旧実装はここを取りこぼしていた)。
  # 上と同じ fixture(pre-swap cleanup 無効化)を使い、事前に .global-sync を sync_stamp と
  # 一致させておくことで「定常状態」を確定的に再現する。
  ks506_steady_ws="$(mktemp -d)"; ks506_steady_proj="$ks506_steady_ws/proj"; ks506_steady_cache_home="$ks506_steady_ws/cache"; ks506_steady_cache="${ks506_steady_cache_home}/yosage-dev-harness/knowledge"
  mkdir -p "$ks506_steady_proj/.claude/knowledge/global/api" "$ks506_steady_cache/knowledge/api"
  printf -- '---\nid: gid-1\ndomain: api\nsummary: current\n---\nbody current\n' > "$ks506_steady_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md"
  printf -- '---\nid: gid-1\ndomain: api\nsummary: current\n---\nbody current\n' > "$ks506_steady_cache/knowledge/api/2026-01-01-gid-1.md"
  ( cd "$ks506_steady_cache" && git init -q && gitc add -A && gitc commit -qm steady ) >/dev/null 2>&1
  printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ks506_steady_cache" > "$ks506_steady_proj/.claude/yosage-dev-harness.local.json"
  ks506_steady_stamp="$(cd "$ks506_steady_cache" && git log -1 --format='%H %cI')"
  printf '%s\n' "$ks506_steady_stamp" > "$ks506_steady_proj/.claude/knowledge/.global-sync"   # 事前に「既に最新」を模す
  mkdir -p "$ks506_steady_proj/.claude/knowledge/.global.old/marker-dir"
  printf 'PRE-EXISTING-OLD-MARKER\n' > "$ks506_steady_proj/.claude/knowledge/.global.old/marker-dir/x.txt"
  ks506_steady_out="$(bash "$ks506_fixture_payload/harness/lib/knowledge-sync.sh" "$ks506_steady_proj" "$ks506_steady_cache" 2>&1)"
  out_has "無進捗可視化(定常状態): 退避失敗のログが実際に出る(前提の確認)" "退避に失敗" "$ks506_steady_out"
  out_has "無進捗可視化(定常状態): 追いついた後の競合も outcome=no-progress と記録される(up-to-date に誤分類しない)" "outcome=no-progress" \
    "$(tail -n1 "$ks506_steady_proj/.claude/knowledge/.sync-log" 2>/dev/null)"

  # 破壊試験: 上と同じ ks_swap_failed の優先判定を無効化すると、この定常状態での競合が
  # outcome=up-to-date と誤記録されるようになる(一次レビューが実際に再現した欠陥そのものの再現)。
  ks506_steady_mut_count="$(grep -Fc "$ks506_mut_target" "$ROOT/harness/lib/knowledge-sync.sh")"
  if [ "$ks506_steady_mut_count" = "1" ]; then
    ks506_steady_mut_payload="$(_src_copy)"
    python3 - "$ks506_steady_mut_payload/harness/lib/knowledge-sync.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old1 = '    [ -e "$dest/knowledge/global" ] && rm -rf "$ks_old"\n'
new1 = '    : # FIXTURE(regression): skip pre-swap old cleanup so a pre-seeded .global.old survives to swap-time\n'
assert s.count(old1) == 1
s = s.replace(old1, new1, 1)
old2 = '    if [ "$ks_swap_failed" = 1 ]; then\n'
new2 = '    if false; then # MUTATED(regression): disable the swap-failure override, fall back to stamp-only comparison\n'
assert s.count(old2) == 1
s = s.replace(old2, new2, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
    ks506_steady_mut_ws="$(mktemp -d)"; ks506_steady_mut_proj="$ks506_steady_mut_ws/proj"; ks506_steady_mut_cache_home="$ks506_steady_mut_ws/cache"; ks506_steady_mut_cache="${ks506_steady_mut_cache_home}/yosage-dev-harness/knowledge"
    mkdir -p "$ks506_steady_mut_proj/.claude/knowledge/global/api" "$ks506_steady_mut_cache/knowledge/api"
    printf -- '---\nid: gid-1\ndomain: api\nsummary: current\n---\nbody current\n' > "$ks506_steady_mut_proj/.claude/knowledge/global/api/2026-01-01-gid-1.md"
    printf -- '---\nid: gid-1\ndomain: api\nsummary: current\n---\nbody current\n' > "$ks506_steady_mut_cache/knowledge/api/2026-01-01-gid-1.md"
    ( cd "$ks506_steady_mut_cache" && git init -q && gitc add -A && gitc commit -qm steady ) >/dev/null 2>&1
    printf '{ "knowledge": { "enabled": true, "source": "%s", "ref": "main" } }\n' "$ks506_steady_mut_cache" > "$ks506_steady_mut_proj/.claude/yosage-dev-harness.local.json"
    ks506_steady_mut_stamp="$(cd "$ks506_steady_mut_cache" && git log -1 --format='%H %cI')"
    printf '%s\n' "$ks506_steady_mut_stamp" > "$ks506_steady_mut_proj/.claude/knowledge/.global-sync"
    mkdir -p "$ks506_steady_mut_proj/.claude/knowledge/.global.old/marker-dir"
    printf 'PRE-EXISTING-OLD-MARKER\n' > "$ks506_steady_mut_proj/.claude/knowledge/.global.old/marker-dir/x.txt"
    ks506_steady_mut_out="$(bash "$ks506_steady_mut_payload/harness/lib/knowledge-sync.sh" "$ks506_steady_mut_proj" "$ks506_steady_mut_cache" 2>&1)"
    ks506_steady_mut_last="$(tail -n1 "$ks506_steady_mut_proj/.claude/knowledge/.sync-log" 2>/dev/null)"
    if printf '%s' "$ks506_steady_mut_out" | grep -q "退避に失敗" && printf '%s' "$ks506_steady_mut_last" | grep -q "outcome=up-to-date"; then
      ok "無進捗可視化(定常状態・破壊試験): 優先判定を外すと退避失敗ラウンドが outcome=up-to-date と誤記録される(検証が実際に効いている確認・一次レビュー欠陥の再現)"
    else
      ng "無進捗可視化(定常状態・破壊試験): 想定した壊れ方が再現しない(検証の前提が崩れている疑い)"
    fi
    rm -rf "$ks506_steady_mut_ws" "$ks506_steady_mut_payload"
  else
    ng "無進捗可視化(定常状態・破壊試験): 壊す対象のパターンが本体に見つからない(件数=$ks506_steady_mut_count。事前確認に失敗)"
  fi
  rm -rf "$ks506_steady_ws"

  rm -rf "$ks506_contend_ws" "$ks506_fixture_payload"
else
  ng "無進捗可視化: 壊す対象のパターンが本体に見つからない(cleanup=$ks506_cleanup_count。事前確認に失敗)"
fi
rm -rf "$ks506_ws"

echo "== knowledge-index フック(ローカル索引は廃止: エントリ変更でも INDEX.md を作らない) =="
t="$(mktemp -d)"; mk_consumer "$t"
mkdir -p "$t/.claude/knowledge/api"
printf -- '---\nid: hooktest\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: フック確認\n---\n' > "$t/.claude/knowledge/api/2026-01-01-hooktest.md"
json_file "$t/.claude/knowledge/api/2026-01-01-hooktest.md" "$t" | CLAUDE_PROJECT_DIR="$t" bash "$H/hooks/knowledge-index.sh" >/dev/null 2>&1
file_isnt "hook: エントリ変更でも .claude/knowledge/INDEX.md は作られない(ローカル索引は廃止)" "$t/.claude/knowledge/INDEX.md"
mkdir -p "$t/.claude/knowledge/global/api"; printf 'g\n' > "$t/.claude/knowledge/global/api/g.md"
json_file "$t/.claude/knowledge/global/api/g.md" "$t" | CLAUDE_PROJECT_DIR="$t" bash "$H/hooks/knowledge-index.sh" >/dev/null 2>&1
file_isnt "hook: global の編集でも INDEX.md は作られない" "$t/.claude/knowledge/INDEX.md"
printf '# keep2\n' > "$t/.claude/knowledge/INDEX.md"   # 手元に既に在る場合でもフックは触らない(再帰しない)ことの確認
json_file "$t/.claude/knowledge/INDEX.md" "$t" | CLAUDE_PROJECT_DIR="$t" bash "$H/hooks/knowledge-index.sh" >/dev/null 2>&1
out_has "hook: INDEX.md 自身の編集は無反応(既存のファイルにも触らない)" "keep2" "$(cat "$t/.claude/knowledge/INDEX.md" 2>/dev/null)"
rm -rf "$t"

echo "== knowledge-index フック(ネストしたメンバー repo: \$file から repo ルートを導出し、CLAUDE_PROJECT_DIR/.cwd の誤誘導に流されない) =="
ws="$(mktemp -d)"; member="$ws/member"; mkdir -p "$member"
mk_consumer "$ws"
mk_consumer "$member"
mkdir -p "$member/.claude/knowledge/api"
# proj が member(正)/ws(誤)のどちらを掴んだかは、INDEX 再生成(廃止済み)ではなく、監査対象の
# 基点が正しいかどうかで判定する: bare-issue-ref を仕込み、member を正しく基点にできれば
# systemMessage に現れ、誤って ws を基点にすれば member 配下のエントリは ws/.claude/knowledge
# 直下には無いため監査が何も見つけられず無反応になる(=誤誘導されたことが無出力で判る)。
printf -- '---\nid: nestedtest\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: ネスト確認\n---\nissue '"$HSH"'741 with no repo.\n' > "$member/.claude/knowledge/api/2026-01-01-nestedtest.md"
# CLAUDE_PROJECT_DIR も .cwd もワークスペースのルート($ws)を指す。実セッションでワークスペース
# 直下を開いたまま member 配下のエントリを編集した状況を再現する。
out_nested="$(json_file "$member/.claude/knowledge/api/2026-01-01-nestedtest.md" "$ws" | CLAUDE_PROJECT_DIR="$ws" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_has   "hook: 編集された member repo 自身が監査の基点になる(proj=member を掴む)" "bare-issue-ref" "$out_nested"
file_isnt "hook: member 側にも INDEX.md は作られない(ローカル索引は廃止)" "$member/.claude/knowledge/INDEX.md"
rm -rf "$ws"

echo "== knowledge-index フック(パスに \`/.claude/knowledge/\` が複数回出現しても最も内側=所有 repo を掴む)(一次レビュー) =="
outer="$(mktemp -d)"; inner="$outer/.claude/knowledge/mirror"; mkdir -p "$inner"
mk_consumer "$outer"
mk_consumer "$inner"
mkdir -p "$inner/.claude/knowledge/process"
# $file = $outer/.claude/knowledge/mirror/.claude/knowledge/process/2026-01-01-innertest.md には
# `/.claude/knowledge/` が2回現れる。最短サフィックス除去(%)なら最後の出現(=$inner)から切れて
# 所有 repo($inner)を掴む。最長サフィックス除去(%%)だと最初の出現(=$outer)から切れて誤射する。
# 判定は上と同じくbare-issue-refの有無で行う(INDEX再生成は廃止済み)。
printf -- '---\nid: innertest\ndate: 2026-01-01\ndomain: process\ntags: []\nscope: local\nstatus: active\nsummary: 入れ子確認\n---\nissue '"$HSH"'742 with no repo.\n' > "$inner/.claude/knowledge/process/2026-01-01-innertest.md"
out_inner="$(json_file "$inner/.claude/knowledge/process/2026-01-01-innertest.md" "$outer" | CLAUDE_PROJECT_DIR="$outer" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_has "hook: 複数出現時、最も内側(所有 repo=inner)が監査の基点になる" "bare-issue-ref" "$out_inner"
file_isnt "hook: inner 側にも INDEX.md は作られない(ローカル索引は廃止)" "$inner/.claude/knowledge/INDEX.md"
rm -rf "$outer"

echo "== knowledge-index フック(生成器が失敗したら systemMessage と additionalContext で可視化する) =="
t2="$(mktemp -d)"; mk_consumer "$t2"
# resolve_lib() は自分の位置(hook 自身が属する lib/)からしか見つけないため、実体
# ($H/hooks・$H/lib)を直接壊すわけにはいかない。相対関係を保ったままスクラッチへコピーし、
# コピー側の生成器だけを壊れた版に差し替えて、コピーされた hook を叩く。
t2scratch="$(mktemp -d)"; _mk_ki_scratch_hooks "${t2scratch}"
mkdir -p "$t2/.claude/knowledge/api"
printf -- '---\nid: failtest\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 失敗確認\n---\n' > "$t2/.claude/knowledge/api/2026-01-01-failtest.md"
# 生成器が失敗する状況を模す(壊れた生成器に差し替え)。systemMessage はユーザーにのみ表示され
# Claude には届かないため、Claude 自身に再生成をやり直させるには hookSpecificOutput.additionalContext
# も合わせて返す必要がある。
printf '#!/usr/bin/env bash\necho "boom" >&2\nexit 1\n' > "$t2scratch/lib/knowledge-index.sh"
out_fail="$(json_file "$t2/.claude/knowledge/api/2026-01-01-failtest.md" "$t2" | CLAUDE_PROJECT_DIR="$t2" bash "$t2scratch/hooks/knowledge-index.sh" 2>/dev/null)"
out_has "hook: 生成器失敗を systemMessage で可視化する" "systemMessage" "$out_fail"
out_has "hook: systemMessage に生成器のエラー内容を含める" "boom" "$out_fail"
out_has "hook: additionalContext(hookSpecificOutput)を返す" "additionalContext" "$out_fail"
out_fail_ctx="$(printf '%s' "$out_fail" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("hookSpecificOutput",{}).get("additionalContext",""))' 2>/dev/null)"
out_has "hook: additionalContext に生成器の stderr を含める" "boom" "$out_fail_ctx"
rm -rf "$t2" "$t2scratch"

echo "== knowledge-index フック(生成器が exit 0 で警告(stderr非空)を出しても『失敗』と誤報告しない) =="
t2w="$(mktemp -d)"; mk_consumer "$t2w"
mkdir -p "$t2w/.claude/knowledge/api"
# 編集エントリ: summary が壊れている(YAML ブロックスカラー) → 生成器は exit 0 で警告を stderr に出す
printf -- '---\nid: edited\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: >\n  broken\n---\n' \
  > "$t2w/.claude/knowledge/api/2026-01-01-edited.md"
# 他エントリ: 同じく壊れているが、今回の PostToolUse では編集していない → 警告に出てはいけない
printf -- '---\nid: other\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: >\n  broken2\n---\n' \
  > "$t2w/.claude/knowledge/api/2026-01-01-other.md"
out_warn="$(json_file "$t2w/.claude/knowledge/api/2026-01-01-edited.md" "$t2w" | CLAUDE_PROJECT_DIR="$t2w" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_hasnt "hook: rc=0 の警告を『再生成に失敗しました』と誤報告しない" "再生成に失敗しました" "$out_warn"
out_has   "hook: rc=0 の警告は systemMessage で可視化する" "systemMessage" "$out_warn"
out_has   "hook: 警告に編集エントリ自身のファイル名を含める" "2026-01-01-edited.md" "$out_warn"
out_hasnt "hook: 編集していない他エントリの警告は出さない" "2026-01-01-other.md" "$out_warn"
file_isnt "hook: rc=0 の警告時にも INDEX.md は作られない(ローカル索引は廃止)" "$t2w/.claude/knowledge/INDEX.md"
# クリーンな編集(壊れた summary なし)では無反応(ノイズ0)
printf -- '---\nid: edited\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 正常なsummary\n---\n' \
  > "$t2w/.claude/knowledge/api/2026-01-01-edited.md"
out_clean_warn="$(json_file "$t2w/.claude/knowledge/api/2026-01-01-edited.md" "$t2w" | CLAUDE_PROJECT_DIR="$t2w" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_hasnt "hook: 壊れた summary が無いクリーンな編集では無出力(ノイズ0)" "systemMessage" "$out_clean_warn"
rm -rf "$t2w"

echo "== knowledge-index フック(basename が部分文字列関係でも他エントリの警告が漏れない)(一次レビュー) =="
t2sub="$(mktemp -d)"; mk_consumer "$t2sub"
mkdir -p "$t2sub/.claude/knowledge/api"
# 編集エントリの basename(notes.md)が、未編集エントリの basename(important-notes.md)の部分文字列。
# 両方とも summary が壊れている。編集は notes.md のみ。
printf -- '---\nid: notes\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: >\n  broken\n---\n' \
  > "$t2sub/.claude/knowledge/api/notes.md"
printf -- '---\nid: important-notes\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: >\n  broken2\n---\n' \
  > "$t2sub/.claude/knowledge/api/important-notes.md"
out_sub="$(json_file "$t2sub/.claude/knowledge/api/notes.md" "$t2sub" | CLAUDE_PROJECT_DIR="$t2sub" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
# "notes.md" は "important-notes.md" の部分文字列なので、out_has だけでは漏洩時も偽陽性で
# 合格してしまう。生成器の stderr 行の固定書式(`knowledge-index: <basename>: `)まで含めた
# 完全な部分文字列で照合し、"notes.md" 単体の緩い一致にしない。
out_has   "hook: 編集した notes.md の警告は出る" "knowledge-index: notes.md:" "$out_sub"
out_hasnt "hook: basename が部分文字列関係でも未編集 important-notes.md の警告は漏れない" "important-notes.md" "$out_sub"
rm -rf "$t2sub"

echo "== knowledge-index フック: 監査経由の欠陥(tags欠落)は systemMessage に出る =="
tovd="$(mktemp -d)"; mk_consumer "$tovd"
mkdir -p "$tovd/.claude/knowledge/api"
printf -- '---\nid: defaudit\ndate: 2026-01-01\ndomain: api\nscope: local\nstatus: active\nsummary: 監査確認\n---\n' > "$tovd/.claude/knowledge/api/2026-01-01-defaudit.md"
out_ovd="$(json_file "$tovd/.claude/knowledge/api/2026-01-01-defaudit.md" "$tovd" | CLAUDE_PROJECT_DIR="$tovd" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_has "hook: 同じ欠陥(tags欠落)は監査経由で systemMessage に出る" "systemMessage" "$out_ovd"
out_has "hook: frontmatter-missing-field として報告される" "frontmatter-missing-field" "$out_ovd"
rm -rf "$tovd"

echo "== knowledge-index フック: 監査だけが検出する欠陥(domain 不一致)も検出される =="
tovdm="$(mktemp -d)"; mk_consumer "$tovdm"
mkdir -p "$tovdm/.claude/knowledge/api"
printf -- '---\nid: ovdmismatch\ndate: 2026-01-01\ndomain: wrong-domain\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n' > "$tovdm/.claude/knowledge/api/2026-01-01-ovdmismatch.md"
out_ovdm="$(json_file "$tovdm/.claude/knowledge/api/2026-01-01-ovdmismatch.md" "$tovdm" | CLAUDE_PROJECT_DIR="$tovdm" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_has "hook: domain 不一致が systemMessage で報告される" "domain-mismatch" "$out_ovdm"
rm -rf "$tovdm"

echo "== knowledge-audit.sh: 実在する構造的欠陥(domain不一致・dangling-link)を検出し、正しいエントリは誤検知しない =="
tka="$(mktemp -d)"; mk_consumer "$tka"
mkdir -p "$tka/.claude/knowledge/api" "$tka/.claude/knowledge/global/api"
# グローバルミラー(global/)を同期済み扱いにする(1件でも置けば global_present=true になり、
# 未解決の [[...]] を「未 sync のため判定不能」ではなく本当の dangling として判定できる)。
printf -- '---\nid: kaov-global-anchor\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\nanchor\n' > "$tka/.claude/knowledge/global/api/2026-01-01-kaov-global-anchor.md"
# 実在する構造的欠陥(domain 不一致 + dangling-link)を含むエントリ
printf -- '---\nid: kaov-bad\ndate: 2026-01-01\ndomain: wrong-dom\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nSee [[kaov-missing-target]].\n' > "$tka/.claude/knowledge/api/2026-01-01-kaov-bad.md"
# 偽陽性対照: 実在する内部パス参照(論理パス。使用中の版のプラグインに実在するファイル)を
# 含む、構造的に正しいエントリ
printf -- '---\nid: kaov-good\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `yosage-dev-harness:lib/knowledge-audit.sh`(実在)\n' > "$tka/.claude/knowledge/api/2026-01-01-kaov-good.md"
ka_ov_out="$(bash "$H/lib/knowledge-audit.sh" "$tka/.claude" 2>/dev/null)"
ka_ov_stderr="$(bash "$H/lib/knowledge-audit.sh" "$tka/.claude" 2>&1 1>/dev/null)"
out_has "knowledge-audit.sh: 走査件数が0件ではない(偽クリーンでないことを確認)" "project-local エントリを 2 件走査し" "$ka_ov_stderr"
if ka_has "knowledge/api/2026-01-01-kaov-bad.md" "domain-mismatch" "$ka_ov_out"; then ok "knowledge-audit.sh: domain 不一致を検出"; else ng "knowledge-audit.sh: domain 不一致を検出"; fi
if ka_has "knowledge/api/2026-01-01-kaov-bad.md" "dangling-link" "$ka_ov_out"; then ok "knowledge-audit.sh: dangling [[...]] を検出"; else ng "knowledge-audit.sh: dangling [[...]] を検出"; fi
out_hasnt "knowledge-audit.sh: 正しいエントリ(kaov-good)は誤検知しない" "kaov-good" "$ka_ov_out"
rm -rf "$tka"

echo "== knowledge-audit.sh: 第2引数(旧 <knowledge-dir>)を渡すと使い方を表示して exit 2(黙って無視しない) =="
tka2="$(mktemp -d)"; mk_consumer "$tka2"
tka2_out="$(bash "$H/lib/knowledge-audit.sh" "$tka2/.claude" "$tka2/.claude/knowledge" 2>&1)"; tka2_rc=$?
exit_is "knowledge-audit.sh: 第2引数を渡すと exit 2" 2 "$tka2_rc"
out_has "knowledge-audit.sh: 使い方を案内する" "使い方" "$tka2_out"
rm -rf "$tka2"

echo "== knowledge-index 生成(frontmatter→INDEX) =="
ki="$(mktemp -d)"; mkdir -p "$ki/api" "$ki/global"
printf -- '---\nid: e1\ndate: 2026-01-01\ndomain: api\ntags: [a, b]\nscope: local\nstatus: active\nsummary: 要約X\n---\n# body\n' > "$ki/api/2026-01-01-e1.md"
printf -- '---\nid: draft\nsummary: d\n---\n' > "$ki/api/_draft.md"        # _* は除外
printf -- '---\nid: gx\nsummary: g\n---\n' > "$ki/global/2026-01-01-g.md"  # global は除外
printf -- '---\nid: e2\ndate: 2026-01-02\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: a | b\n---\n' > "$ki/api/2026-01-02-e2.md"  # パイプ・空tags
bash "$ROOT/harness/lib/knowledge-index.sh" "$ki" >/dev/null 2>&1
file_is   "INDEX.md 生成"     "$ki/INDEX.md"
out_has   "summary が入る"    "要約X" "$(cat "$ki/INDEX.md" 2>/dev/null)"
out_has   "tags がカンマ結合" "a,b"   "$(cat "$ki/INDEX.md" 2>/dev/null)"
out_hasnt "global/ は除外"    "gx"    "$(cat "$ki/INDEX.md" 2>/dev/null)"
out_hasnt "_* 雛形は除外"     "draft" "$(cat "$ki/INDEX.md" 2>/dev/null)"
out_has   "summary のパイプを / に置換" "a / b" "$(cat "$ki/INDEX.md" 2>/dev/null)"
out_has   "空 tags でも行が出る"        "e2"    "$(cat "$ki/INDEX.md" 2>/dev/null)"
rm -rf "$ki"

echo "== knowledge-index: id 省略時はファイル名 slug から導出する =="
ki="$(mktemp -d)"; mkdir -p "$ki/api"
printf -- '---\nid: e1\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 要約X\n---\n' > "$ki/api/2026-01-01-e1.md"
printf -- '---\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: id無し\n---\n' > "$ki/api/2026-01-01-noid.md"
printf -- '---\nid: explicit-id\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 明示id優先\n---\n' > "$ki/api/2026-01-01-filename-slug.md"
printf -- '---\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 日付無しファイル名\n---\n' > "$ki/api/foo-bar.md"
printf -- '---\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 日付直後が空\n---\n' > "$ki/api/2026-07-08-.md"
err="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$ki" 2>&1 1>/dev/null)"; rc=$?
idx="$(cat "$ki/INDEX.md" 2>/dev/null)"
exit_is "id 欠落があっても exit 0" 0 "$rc"
out_hasnt "stderr に警告を出さない(診断機能に委譲)" "warning" "$err"
out_has   "id 欠落エントリは導出 id(noid)で INDEX に載る" "| noid |" "$idx"
out_has   "明示 id は導出(filename-slug)より優先される" "| explicit-id |" "$idx"
out_hasnt "導出より優先されるので導出値では載らない" "| filename-slug |" "$idx"
out_has   "日付プレフィックス無しは basename 全体が slug(foo-bar)" "| foo-bar |" "$idx"
out_has   "日付直後が空でも実効 id は空文字にならず stem 全体に倒す" "| 2026-07-08- |" "$idx"
out_hasnt "INDEX の第1列が空の行を生まない" "|  | api |" "$idx"
out_has   "INDEX には他の正常エントリも載る" "要約X" "$idx"
rm -rf "$ki"

echo "== knowledge-index: status で 3-way 振り分け(denylist方式。) =="
ki3="$(mktemp -d)"; mkdir -p "$ki3/api"
printf -- '---\nid: e-active\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 現行エントリ\n---\n' > "$ki3/api/2026-01-01-e-active.md"
printf -- '---\nid: e-superseded\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: superseded\nsummary: 旧版エントリ\n---\n' > "$ki3/api/2026-01-01-e-superseded.md"
printf -- '---\nid: e-archived\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: archived\nsummary: 退役エントリ\n---\n' > "$ki3/api/2026-01-01-e-archived.md"
printf -- '---\nid: e-nostatus\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nsummary: status欠落エントリ\n---\n' > "$ki3/api/2026-01-01-e-nostatus.md"
printf -- '---\nid: e-typo\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: actve\nsummary: statusタイポエントリ\n---\n' > "$ki3/api/2026-01-01-e-typo.md"
gen_out3="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$ki3" 2>/dev/null)"
idx3="$(cat "$ki3/INDEX.md" 2>/dev/null)"
arc3="$(cat "$ki3/INDEX.archive.md" 2>/dev/null)"
exit_is "生成器の stdout は2行(パス2つ)" 2 "$(printf '%s\n' "$gen_out3" | wc -l | tr -d ' ')"
out_has "stdout 1行目は INDEX.md のパス" "$ki3/INDEX.md" "$(printf '%s\n' "$gen_out3" | sed -n '1p')"
out_has "stdout 2行目は INDEX.archive.md のパス" "$ki3/INDEX.archive.md" "$(printf '%s\n' "$gen_out3" | sed -n '2p')"
file_is "INDEX.archive.md が生成される" "$ki3/INDEX.archive.md"
out_has   "active は INDEX.md に載る" "現行エントリ" "$idx3"
out_hasnt "superseded は INDEX.md から消える" "旧版エントリ" "$idx3"
out_hasnt "archived は INDEX.md から消える" "退役エントリ" "$idx3"
out_has   "superseded は INDEX.archive.md に載る" "旧版エントリ" "$arc3"
out_has   "archived は INDEX.archive.md に載る" "退役エントリ" "$arc3"
out_hasnt "active は INDEX.archive.md に載らない" "現行エントリ" "$arc3"
# denylist 方式の歯止め(ここが割れたら allowlist に退行している): status 欠落/未知の値を持つ
# エントリは「安全側デフォルト」の INDEX.md に残る。INDEX.archive.md にも漏れない。
out_has   "status 欠落エントリは INDEX.md に残る(denylistの歯止め)" "status欠落エントリ" "$idx3"
out_hasnt "status 欠落エントリは INDEX.archive.md に漏れない" "status欠落エントリ" "$arc3"
out_has   "status 未知値エントリは INDEX.md に残る(denylistの歯止め)" "statusタイポエントリ" "$idx3"
out_hasnt "status 未知値エントリは INDEX.archive.md に漏れない" "statusタイポエントリ" "$arc3"
out_has   "INDEX.md ヘッダに INDEX.archive.md への案内がある" "INDEX.archive.md" "$idx3"
out_has   "INDEX.archive.md ヘッダに現行外・active recallでは引かない旨の明記" "現行外" "$arc3"
rm -rf "$ki3"

echo "== knowledge-index: 現行外が0件でも INDEX.archive.md を空表で生成する =="
ki4="$(mktemp -d)"; mkdir -p "$ki4/api"
printf -- '---\nid: only-active\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 唯一のエントリ\n---\n' > "$ki4/api/2026-01-01-only-active.md"
bash "$ROOT/harness/lib/knowledge-index.sh" "$ki4" >/dev/null 2>&1
file_is "現行外0件でも INDEX.archive.md が生成される" "$ki4/INDEX.archive.md"
arc4="$(cat "$ki4/INDEX.archive.md" 2>/dev/null)"
out_hasnt "現行外0件なら本文に行が無い(ヘッダのみ)" "唯一のエントリ" "$arc4"
out_has   "現行外0件でもテーブルヘッダは出る" "| id | domain |" "$arc4"
rm -rf "$ki4"

echo "== knowledge-index --list/--list-archive: 索引ファイル無しでの直接列挙 =="
# 索引(INDEX.md/INDEX.archive.md)が一度も存在しない状態でも --list/--list-archive が
# 書き出しモードと同じ解析・フィルタ(active/archive の denylist 振り分け)を返すことを確認する。
# recall の主経路はこのコマンドであり、索引ファイルの有無に依存しないことがここでの契約。
# 一時ディレクトリ名に検査対象の id と同じ文字列を含める(--list の最終列はこの絶対パスになる)。
# id の検査は出力全体への部分一致ではなく id 列(1列目)の完全一致で行うため、パスに同名の文字列が
# (ここでは意図的に)入っても結果が変わらないことを、この fixture 自体が毎回確かめる。
kl_base="$(mktemp -d)"; kl="$kl_base/gx-draft-e-superseded-e-archived-e-active"
mkdir -p "$kl/api" "$kl/testing" "$kl/global" "$kl/_draft"
# --list/--list-archive の出力(TSV)から id 列(1列目)だけを取り出す道具。out_has/out_hasnt は部分一致なので、
# 改行で挟んだ id 列の塊に対し改行で挟んだ id を探せば id 列の行単位の完全一致になる(path 列等は見ない)。
NL=$'\n'
_ids_col() { printf '%s%s%s' "$NL" "$(printf '%s\n' "$1" | cut -f1)" "$NL"; }
_id_listed() { case "$(_ids_col "$2")" in *"${NL}$1${NL}"*) return 0;; *) return 1;; esac; }
printf -- '---\nid: e-active\ndate: 2026-01-01\ndomain: api\ntags: [a, b]\nscope: local\nstatus: active\nsummary: 現行API\n---\n' > "$kl/api/2026-01-01-e-active.md"
printf -- '---\nid: e-superseded\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: superseded\nsummary: 旧版API\n---\n' > "$kl/api/2026-01-01-e-superseded.md"
printf -- '---\nid: e-archived\ndate: 2026-01-01\ndomain: testing\ntags: []\nscope: local\nstatus: archived\nsummary: 退役testing\n---\n' > "$kl/testing/2026-01-01-e-archived.md"
printf -- '---\nid: e-test-active\ndate: 2026-01-02\ndomain: testing\ntags: []\nscope: local\nstatus: active\nsummary: 現行testing\n---\n' > "$kl/testing/2026-01-02-e-test-active.md"
printf -- '---\nid: gx\nsummary: グローバル(除外対象)\n---\n' > "$kl/global/2026-01-01-gx.md"
printf -- '---\nid: draft\nsummary: 雛形(除外対象)\n---\n' > "$kl/_draft/_template.md"
if [ -f "$kl/INDEX.md" ]; then ng "前提: この時点で INDEX.md は存在しない"; else ok "前提: この時点で INDEX.md は存在しない"; fi
list_out="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$kl" --list 2>/dev/null)"
list_arc_out="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$kl" --list-archive 2>/dev/null)"
list_ids="$(_ids_col "$list_out")${NL}"; list_arc_ids="$(_ids_col "$list_arc_out")${NL}"
if [ -f "$kl/INDEX.md" ] || [ -f "$kl/INDEX.archive.md" ]; then
  ng "--list/--list-archive は索引ファイルを書き出さない(副作用が無いはず)"
else
  ok "--list/--list-archive は索引ファイルを書き出さない(副作用が無いはず)"
fi
out_has   "--list: active エントリが列挙される(id列)"      "${NL}e-active${NL}"      "$list_ids"
out_has   "--list: 別 domain の active エントリも列挙される" "${NL}e-test-active${NL}" "$list_ids"
out_hasnt "--list: superseded は列挙されない"                "${NL}e-superseded${NL}"  "$list_ids"
out_hasnt "--list: archived は列挙されない"                  "${NL}e-archived${NL}"    "$list_ids"
out_hasnt "--list: global/ は除外される"                     "${NL}gx${NL}"            "$list_ids"
out_hasnt "--list: _* 雛形は除外される"                       "${NL}draft${NL}"         "$list_ids"
out_has   "--list: tags 列がカンマ結合で入る"                 "a,b"           "$list_out"
out_has   "--list: path 列に実在する絶対パスが入る(index 無しでも id→場所が引ける)" "$kl/api/2026-01-01-e-active.md" "$list_out"
out_has   "--list-archive: superseded が列挙される" "${NL}e-superseded${NL}" "$list_arc_ids"
out_has   "--list-archive: archived が列挙される"   "${NL}e-archived${NL}"   "$list_arc_ids"
out_hasnt "--list-archive: active は列挙されない"    "${NL}e-active${NL}"     "$list_arc_ids"
out_hasnt "--list-archive: 別 domain の active も列挙されない" "${NL}e-test-active${NL}" "$list_arc_ids"

# domain フィルタ(第3引数)
list_api_only="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$kl" --list api 2>/dev/null)"
list_api_ids="$(_ids_col "$list_api_only")${NL}"
out_has   "--list <domain>: 指定 domain のエントリは残る"     "${NL}e-active${NL}"      "$list_api_ids"
out_hasnt "--list <domain>: 他 domain のエントリは絞られる"   "${NL}e-test-active${NL}" "$list_api_ids"

# 陽性対照: 除外が壊れて global/ の id が id 列に出た場合は検出できる(道具が常に緑にならない)。
# 逆に、id 列以外(path 列)にだけ同じ文字列があっても検出しない(fixture のパスに gx を含む)。
_leak="$(printf 'gx\tglobal\t\t2026-01-01\tlocal\tactive\ts\t/p/x.md\n%s' "$list_out")"
if _id_listed gx "$_leak"; then ok "陽性対照: global/ の id が id 列に出れば検出される"; else ng "陽性対照: global/ の id が id 列に出れば検出される"; fi
if _id_listed gx "$list_out"; then ng "path 列にだけ id と同じ文字列がある場合は検出しない"; else ok "path 列にだけ id と同じ文字列がある場合は検出しない"; fi

# 等価性: 索引ファイル無しの --list が返す active id 集合は、同じフィクスチャで通常(書き出し)
# モードを実行して得られる INDEX.md の active id 集合と一致する(別の解析器を持たないので
# 構造的に一致するはずで、ここではそれを実データで裏取りする)。
bash "$ROOT/harness/lib/knowledge-index.sh" "$kl" >/dev/null 2>&1
written_idx="$(cat "$kl/INDEX.md" 2>/dev/null)"
out_has   "等価性: 書き出しモードの INDEX.md にも同じ active エントリが載る" "e-active"      "$written_idx"
out_has   "等価性: 書き出しモードの INDEX.md にも別 domain の active エントリが載る" "e-test-active" "$written_idx"
out_hasnt "等価性: 書き出しモードの INDEX.md にも superseded は載らない" "e-superseded" "$written_idx"
# 等価性(退役側・対称): --list-archive が返す現行外 id 集合も、同じフィクスチャで書き出した
# INDEX.archive.md の内容と一致する。現役側だけでなく退役側も対称に実データで裏取りする
# (両モードの結果が一致することこそがこの設計の要のため)。
written_arc="$(cat "$kl/INDEX.archive.md" 2>/dev/null)"
out_has   "等価性(退役側): 書き出しモードの INDEX.archive.md にも同じ superseded エントリが載る" "e-superseded" "$written_arc"
out_has   "等価性(退役側): 書き出しモードの INDEX.archive.md にも同じ archived エントリが載る"    "e-archived"   "$written_arc"
out_hasnt "等価性(退役側): 書き出しモードの INDEX.archive.md には active は載らない"              "e-active"     "$written_arc"
out_hasnt "等価性(退役側): 書き出しモードの INDEX.archive.md には別 domain の active も載らない"  "e-test-active" "$written_arc"
rm -rf "$kl_base"

echo "== knowledge-index --list: ディレクトリが解決できない場合は非ゼロ終了し『0件』と区別できる =="
# knowledge.md の受け入れ条件「列挙の失敗を0件と誤認しない」の土台。ここでは knowledge-index.sh 自体の
# 既存挙動(不変)を固定する: 実在しないディレクトリを渡すと非ゼロ終了+stderr、実在するが該当
# エントリが0件のディレクトリ/domain 絞り込みは終了コード0+空出力になり、両者は区別できる。
ki_missing="$(mktemp -d)/does-not-exist"
ki_missing_out="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$ki_missing" --list 2>/dev/null)"; ki_missing_rc=$?
ki_missing_err="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$ki_missing" --list 2>&1 1>/dev/null)"
if [ "$ki_missing_rc" -ne 0 ]; then ok "--list: 解決できないディレクトリは非ゼロ終了する(失敗を『0件』と誤認しない土台)"; else ng "--list: 解決できないディレクトリは非ゼロ終了する(失敗を『0件』と誤認しない土台) (got rc=$ki_missing_rc)"; fi
if [ -z "$ki_missing_out" ]; then ok "--list: 解決できないディレクトリでも stdout は空(0件出力と見た目は同じになりうる)"; else ng "--list: 解決できないディレクトリでも stdout は空 (got: $ki_missing_out)"; fi
out_has "--list: 解決できないディレクトリは stderr に理由を出す(呼び出し元が判別できる)" "ディレクトリが不正" "$ki_missing_err"
ki_empty="$(mktemp -d)"; mkdir -p "$ki_empty/api"
ki_empty_out="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$ki_empty" --list 2>/dev/null)"; ki_empty_rc=$?
exit_is "--list: 実在するが該当エントリ0件のディレクトリは終了コード0(失敗とは区別される)" 0 "$ki_empty_rc"
if [ -z "$ki_empty_out" ]; then ok "--list: 該当エントリ0件は stdout も空(『失敗』と外形が同じでも終了コードで判別できる)"; else ng "--list: 該当エントリ0件は stdout も空 (got: $ki_empty_out)"; fi
rm -rf "$ki_empty" "$(dirname "$ki_missing")"

echo "== knowledge-index/audit: 導入先(設定ファイルあり)で knowledge/ が無いときは知見0件(終了コード0)、設定ファイルも無ければ失敗のまま =="
# (a) 設定ファイルあり・knowledge/ なし → 0件・終了コード0
kz_a="$(mktemp -d)"; mkdir -p "$kz_a/.claude"; printf '{}\n' > "$kz_a/.claude/yosage-dev-harness.local.json"
for _m in --list --list-archive --check; do
  _o="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_a/.claude/knowledge" "$_m" 2>/dev/null)"; _rc=$?
  exit_is "index $_m: 設定ファイルあり・knowledge/ なしは終了コード0" 0 "$_rc"
  out_is_empty "index $_m: 設定ファイルあり・knowledge/ なしは出力なし" "$_o"
done
_o="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_a/.claude/knowledge/" --list 2>/dev/null)"; _rc=$?
exit_is "index --list: 末尾スラッシュ付きの引数でも同じ判定(終了コード0)" 0 "$_rc"
bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_a/.claude/knowledge" >/dev/null 2>&1; _rc=$?
if [ "$_rc" -ne 0 ]; then ok "index 書き出しモード: knowledge/ が無ければ(書き込み先が無いので)従来どおり非ゼロ"; else ng "index 書き出しモード: knowledge/ が無ければ従来どおり非ゼロ"; fi
file_isnt "index 書き出しモード: knowledge/ を勝手に作らない" "$kz_a/.claude/knowledge"
kz_a_o="$(bash "$ROOT/harness/lib/knowledge-audit.sh" "$kz_a/.claude" 2>/dev/null)"; kz_a_rc=$?
kz_a_e="$(bash "$ROOT/harness/lib/knowledge-audit.sh" "$kz_a/.claude" 2>&1 1>/dev/null)"
exit_is "audit: 設定ファイルあり・knowledge/ なしは終了コード0" 0 "$kz_a_rc"
out_is_empty "audit: 設定ファイルあり・knowledge/ なしは標準出力が空" "$kz_a_o"
out_has "audit: 設定ファイルあり・knowledge/ なしは走査0件を標準エラー出力へ出す" "0 件走査" "$kz_a_e"
# (b) 設定ファイルなし・knowledge/ なし → 非ゼロ
kz_b="$(mktemp -d)"; mkdir -p "$kz_b/.claude"
for _m in --list --list-archive --check; do
  bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_b/.claude/knowledge" "$_m" >/dev/null 2>&1; _rc=$?
  if [ "$_rc" -ne 0 ]; then ok "index $_m: 設定ファイルなし・knowledge/ なしは非ゼロ(失敗を0件と誤認しない)"; else ng "index $_m: 設定ファイルなし・knowledge/ なしは非ゼロ"; fi
done
bash "$ROOT/harness/lib/knowledge-audit.sh" "$kz_b/.claude" >/dev/null 2>&1; _rc=$?
if [ "$_rc" -ne 0 ]; then ok "audit: 設定ファイルなし・knowledge/ なしは非ゼロ"; else ng "audit: 設定ファイルなし・knowledge/ なしは非ゼロ"; fi
# 親ディレクトリ(.claude/)自体が無い場合は設定ファイルも無いので非ゼロ
bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_b/nodir/knowledge" --list >/dev/null 2>&1; _rc=$?
if [ "$_rc" -ne 0 ]; then ok "index --list: .claude/ 自体が無ければ非ゼロ"; else ng "index --list: .claude/ 自体が無ければ非ゼロ"; fi
# 設定ファイルの位置の取り違え: knowledge/ の中に置いても導入先とは見なさない(同じ .claude/ に無いと効かない)
kz_c="$(mktemp -d)"; mkdir -p "$kz_c/.claude"; printf '{}\n' > "$kz_c/yosage-dev-harness.local.json"
bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_c/.claude/knowledge" --list >/dev/null 2>&1; _rc=$?
if [ "$_rc" -ne 0 ]; then ok "index --list: 設定ファイルが .claude/ の外(プロジェクト直下)にあっても導入先とは見なさない"; else ng "index --list: 設定ファイルが .claude/ の外にあれば非ゼロ"; fi
# (c) knowledge/ あり・エントリ0件 → 0件・終了コード0
kz_d="$(mktemp -d)"; mkdir -p "$kz_d/.claude/knowledge"
_o="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_d/.claude/knowledge" --list 2>/dev/null)"; _rc=$?
exit_is "index --list: knowledge/ あり・エントリ0件(設定ファイルなしでも)は終了コード0" 0 "$_rc"
out_is_empty "index --list: knowledge/ あり・エントリ0件は出力なし" "$_o"
bash "$ROOT/harness/lib/knowledge-audit.sh" "$kz_d/.claude" >/dev/null 2>&1; _rc=$?
exit_is "audit: knowledge/ あり・エントリ0件は終了コード0(従来どおり)" 0 "$_rc"
# (d) エントリあり → 列挙される(設定ファイルの有無に関わらず)
mkdir -p "$kz_d/.claude/knowledge/api"
printf -- '---\nid: kz-entry\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nbody\n' > "$kz_d/.claude/knowledge/api/2026-01-01-kz-entry.md"
_o="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_d/.claude/knowledge" --list 2>/dev/null)"; _rc=$?
exit_is "index --list: エントリありは終了コード0" 0 "$_rc"
out_has "index --list: エントリが列挙される" "${NL}kz-entry${NL}" "$(_ids_col "$_o")${NL}"
printf '{}\n' > "$kz_d/.claude/yosage-dev-harness.local.json"
_o="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_d/.claude/knowledge" --list 2>/dev/null)"
out_has "index --list: 設定ファイルありでもエントリが列挙される" "${NL}kz-entry${NL}" "$(_ids_col "$_o")${NL}"
_e="$(bash "$ROOT/harness/lib/knowledge-audit.sh" "$kz_d/.claude" 2>&1 1>/dev/null)"
out_has "audit: エントリありは1件走査と報告する" "1 件走査" "$_e"
# 設定ファイルがあっても knowledge が通常ファイル・壊れたシンボリックリンクなら「無い」ではなく異常 → 非ゼロ
kz_e="$(mktemp -d)"; mkdir -p "$kz_e/f/.claude" "$kz_e/l/.claude"
printf '{}\n' > "$kz_e/f/.claude/yosage-dev-harness.local.json"; printf '{}\n' > "$kz_e/l/.claude/yosage-dev-harness.local.json"
: > "$kz_e/f/.claude/knowledge"; ln -s "$kz_e/nowhere" "$kz_e/l/.claude/knowledge"
for _k in f l; do
  for _m in --list --list-archive --check; do
    bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_e/$_k/.claude/knowledge" "$_m" >/dev/null 2>&1; _rc=$?
    if [ "$_rc" -ne 0 ]; then ok "index $_m: 設定ファイルあり・knowledge が異常な形($_k: f=通常ファイル/l=壊れたリンク)は非ゼロ"; else ng "index $_m: knowledge が異常な形($_k)は非ゼロ"; fi
  done
  bash "$ROOT/harness/lib/knowledge-audit.sh" "$kz_e/$_k/.claude" >/dev/null 2>&1; _rc=$?
  if [ "$_rc" -ne 0 ]; then ok "audit: 設定ファイルあり・knowledge が異常な形($_k)は非ゼロ"; else ng "audit: knowledge が異常な形($_k)は非ゼロ"; fi
done
# audit: 末尾スラッシュ付きの引数でも導入先判定は効く / 設定ファイルが .claude/ の外なら失敗のまま
bash "$ROOT/harness/lib/knowledge-audit.sh" "$kz_a/.claude/" >/dev/null 2>&1; _rc=$?
exit_is "audit: 末尾スラッシュ付きの引数でも設定ファイルあり・knowledge/ なしは終了コード0" 0 "$_rc"
bash "$ROOT/harness/lib/knowledge-audit.sh" "$kz_c/.claude" >/dev/null 2>&1; _rc=$?
if [ "$_rc" -ne 0 ]; then ok "audit: 設定ファイルが .claude/ の外にあれば導入先とは見なさず非ゼロ"; else ng "audit: 設定ファイルが .claude/ の外にあれば非ゼロ"; fi
# 末尾スラッシュ(複数も)付きの引数でも、通常ファイル・壊れたリンクは「無い」と誤判定しない。本当に無ければ0件のまま
for _k in f l; do
  for _sl in / //; do
    for _m in --list --list-archive --check; do
      bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_e/$_k/.claude/knowledge$_sl" "$_m" >/dev/null 2>&1; _rc=$?
      if [ "$_rc" -ne 0 ]; then ok "index $_m: 末尾スラッシュ($_sl)付き × knowledge が異常な形($_k)は非ゼロ"; else ng "index $_m: 末尾スラッシュ($_sl)付き × 異常な形($_k)は非ゼロ"; fi
    done
  done
done
for _sl in / //; do
  for _m in --list --list-archive --check; do
    bash "$ROOT/harness/lib/knowledge-index.sh" "$kz_a/.claude/knowledge$_sl" "$_m" >/dev/null 2>&1; _rc=$?
    exit_is "index $_m: 末尾スラッシュ($_sl)付き × 本当に無い(設定ファイルあり)は終了コード0" 0 "$_rc"
  done
done
rm -rf "$kz_e"
rm -rf "$kz_a" "$kz_b" "$kz_c" "$kz_d"

echo "== knowledge.md: project-local ストアは .claude/knowledge に固定(置き場を変える機能は撤去済み) =="
_kn_pos_body="$(cat "$H/rules/knowledge.md" 2>/dev/null)"
out_has "knowledge.md: ローカル索引節が存在" "ローカル索引は任意のキャッシュ" "$_kn_pos_body"
out_hasnt "knowledge.md: 旧解決式(YOSAGE_KNOWLEDGE_LOCAL_DIR)が残っていない(回帰防止)" "YOSAGE_KNOWLEDGE_LOCAL_DIR" "$_kn_pos_body"
out_has "knowledge.md: 列挙の失敗を0件と誤認しない節が存在" "列挙の失敗を「0件」と誤認しない" "$_kn_pos_body"
out_has "knowledge.md: 非ゼロ終了は停止して報告する旨を明記" "その場で停止し" "$_kn_pos_body"
out_has "knowledge.md: 導入先(設定ファイルあり)で knowledge/ が無いときは0件と読める" "yosage-dev-harness.local.json" "$_kn_pos_body"
out_hasnt "knowledge.md: 旧版の前提(install が作成する)が残っていない" "install が作成" "$_kn_pos_body"
for _f in "$H/skills/recall-knowledge/SKILL.md" "$H/agents/librarian.md" "$H/skills/capture-learning/SKILL.md"; do
  _fb="$(cat "$_f" 2>/dev/null)"
  out_has  "$(basename "$_f"): ストア位置は固定置き場(.claude/knowledge)を使う" ".claude/knowledge" "$_fb"
  out_hasnt "$(basename "$_f"): 旧解決式(YOSAGE_KNOWLEDGE_LOCAL_DIR)が残っていない" "YOSAGE_KNOWLEDGE_LOCAL_DIR" "$_fb"
done
out_has "librarian.md: 終了コード確認(非ゼロを『知見なし』と誤認しない)を明記" "終了コードを確認する" "$(cat "$H/agents/librarian.md" 2>/dev/null)"
out_has "recall-knowledge/SKILL.md: 終了コード確認を明記" "終了コードを確認する" "$(cat "$H/skills/recall-knowledge/SKILL.md" 2>/dev/null)"
out_has "capture-learning/SKILL.md: 書き込み先ディレクトリが解決できない場合は停止して報告する旨を明記" "既定レイアウトを勝手に作らず停止して報告する" "$(cat "$H/skills/capture-learning/SKILL.md" 2>/dev/null)"

echo "== knowledge-index: summary の YAML ブロックスカラー(>/ |)/空は警告し、壊れた値を INDEX に出さない =="
ki5="$(mktemp -d)"; mkdir -p "$ki5/api"
printf -- '---\nid: fs-folded\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: >\n  折り返した本文\n---\n' > "$ki5/api/2026-01-01-fs-folded.md"
printf -- '---\nid: fs-literal\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: |\n  折り返した本文\n---\n' > "$ki5/api/2026-01-01-fs-literal.md"
printf -- '---\nid: fs-empty\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary:\n---\n' > "$ki5/api/2026-01-01-fs-empty.md"
printf -- '---\nid: fs-chomp\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: >2-\n  折り返した本文\n---\n' > "$ki5/api/2026-01-01-fs-chomp.md"
printf -- '---\nid: fs-plain\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: `foo.sh` の挙動: 正常系\n---\n' > "$ki5/api/2026-01-01-fs-plain.md"
err5="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$ki5" 2>&1 1>/dev/null)"
idx5="$(cat "$ki5/INDEX.md" 2>/dev/null)"
out_has   "折り返し(>): 該当ファイル名付きで stderr に警告"        "2026-01-01-fs-folded.md" "$err5"
out_has   "保持(|): 該当ファイル名付きで stderr に警告"            "2026-01-01-fs-literal.md" "$err5"
out_has   "空: 該当ファイル名付きで stderr に警告"                 "2026-01-01-fs-empty.md" "$err5"
out_has   "chomping/indent 付き(>2-)でも stderr に警告"           "2026-01-01-fs-chomp.md" "$err5"
out_hasnt "正常な1行プレーンスカラーには警告が出ない"              "fs-plain.md" "$err5"
out_hasnt "折り返し(>)の壊れた値(>)が INDEX にそのまま出ない"      "| local | active | > |" "$idx5"
# 保持(|)は行組み立て時に `|` → `/` へエスケープされる(表崩れ防止)ため、単純な文字列不在チェックでは
# 壊れた値がエスケープ後の "/" として紛れ込んでも検出できない(検出無効化時も見た目上「/」に化けて
# 偽陰性になる)。summary 列が空になった行全体を期待値として明示的に照合する。
out_has   "保持(|)の値は summary 列が空の行として INDEX に載る(エスケープされた値と誤認しない)" \
          "| fs-literal | api |  | 2026-01-01 | local | active |  |" "$idx5"
out_has   "1行プレーンスカラーはバッククォート/コロンを含めてそのまま INDEX に載る(回帰なし)" \
          '`foo.sh` の挙動: 正常系' "$idx5"
out_has   "壊れたエントリも id 自体は INDEX に残る(summary 列だけ空)" "| fs-folded |" "$idx5"
rm -rf "$ki5"

echo "== knowledge-index: domain は frontmatter を正とし配置ディレクトリへフォールバックする(id と対称。) =="
ki6="$(mktemp -d)"; mkdir -p "$ki6/testing" "$ki6/api"
# frontmatter の domain(api) と配置ディレクトリ(testing)が食い違うエントリ
printf -- '---\nid: mismatch-entry\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: frontmatterはapiだがtestingに置かれている\n---\n' > "$ki6/testing/2026-01-01-mismatch-entry.md"
# frontmatter に domain: が無いエントリ(後方互換: 配置ディレクトリへフォールバック)
printf -- '---\nid: no-domain-entry\ndate: 2026-01-01\ntags: []\nscope: local\nstatus: active\nsummary: domain frontmatterが無い\n---\n' > "$ki6/api/2026-01-01-no-domain-entry.md"
err6="$(bash "$ROOT/harness/lib/knowledge-index.sh" "$ki6" 2>&1 1>/dev/null)"
idx6="$(cat "$ki6/INDEX.md" 2>/dev/null)"
out_has   "食い違うエントリは frontmatter の domain(api)を採用する" "| mismatch-entry | api |" "$idx6"
out_hasnt "食い違うエントリの domain 列に配置ディレクトリ名(testing)は出ない" "| mismatch-entry | testing |" "$idx6"
# 生成器自身は食い違いを診断しない(黙って frontmatter を採用する。理由は lib/knowledge-index.sh の
# resolve_domain コメント参照: この条件の検出は project-local エントリを対象にする構造監査
# (lib/knowledge-audit.sh の check7/domain-mismatch)に委ね、生成器はどの呼び出し経路でも stderr を
# 出さない)。
out_hasnt "生成器自身は食い違いを stderr で診断しない(検出は構造監査に委ねる)" "2026-01-01-mismatch-entry.md" "$err6"
out_has   "domain frontmatter 無しエントリは配置ディレクトリ(api)へフォールバックする(後方互換)" "| no-domain-entry | api |" "$idx6"
out_hasnt "domain frontmatter 無しエントリでも stderr は出ない" "no-domain-entry.md" "$err6"
rm -rf "$ki6"

echo "== knowledge.md: home repo固有パスと配布 payload パスの区別(取っ手を剥がしすぎない) =="
_kn_body="$(cat "$H/rules/knowledge.md" 2>/dev/null)"
out_has "knowledge.md: home repo固有パスと配布payloadパスの区別節を明記" "home repo 固有パスと配布 payload パスの区別" "$_kn_body"
out_has "knowledge.md: 論理パスの書式・例を明記" "yosage-dev-harness:lib/gh-review.sh" "$(echo "$_kn_body" | tr -d '\`')"
out_has "knowledge.md: 導入先のパスは書かない旨を明記" "legacy-payload-path" "$_kn_body"
out_has "knowledge.md: 変換スクリプト名を明記" "yosage-dev-harness-knowledge-convert-paths" "$_kn_body"
out_has "knowledge.md: 配布payloadパスは剥がさない旨を明記" "剥がさない" "$_kn_body"
out_has "knowledge.md: 取っ手は必須にしない旨を明記" "取っ手は必須にしない" "$_kn_body"
out_has "knowledge.md: 捏造取っ手は検証不能より悪い旨を明記" "捏造された取っ手は検証不能より悪い" "$_kn_body"
out_has "promote-knowledge: de-localize手順は配布payloadパスを剥がさない旨を明記" "は剥がさず取っ手として残す" "$(cat "$H/skills/promote-knowledge/SKILL.md" 2>/dev/null)"
out_has "capture-learning: staging時に配布payloadパスの取っ手を促す" "安定ハンドルとして書いておく" "$(cat "$H/skills/capture-learning/SKILL.md" 2>/dev/null)"

echo "== knowledge-logical-path.sh: ydh_lp_resolve/ydh_lp_is_logical 単体 =="
( . "$H/lib/knowledge-logical-path.sh"
  if ydh_lp_is_logical "yosage-dev-harness:lib/gh-review.sh"; then ok "is_logical: / を含む論理パスは0"; else ng "is_logical: / を含む論理パスは0"; fi
  if ydh_lp_is_logical "yosage-dev-harness:implementer"; then ng "is_logical: / を含まないエージェント名参照は1"; else ok "is_logical: / を含まないエージェント名参照は1"; fi
  if ydh_lp_is_logical "not-a-logical-path/foo"; then ng "is_logical: 接頭辞違いは1"; else ok "is_logical: 接頭辞違いは1"; fi
  _lp_out="$(ydh_lp_resolve "yosage-dev-harness:lib/knowledge-audit.sh")"; _lp_rc=$?
  exit_is "resolve: 実在する論理パスは exit 0" 0 "$_lp_rc"
  out_has "resolve: 実在する論理パスは絶対パスを返す(harness/lib配下)" "lib/knowledge-audit.sh" "$_lp_out"
  ydh_lp_resolve "yosage-dev-harness:lib/nonexistent-xyz.sh" >/dev/null 2>&1
  exit_is "resolve: 実在しない論理パスは exit 1" 1 "$?"
  ydh_lp_resolve "yosage-dev-harness:lib/../../etc/passwd" >/dev/null 2>&1
  exit_is "resolve: .. を含む論理パスは exit 2" 2 "$?"
  ydh_lp_resolve "not-yosage-dev-harness:lib/foo.sh" >/dev/null 2>&1
  exit_is "resolve: 接頭辞違いは exit 2" 2 "$?"
)

echo "== knowledge-audit.sh: 論理パスの解決(check3)・導入先パスの検出(legacy-payload-path) =="
tlp="$(mktemp -d)"; mk_consumer "$tlp"
mkdir -p "$tlp/.claude/knowledge/api"
printf -- '---\nid: lp-ok\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `yosage-dev-harness:lib/gh-review.sh`(実在)\n' \
  > "$tlp/.claude/knowledge/api/2026-01-01-lp-ok.md"
printf -- '---\nid: lp-broken\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `yosage-dev-harness:lib/totally-missing-xyz.sh`\n' \
  > "$tlp/.claude/knowledge/api/2026-01-02-lp-broken.md"
printf -- '---\nid: lp-legacy\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `.claude/lib/gh-review.sh`\n' \
  > "$tlp/.claude/knowledge/api/2026-01-03-lp-legacy.md"
lp_out="$(bash "$H/lib/knowledge-audit.sh" "$tlp/.claude" 2>/dev/null)"
out_hasnt "audit: 実在する論理パスは誤検知しない" "lp-ok.md" "$lp_out"
if ka_has "knowledge/api/2026-01-02-lp-broken.md" "broken-path-ref" "$lp_out"; then ok "audit: 実在しない論理パスは broken-path-ref"; else ng "audit: 実在しない論理パスは broken-path-ref"; fi
if ka_has "knowledge/api/2026-01-03-lp-legacy.md" "legacy-payload-path" "$lp_out"; then ok "audit: 導入先のパス(.claude/lib/...)は legacy-payload-path で報告される"; else ng "audit: 導入先のパス(.claude/lib/...)は legacy-payload-path で報告される"; fi
out_has "audit: legacy-payload-path のメッセージに変換スクリプト名を含める" "yosage-dev-harness-knowledge-convert-paths" "$lp_out"
rm -rf "$tlp"

echo "== knowledge-audit.sh(一次レビュー対応): legacy-payload-path と broken-path-ref の二重報告を解消する =="
# 実在する旧パス → legacy-payload-path のみ(broken-path-ref は出ない)。
tdup1="$(mktemp -d)"; mk_consumer "$tdup1"
mkdir -p "$tdup1/.claude/knowledge/api"
printf -- '---\nid: dup-exists\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `.claude/lib/gh-review.sh`(実在)\n' \
  > "$tdup1/.claude/knowledge/api/2026-01-01-dup-exists.md"
dup1_out="$(bash "$H/lib/knowledge-audit.sh" "$tdup1/.claude" 2>/dev/null)"
dup1_count="$(printf '%s\n' "$dup1_out" | grep -c 'dup-exists\.md')"
exit_is "audit(一次レビュー): 実在する旧パスの報告は1件だけ" 1 "$dup1_count"
if ka_has "knowledge/api/2026-01-01-dup-exists.md" "legacy-payload-path" "$dup1_out"; then ok "audit(一次レビュー): 実在する旧パスは legacy-payload-path"; else ng "audit(一次レビュー): 実在する旧パスは legacy-payload-path"; fi
if ka_has "knowledge/api/2026-01-01-dup-exists.md" "broken-path-ref" "$dup1_out"; then ng "audit(一次レビュー): 実在する旧パスに broken-path-ref は出ない(二重報告の解消)"; else ok "audit(一次レビュー): 実在する旧パスに broken-path-ref は出ない(二重報告の解消)"; fi
rm -rf "$tdup1"
# 撤去済み(変換先が実在しない)旧パス → 1件だけ・「手で直す」案内。
tdup2="$(mktemp -d)"; mk_consumer "$tdup2"
mkdir -p "$tdup2/.claude/knowledge/api"
printf -- '---\nid: dup-removed\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `.claude/lib/payload-drift.sh`(撤去済み)\n' \
  > "$tdup2/.claude/knowledge/api/2026-01-01-dup-removed.md"
dup2_out="$(bash "$H/lib/knowledge-audit.sh" "$tdup2/.claude" 2>/dev/null)"
dup2_count="$(printf '%s\n' "$dup2_out" | grep -c 'dup-removed\.md')"
exit_is "audit(一次レビュー): 撤去済み旧パスの報告は1件だけ(二重報告の解消)" 1 "$dup2_count"
if ka_has "knowledge/api/2026-01-01-dup-removed.md" "legacy-payload-path" "$dup2_out"; then ok "audit(一次レビュー): 撤去済み旧パスは legacy-payload-path(1件だけ)"; else ng "audit(一次レビュー): 撤去済み旧パスは legacy-payload-path(1件だけ)"; fi
if ka_has "knowledge/api/2026-01-01-dup-removed.md" "broken-path-ref" "$dup2_out"; then ng "audit(一次レビュー): 撤去済み旧パスに broken-path-ref は出ない"; else ok "audit(一次レビュー): 撤去済み旧パスに broken-path-ref は出ない"; fi
out_has "audit(一次レビュー): 撤去済み旧パスの案内は『手で直す』(変換スクリプト誘導のミスリードを避ける)" "手で直してください" "$dup2_out"
out_hasnt "audit(一次レビュー): 撤去済み旧パスの案内に変換スクリプトへの誘導は出ない(ミスリード回避)" "書き換えてください" "$dup2_out"
rm -rf "$tdup2"

echo "== knowledge-audit.sh(一次レビュー対応): CANDIDATE_ROOTS からプラグインのルートを候補にする解決を撤去する =="
tcrm="$(mktemp -d)"; mk_ka_copy "$tcrm"
mkdir -p "$tcrm/harness/hooks"
printf '#!/usr/bin/env bash\necho hi\n' > "$tcrm/harness/hooks/candroot-removed-hook.sh"
mkdir -p "$tcrm/.claude/knowledge/api"
# prefix 省略(plugin_root 相対のみ)のベアパス: 実在しても、論理パスでも `.claude/` 前置きでも
# ないため broken-path-ref になる(CANDIDATE_ROOTS 撤去の直接確認)。
printf -- '---\nid: crm-bare\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `hooks/candroot-removed-hook.sh`\n' \
  > "$tcrm/.claude/knowledge/api/2026-01-01-crm-bare.md"
# 同じ実体を論理パスで書けば引き続き解決する(迂回路を塞いだだけで、正しい書き方は壊していない)。
printf -- '---\nid: crm-logical\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `yosage-dev-harness:hooks/candroot-removed-hook.sh`\n' \
  > "$tcrm/.claude/knowledge/api/2026-01-02-crm-logical.md"
# 同じ実体を repo ルート相対(harness/hooks/...)で書けば引き続き解決する(導入先リポジトリの中の
# パスとしての解決は残る、という裁定の直接確認)。
printf -- '---\nid: crm-repo-relative\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/hooks/candroot-removed-hook.sh`\n' \
  > "$tcrm/.claude/knowledge/api/2026-01-03-crm-repo-relative.md"
crm_out="$(bash "$tcrm/harness/lib/knowledge-audit.sh" "$tcrm/.claude" 2>/dev/null)"
if ka_has "knowledge/api/2026-01-01-crm-bare.md" "broken-path-ref" "$crm_out"; then ok "audit(一次レビュー): plugin_root相対のベアパスはもう解決されない(broken-path-ref)"; else ng "audit(一次レビュー): plugin_root相対のベアパスはもう解決されない(broken-path-ref)"; fi
out_hasnt "audit(一次レビュー): 論理パスで書けば引き続き誤検知しない" "crm-logical.md" "$crm_out"
out_hasnt "audit(一次レビュー): repo ルート相対で書けば引き続き誤検知しない(導入先リポジトリの中のパスとしての解決は残す)" "crm-repo-relative.md" "$crm_out"
rm -rf "$tcrm"

echo "== knowledge-audit.sh: 論理パスは使用中の版のプラグインの中で解決する(両方向) =="
tlpA="$(mktemp -d)"; mkdir -p "$tlpA/lib"
cp "$H/lib/knowledge-audit.sh" "$tlpA/lib/knowledge-audit.sh"
printf '#!/usr/bin/env bash\necho present\n' > "$tlpA/lib/dummy-target.sh"
mkdir -p "$tlpA/.claude/knowledge/api"
printf -- '---\nid: lp-both\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `yosage-dev-harness:lib/dummy-target.sh`\n' \
  > "$tlpA/.claude/knowledge/api/2026-01-01-lp-both.md"
lpA_out="$(bash "$tlpA/lib/knowledge-audit.sh" "$tlpA/.claude" 2>/dev/null)"
out_hasnt "audit(版A・対象ファイル在): 論理パスは誤検知しない" "lp-both" "$lpA_out"
tlpB="$(mktemp -d)"; mkdir -p "$tlpB/lib"
cp "$H/lib/knowledge-audit.sh" "$tlpB/lib/knowledge-audit.sh"
cp -R "$tlpA/.claude" "$tlpB/.claude"
lpB_out="$(bash "$tlpB/lib/knowledge-audit.sh" "$tlpB/.claude" 2>/dev/null)"
if ka_has "knowledge/api/2026-01-01-lp-both.md" "broken-path-ref" "$lpB_out"; then ok "audit(版B・対象ファイル無): 同じ論理パスが broken-path-ref になる"; else ng "audit(版B・対象ファイル無): 同じ論理パスが broken-path-ref になる"; fi
rm -rf "$tlpA" "$tlpB"

echo "== knowledge-convert-paths: dry-run/--apply/2回目は何もしない/globalは触らない/要手直しの検出 =="
tcv="$(mktemp -d)"; mkdir -p "$tcv/api" "$tcv/global/api"
printf -- '---\nid: cv1\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `.claude/lib/gh-review.sh`\n- ルール: `.claude/rules/harness/knowledge.md`\n- 撤去済み: `.claude/lib/totally-missing-conv-xyz.sh`\n' \
  > "$tcv/api/2026-01-01-cv1.md"
printf -- '---\nid: cv-global\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\n`.claude/lib/gh-review.sh`\n' \
  > "$tcv/global/api/g.md"
cv_dry_out="$(bash "$H/lib/knowledge-convert-paths.sh" "$tcv")"; cv_dry_rc=$?
exit_is "convert: dry-run は変更対象があれば exit 10" 10 "$cv_dry_rc"
out_has "convert: dry-run に旧→新の行が出る" "yosage-dev-harness:lib/gh-review.sh" "$cv_dry_out"
out_has "convert: dry-run に要手直しの一覧が出る" "要手直し" "$cv_dry_out"
out_has "convert: dry-run では何も書き換わらない" "\`.claude/lib/gh-review.sh\`" "$(cat "$tcv/api/2026-01-01-cv1.md")"
bash "$H/lib/knowledge-convert-paths.sh" --apply "$tcv" >/dev/null; cv_apply_rc=$?
exit_is "convert: --apply は exit 0" 0 "$cv_apply_rc"
out_has "convert: --apply で実際に書き換わる" "\`yosage-dev-harness:lib/gh-review.sh\`" "$(cat "$tcv/api/2026-01-01-cv1.md")"
out_has "convert: 要手直しは書き換えず元のままにする" "\`.claude/lib/totally-missing-conv-xyz.sh\`" "$(cat "$tcv/api/2026-01-01-cv1.md")"
out_hasnt "convert: global/ は触らない" "yosage-dev-harness:lib/gh-review.sh" "$(cat "$tcv/global/api/g.md")"
cv_dry2_out="$(bash "$H/lib/knowledge-convert-paths.sh" "$tcv")"; cv_dry2_rc=$?
exit_is "convert: --apply 後の2回目の dry-run は置き換え対象なしで exit 0" 0 "$cv_dry2_rc"
out_hasnt "convert: 2回目には既に変換済みの行が再度出ない" "-> yosage-dev-harness:lib/gh-review.sh" "$cv_dry2_out"
rm -rf "$tcv"

echo "== knowledge-index.sh --check: 検証だけでファイルを書かない =="
tck="$(mktemp -d)"; mkdir -p "$tck/api"
printf -- '---\nid: ck-clean\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 正常\n---\n' > "$tck/api/2026-01-01-ck-clean.md"
printf -- '---\nid: ck-broken\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: >\n  broken\n---\n' > "$tck/api/2026-01-01-ck-broken.md"
ck_err="$(bash "$H/lib/knowledge-index.sh" "$tck" --check 2>&1 1>/dev/null)"; ck_rc=$?
exit_is "--check: 正常終了は exit 0" 0 "$ck_rc"
out_has "--check: 壊れた summary は警告する" "2026-01-01-ck-broken.md" "$ck_err"
file_isnt "--check: INDEX.md は書かれない" "$tck/INDEX.md"
file_isnt "--check: INDEX.archive.md も書かれない" "$tck/INDEX.archive.md"
rm -rf "$tck"

echo "== knowledge-template: harness/knowledge/_entry-template.md の中身を出力する =="
kt_out="$(bash "$H/lib/knowledge-template.sh")"
out_has "knowledge-template: frontmatter の id 行を含む" "id: <kebab-slug>" "$kt_out"
out_has "knowledge-template: harness/knowledge/_entry-template.md の中身と一致する" "$(cat "$H/knowledge/_entry-template.md")" "$kt_out"

echo "== knowledge.md: 参照とリテラルの書き分け(。コードスパンで判別する規約) =="
out_has "knowledge.md: 参照とリテラルの書き分け節を明記" "参照とリテラルの書き分け（コードスパンで判別する）" "$_kn_body"
out_has "knowledge.md: issue/PR参照は地の文に書く規約を明記" "地の文に書く" "$_kn_body"
out_has "knowledge.md: コードスパンの中身はリテラルである旨を明記" "コードスパンの中身" "$_kn_body"
out_has "knowledge.md: load-bearingでない例示は不変に抵触しない旨を明記" "抵触しない" "$_kn_body"
out_has "knowledge.md: 判定基準に load-bearing かどうかを明記(見出しとの整合)" "**番号**についてはさらに**load-bearing か**" "$_kn_body"
out_has "knowledge.md: load-bearing の限定は番号だけに掛かる(repo名/org identityは無条件で載せない)" "**load-bearing な番号**・repo 名・org identity を載せない" "$_kn_body"
out_hasnt "knowledge.md: load-bearing の限定が repo名/org identityへ広がっていない(一次レビュー回帰)" "**load-bearing な**番号・repo 名・org identity を載せない" "$_kn_body"
# 正本一元化(単一ホーム): 配布payloadパスの具体的な列挙(4パターン)は knowledge.md にだけ置き、
# skill 側は名前参照に留める(pr-loop.md の「レビュー投稿形式」節が code-reviewer 等の直書きを
# out_hasnt で禁止しているのと同型)。列挙が skill 側に再出現(drift)したら落ちるネガティブ側。
for _pk_nofp in "$H/skills/promote-knowledge/SKILL.md" "$H/skills/capture-learning/SKILL.md"; do
  _pk_nofp_body="$(cat "$_pk_nofp" 2>/dev/null)"
  out_hasnt "$(basename "$(dirname "$_pk_nofp")")/$(basename "$_pk_nofp"): 配布payloadパスの具体列挙(rules/<name>.md)を再記述していない(正本のみが持つ)" ".claude/rules/<name>.md" "$_pk_nofp_body"
  out_hasnt "$(basename "$(dirname "$_pk_nofp")")/$(basename "$_pk_nofp"): 配布payloadパスの具体列挙(skills/<name>/SKILL.md)を再記述していない(正本のみが持つ)" ".claude/skills/<name>/SKILL.md" "$_pk_nofp_body"
  out_hasnt "$(basename "$(dirname "$_pk_nofp")")/$(basename "$_pk_nofp"): 配布payloadパスの具体列挙(agents/<name>.md)を再記述していない(正本のみが持つ)" ".claude/agents/<name>.md" "$_pk_nofp_body"
  out_hasnt "$(basename "$(dirname "$_pk_nofp")")/$(basename "$_pk_nofp"): 配布payloadパスの具体列挙(lib/<name>.sh)を再記述していない(正本のみが持つ)" ".claude/lib/<name>.sh" "$_pk_nofp_body"
done

echo "== knowledge.md: 書き方不変: 引用照合ゲート(source: を持つ知見は原典と照合する。真偽軸の単一正本) =="
_kn_qv_body="$(cat "$H/rules/knowledge.md" 2>/dev/null)"
out_has "knowledge.md: 引用照合ゲート節が存在" "書き方不変: 引用照合ゲート" "$_kn_qv_body"
out_has "knowledge.md: source:が付いていること自体は信頼の根拠にならない旨を明記" "「確認済み」" "$_kn_qv_body"
out_has "knowledge.md: 安定ハンドル(見出し名・表名・逐語引用)を要求する旨を明記" "見出し名・表名・逐語の引用" "$(echo "$_kn_qv_body" | tr -d '\`')"
out_has "knowledge.md: 原典を実際に開いて逐語で突き合わせる旨を明記" "原典を実際に開いて逐語で突き合わせる" "$_kn_qv_body"
out_has "knowledge.md: 委譲時はsubagentの報告を鵜呑みにせず原典の逐語引用を突き合わせる旨を明記" "原典の逐語引用" "$_kn_qv_body"
out_has "knowledge.md: checked:は原典を開いて照合した日を意味する旨を明記" "\`checked:\` は**原典を開いて照合した日**を指す" "$_kn_qv_body"
out_has "knowledge.md: 原典に無い主張をdoc由来として書かない旨を明記" "原典に無い主張を doc 由来として書かない" "$_kn_qv_body"
out_has "knowledge.md: 原典と矛盾する主張は止める旨を明記" "原典と矛盾する主張" "$_kn_qv_body"
out_has "knowledge.md: 照合不能時も止める旨を明記" "照合不能" "$_kn_qv_body"
out_has "knowledge.md: 着火点固有の挙動は各着火点が持つ旨を明記(capture/promote双方への配線点)" "着火点固有の挙動は各着火点が持つ" "$_kn_qv_body"
# 両 skill が真偽軸の共通手順(regime本文)を逐語コピーしていないことを確認(指紋テストの再記述禁止パターンに倣う)
for _qv_nofp in "$H/skills/promote-knowledge/SKILL.md" "$H/skills/capture-learning/SKILL.md"; do
  _qv_nofp_body="$(cat "$_qv_nofp" 2>/dev/null)"
  out_hasnt "$(basename "$(dirname "$_qv_nofp")")/$(basename "$_qv_nofp"): 「確認済み」の定義文を逐語コピーしていない(正本のみが持つ)" "原典を実際に開いて逐語で突き合わせて初めて" "$_qv_nofp_body"
  out_hasnt "$(basename "$(dirname "$_qv_nofp")")/$(basename "$_qv_nofp"): 安定ハンドル要求の本文(見出し名・表名・逐語の引用)を逐語コピーしていない(正本のみが持つ)" "見出し名・表名・逐語の引用" "$_qv_nofp_body"
  out_hasnt "$(basename "$(dirname "$_qv_nofp")")/$(basename "$_qv_nofp"): 委譲時の逐語引用要求の本文を逐語コピーしていない(正本のみが持つ)" "委譲する場合、subagent の「確認した」という報告だけでは受理しない" "$_qv_nofp_body"
done

echo "== capture-learning: 引用照合(source: を持つ知見は capture 時点で原典と照合する。相当のshift-left側) =="
_cl_skill_body="$(cat "$H/skills/capture-learning/SKILL.md" 2>/dev/null)"
out_has "capture-learning: 真偽軸の共通手順をknowledge.mdへ名前参照(再記述しない)" "書き方不変: 引用照合ゲート」節（本 skill には再記述しない）" "$_cl_skill_body"
out_has "capture-learning: 照合はcapture時点で行う旨を明記" "照合は capture 時点で行う" "$_cl_skill_body"
out_has "capture-learning: 一致したらchecked:を今日にする旨を明記" "一致したら \`checked:\` を今日にする" "$_cl_skill_body"
out_has "capture-learning: 矛盾・照合不能時はその記述を書かない旨を明記(capture固有の停止具体化)" "その記述は書かない" "$_cl_skill_body"
out_has "capture-learning: 人間へのエスカレーションはpromote側のバックストップが担う旨を明記(分業の明示)" "人間へのエスカレーションは昇格時点のバックストップ" "$_cl_skill_body"
out_has "capture-learning: 原則に引用照合ゲートの省略禁止を明記" "引用照合ゲートを省略しない" "$_cl_skill_body"

echo "== knowledge.md: 書き方不変: 書き込み前の自己チェック(粒度混在・scope妥当性。capture時点の品質ゲート) =="
_kn_sc_body="$(cat "$H/rules/knowledge.md" 2>/dev/null)"
out_has "knowledge.md: 書き込み前の自己チェック節が存在" "書き方不変: 書き込み前の自己チェック" "$_kn_sc_body"
out_has "knowledge.md: 1件1ルールになっているかを問う" "1件1ルールになっているか" "$_kn_sc_body"
out_has "knowledge.md: 固有の事実と一般形の混在を問う" "固有の事実と一般形が混ざっていないか" "$_kn_sc_body"
out_has "knowledge.md: scopeの妥当性を問う" "\`scope\` はそれでよいか" "$_kn_sc_body"
out_has "knowledge.md: issue-discipline の起票前自己チェックと同型である旨を明記" "起票／書き込み前の主体 in-context 自己チェック" "$_kn_sc_body"
out_has "knowledge.md: sensitive-data のcommit前自己チェックと同型である旨を明記" "commit 前の自己チェック（主体が in-context で行う）" "$_kn_sc_body"
out_has "knowledge.md: それらの中身は再記述しない旨を明記" "それらの中身（符牒展開・secret/PII" "$_kn_sc_body"
out_has "knowledge.md: 昇格時点の確認とは別軸である旨を明記(責務分担)" "昇格時点の確認とは別軸" "$_kn_sc_body"

echo "== capture-learning: 書き込む前の自己チェック(位置=手順内で書き込みより前・正本を名前参照) =="
out_has "capture-learning: 手順内で書き込む前の自己チェックを明記" "書き込む前に自己チェックを通す" "$_cl_skill_body"
out_has "capture-learning: 正本をknowledge.mdへ名前参照(再記述しない)" "書き方不変: 書き込み前の自己チェック」節。本 skill には再記述しない" "$_cl_skill_body"
out_has "capture-learning: 原則に書き込み前の自己チェックの省略禁止を明記" "書き込む前の自己チェックを省略しない" "$_cl_skill_body"
# 手順内の相対位置: 自己チェック(手順4)が既存ファイル追記(手順5)より前に置かれていること(=書き込む前)。
_cl_step4_pos=$(printf '%s' "$_cl_skill_body" | grep -n "書き込む前に自己チェックを通す" | head -1 | cut -d: -f1)
_cl_step5_pos=$(printf '%s' "$_cl_skill_body" | grep -n "対象ファイルの既存を確認" | head -1 | cut -d: -f1)
if [ -n "$_cl_step4_pos" ] && [ -n "$_cl_step5_pos" ] && [ "$_cl_step4_pos" -lt "$_cl_step5_pos" ]; then
  ok "capture-learning: 自己チェックが既存ファイルへの書き込み手順より前の行にある"
else
  ng "capture-learning: 自己チェックが既存ファイルへの書き込み手順より前の行にある (step4=$_cl_step4_pos step5=$_cl_step5_pos)"
fi
# 三つの問いは正本(knowledge.md)にのみ置き、capture-learning側は名前参照に留める(drift回避。)
for _sc_nofp in "$H/skills/capture-learning/SKILL.md" "$H/skills/promote-knowledge/SKILL.md"; do
  _sc_nofp_body="$(cat "$_sc_nofp" 2>/dev/null)"
  out_hasnt "$(basename "$(dirname "$_sc_nofp")")/$(basename "$_sc_nofp"): 書き込み前チェックの三つの問いを逐語コピーしていない(正本のみが持つ)" "固有の事実と一般形が混ざっていないか" "$_sc_nofp_body"
done
# 本issueのスコープ外(promote-knowledge に昇格時の確認手順を書かない): 責務分担を崩していないことの回帰ガード
out_hasnt "promote-knowledge: 書き込み前の自己チェック節を持ち込んでいない(責務はcapture-learning側)" "書き方不変: 書き込み前の自己チェック" "$(cat "$H/skills/promote-knowledge/SKILL.md" 2>/dev/null)"

out_has "正本 commit.md が存在"           "コミット"       "$(cat "$H/rules/commit.md" 2>/dev/null)"
# 単一ホーム化: Co-Authored-By 署名トレーラの判断軸は commit.md が正本。雛形を持つ2 skill は
# 名前参照のみに留め、判断基準本文(自社所有/開示宣言の分岐)を再記述していないことを確認する。
# 検知は二重化する(役割が違うため両方残す): 上の「横断ルール: ポリシー指紋」ブロックの fp_fail 側が
# 未知の第三のファイルによる再記述も広く拾う一方、ここの targeted assertion(名指し out_hasnt)は
# 既知の2ファイルに対して「どのファイルの何が re-state されたか」を具体的に落とす
# (「レビュー投稿形式」パターンに倣う)。
_ci_body="$(cat "$H/rules/commit.md" 2>/dev/null)"
out_has "commit.md: Co-Authored-By 署名トレーラ節が存在" "Co-Authored-By 署名トレーラ" "$_ci_body"
out_has "commit.md: 自社所有→付ける(既定)を明記" "自社所有のリポジトリ** → 付ける" "$_ci_body"
out_has "commit.md: 非自社→宣言が無ければ付けないを明記" "宣言が無ければ付けない" "$_ci_body"
out_has "commit.md: 開示不明も未宣言として扱う(曖昧を付ける側へ倒さない)旨を明記" "未宣言として扱われる" "$_ci_body"
out_has "commit.md: 案件固有の事実は project-profile の切り分けに従う参照の形になっている" "project-profile" "$_ci_body"
_ii_body="$(cat "$H/skills/issue-implement/SKILL.md" 2>/dev/null)"
out_has "issue-implement: commit.md の Co-Authored-By 署名トレーラ節への名前参照" "commit\` の「Co-Authored-By 署名トレーラ」節" "$_ii_body"
out_hasnt "issue-implement: 署名要否の判断基準本文(自社所有/開示宣言)を再記述していない" "自社所有のリポジトリ" "$_ii_body"
_eis_body="$(cat "$H/skills/epic-implement-subissue/SKILL.md" 2>/dev/null)"
out_has "epic-implement-subissue: commit.md の Co-Authored-By 署名トレーラ節への名前参照" "commit\` の「Co-Authored-By 署名トレーラ」節" "$_eis_body"
out_hasnt "epic-implement-subissue: 署名要否の判断基準本文(自社所有/開示宣言)を再記述していない" "自社所有のリポジトリ" "$_eis_body"

# follow-up: coordinator指摘により、統合の単位の選択(既定=develop・まとめる場合のみ epic ブランチ)を
# pr-loop.md/change-lanes.md だけでなく、Sub-issue の標準実装レーンが無条件に epic ブランチ基点だと
# 述べていた箇所(実装ルーティング・実装スキル・作業部隊定義)にも揃える。
out_has "issue-implement: epic-implement-subissue の取り込み先(pr-loop.md準拠)への言及を明記" "取り込み先は Sub-issue の本文に書かれた Epic ブランチか導入先の既定ブランチ" "$_ii_body"
out_hasnt "issue-implement: epic-implement-subissue が epic ブランチ基点固定という旧文言が残っていない" "ブランチ基点**で実装するのは" "$_ii_body"

out_has "epic-implement-subissue: PR のベースブランチは Sub-issue 本文の取り込み先(既定は Epic ブランチ)である旨を明記" "PR のベースブランチは Sub-issue の本文の取り込み先" "$_eis_body"
out_has "epic-implement-subissue: 取り込み先を途中で変えたくなったら自分で変えず統制側へ提案する旨を明記" "自分では変えない" "$_eis_body"
out_has "epic-implement-subissue: Epic ブランチ向けの PR 本文は Part of を書き Closes # を書かない旨を明記" "「Part of #<Epic番号>」" "$_eis_body"
out_has "epic-implement-subissue: コミット末尾の Closes # は残す旨を明記" "コミット末尾の \`Closes #<issue番号>\` は残す" "$_eis_body"
out_hasnt "epic-implement-subissue: PR ベースが Epic ブランチ固定(main/developではない)という旧文言が残っていない" "\`main\`/\`develop\` ではない" "$_eis_body"

_ir_body="$(cat "$H/rules/implement-routing.md" 2>/dev/null)"
out_has "implement-routing: Epic の Sub-issue の取り込み先は本文の取り込み先に従う旨を明記" "取り込み先は Sub-issue の本文の「取り込み先」に従う" "$_ir_body"
out_hasnt "implement-routing: Epic の Sub-issue が epic ブランチ基点固定という旧文言が残っていない" "ブランチ基点**で実装（[[epic-implement-subissue]]）" "$_ir_body"

_impl_body="$(cat "$H/agents/implementer.md" 2>/dev/null)"
out_has "implementer.md: draft PR の base は dispatch 時の指示に従う旨(Sub-issue 本文の取り込み先)を明記" "Epic 配下 Sub-issue は Sub-issue の本文の取り込み先" "$_impl_body"
out_has "implementer.md: Epic ブランチ向けの PR 本文は Part of を書く旨を明記" "「Part of #<Epic>」で \`Closes #\` を書かない" "$_impl_body"
out_hasnt "implementer.md: Epic 配下なら base は Epic ブランチという旧文言が残っていない" "Epic 配下なら base は Epic ブランチ" "$_impl_body"

# follow-up: visual-design の人間確認ステップ(SKILL.md (e)節)を implementer が満たせない場合、
# 正本への確定直前で停止し dispatch元の再開を待つ2段構成の規律を明記する。
out_has "implementer.md: visual-design の人間確認ステップを満たせない場合は確定コミット直前で停止する旨を明記" "確定コミットの直前で停止する" "$_impl_body"
out_has "implementer.md: visual-design SKILL.md の (e) 自己批評節への言及を明記" "\`(e) 自己批評\` 節が定める" "$_impl_body"
out_has "implementer.md: SendMessage による再開指示を受けて続きを完了させる旨を明記" "\`SendMessage\` で再開の指示" "$_impl_body"
out_has "implementer.md: buildを終えたことを停止トリガにしない旨を明記(検証3は停止前に完了)" "「build を終えたこと」を停止のトリガにしない" "$_impl_body"
out_has "implementer.md: 停止位置が確定コミット(手順4)の直前である旨を明記" "正本として確定させる commit（手順4のコミット・push・draft PR 作成）の直前" "$_impl_body"

out_has "正本 issue-discipline.md が存在" "issue 規律"     "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 文脈的自己完結を明記" "文脈的自己完結" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: セッション内符牒の本文を明記" "セッション内符牒" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 適用範囲に人へ判断を求める提示を含む旨を明記" "人へ判断を求める提示" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 記号の使用自体は禁止しない旨を明記" "記号の使用自体は禁止されていない" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 適用範囲拡張の反証条件を明記" "反証条件" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 配布 payload コメントの carve-out を明記" "carve-out（配布 payload）" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 防御の主線(起票/書き込み前の自己チェック)を明記" "防御の主線: 起票／書き込み前の主体 in-context 自己チェック" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 検出を独立した安全網(2層の補完)として明記" "検出は独立した安全網（2層の補完）" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_hasnt "issue-discipline: 検出を格下げする表現が無い" "格下げ" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 第2層が人への提示に届かない旨を明記" "第2層は「人へ判断を求める提示」には届かない" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 第1層だけで受けるのが判断の結果である旨を明記(不作為との区別)" "判断してそう決めている" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 人へ判断を求める提示のうち判断そのものを求めるものは durable な記録を伴う旨を明記" "「人へ判断を求める提示」のうち判断そのものを求めるものは durable な記録を伴う" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: durable な記録の対象は実質的な判断を求める提示に限る旨を明記(軽い確認・往復は対象外)" "軽い確認・往復は対象外" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 起票前の重複確認節を明記" "起票前の重複確認" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: クローズ済みも検索対象に含める旨を明記" "closed も検索対象に含める" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 重複時の扱い(同一問題/別物)の判断基準を明記" "同一の問題" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
out_has "issue-discipline: 検索したこと自体を前提の手順とする旨を明記" "検索したこと自体を前提の手順とする" "$(cat "$H/rules/issue-discipline.md" 2>/dev/null)"
_ic_body="$(cat "$H/skills/issue-create/SKILL.md" 2>/dev/null)"
out_has "issue-create: issue-discipline 文脈的自己完結節への名前参照" "issue-discipline\` の「文脈的自己完結" "$_ic_body"
out_has "issue-create: issue-discipline 起票前の重複確認節への名前参照" "issue-discipline\` の「起票前の重複確認」" "$_ic_body"
out_hasnt "issue-create: 主線ポリシー本文の逐語コピーが無い(commit 前の自己チェック)" "commit 前の自己チェック" "$_ic_body"
_eci_body="$(cat "$H/skills/epic-create-issues/SKILL.md" 2>/dev/null)"
out_has "epic-create-issues: issue-discipline 文脈的自己完結節への名前参照" "issue-discipline\` の「文脈的自己完結" "$_eci_body"
out_hasnt "epic-create-issues: 主線ポリシー本文の逐語コピーが無い(commit 前の自己チェック)" "commit 前の自己チェック" "$_eci_body"
out_has "正本 doc-placement.md が存在"    "置き場"         "$(cat "$H/rules/doc-placement.md" 2>/dev/null)"
out_has "正本 grounding-labels.md が存在" "接地ラベル"     "$(cat "$H/rules/grounding-labels.md" 2>/dev/null)"
_gl_body="$(cat "$H/rules/grounding-labels.md" 2>/dev/null)"
out_has "grounding-labels: 実測ラベルが定義済み" "✓実測 <観測構成>" "$_gl_body"
out_has "grounding-labels: 観測構成の要件(何をどう動かして何を観測したか)を明記" "何をどう動かして何を観測したか" "$_gl_body"
out_has "grounding-labels: 未検証の実行時主張も補完・前提節に残す運用を明記" "動かさないと決着しない実行時の主張が未検証のまま残る場合" "$_gl_body"
_gd_body="$(cat "$H/skills/grounded-design/SKILL.md" 2>/dev/null)"
out_has "grounded-design: 読んで決着するか/動かさないと決着しないかの判定工程を明記" "動かさないと決着しないかを判定する" "$_gd_body"
out_has "grounded-design: 動かさないと決着しない主張は researcher で裏取りできない旨を明記" "researcher\` では裏取りできない" "$_gd_body"
out_has "grounded-design: 報告に書かれた原因は接地でない旨を明記" "報告に書かれた原因は接地ではない" "$_gd_body"
out_has "grounded-design: 検証が重い場合は主体判断で issue 化してよい旨を明記" "主体の判断で検証を独立した issue として切ってよい" "$_gd_body"
out_has "grounded-design: 未検証のまま受け入れ条件を確定させない旨を明記" "その主張に依存する受け入れ条件を確定させない" "$_gd_body"
out_has "正本 agent-watchdog.md が存在"   "watchdog"       "$(cat "$H/rules/agent-watchdog.md" 2>/dev/null)"
out_has "正本 implement-routing.md が存在" "実装ルーティング" "$(cat "$H/rules/implement-routing.md" 2>/dev/null)"
out_has "implement-routing: 上流 design-routing への相互リンク" "design-routing" "$(cat "$H/rules/implement-routing.md" 2>/dev/null)"
out_has "正本 sensitive-data.md が存在"   "センシティブデータ" "$(cat "$H/rules/sensitive-data.md" 2>/dev/null)"
out_has "正本 naming.md が存在"          "命名の優先順位"     "$(cat "$H/rules/naming.md" 2>/dev/null)"
out_has "naming.md: 優先順位(正本文書→ドメイン一般語→新語)を明記" "正本文書に既にある語" "$(cat "$H/rules/naming.md" 2>/dev/null)"
out_has "naming.md: 新語作成時の他分野衝突チェックを明記" "他分野で別の意味を持たないか" "$(cat "$H/rules/naming.md" 2>/dev/null)"
out_has "正本 design-routing.md が存在"   "設計ルーティング" "$(cat "$H/rules/design-routing.md" 2>/dev/null)"
out_has "design-routing: Direct 明示除外を明記" "Direct" "$(cat "$H/rules/design-routing.md" 2>/dev/null)"
out_has "design-routing: implement-routing との接続を明記" "implement-routing" "$(cat "$H/rules/design-routing.md" 2>/dev/null)"
file_is "skill: deliberate-design が存在" "$H/skills/deliberate-design/SKILL.md"
out_has "deliberate-design: design-routing への名前参照" "design-routing" "$(cat "$H/skills/deliberate-design/SKILL.md" 2>/dev/null)"

echo "== promote-knowledge skill =="
file_is "skill: promote-knowledge が存在" "$H/skills/promote-knowledge/SKILL.md"
out_has "promote-knowledge: 明示実行のみ(disable-model-invocation)" "disable-model-invocation: true" "$(cat "$H/skills/promote-knowledge/SKILL.md" 2>/dev/null)"
out_has "promote-knowledge: value gate を capture-learning 参照" "capture-learning" "$(cat "$H/skills/promote-knowledge/SKILL.md" 2>/dev/null)"
out_has "promote-knowledge: de-localize 手順を明記" "de-localize" "$(cat "$H/skills/promote-knowledge/SKILL.md" 2>/dev/null)"
out_has "promote-knowledge: 昇格後の move 規則を明記" "昇格＝move" "$(cat "$H/skills/promote-knowledge/SKILL.md" 2>/dev/null)"
out_has "promote-knowledge: entry file のみ・INDEX.md は含めない" "INDEX.md は含めない" "$(cat "$H/skills/promote-knowledge/SKILL.md" 2>/dev/null | tr -d '\`')"
echo "== promote-knowledge: 引用照合ゲート(source: を持つ候補を原典と照合。真偽軸の正本は knowledge.md へ hoist 済み) =="
_pk_skill_body="$(cat "$H/skills/promote-knowledge/SKILL.md" 2>/dev/null)"
out_has "promote-knowledge: 引用照合ゲートの手順が存在" "引用照合ゲート" "$_pk_skill_body"
out_has "promote-knowledge: 真偽軸の共通手順をknowledge.mdへ名前参照(再記述しない)" "書き方不変: 引用照合ゲート」節（本 skill には再記述しない）" "$_pk_skill_body"
out_has "promote-knowledge: 原典と矛盾したら昇格を止めて人間へ差し戻す旨を明記(loud停止・昇格時点固有の帰結)" "昇格を止めて人間へ差し戻す" "$_pk_skill_body"
out_has "promote-knowledge: 矛盾時に候補を静かに local へ降格しない旨を明記(自動降格しない)" "候補を静かに \`scope: local\` へ降格しない" "$_pk_skill_body"
out_has "promote-knowledge: 一致時は手順6(ストアclone)へ進む旨を明記" "手順6（ストア clone）へ進む" "$_pk_skill_body"
out_has "promote-knowledge: 照合不能時も到達不能である旨と試みたURLを人間へ報告する旨を明記(矛盾ブランチと対称・hoist時のsilent drop再発防止)" "到達不能である旨と試みた URL を人間へ報告する" "$_pk_skill_body"
out_has "promote-knowledge: 原則に引用照合ゲートの省略禁止を明記" "引用照合ゲートを省略しない" "$_pk_skill_body"

echo "== promote-knowledge: 検証の種類による分類・案件固有判断混入確認・非局所化の剥がすもの区別・相互参照確認 =="
out_has "promote-knowledge: 分類の工程が独立した手順として存在" "## 2. 分類（検証の種類で束ねる）" "$_pk_skill_body"
out_has "promote-knowledge: 分類軸は技術領域ではないことを明記" "「どの技術の話か」ではない" "$_pk_skill_body"
out_has "promote-knowledge: 件数で機械的に区切らない旨を明記" "件数で機械的に区切らない" "$_pk_skill_body"
out_has "promote-knowledge: 外部要件由来の分類と確認条件(原典に書いてあるか)を明記" "外部要件由来" "$_pk_skill_body"
out_has "promote-knowledge: 外部要件由来はURL生存と主張支持が別である旨を明記" "出典 URL が生きていることと、主張を支持していることは別" "$_pk_skill_body"
out_has "promote-knowledge: ライブラリ挙動由来の分類と確認条件(どの版で観測したか)を明記" "ライブラリ挙動由来" "$_pk_skill_body"
out_has "promote-knowledge: ライブラリ挙動由来は確認した版を本文に記録する旨を明記" "確認した版を本文に記録する" "$_pk_skill_body"
out_has "promote-knowledge: 版の構造化は別途の議論に委ねる旨を明記(frontmatter構造化issueとの責務分担)" "frontmatter への構造化は別途の議論に委ねる" "$_pk_skill_body"
out_has "promote-knowledge: 手法・技法の分類と確認条件(読者が再現できるか)を明記" "手法・技法の記録" "$_pk_skill_body"
out_has "promote-knowledge: 手法・技法は前提条件の明示を確認する旨を明記" "前提条件が明示されているか" "$_pk_skill_body"
out_has "promote-knowledge: 実装上の落とし穴の分類と確認条件(他の解が誤りである理由)を明記" "実装上の落とし穴" "$_pk_skill_body"
out_has "promote-knowledge: 落とし穴はXが駄目な理由とYが最適である前提の明示を確認する旨を明記" "Y が最適である前提" "$_pk_skill_body"
out_has "promote-knowledge: 案件固有の判断混入チェックが value gate に存在" "案件固有の判断が混入していないかを確認する" "$_pk_skill_body"
out_has "promote-knowledge: 混入時は部分昇格し一般部分と固有部分を分ける旨を明記" "部分昇格" "$_pk_skill_body"
out_has "promote-knowledge: 案件固有判断チェックがcapture-learningの書き込み前自己チェックとは別軸(最後の砦)である旨を明記(責務分担)" "昇格時点の最後の砦として再度確認する" "$_pk_skill_body"
out_has "promote-knowledge: de-localizeで第三者ライブラリ名・API名・版は剥がさない旨を明記" "第三者ライブラリ名・API 名・バージョン番号は対象外（剥がさない）" "$_pk_skill_body"
out_has "promote-knowledge: 相互参照が宙に浮いていないかの確認項目を明記" "相互参照の解決確認" "$_pk_skill_body"
out_has "promote-knowledge: 原則に分類の省略禁止を明記" "検証の種類による分類を省略しない" "$_pk_skill_body"
out_has "promote-knowledge: 原則に案件固有判断混入確認の省略禁止を明記" "案件固有の判断の混入確認を省略しない" "$_pk_skill_body"
echo "== promote-knowledge: 部分昇格の元ネタ保持(ストアPRマージまで原本を編集・削除しない) =="
out_has "promote-knowledge: 部分昇格の書き直し元ネタは原本entryそのものである旨を明記" "書き直しの元ネタは、混入が見つかった元の entry ファイルそのもの" "$_pk_skill_body"
out_has "promote-knowledge: 部分昇格候補は手順4以降を作業用コピーへ適用し原本を直接編集しない旨を明記" "原本を直接編集せず、複製した作業用コピーに対して行う" "$_pk_skill_body"
out_has "promote-knowledge: de-localize手順の冒頭で部分昇格候補は作業用コピーへ適用する旨を再掲" "この手順以降を作業用コピーに対して行う" "$_pk_skill_body"
out_has "promote-knowledge: ストアPRマージまで原本の全文を参照できる状態を保つ旨を明記" "いつでも元の全文を参照できる状態を保つ" "$_pk_skill_body"
out_has "promote-knowledge: moveでは部分昇格候補は削除ではなく原本の書き直しである旨を明記(通常moveとの違い)" "削除ではなく書き直し" "$_pk_skill_body"
out_has "promote-knowledge: 書き直しが完了し保存されるまで原本を削除しない旨を明記" "書き直しが完了し保存されるまでは原本を削除しない" "$_pk_skill_body"
# 正本(knowledge.md)の書き込み前自己チェック文言を逐語コピーしていないこと(/の責務分担・drift回避)
out_hasnt "promote-knowledge: 書き込み前自己チェックの正本見出しを逐語コピーしていない(名前参照のみ)" "書き方不変: 書き込み前の自己チェック" "$_pk_skill_body"
out_hasnt "promote-knowledge: 書き込み前自己チェックの三つの問い(固有の事実と一般形)を逐語コピーしていない(正本のみが持つ)" "固有の事実と一般形が混ざっていないか" "$_pk_skill_body"

echo "== federation-aware promotion: promote-knowledge が workspace 一括で member repo を読み下ろす =="
_pk_body="$(cat "$H/skills/promote-knowledge/SKILL.md" 2>/dev/null)"
out_has "promote-knowledge: workspace 設定を収集手順に明記" "yosage-dev-harness-config-get workspace" "$_pk_body"
out_has "promote-knowledge: member repo を読み下ろして集約する旨を明記" "各 member repo" "$_pk_body"
out_has "promote-knowledge: 設定無しは cwd 単体の後方互換を明記" "後方互換" "$_pk_body"
out_has "promote-knowledge: 由来 repo を控えて move で使う旨を明記" "由来 repo" "$_pk_body"
out_has "promote-knowledge: cross-repo move（member repo 由来はその repo で削除）を明記" "cross-repo 化" "$_pk_body"
out_has "promote-knowledge: member 側の削除も標準 PR ループに乗せる旨を明記" "各 member の標準 PR ループ" "$_pk_body"

echo "== promote-knowledge: 収集ロジックは lib スクリプト呼び出し(brace-obfuscation ガード回避) =="
# SKILL の動的コンテキストがインラインのブレースグループ`{ …; }`＋クォートを直書きしていると、
# ホスト側の permission チェック(ブレース+クォートの組み合わせを難読化コマンドとみなすヒューリスティック)に
# 弾かれ SKILL 起動自体が失敗する。収集ロジックは lib スクリプトへ出し、SKILL 側は単純呼び出しにする。
out_has "promote-knowledge: 生層収集は lib スクリプト呼び出し" "yosage-dev-harness-promote-collect entries" "$_pk_body"
out_has "promote-knowledge: 蒸留層収集は lib スクリプト呼び出し" "yosage-dev-harness-promote-collect criteria" "$_pk_body"
out_hasnt "promote-knowledge: 動的コンテキストにインラインのブレースグループ+クォートが残っていない" '{ grep' "$_pk_body"
out_hasnt "promote-knowledge: 動的コンテキストにインラインのブレースグループ+クォートが残っていない(criteria側)" '{ [ -f' "$_pk_body"
file_is "lib: promote-collect.sh が存在" "$H/lib/promote-collect.sh"

# 動的コンテキストの収集コマンド自体を fixture で検証(SKILL の `!`command`` は skill-load 時実行なので、
# lib スクリプトを workspace/単一 repo の両モードで正しく分岐することを直接叩いて確認する)。
_pk_ws="$(mktemp -d)"
mkdir -p "$_pk_ws/.claude/knowledge/api" "$_pk_ws/member1/.claude/knowledge/testing" "$_pk_ws/member1/.git" "$_pk_ws/member2/.claude/knowledge/ops" "$_pk_ws/member2/.git"
cat > "$_pk_ws/.claude/knowledge/api/entry1.md" <<'PKEOF'
---
id: e1
scope: global
status: active
---
self entry
PKEOF
cat > "$_pk_ws/member1/.claude/knowledge/testing/entry2.md" <<'PKEOF'
---
id: e2
scope: global
status: active
---
member1 entry
PKEOF
cat > "$_pk_ws/member2/.claude/knowledge/ops/entry3.md" <<'PKEOF'
---
id: e3
scope: global
status: active
---
member2 entry
PKEOF
# status: superseded な global entry(自ストア側)は収集されないことも確認する(一次レビュー Nit の回帰防止:
# 説明文は "scope: global かつ status: active" だが実装 grep が scope: global だけしか見ていなかったギャップ)。
cat > "$_pk_ws/.claude/knowledge/api/entry-old.md" <<'PKEOF'
---
id: e-old
scope: global
status: superseded
---
superseded entry(収集対象外)
PKEOF
_pk_collect() {  # <workspace-root>  (SKILL.md が呼ぶのと同じ lib スクリプトを直接叩く)
  ( cd "$1" && bash "$H/lib/promote-collect.sh" entries )
}
_pk_out_single="$(_pk_collect "$_pk_ws")"
out_hasnt "promote-knowledge収集: マーカー無しは member を読み下ろさない(単一 repo 後方互換)" "member1" "$_pk_out_single"
out_has "promote-knowledge収集: マーカー無しでも自ストアは拾う" ".: .claude/knowledge/api/entry1.md" "$_pk_out_single"
out_hasnt "promote-knowledge収集: status: superseded な自ストア entry は収集しない" "entry-old.md" "$_pk_out_single"
printf '{ "workspace": true }\n' > "$_pk_ws/.claude/yosage-dev-harness.local.json"
_pk_out_ws="$(_pk_collect "$_pk_ws")"
out_has "promote-knowledge収集: workspace モードで member1 の staged entry を集約" "member1: member1/.claude/knowledge/testing/entry2.md" "$_pk_out_ws"
out_has "promote-knowledge収集: workspace モードで member2 の staged entry を集約" "member2: member2/.claude/knowledge/ops/entry3.md" "$_pk_out_ws"
out_has "promote-knowledge収集: workspace モードでも自ストアを含む" ".: .claude/knowledge/api/entry1.md" "$_pk_out_ws"
out_hasnt "promote-knowledge収集: workspace モードでも status: superseded は収集しない" "entry-old.md" "$_pk_out_ws"
rm -rf "$_pk_ws"

echo "== promote-knowledge: 手順8の gh pr create を --repo/--head/--title/--assignee 明示に =="
out_has "promote-knowledge: gh pr create に --repo を明示" "gh pr create --repo" "$_pk_body"
out_has "promote-knowledge: gh pr create に --head を明示" "--head <branch>" "$(printf '%s' "$_pk_body" | tr -d '\`')"
out_has "promote-knowledge: gh pr create に --title を明示" "--title \"<title>\"" "$(printf '%s' "$_pk_body" | tr -d '\`')"
out_has "promote-knowledge: gh pr create に --assignee @me を明示" "--assignee @me" "$(printf '%s' "$_pk_body" | tr -d '\`')"
out_has "promote-knowledge: 一時 clone からの auto-detect 失敗を注記" "auto-detect" "$_pk_body"

echo "== federation-aware recall: librarian / recall-knowledge が member でも直接列挙を方向つきで行う =="
out_has "librarian: 方向つき federation-aware recall を明記" "方向つき federation-aware recall" "$(cat "$H/agents/librarian.md" 2>/dev/null)"
out_has "librarian: workspace/orchestrator は member でも同じ直接列挙を行う" "各 member repo でも同じ直接列挙を行う" "$(cat "$H/agents/librarian.md" 2>/dev/null | tr -d '\`')"
out_has "librarian: member セッションは自ストア+global のみ(上・兄弟へ読み上げない)" "member セッション" "$(cat "$H/agents/librarian.md" 2>/dev/null)"
out_has "librarian: workspace 判定は設定(yosage-dev-harness-config-get workspace)を一次シグナルにする" "yosage-dev-harness-config-get workspace" "$(cat "$H/agents/librarian.md" 2>/dev/null)"
out_has "librarian: マーカー無し consumer 向けフォールバックの .git 子ディレクトリ検知を明記" "を持つ子ディレクトリが複数ある" "$(cat "$H/agents/librarian.md" 2>/dev/null)"
out_hasnt "librarian: 暫定/将来置換予定の符牒的注記が消えている" "そのシグナルへ置き換える" "$(cat "$H/agents/librarian.md" 2>/dev/null)"
out_has "recall-knowledge: 索引範囲に方向つきスコープを明記" "方向つき" "$(cat "$H/skills/recall-knowledge/SKILL.md" 2>/dev/null)"
out_has "recall-knowledge: workspace で member でも同じ直接列挙を行う旨を明記" "member repo でも同じ直接列挙を行う" "$(cat "$H/skills/recall-knowledge/SKILL.md" 2>/dev/null | tr -d '\`')"

echo "== librarian: 検証手段(安定ハンドル/source:)を持たないエントリに検証済みの顔(✓)を偽装しない新設鮮度判定 =="
# 安定ハンドルも source: も無いエントリは、内部向け(ハンドル再解決)・外部向け(checked:経過)のどちらの
# 検証手段も適用できない。それを✓接地確認として返すと「検証していないのに検証済みの顔」になるため、
# 新設判定を持つ(既存の⚠要確認には寄せない=主体が取るアクションが違うため)。
_lib_body="$(cat "$H/agents/librarian.md" 2>/dev/null | tr -d '\`')"
out_has "librarian: 検証手段が無いエントリ向けの新設鮮度判定シンボルがある" "∅接地対象なし" "$_lib_body"
out_has "librarian: 手順5に接地対象なしの分岐を持ち検証手段が構造的に存在しないと言明" "検証手段が構造的に存在しない" "$_lib_body"
out_has "librarian: 接地対象なしのエントリには✓接地確認を付けないと明言(検証していないことを偽装しない)" "この場合は ✓接地確認 を付けない" "$_lib_body"
out_has "librarian: 深掘り上限に掛かっただけ(ハンドルはある)のケースは引き続き✓を出してよいと境界を明確化" "上限に掛かって意味的検証を省いたエントリにも ✓接地確認 を出してよい" "$_lib_body"
out_has "librarian: 新設判定は⚠要確認(調べる価値がある)と意味/アクションが違うため混ぜないと明記" "調べても何も出ない」種類の知識であり、混ぜない" "$_lib_body"
out_has "librarian: カバレッジ宣言の書式に検証手段なしの件数を含める" "検証手段なし K 件" "$_lib_body"
out_has "librarian: 手順6の昇格候補ゲートは接地対象なしのentryも通す(取っ手を持てないことを理由に昇格を妨げない)" "✓接地確認 または ∅接地対象なし" "$_lib_body"
out_has "librarian: 原則の「鮮度を必ず付ける」を新設判定の履行として整合させる" "検証手段そのものが無いエントリに ✓ を偽装しない" "$_lib_body"
# ネガティブコントロール: 既存の⚠要確認の凡例行に新設判定を混ぜ込んでいない(別判定として独立させ、
# ⚠が「どうせ直せない件」で埋もれてオオカミ少年化するのを避ける)ことを行単位で確認する。
_lib_warn_line="$(printf '%s\n' "$_lib_body" | grep -F '⚠要確認 —')"
out_hasnt "librarian: ⚠要確認の凡例行に新設判定(接地対象なし)を混ぜていない" "接地対象なし" "$_lib_warn_line"

echo "== knowledge-audit.sh: 9項目の決定論監査(fixture) =="
ka="$(mktemp -d)"
gitc -C "$ka" init -q
mkdir -p "$ka/.claude/knowledge/harness-dev" "$ka/.claude/knowledge/global/harness" \
         "$ka/harness/skills/sample-skill" "$ka/harness/agents" "$ka/harness/rules" \
         "$ka/harness/lib" "$ka/harness/hooks" "$ka/harness/review" "$ka/harness/lib/(group)" \
         "$ka/harness/lib/(group)/sub" "$ka/bin" "$ka/.docs" "$ka/.git/info"
# 監査スクリプト自身のプラグインルート(BASH_SOURCE から自己解決)を fixture 自身の harness/ に
# させるため、実体のコピーをそこへ置いて呼ぶ(mk_ka_copy。common.sh 参照)。
mk_ka_copy "$ka"
printf -- '---\nname: sample-skill\ndescription: d\n---\nbody\n' > "$ka/harness/skills/sample-skill/SKILL.md"
printf -- '---\nname: sample-agent\ndescription: d\n---\nbody\n' > "$ka/harness/agents/sample-agent.md"
printf '# Sample Rule\n\n> note\n' > "$ka/harness/rules/sample-rule.md"
printf 'l1\nl2\nl3\n' > "$ka/harness/lib/real.sh"
printf '#!/usr/bin/env bash\necho hi\n' > "$ka/harness/hooks/real-hook.sh"
# 括弧を含むディレクトリ(ルートグループ記法等)配下の実在ファイル(偽陽性クラス1の回帰用)。
printf 'l1\nl2\nl3\n' > "$ka/harness/lib/(group)/real-paren.sh"
# 括弧の直後にさらにサブディレクトリを挟む実在ファイル(一次レビュー: PATHLINE_RE の
# truncation バグは、括弧の直後がファイル名1階層だけだと再現しない。PATHLINE_RE は
# `seg1/[middle]*\.ext:num` という形で、seg1 の直後に必ず `/` を要求するため、括弧で
# 一致が切れた残りが「単一セグメント + 拡張子」だと `/` が無く、そもそもマッチ自体が
# 起きない。実際に truncation で誤ったパスを拾い直す(=偽陽性が起きる)には、括弧の後ろに
# もう1段ディレクトリが要る)。
printf 'l1\nl2\nl3\n' > "$ka/harness/lib/(group)/sub/real-paren-line.sh"
# 大文字拡張子の実在ファイル(二次レビュー: 拡張子 allowlist の照合は大文字小文字を
# 区別してはいけない。実ファイルシステムには `README.MD` のような大文字拡張子が実在しうる)。
printf '# Real Upper\n' > "$ka/harness/lib/REAL-UPPER.MD"
# 大文字拡張子・path:line 形式の実在ファイル(二次レビュー総ざらいで判明: `BARE_PATH_RE` の
# 大文字小文字無視は bare backtick(拡張子一致)側でしか検証しておらず、`PATHLINE_RE`(行番号
# 一致)側は同じ `re.IGNORECASE` を付けたのに独立した検証が無かった。「対になった修正の片方
# だけテストする」という同型の穴のため、path:line 側にも専用の実在/実在しないファイルを置く)。
printf 'l1\nl2\nl3\n' > "$ka/harness/lib/REAL-UPPER-LINE.MD"
# allowlist を配布先(consumer)基準へ広げたカテゴリの実在ファイル(二次レビュー総ざらいで判明:
# 広げたこと自体は手動の scratch 検証でしか確かめておらず、恒久的な回帰テストが無かった。
# 代表として元々このリポジトリには実例の無かった tf/rb/yaml を置く)。
printf 'resource "x" {}\nline2\nline3\n' > "$ka/harness/lib/real-infra.tf"
printf 'class X; end\nline2\nline3\n' > "$ka/harness/lib/real-script.rb"
printf 'key: value\nline2\nline3\n' > "$ka/harness/lib/real-config.yaml"
# review/criteria.md は sync 生成物で gitignore(実物の harness/review/.gitignore と同じ形)。
printf 'criteria.md\n' > "$ka/harness/review/.gitignore"

# check1: 裸の#N(repo未明記)を検知しつつ、repo明示済みは誤検知しない
printf -- '---\nid: e-bare\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nissue '"$HSH"'501 bare. yosage-dev-harness'"$HSH"'502 qualified.\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-bare.md"

# check1: 連続する issue 参照を "owner/repo#N/N" のようにスラッシュ区切りで列挙・範囲で書くと、
# 「#の直前が/」で qualified 誤判定され2つめ以降が見逃されていた偽陰性の回帰。1つめは repo 明示済みで
# 誤検知しない一方、2つめは裸として検出されるべき。
printf -- '---\nid: e-bare-slash-enum\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nyosage-dev-harness'"$HSH"'191/'"$HSH"'192 のように列挙で書くと2つめが見逃されていた。\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-bare-slash-enum.md"

# check1: URL のパス・フラグメントに含まれる #N を裸参照と誤検知しない(`/` を qualified
# 文字集合から外した副作用の回帰。裸URL・markdownリンクの両方の形を覆う)。地の文の実参照
# は同じ行構成の中でも引き続き検出される(偽陰性テスト)。
printf -- '---\nid: e-bare-url-fragment\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n裸URL: https://example.com/issues/'"$HSH"'601 は誤検知しない。\n\nmarkdownリンク: [詳細](https://example.com/pulls/'"$HSH"'602) も誤検知しない。\n\n地の文の実参照: '"$HSH"'603 はこの通り検出される。\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-bare-url-fragment.md"

# check1(一次レビュー): URL の直後に空白なしで地の文が続く場合(日本語では常態)の偽陰性回帰。
# check3 専用の `URL_RE`(末尾 `\S*` で空白でしか止まらない)を url_spans() へ転用すると、URL の
# 直後に空白なしで続く地の文まで丸ごと URL 範囲として飲み込み、その先の #N を見逃す
# (元の用途「URL を消せればよい」(消しすぎ許容)と、この用途「URL の範囲を正確に取る」
# (消しすぎ不可)は要件が違う primitive の転用によるバグ)。URL の前に地の文がある形・URL の後に
# 読点で地の文が続く形の両方を、地の文の実参照(//)が検出されることで確認する。
# markdownリンクの閉じ括弧直後に空白なしで地の文が続く形も、URL フラグメント自体は
# 引き続き誤検知しないことと合わせて確認する。
printf -- '---\nid: e-bare-url-no-space\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n詳細はhttps://example.com/docsを参照。この件は'"$HSH"'901で報告されている問題と関連する。\n\n参考: https://e.invalid/a、'"$HSH"'902も別件です。\n\n'"$HSH"'903 の件は https://e.invalid/x を見よ(URL前の地の文)。\n\n[x](https://e.invalid/p'"$HSH"'904)を見た'"$HSH"'905という報告あり。\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-bare-url-no-space.md"

# check1: 「参照」と「例示」の区別。インラインコード・フェンスされたコードブロック内の #N は
# 例示(書き方自体の説明・再現用の入力リテラル)として検出対象外にしつつ、地の文の #N は引き続き検出する
# (偽陽性を偽陰性にすり替えていないことを両方向で確認する)。
printf -- '---\nid: e-bare-codespan\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n禁止パターンの見本: `'"$HSH"'910` のように裸番号で書いてはいけない。\n\n```\nplain ascii issue '"$HSH"'912 here\n```\n\n地の文の実参照: '"$HSH"'911 はこの通り検出される。\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-bare-codespan.md"

# check1: ダブルバッククォート(以上)のコードスパンは CommonMark の正式な構文
# (開始のバッククォート"連続列"と同じ長さの列で閉じる。スパン内にリテラルのバッククォートを
# 埋め込める)。単一バッククォート前提の素朴な判定だと、この中の #N を地の文と誤認して
# 誤検知する。地の文の #N は引き続き検出されることも同じ fixture で確認する(偽陰性テスト)。
printf -- '---\nid: e-bare-doublebacktick\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n``code with ` inside '"$HSH"'207``\n\n地の文の実参照: '"$HSH"'208 はこの通り検出される。\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-bare-doublebacktick.md"

# check1: inline_code_spans() の delimiter 横取りバグ(一次レビューで発見)。同じ行に「内部へ
# リテラルバッククォートを埋め込んだダブルバッククォートスパン」と、その後に続く別の単一
# バッククォートスパンが同居すると、旧実装(行全体の run を先頭から同じ長さ同士で総当りペア
# リング)は前者の内部リテラル backtick を「未使用」のまま残し、後続の無関係な run と誤って
# ペアリングしてしまい、後者のスパン内にあるはずの #N を地の文=bare と誤検知していた
# (Python 版 CommonMark 参照実装(`commonmark`パッケージ)で実際に parse し、`` が
# `<code>` タグの内側になることを確認済み)。単一・二重・三重が混在する行、および地の文の
# #N が引き続き検出されること(偽陰性テスト)も同じ fixture で確認する。
printf -- '---\nid: e-bare-delimiter-hijack\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n``x ` y`` の後に `'"$HSH"'301` がある。\n\nsingle `a` double ``p ` q`` triple ```r``` and narrative '"$HSH"'401 here.\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-bare-delimiter-hijack.md"

# check2: travel面(グローバルミラー自身 / scope:global の staging local)に issue番号が残っている
printf -- '---\nid: e-store\ndate: 2026-01-01\ndomain: harness\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\nyosage-dev-harness'"$HSH"'503 leaked into store.\n' \
  > "$ka/.claude/knowledge/global/harness/2026-01-01-e-store.md"
printf -- '---\nid: e-staged\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\nyosage-dev-harness'"$HSH"'504 leaked while staged.\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-staged.md"

# check2: travel面でも同じ区別を適用する。フェンスされたコードブロック内の再現用入力リテラルや
# インラインコード内の例示は検出対象外にしつつ、地の文の #N は引き続き検出する。
printf -- '---\nid: e-store-codespan\ndate: 2026-01-01\ndomain: harness\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\n実測の再現例:\n\n```\nplain ascii issue '"$HSH"'920 here\n```\n\nインラインの例示 `'"$HSH"'922` も対象外。地の文で leaked: '"$HSH"'921 (検出される)。\n' \
  > "$ka/.claude/knowledge/global/harness/2026-01-01-e-store-codespan.md"

# check2: travel面でもダブルバッククォートのコードスパンを正しく1スパンとして扱う。
printf -- '---\nid: e-store-doublebacktick\ndate: 2026-01-01\ndomain: harness\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\n``code with ` inside '"$HSH"'925``\n\n地の文で leaked: '"$HSH"'926 (検出される)。\n' \
  > "$ka/.claude/knowledge/global/harness/2026-01-01-e-store-doublebacktick.md"

# check3: 破損したパス参照(実在しない path / 行超過の path:line)。実在参照は誤検知しない。
# path:line 形式は「## 根拠 / 実例」節の中だけを検査する(節の外の自己言及的な例示は対象外)。
printf -- '---\nid: e-path\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/lib/real.sh`(実在) `harness/lib/real.sh:2`(実在行) `harness/lib/real.sh:999`(行超過) `harness/lib/missing.sh`(実在しない)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path.md"
# check3: 「## 根拠 / 実例」節の外(判断/ルール節)にある path:line は、実在しなくても検査対象外
# (grounding-check-resolves-paths-repo-root-relative が判断/ルール節で架空の foo.sh を例示している実例と同型)。
printf -- '---\nid: e-path-narrative\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 判断 / ルール\n例: `harness/hooks/foo.sh:12`。bare `hooks/foo.sh:12` も同様。\n\n## 根拠 / 実例\n- 内部: `harness/lib/real.sh`\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-narrative.md"
# check3(一次レビュー対応): repo ルート/`.claude/` プレフィックスのどちらも無い prefix 省略パス
# (`hooks/real-hook.sh`)は、CANDIDATE_ROOTS が plugin_root を候補にする経路を撤去したため、
# 実在するファイルを指していても broken-path-ref として検出される(論理パス `yosage-dev-harness:
# hooks/real-hook.sh` か、導入先パス `.claude/hooks/real-hook.sh` のどちらかで書く必要がある。
# 「CLI の撤去の段で入れたプラグインのルート直下を候補にする解決は、論理パスの解決に置き換える」
# という要求に対応)。
printf -- '---\nid: e-path-prefix\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n- 内部: `hooks/real-hook.sh`(prefix省略。実在するが検出される)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-prefix.md"
# check3: gitignore された/opt-in の領域(review/criteria.md 等)は実在を判定できないため skip する
printf -- '---\nid: e-path-ignore\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n- 内部: `review/criteria.md`(sync生成物でgitignore)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-ignore.md"
# check3: `...` 省略記法は何を省略したか本文からは決定できないため skip する
printf -- '---\nid: e-path-ellipsis\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n- 内部: `.../skills/foo/SKILL.md`(省略記法)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-ellipsis.md"
# check3(偽陽性クラス1): セグメントに括弧を含む実在パスは、bare backtick(拡張子一致・
# `BARE_PATH_RE`)・path:line(行番号一致・`PATHLINE_RE`)のどちらの形でも誤検知しない。同じ
# エントリの中に括弧を含む「実在しない」パスも入れ、括弧を許すようにしたことで真の検出
# (broken-path-ref)まで一緒に消えていないことも同時に確認する(偽陽性を消す変更が真陽性を
# 巻き添えにしていないかの回帰)。
#
# 一次レビューで判明した点: `PATHLINE_RE` の truncation バグ(括弧の後ろを独立パスとして拾い
# 直す)は、括弧の直後に**もう1段ディレクトリ**が無いと再現しない(上のコメント参照)。単一階層
# (`(group)/real-paren.sh:2`)の path:line 参照だけでは、旧実装(括弧を文字クラスに含めない版)
# でもそもそも一切マッチせず、`out_hasnt`(偽陽性が無いことの確認)は「旧実装でも新実装でも
# 無出力」という理由だけで通ってしまい、括弧サポート自体を revert しても検知できない
# (mutation で確認済み)。このため path:line 形式の回帰は、上の `sub/real-paren-line.sh`
# (括弧の後ろにもう1段ある実在ファイル)を使った別エントリ(e-path-paren-nested)で確認する
# (bare backtick 側の単一階層アサーションは、`BARE_PATH_RE` が単離済みトークンへの完全一致
# 判定であり truncation が構造的に起きえないため、階層を深くしても mutation 感度は変わらない
# ——このアサーションの mutation 感度は「括弧を含む実在しないパスが引き続き検出される」側が
# 担う。詳細は追加した knowledge エントリを参照)。
printf -- '---\nid: e-path-paren\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/lib/(group)/real-paren.sh`(括弧を含む実在パス) `harness/lib/(group)/real-paren.sh:2`(括弧を含む実在行) `harness/lib/(group)/missing-paren.sh`(括弧を含むが実在しない)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-paren.md"
# check3(偽陽性クラス1・一次レビュー対応): `PATHLINE_RE` の truncation バグの直接再現。
# 括弧の後ろにもう1段ディレクトリ(`sub/`)を挟むことで、旧実装は `/sub/real-paren-line.sh:2`
# (括弧の前が失われた誤ったパス)として実在ファイルを broken 扱いする。修正後は正しいフルパス
# でのみ判定し、実在ファイルは誤検知せず・実在しないファイルは正しいフルパスで検出される。
printf -- '---\nid: e-path-paren-nested\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/lib/(group)/sub/real-paren-line.sh:2`(括弧の後ろにさらにセグメントがある実運用形・実在) `harness/lib/(group)/sub/missing-paren-line.sh:3`(同形だが実在しない)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-paren-nested.md"
# check3(偽陽性クラス2): 構造がパスと同型の非パス識別子(GCP IAM ロール ID)は、拡張子
# allowlist に無いため path として拾われず誤検知しない。
printf -- '---\nid: e-path-roleid\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nIAM ロール: `roles/run.invoker` と `roles/iam.serviceAccountUser` を付与する。\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-roleid.md"
# check3(二次レビュー対応): 拡張子 allowlist の照合は大文字小文字を無視する。大文字拡張子の
# 実在パスは誤検知せず、大文字拡張子の実在しないパスは引き続き検出される(allowlist 化そのものが
# 生んだ regression。旧実装は `[A-Za-z0-9]+` で大文字小文字を区別せず拾えていた)。
printf -- '---\nid: e-path-case\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n- 内部: `harness/lib/REAL-UPPER.MD`(大文字拡張子・実在) `harness/lib/MISSING-UPPER.MD`(大文字拡張子・実在しない)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-case.md"
# check3(二次レビュー総ざらいで追加): `PATHLINE_RE`(path:line 形式)側の大文字小文字無視を
# bare backtick 側とは独立に検証する(`BARE_PATH_RE` に対する検証だけでは `PATHLINE_RE` の
# `re.IGNORECASE` が抜けても検知できない。mutation で確認済み)。
printf -- '---\nid: e-path-case-line\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/lib/REAL-UPPER-LINE.MD:2`(大文字拡張子・path:line・実在) `harness/lib/MISSING-UPPER-LINE.MD:3`(大文字拡張子・path:line・実在しない)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-case-line.md"
# check3(二次レビュー総ざらいで追加): allowlist を配布先基準へ広げたカテゴリが実際に
# 効いていることの恒久的な回帰テスト(以前は scratch での手動実測のみで、テストコードに反映
# していなかった)。実在パスは誤検知せず、実在しないパスは新たに検出される。
printf -- '---\nid: e-path-ext-broadened\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n- 内部: `harness/lib/real-infra.tf`(実在) `harness/lib/missing-infra.tf`(実在しない) `harness/lib/real-script.rb`(実在) `harness/lib/missing-script.rb`(実在しない) `harness/lib/real-config.yaml`(実在) `harness/lib/missing-config.yaml`(実在しない)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-ext-broadened.md"
# check3(三次レビュー対応・「片方だけ」型の4件目): 広げた allowlist カテゴリの回帰テストが
# bare backtick 形式にしかなく、path:line 形式(`PATHLINE_RE`)側が未検証だった。`PATHLINE_RE` の
# 拡張子リストだけを狭い版に戻す mutation を自分で当てて確認したところ、`real-infra.tf:2` のような
# 参照が実在・実在しないパスのどちらでも完全に沈黙する(=既存アサーションのどれも検知しない)ことを
# 再現した。path:line 側専用の実在/実在しないファイル参照を追加する。
printf -- '---\nid: e-path-ext-broadened-line\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/lib/real-infra.tf:2`(実在) `harness/lib/missing-infra.tf:3`(実在しない) `harness/lib/real-script.rb:2`(実在) `harness/lib/missing-script.rb:3`(実在しない) `harness/lib/real-config.yaml:2`(実在) `harness/lib/missing-config.yaml:3`(実在しない)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-ext-broadened-line.md"
# check3(二次レビュー対応): 大文字小文字を無視しても、大文字始まりの非パス識別子
# (`Admin`/`Writer` 等)は allowlist の語と一致しないため誤検知しない。
printf -- '---\nid: e-path-roleid-case\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nIAM ロール(大文字始まり): `roles/run.Invoker` `roles/iam.Admin` `roles/storage.Writer`\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-path-roleid-case.md"

# check4: dangling [[...]]。skill/agent/rule(ファイル名解決)は誤検知しない
printf -- '---\nid: e-link\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nSee [[sample-skill]] [[sample-agent]] [[sample-rule]] [[nonexistent-thing]].\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-link.md"

# check5: supersedes: の指す先が実在しない
printf -- '---\nid: e-badsuper\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\nsupersedes: nonexistent-id\n---\nbody\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-badsuper.md"

# check6: status: superseded なのに back-link が無い(e-old)。back-link ありは誤検知しない(e-old2)
printf -- '---\nid: e-old\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: superseded\nsummary: s\n---\nbody\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-old.md"
printf -- '---\nid: e-old2\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: superseded\nsummary: s\n---\nbody\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-old2.md"
printf -- '---\nid: e-new2\ndate: 2026-01-02\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\nsupersedes: e-old2\n---\nbody\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-02-e-new2.md"

# check7: 必須フィールド欠落 ＋ domain とディレクトリ名の不一致
printf -- '---\nid: e-badfm\ndomain: wrong-dir\nsummary: s\n---\nbody\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-badfm.md"

# check8: scope:global のエントリが scope:local のエントリを参照している(昇格=move で解決不能になる)
printf -- '---\nid: e-local-target\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nbody\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-local-target.md"
printf -- '---\nid: e-global-src\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: global\nstatus: active\nsummary: s\nsupersedes: e-local-target\n---\nAlso see [[e-local-target]].\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-global-src.md"

# check9: scope:global エントリのパス参照が実在はするが導入先へ配布されない位置を指している。
# 実例3件のうち「配布されないCLI本体のパス」「配布元だけの位置」を fixture で再現する
# (3件目「配布されない知見への誘導」は check8 が同じ形(scope:global→scope:localの[[...]]参照)で
# 既に捕まえている。上の e-global-src/e-local-target がその回帰)。
printf '#!/usr/bin/env bash\necho cli\n' > "$ka/bin/cli-entry"
printf '# source-only doc\n' > "$ka/.docs/source-only-doc.md"
printf '# git internal metadata (git init が作る汎用ファイル)\n' > "$ka/.git/info/exclude"
# 実例1: 配布されないCLI本体のパス(拡張子なし。BARE_PATH_RE は拡張子必須のため check3 の
# 拾い方では検出できず、check9 専用の拡張子不問パターンで検出できることを確認する)
printf -- '---\nid: e-travel-cli\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `bin/cli-entry`(実在するが配布対象外のCLI本体)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-travel-cli.md"
# 実例2: 配布元だけの位置(このリポジトリのソースにはあるが harness/ 配下ではない)
printf -- '---\nid: e-travel-docs\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `.docs/source-only-doc.md`(実在するが配布元にしか無い)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-travel-docs.md"
# 正当な参照(travel-safe)は誤検知しない: harness/ 配下の実在パスは check9 で検知されない
printf -- '---\nid: e-travel-safe\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/lib/real.sh`(実在・travel-safe)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-travel-safe.md"
# scope:local は check9 の対象外(scope:globalのみが対象という討議収束どおり)
printf -- '---\nid: e-travel-cli-local\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `bin/cli-entry`(scope:localなので check9 の対象外)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-travel-cli-local.md"
# .git/ 配下は全 git リポジトリに共通の汎用メタデータであり、travel-safety の判定軸の外
# (実測記述で汎用の git 挙動を指すためだけに使われる実例があり、誤検知の回帰として確認する)
printf -- '---\nid: e-travel-gitinternal\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- ✓実測: 任意の git リポジトリの `.git/info/exclude` に除外ルールを追加すると挙動を確認できる。\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-travel-gitinternal.md"
# check9 一次レビュー指摘の回帰: `.claude/knowledge/<domain>/*.md`(project-local エントリ本体。
# consumer 所有・非配布)は「.claude/ 配下」というだけで travel-safe と
# 誤判定してはならない。裸パス(コードスパンだが [[...]] 形式ではない)で他のローカル知見を
# 参照する scope:global エントリが見逃されていた実例の回帰(参照先は既存の e-badfm.md を再利用)。
mkdir -p "$ka/harness/knowledge"
printf '# template\n' > "$ka/harness/knowledge/_entry-template.md"
printf -- '---\nid: e-travel-knowledge-bare\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `.claude/knowledge/harness-dev/2026-01-01-e-badfm.md`(project-localエントリを裸パス参照・非配布)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-travel-knowledge-bare.md"
# knowledge/ 直下(1階層)の managed テンプレートは引き続き travel-safe(除外はサブディレクトリのみ)
printf -- '---\nid: e-travel-knowledge-template\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/knowledge/_entry-template.md`(managedテンプレート・travel-safe)\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-travel-knowledge-template.md"

ka_out="$(bash "$ka/harness/lib/knowledge-audit.sh" "$ka/.claude" 2>&1)"

if ka_has "knowledge/harness-dev/2026-01-01-e-bare.md" "bare-issue-ref" "$ka_out"; then ok "check1: 裸の #N を検知"; else ng "check1: 裸の #N を検知"; fi
out_hasnt "check1: repo 明示済み(502)は誤検知しない対象に含めない" "${HSH}502 参照" "$ka_out"
# check1: 列挙・範囲表記の2つめ以降(直前が/)が qualified 誤判定で見逃されていた偽陰性の回帰。
if ka_has "knowledge/harness-dev/2026-01-01-e-bare-slash-enum.md" "bare-issue-ref" "$ka_out"; then ok "check1: 列挙表記の2つめ以降(192)を裸として検出"; else ng "check1: 列挙表記の2つめ以降(192)を裸として検出"; fi
out_has   "check1: 検出メッセージが 192 を指す"                "${HSH}192" "$ka_out"
out_hasnt "check1: repo明示済みの191は誤検知しない対象に含めない" "${HSH}191 参照" "$ka_out"
# check1: URL のパス・フラグメント(裸URL・markdownリンクの両方)に含まれる #N を誤検知しない
# (`/` を qualified 文字集合から外した副作用の回帰)。地の文の実参照は引き続き検知される。
if ka_has "knowledge/harness-dev/2026-01-01-e-bare-url-fragment.md" "bare-issue-ref" "$ka_out"; then ok "check1: URL断片と同居する地の文の 603 は検知される"; else ng "check1: URL断片と同居する地の文の 603 は検知される"; fi
out_has   "check1: 検出メッセージが地の文の 603 を指す"        "${HSH}603" "$ka_out"
out_hasnt "check1: 裸URLのフラグメント 601 を誤検知しない"     "${HSH}601" "$ka_out"
out_hasnt "check1: markdownリンクのフラグメント 602 を誤検知しない" "${HSH}602" "$ka_out"
# check1(一次レビュー): URL の直後に空白なしで地の文が続く形(日本語で常態)の偽陰性回帰。
# check3 専用 URL_RE(`\S*` で空白でしか止まらない)の転用が、URL 直後の地の文まで飲み込んで
# 見逃していた欠陥。URL の前後どちらに地の文があっても検出されること・URL フラグメント自体は
# 引き続き誤検知しないこと(閉じ括弧直後に空白が無い場合も)の両方を確認する。
if ka_has "knowledge/harness-dev/2026-01-01-e-bare-url-no-space.md" "bare-issue-ref" "$ka_out"; then ok "check1: URL直後に空白無しで続く地の文の 901 は検知される"; else ng "check1: URL直後に空白無しで続く地の文の 901 は検知される"; fi
out_has   "check1: 検出メッセージが 901 を指す(URL直後・空白無し)"     "${HSH}901" "$ka_out"
out_has   "check1: 検出メッセージが 902 を指す(URL直後・読点区切り)"   "${HSH}902" "$ka_out"
out_has   "check1: 検出メッセージが 903 を指す(URL前の地の文)"        "${HSH}903" "$ka_out"
out_has   "check1: 検出メッセージが 905 を指す(markdownリンク直後・空白無し)" "${HSH}905" "$ka_out"
out_hasnt "check1: markdownリンクのフラグメント 904 は閉じ括弧直後でも誤検知しない" "${HSH}904" "$ka_out"
if ka_has "knowledge/global/harness/2026-01-01-e-store.md" "travel-issue-ref" "$ka_out"; then ok "check2: グローバルミラー自身の issue番号を検知"; else ng "check2: グローバルミラー自身の issue番号を検知"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-staged.md" "travel-issue-ref" "$ka_out"; then ok "check2: scope:global(staging)の issue番号も検知"; else ng "check2: scope:global(staging)の issue番号も検知"; fi
# check1/check2 共通: 「参照」と「例示」の区別(コードスパンの内か外か)。
# 偽陽性(例示の誤検知)を潰しつつ、地の文の実参照は引き続き検知する(=偽陽性を偽陰性にすり替えていない)。
if ka_has "knowledge/harness-dev/2026-01-01-e-bare-codespan.md" "bare-issue-ref" "$ka_out"; then ok "check1: コードスパン併存時も地の文の 911 は検知される"; else ng "check1: コードスパン併存時も地の文の 911 は検知される"; fi
out_has   "check1: 検出メッセージが地の文の 911 を指す"                       "${HSH}911" "$ka_out"
out_hasnt "check1: インラインコード内の 910(禁止パターンの見本)は検知しない" "${HSH}910" "$ka_out"
out_hasnt "check1: フェンスされたコードブロック内の 912(再現用の入力)は検知しない" "${HSH}912" "$ka_out"
if ka_has "knowledge/global/harness/2026-01-01-e-store-codespan.md" "travel-issue-ref" "$ka_out"; then ok "check2: travel面でもコードスパン併存時に地の文の 921 は検知される"; else ng "check2: travel面でもコードスパン併存時に地の文の 921 は検知される"; fi
out_has   "check2: 検出メッセージが地の文の 921 を指す"                       "${HSH}921" "$ka_out"
out_hasnt "check2: フェンスされたコードブロック内の 920(再現用の入力)は検知しない" "${HSH}920" "$ka_out"
out_hasnt "check2: インラインコード内の 922(例示)は検知しない"               "${HSH}922" "$ka_out"
# check1/check2 共通(一次レビュー): ダブルバッククォート(以上)のコードスパンは CommonMark の
# 正式な構文(開始run と同じ長さの run で閉じ、スパン内にリテラルのバッククォートを埋め込める)であり、
# 単一バッククォート前提の素朴な判定では中の #N を誤検知していた。1スパンとして正しく扱うこと・
# 地の文の #N は引き続き検知されること(偽陰性テスト)の両方を確認する。
if ka_has "knowledge/harness-dev/2026-01-01-e-bare-doublebacktick.md" "bare-issue-ref" "$ka_out"; then ok "check1: ダブルバッククォート併存時も地の文の 208 は検知される"; else ng "check1: ダブルバッククォート併存時も地の文の 208 は検知される"; fi
out_has   "check1: 検出メッセージが地の文の 208 を指す" "${HSH}208" "$ka_out"
out_hasnt "check1: ダブルバッククォート内(埋め込みリテラルバッククォート込み)の 207 は1スパンとして検知しない" "${HSH}207" "$ka_out"
# check1: delimiter 横取りバグの回帰(一次レビューで発見)。
if ka_has "knowledge/harness-dev/2026-01-01-e-bare-delimiter-hijack.md" "bare-issue-ref" "$ka_out"; then ok "check1: 混在行でも地の文の 401 は検知される"; else ng "check1: 混在行でも地の文の 401 は検知される"; fi
out_has   "check1: 検出メッセージが地の文の 401 を指す" "${HSH}401" "$ka_out"
out_hasnt "check1: 先行スパンの内部リテラルbacktickに横取りされず、後続スパン内の 301 を誤検知しない" "${HSH}301" "$ka_out"
if ka_has "knowledge/global/harness/2026-01-01-e-store-doublebacktick.md" "travel-issue-ref" "$ka_out"; then ok "check2: travel面でもダブルバッククォート併存時に地の文の 926 は検知される"; else ng "check2: travel面でもダブルバッククォート併存時に地の文の 926 は検知される"; fi
out_has   "check2: 検出メッセージが地の文の 926 を指す" "${HSH}926" "$ka_out"
out_hasnt "check2: ダブルバッククォート内(埋め込みリテラルバッククォート込み)の 925 は1スパンとして検知しない" "${HSH}925" "$ka_out"
if ka_has "knowledge/harness-dev/2026-01-01-e-path.md" "broken-path-ref" "$ka_out"; then ok "check3: 破損したパス参照を検知"; else ng "check3: 破損したパス参照を検知"; fi
out_has   "check3: 存在しないファイルを個別に指摘" "harness/lib/missing.sh\` — ファイルが存在しない" "$ka_out"
out_has   "check3: 行超過を個別に指摘"             "実体は 3 行までしかない"                          "$ka_out"
out_hasnt "check3: 「## 根拠 / 実例」節の外の path:line は実在しなくても検査対象外" "foo.sh:12\` —" "$ka_out"
# check3(偽陽性クラス1): 括弧を含む実在パスは bare backtick・path:line のどちらでも誤検知しない。
# 注記(一次レビュー): この2つの out_hasnt 自体は「括弧サポートを revert しても落ちない」
# (`BARE_PATH_RE` は完全一致のためトークンごと不一致になるだけで truncation が起きず、
# 単一階層の path:line も `PATHLINE_RE` の `/` 要件を満たさずそもそも無出力になるため)。
# 括弧サポートの mutation 感度は、bare backtick 側は直後の「実在しないパスが引き続き検出
# される」アサーションが、path:line 側は下の e-path-paren-nested 用アサーションが担う
# (詳細はそれぞれのアサーション直前のコメント)。
out_hasnt "check3: 括弧を含む実在パス(bare backtick)を誤検知しない" "(group)/real-paren.sh\` — ファイルが存在しない" "$ka_out"
out_hasnt "check3: 括弧を含む実在パス(path:line)を誤検知しない" "(group)/real-paren.sh:2\` —" "$ka_out"
# 同じ変更で真の検出(括弧を含むが実在しないパス)まで一緒に消えていないことを確認する。
# (bare backtick 形式。`BARE_PATH_RE` は完全一致なので、括弧サポートを revert すると
# トークン自体が不一致になり検出できなくなる=mutation 感度あり。確認済み)
if ka_has "knowledge/harness-dev/2026-01-01-e-path-paren.md" "broken-path-ref" "$ka_out"; then ok "check3: 括弧を含んでいても実在しないパスは引き続き検出される"; else ng "check3: 括弧を含んでいても実在しないパスは引き続き検出される"; fi
out_has   "check3: 括弧を含む実在しないパスを個別に指摘" "(group)/missing-paren.sh\` — ファイルが存在しない" "$ka_out"
# check3(偽陽性クラス1・一次レビュー対応): `PATHLINE_RE` の truncation バグの直接再現
# (括弧の後ろにもう1段ディレクトリがある構成)。括弧を含む実在パスは誤って切り詰められた形
# (`/sub/real-paren-line.sh:2`)でも報告されず、実在しないパスは正しいフルパスで報告される
# (切り詰められた誤ったパスでの報告に置き換わっていないことも同時に確認)。
out_hasnt "check3: 括弧の後ろに更にセグメントがある実在パス(path:line)を truncation で誤検知しない" "real-paren-line.sh:2\` —" "$ka_out"
if ka_has "knowledge/harness-dev/2026-01-01-e-path-paren-nested.md" "broken-path-ref" "$ka_out"; then ok "check3: 括弧の後ろに更にセグメントがあっても実在しないパスは引き続き検出される"; else ng "check3: 括弧の後ろに更にセグメントがあっても実在しないパスは引き続き検出される"; fi
out_has   "check3: 括弧の後ろに更にセグメントがある実在しないパスを正しいフルパスで指摘(truncationされた誤ったパスに置き換わっていない)" "harness/lib/(group)/sub/missing-paren-line.sh:3\` — ファイルが存在しない" "$ka_out"
# check3(偽陽性クラス2): 構造がパスと同型の非パス識別子(拡張子が allowlist に無い)は誤検知しない。
if ka_has "knowledge/harness-dev/2026-01-01-e-path-roleid.md" "broken-path-ref" "$ka_out"; then ng "check3: パスと同型の識別子(roles/run.invoker)を broken-path-ref と誤検知しない"; else ok "check3: パスと同型の識別子(roles/run.invoker)を broken-path-ref と誤検知しない"; fi
# check3(二次レビュー対応): 拡張子 allowlist の照合は大文字小文字を無視する。
out_hasnt "check3: 大文字拡張子の実在パスを誤検知しない" "REAL-UPPER.MD\` — ファイルが存在しない" "$ka_out"
if ka_has "knowledge/harness-dev/2026-01-01-e-path-case.md" "broken-path-ref" "$ka_out"; then ok "check3: 大文字拡張子でも実在しないパスは検出される(allowlist化のregression回帰)"; else ng "check3: 大文字拡張子でも実在しないパスは検出される(allowlist化のregression回帰)"; fi
out_has   "check3: 大文字拡張子の実在しないパスを個別に指摘" "MISSING-UPPER.MD\` — ファイルが存在しない" "$ka_out"
if ka_has "knowledge/harness-dev/2026-01-01-e-path-roleid-case.md" "broken-path-ref" "$ka_out"; then ng "check3: 大文字始まりの非パス識別子(roles/run.Invoker 等)を大文字小文字無視でも誤検知しない"; else ok "check3: 大文字始まりの非パス識別子(roles/run.Invoker 等)を大文字小文字無視でも誤検知しない"; fi
# check3(二次レビュー総ざらいで追加): PATHLINE_RE(path:line 形式)側の大文字小文字無視。
out_hasnt "check3: 大文字拡張子の実在パス(path:line)を誤検知しない" "REAL-UPPER-LINE.MD:2\` —" "$ka_out"
if ka_has "knowledge/harness-dev/2026-01-01-e-path-case-line.md" "broken-path-ref" "$ka_out"; then ok "check3: 大文字拡張子(path:line)でも実在しないパスは検出される"; else ng "check3: 大文字拡張子(path:line)でも実在しないパスは検出される"; fi
out_has   "check3: 大文字拡張子(path:line)の実在しないパスを個別に指摘" "MISSING-UPPER-LINE.MD:3\` — ファイルが存在しない" "$ka_out"
# check3(二次レビュー総ざらいで追加): 広げた allowlist カテゴリ(tf/rb/yaml)の恒久回帰テスト。
out_hasnt "check3: 広げたカテゴリ(tf)の実在パスを誤検知しない" "real-infra.tf\` — ファイルが存在しない" "$ka_out"
out_has   "check3: 広げたカテゴリ(tf)の実在しないパスを検出する" "missing-infra.tf\` — ファイルが存在しない" "$ka_out"
out_hasnt "check3: 広げたカテゴリ(rb)の実在パスを誤検知しない" "real-script.rb\` — ファイルが存在しない" "$ka_out"
out_has   "check3: 広げたカテゴリ(rb)の実在しないパスを検出する" "missing-script.rb\` — ファイルが存在しない" "$ka_out"
out_hasnt "check3: 広げたカテゴリ(yaml)の実在パスを誤検知しない" "real-config.yaml\` — ファイルが存在しない" "$ka_out"
out_has   "check3: 広げたカテゴリ(yaml)の実在しないパスを検出する" "missing-config.yaml\` — ファイルが存在しない" "$ka_out"
# check3(三次レビュー対応): 広げたカテゴリの path:line 形式(PATHLINE_RE)側の恒久回帰テスト。
out_hasnt "check3: 広げたカテゴリ(tf・path:line)の実在パスを誤検知しない" "real-infra.tf:2\` —" "$ka_out"
out_has   "check3: 広げたカテゴリ(tf・path:line)の実在しないパスを検出する" "missing-infra.tf:3\` — ファイルが存在しない" "$ka_out"
out_hasnt "check3: 広げたカテゴリ(rb・path:line)の実在パスを誤検知しない" "real-script.rb:2\` —" "$ka_out"
out_has   "check3: 広げたカテゴリ(rb・path:line)の実在しないパスを検出する" "missing-script.rb:3\` — ファイルが存在しない" "$ka_out"
out_hasnt "check3: 広げたカテゴリ(yaml・path:line)の実在パスを誤検知しない" "real-config.yaml:2\` —" "$ka_out"
out_has   "check3: 広げたカテゴリ(yaml・path:line)の実在しないパスを検出する" "missing-config.yaml:3\` — ファイルが存在しない" "$ka_out"
if ka_has "knowledge/harness-dev/2026-01-01-e-path-prefix.md" "broken-path-ref" "$ka_out"; then ok "check3(一次レビュー対応): plugin_root を候補にする解決を撤去したので prefix 省略パスは broken-path-ref になる"; else ng "check3(一次レビュー対応): plugin_root を候補にする解決を撤去したので prefix 省略パスは broken-path-ref になる"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-path-ignore.md" "broken-path-ref" "$ka_out"; then ng "check3: gitignore/opt-in 領域を broken と断定しない"; else ok "check3: gitignore/opt-in 領域を broken と断定しない"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-path-ignore.md" "broken-path-ref-skipped" "$ka_out"; then ok "check3: gitignore/opt-in 領域はスキップした旨を報告する"; else ng "check3: gitignore/opt-in 領域はスキップした旨を報告する"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-path-ellipsis.md" "broken-path-ref" "$ka_out"; then ng "check3: 省略記法(...)を broken と断定しない"; else ok "check3: 省略記法(...)を broken と断定しない"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-path-ellipsis.md" "broken-path-ref-skipped" "$ka_out"; then ok "check3: 省略記法(...)はスキップした旨を報告する"; else ng "check3: 省略記法(...)はスキップした旨を報告する"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-link.md" "dangling-link" "$ka_out"; then ok "check4: dangling [[...]] を検知"; else ng "check4: dangling [[...]] を検知"; fi
out_hasnt "check4: skill 参照は誤検知しない"       "[[sample-skill]] の解決先"  "$ka_out"
out_hasnt "check4: agent 参照は誤検知しない"       "[[sample-agent]] の解決先"  "$ka_out"
out_hasnt "check4: rule(ファイル名解決)参照は誤検知しない" "[[sample-rule]] の解決先" "$ka_out"
if ka_has "knowledge/harness-dev/2026-01-01-e-badsuper.md" "bad-supersedes" "$ka_out"; then ok "check5: supersedes の解決先欠如を検知"; else ng "check5: supersedes の解決先欠如を検知"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-old.md" "missing-backlink" "$ka_out"; then ok "check6: back-link 書き忘れを検知"; else ng "check6: back-link 書き忘れを検知"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-old2.md" "missing-backlink" "$ka_out"; then ng "check6: back-link ありは誤検知しない"; else ok "check6: back-link ありは誤検知しない"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-badfm.md" "frontmatter-missing-field" "$ka_out"; then ok "check7: 必須フィールド欠落を検知"; else ng "check7: 必須フィールド欠落を検知"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-badfm.md" "domain-mismatch" "$ka_out"; then ok "check7: domain とディレクトリ名の不一致を検知"; else ng "check7: domain とディレクトリ名の不一致を検知"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-global-src.md" "global-refs-local" "$ka_out"; then ok "check8: scope:global が scope:local を参照している事を検知"; else ng "check8: scope:global が scope:local を参照している事を検知"; fi
# check9: 実例1(配布されないCLI本体のパス・拡張子なし)を検知する
if ka_has "knowledge/harness-dev/2026-01-01-e-travel-cli.md" "travel-unsafe-path-ref" "$ka_out"; then ok "check9: 配布対象外のCLI本体パス(拡張子なし)を検知"; else ng "check9: 配布対象外のCLI本体パス(拡張子なし)を検知"; fi
out_has "check9: 検出メッセージがCLI本体パスを指す" "bin/cli-entry\` は実在するが" "$ka_out"
# check9: 実例2(配布元だけの位置)を検知する
if ka_has "knowledge/harness-dev/2026-01-01-e-travel-docs.md" "travel-unsafe-path-ref" "$ka_out"; then ok "check9: 配布元だけの位置(.docs/)を検知"; else ng "check9: 配布元だけの位置(.docs/)を検知"; fi
out_has "check9: 検出メッセージが .docs/ の位置を指す" ".docs/source-only-doc.md\` は実在するが" "$ka_out"
# check9: 正当な参照(harness/ 配下の実在パス)は誤検知しない
if ka_has "knowledge/harness-dev/2026-01-01-e-travel-safe.md" "travel-unsafe-path-ref" "$ka_out"; then ng "check9: travel-safe な参照(harness/lib/real.sh)を誤検知しない"; else ok "check9: travel-safe な参照(harness/lib/real.sh)を誤検知しない"; fi
# check9: 対象は scope:global のみ(scope:local の同じ参照は対象外)
if ka_has "knowledge/harness-dev/2026-01-01-e-travel-cli-local.md" "travel-unsafe-path-ref" "$ka_out"; then ng "check9: scope:local エントリは対象外(討議収束どおり)"; else ok "check9: scope:local エントリは対象外(討議収束どおり)"; fi
# check9: .git/ 配下(全 git リポジトリ共通の汎用メタデータ)は travel-safety 判定の対象外
if ka_has "knowledge/harness-dev/2026-01-01-e-travel-gitinternal.md" "travel-unsafe-path-ref" "$ka_out"; then ng "check9: .git/ 配下(汎用git挙動の説明)を誤検知しない"; else ok "check9: .git/ 配下(汎用git挙動の説明)を誤検知しない"; fi
# check9 一次レビュー指摘の回帰: `.claude/knowledge/<domain>/*.md`(project-local・非配布)を
# 裸パスで参照した見逃しが直っていること。knowledge/ 直下(1階層)の managed テンプレートは
# 引き続き travel-safe のまま(除外対象が「サブディレクトリのみ」であることの境界確認)。
if ka_has "knowledge/harness-dev/2026-01-01-e-travel-knowledge-bare.md" "travel-unsafe-path-ref" "$ka_out"; then ok "check9: .claude/knowledge/<domain>/*.md への裸パス参照(非配布)を検知"; else ng "check9: .claude/knowledge/<domain>/*.md への裸パス参照(非配布)を検知"; fi
out_has "check9: 検出メッセージが .claude/knowledge/<domain>/*.md を指す" ".claude/knowledge/harness-dev/2026-01-01-e-badfm.md\` は実在するが" "$ka_out"
if ka_has "knowledge/harness-dev/2026-01-01-e-travel-knowledge-template.md" "travel-unsafe-path-ref" "$ka_out"; then ng "check9: knowledge/ 直下の managed テンプレート参照は travel-safe のまま"; else ok "check9: knowledge/ 直下の managed テンプレート参照は travel-safe のまま"; fi
# id 省略は正式仕様であり欠陥ではない: id 欠落だけを理由に frontmatter-missing-field が付かないこと
printf -- '---\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: id 省略は正式仕様\n---\nbody\n' \
  > "$ka/.claude/knowledge/harness-dev/2026-01-01-e-noid.md"
ka_out2="$(bash "$ka/harness/lib/knowledge-audit.sh" "$ka/.claude" 2>&1)"
if ka_has "knowledge/harness-dev/2026-01-01-e-noid.md" "frontmatter-missing-field" "$ka_out2"; then ng "check7: id 省略単体は欠陥として扱わない(id省略の扱いとの整合)"; else ok "check7: id 省略単体は欠陥として扱わない(id省略の扱いとの整合)"; fi
rm -rf "$ka"

echo "== knowledge-audit.sh: 別domain間の[[...]]参照回帰(fixtureベース) =="
# 以前はこの回帰を実リポジトリの .claude/knowledge(harness-devエントリ→processエントリの
# 実参照)に対する自己監査で確認していたが、開発文書(.claude/knowledge/)を harness から
# 撤去したためこの依存を外せない。確かめたい性質(別domain間の[[...]]参照が解決されること。
# 同domain内の相互参照は check4 の他アサーションで確認済み)だけを、隔離された fixture で
# 再現する。あわせて参照先を消すと同じ形で実際に dangling-link になること(negative control。
# 検査そのものが機能していることの確認)も固定する。
_xd="$(mktemp -d "$ROOT/test/scratch.XXXXXXXX")"
mkdir -p "$_xd/.claude/knowledge/harness-dev" "$_xd/.claude/knowledge/process" "$_xd/.claude/knowledge/global/harness"
printf -- '---\nid: e-xdomain-target\ndate: 2026-01-01\ndomain: process\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nbody\n' \
  > "$_xd/.claude/knowledge/process/2026-01-01-e-xdomain-target.md"
printf -- '---\nid: e-xdomain-src\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nSee [[e-xdomain-target]].\n' \
  > "$_xd/.claude/knowledge/harness-dev/2026-01-01-e-xdomain-src.md"
# global/ にダミーの1件を置いて global_present=true にする(resolve_link は global/ が「未 sync」
# 相当だと判定不能として skipped に倒すため、negative control で実際に dangling を引くには
# global/ が「同期済み」の状態を fixture 側で作る必要がある)。
printf -- '---\nid: e-xdomain-global-dummy\ndate: 2026-01-01\ndomain: harness\ntags: []\nscope: global\nstatus: active\nsummary: s\n---\nbody\n' \
  > "$_xd/.claude/knowledge/global/harness/2026-01-01-e-xdomain-global-dummy.md"
_xd_out="$(bash "$ROOT/harness/lib/knowledge-audit.sh" "$_xd/.claude" 2>&1)"
if ka_has "knowledge/harness-dev/2026-01-01-e-xdomain-src.md" "dangling-link" "$_xd_out"; then ng "check4: 別domain間の[[...]]参照はdangling-linkにならない(id解決)"; else ok "check4: 別domain間の[[...]]参照はdangling-linkにならない(id解決)"; fi
rm -f "$_xd/.claude/knowledge/process/2026-01-01-e-xdomain-target.md"
_xd_out2="$(bash "$ROOT/harness/lib/knowledge-audit.sh" "$_xd/.claude" 2>&1)"
if ka_has "knowledge/harness-dev/2026-01-01-e-xdomain-src.md" "dangling-link" "$_xd_out2"; then ok "check4: negative control - 参照先を消すと別domain間の[[...]]もdangling-linkになる"; else ng "check4: negative control - 参照先を消すと別domain間の[[...]]もdangling-linkになる"; fi
rm -rf "$_xd"

echo "== knowledge-audit.sh: グローバルミラー(global/)が存在しない環境では [[...]] / supersedes: の未解決を dangling と誤判定せずスキップ通知する =="
kb="$(mktemp -d)"; mkdir -p "$kb/.claude/knowledge/harness-dev"
printf -- '---\nid: e1\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\nsupersedes: store-only-id\n---\nSee [[store-only-thing]].\n' \
  > "$kb/.claude/knowledge/harness-dev/2026-01-01-e1.md"
kb_out="$(bash "$ROOT/harness/lib/knowledge-audit.sh" "$kb/.claude" 2>&1)"
if ka_has "knowledge/harness-dev/2026-01-01-e1.md" "dangling-link" "$kb_out"; then ng "global 未 sync: [[...]] を dangling と断定しない"; else ok "global 未 sync: [[...]] を dangling と断定しない"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e1.md" "dangling-link-skipped" "$kb_out"; then ok "global 未 sync: [[...]] はスキップした旨を報告する"; else ng "global 未 sync: [[...]] はスキップした旨を報告する"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e1.md" "bad-supersedes" "$kb_out"; then ng "global 未 sync: supersedes を dangling と断定しない"; else ok "global 未 sync: supersedes を dangling と断定しない"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e1.md" "bad-supersedes-skipped" "$kb_out"; then ok "global 未 sync: supersedes はスキップした旨を報告する"; else ng "global 未 sync: supersedes はスキップした旨を報告する"; fi
rm -rf "$kb"

echo "== knowledge-audit.sh: グローバルミラー(global/)がディレクトリとして存在するが中身が空のときも、不在と同じくdanglingと断定せずスキップ通知する =="
# 同期が中断した場合・同期前に置き場だけ作られた場合・何かが中身を消した場合に生じる「空」状態。
# 「不在」は正しくスキップされるのに「空」だけ dangling として誤検知される非対称の回帰テスト
# (置き場ディレクトリの有無ではなく、実際に読み取れたエントリの有無で判定することで揃える)。
kb2="$(mktemp -d)"; mkdir -p "$kb2/.claude/knowledge/harness-dev" "$kb2/.claude/knowledge/global"
printf -- '---\nid: e1b\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\nsupersedes: store-only-id\n---\nSee [[store-only-thing]].\n' \
  > "$kb2/.claude/knowledge/harness-dev/2026-01-01-e1b.md"
kb2_out="$(bash "$ROOT/harness/lib/knowledge-audit.sh" "$kb2/.claude" 2>&1)"
if ka_has "knowledge/harness-dev/2026-01-01-e1b.md" "dangling-link" "$kb2_out"; then ng "global 空ディレクトリ: [[...]] を dangling と断定しない"; else ok "global 空ディレクトリ: [[...]] を dangling と断定しない"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e1b.md" "dangling-link-skipped" "$kb2_out"; then ok "global 空ディレクトリ: [[...]] はスキップした旨を報告する"; else ng "global 空ディレクトリ: [[...]] はスキップした旨を報告する"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e1b.md" "bad-supersedes" "$kb2_out"; then ng "global 空ディレクトリ: supersedes を dangling と断定しない"; else ok "global 空ディレクトリ: supersedes を dangling と断定しない"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e1b.md" "bad-supersedes-skipped" "$kb2_out"; then ok "global 空ディレクトリ: supersedes はスキップした旨を報告する"; else ng "global 空ディレクトリ: supersedes はスキップした旨を報告する"; fi
rm -rf "$kb2"

echo "== knowledge-audit.sh: グローバルミラー(global/)が存在する環境では、そこに実在する id への参照を dangling 扱いしない(走査対象に含めている) =="
kc="$(mktemp -d)"; mkdir -p "$kc/.claude/knowledge/harness-dev" "$kc/.claude/knowledge/global/testing"
printf -- '---\nid: store-only-id\ndate: 2026-01-01\ndomain: testing\nscope: global\nstatus: active\nsummary: exists only in the store mirror\n---\nbody\n' \
  > "$kc/.claude/knowledge/global/testing/2026-01-01-gid.md"
printf -- '---\nid: e2\ndate: 2026-01-02\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: references a store-only id\nsupersedes: store-only-id\n---\nSee [[store-only-id]].\n' \
  > "$kc/.claude/knowledge/harness-dev/2026-01-02-e2.md"
kc_out="$(bash "$ROOT/harness/lib/knowledge-audit.sh" "$kc/.claude" 2>&1)"
if ka_has "knowledge/harness-dev/2026-01-02-e2.md" "dangling-link" "$kc_out"; then ng "global 実在: [[store-only-id]] を dangling 扱いしない"; else ok "global 実在: [[store-only-id]] を dangling 扱いしない"; fi
if ka_has "knowledge/harness-dev/2026-01-02-e2.md" "bad-supersedes" "$kc_out"; then ng "global 実在: supersedes: store-only-id を dangling 扱いしない"; else ok "global 実在: supersedes: store-only-id を dangling 扱いしない"; fi
rm -rf "$kc"

echo "== knowledge-index フック: 編集された1エントリの構造的欠陥を lib/knowledge-audit.sh で警告する =="
t3="$(mktemp -d)"; mk_consumer "$t3"
mkdir -p "$t3/.claude/knowledge/api"
printf -- '---\nid: audittest\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: フック監査確認\n---\nissue '"$HSH"'321 with no repo.\n' \
  > "$t3/.claude/knowledge/api/2026-01-01-audittest.md"
out_audit="$(json_file "$t3/.claude/knowledge/api/2026-01-01-audittest.md" "$t3" | CLAUDE_PROJECT_DIR="$t3" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_has "hook: 構造監査の警告に systemMessage を含む"        "systemMessage"      "$out_audit"
out_has "hook: 構造監査の警告に該当 check-code を含む"       "bare-issue-ref"     "$out_audit"
out_has "hook: 構造監査の警告に additionalContext を含む"    "additionalContext"  "$out_audit"
out_audit_ctx="$(printf '%s' "$out_audit" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("hookSpecificOutput",{}).get("additionalContext",""))' 2>/dev/null)"
out_has "hook: additionalContext に具体的な指摘内容を含める" "${HSH}321"               "$out_audit_ctx"
# クリーンなエントリでは無反応(ノイズ0)
printf -- '---\nid: audittest\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: クリーン\n---\nno issues here.\n' \
  > "$t3/.claude/knowledge/api/2026-01-01-audittest.md"
out_clean="$(json_file "$t3/.claude/knowledge/api/2026-01-01-audittest.md" "$t3" | CLAUDE_PROJECT_DIR="$t3" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_hasnt "hook: 構造的欠陥が無ければ無出力(ノイズ0)" "systemMessage" "$out_clean"
rm -rf "$t3"

echo "== knowledge-index フック: dangling-link(check4)は書き込み時の報告から除く(監査本体は変更しない) =="
t5="$(mktemp -d)"; mk_consumer "$t5"
mkdir -p "$t5/.claude/knowledge/api" "$t5/.claude/knowledge/global/api"
# global/ を実在させておく(空でも他エントリが1件あればよい): resolve_link() は global/ ミラー自体が
# 不在だと「skipped」を返すため、"dangling" を実際に発火させるにはミラーが存在する状態を作る必要がある。
printf -- '---\nid: unrelated-global-entry\ndate: 2026-01-01\ndomain: api\nscope: global\nstatus: active\nsummary: 無関係なグローバルエントリ\n---\nbody\n' \
  > "$t5/.claude/knowledge/global/api/2026-01-01-g.md"
# 1件目: [[mutual-b]] はまだ存在しない(相手を先に書く)。フック実行前後で full audit を直接
# 走らせ、この時点では確かに dangling-link が(フィルタ前提として)発生する状況であることも確かめる
# (壊す/直す操作が実際に効いていることを、書き込み時フックとは別の経路で確認する)。
printf -- '---\nid: mutual-a\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 相互参照A\n---\nSee [[mutual-b]].\n' \
  > "$t5/.claude/knowledge/api/2026-01-01-mutual-a.md"
full_audit_before="$(bash "$H/lib/knowledge-audit.sh" "$t5/.claude" 2>&1)"
if ka_has "knowledge/api/2026-01-01-mutual-a.md" "dangling-link" "$full_audit_before"; then ok "監査本体: mutual-b 未作成時点では dangling-link が実際に発生する(前提の確認)"; else ng "監査本体: mutual-b 未作成時点では dangling-link が実際に発生する(前提の確認)"; fi
out_a="$(json_file "$t5/.claude/knowledge/api/2026-01-01-mutual-a.md" "$t5" | CLAUDE_PROJECT_DIR="$t5" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
# ローカル索引は廃止済みなので「フックが実際に起動したか」はINDEX再生成では確認できない
# (別経路: 上の full_audit_before で dangling-link が本当に発生する構成であることを確認済み。
# ここでの無出力は正しい除外の結果であり、無反応=無出力とは区別しない)。
out_hasnt "hook: 1件目書き込み時点では相手(mutual-b)が無くても dangling-link を報告しない" "systemMessage" "$out_a"
# 2件目: [[mutual-a]] を書く(相互参照が完成する)。こちらも報告が出ないことを確認する。
printf -- '---\nid: mutual-b\ndate: 2026-01-02\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 相互参照B\n---\nSee [[mutual-a]].\n' \
  > "$t5/.claude/knowledge/api/2026-01-02-mutual-b.md"
out_b="$(json_file "$t5/.claude/knowledge/api/2026-01-02-mutual-b.md" "$t5" | CLAUDE_PROJECT_DIR="$t5" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_hasnt "hook: 2件目(mutual-b)書き込み時にも報告しない" "systemMessage" "$out_b"
# 恒久的に壊れた参照(typo・相手が存在しない)を持つ3件目。書き込み時には(dangling-link を除外した
# 代償として)これも報告されなくなることを確かめつつ、まとめて監査を回せば引き続き検出されること
# (=監査本体の判定は変えていないこと)を別経路で確認する。
printf -- '---\nid: broken-ref-entry\ndate: 2026-01-03\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: 恒久的に壊れた参照\n---\nSee [[nonexistent-entry-xyz]].\n' \
  > "$t5/.claude/knowledge/api/2026-01-03-broken-ref-entry.md"
out_c="$(json_file "$t5/.claude/knowledge/api/2026-01-03-broken-ref-entry.md" "$t5" | CLAUDE_PROJECT_DIR="$t5" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_hasnt "hook: 恒久的に壊れた [[...]] 参照も書き込み時には報告されない(除外の代償)" "systemMessage" "$out_c"
file_isnt "hook: この一連の書き込みでも .claude/knowledge/INDEX.md は作られない(ローカル索引は廃止)" "$t5/.claude/knowledge/INDEX.md"
full_audit_after="$(bash "$H/lib/knowledge-audit.sh" "$t5/.claude" 2>&1)"
if ka_has "knowledge/api/2026-01-03-broken-ref-entry.md" "dangling-link" "$full_audit_after"; then ok "監査本体: まとめて監査を回せば恒久的に壊れた参照は引き続き検出される(判定ロジックは変えていない)"; else ng "監査本体: まとめて監査を回せば恒久的に壊れた参照は引き続き検出される(判定ロジックは変えていない)"; fi
if ka_has "knowledge/api/2026-01-01-mutual-a.md" "dangling-link" "$full_audit_after"; then ng "監査本体: mutual-b が書かれた後は mutual-a→mutual-b の dangling-link は解消している"; else ok "監査本体: mutual-b が書かれた後は mutual-a→mutual-b の dangling-link は解消している"; fi
rm -rf "$t5"

echo "== knowledge-index フック: dangling-link-skipped(グローバルミラー未 sync が根拠の区分)は書き込み時にも引き続き残す =="
t6="$(mktemp -d)"; mk_consumer "$t6"
mkdir -p "$t6/.claude/knowledge/api"
# global/ ディレクトリ自体を作らない → resolve_link() は「skipped」を返す(dangling-link とは別区分)。
printf -- '---\nid: skip-test\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: skip区分は書き込み時にも残る\n---\nSee [[store-only-thing]].\n' \
  > "$t6/.claude/knowledge/api/2026-01-01-skip-test.md"
out_skip="$(json_file "$t6/.claude/knowledge/api/2026-01-01-skip-test.md" "$t6" | CLAUDE_PROJECT_DIR="$t6" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_has "hook: dangling-link-skipped(確認可能な事実が根拠の区分)は書き込み時にも報告される" "dangling-link-skipped" "$out_skip"
rm -rf "$t6"

echo "== knowledge-index フック: check-code の比較は完全一致であり、他の前方一致の組(broken-path-ref/-skipped・bad-supersedes/-skipped)を巻き込まない(一次レビュー) =="
# check4(dangling-link)以外にも、base名がその "-skipped" 派生名の前方一致になっている組が2つある
# (broken-path-ref/broken-path-ref-skipped・bad-supersedes/bad-supersedes-skipped)。書き込み時
# フックの絞り込みが `dangling-link` の完全一致比較のままであれば、この2組はどちらの面(base側/
# skipped側)も無関係に引き続き報告されるはずであることを固定する(部分一致に書き換えた場合の
# 回帰を検知できるようにする)。
# t7: git repo化 + review/.gitignore(criteria.md)をプラグインルート直下に用意し、check3の
# gitignore判定(git check-ignore はプラグインのルート配下の候補に対してのみ行われる)を発火
# できるようにする。フック(knowledge-index.sh)は自分の位置から lib を見つけるため、プラグイン
# ルートを fixture 自身にしたい場合は hook・lib 一式を scratch へコピーする(_mk_ki_scratch_hooks)。
# global/ も用意し、bad-supersedes(base)を発火させる。
t7="$(mktemp -d)"; mk_consumer "$t7"
(cd "$t7" && git init -q)
# scratch のプラグイン一式は $t7 自身の配下(git check-ignore は cwd=repo_root からの相対で
# 判定するため、判定対象のパスが repo_root の木の外にあると正しく動かない)。
t7scratch="$t7/.plugin-fixture"; _mk_ki_scratch_hooks "$t7scratch"
mkdir -p "$t7scratch/review"
printf 'criteria.md\n' > "$t7scratch/review/.gitignore"
mkdir -p "$t7/.claude/knowledge/api" "$t7/.claude/knowledge/global/api"
printf -- '---\nid: unrelated-global-entry\ndate: 2026-01-01\ndomain: api\nscope: global\nstatus: active\nsummary: g\n---\nbody\n' \
  > "$t7/.claude/knowledge/global/api/2026-01-01-g.md"
# broken-path-ref(base): 実在しないパスへの参照
printf -- '---\nid: e-brokenpath\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/lib/totally-missing-file-xyz.sh`\n' \
  > "$t7/.claude/knowledge/api/2026-01-01-e-brokenpath.md"
out_bp="$(json_file "$t7/.claude/knowledge/api/2026-01-01-e-brokenpath.md" "$t7" | CLAUDE_PROJECT_DIR="$t7" bash "$t7scratch/hooks/knowledge-index.sh" 2>/dev/null)"
out_has "hook(一次レビュー): broken-path-ref(baseの前方一致元)は書き込み時にも引き続き報告される" "broken-path-ref" "$out_bp"
# broken-path-ref-skipped: gitignore された review/criteria.md への参照
printf -- '---\nid: e-brokenpath-skip\ndate: 2026-01-02\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `review/criteria.md`\n' \
  > "$t7/.claude/knowledge/api/2026-01-02-e-brokenpath-skip.md"
out_bps="$(json_file "$t7/.claude/knowledge/api/2026-01-02-e-brokenpath-skip.md" "$t7" | CLAUDE_PROJECT_DIR="$t7" bash "$t7scratch/hooks/knowledge-index.sh" 2>/dev/null)"
out_has "hook(一次レビュー): broken-path-ref-skipped(前方一致で巻き込まれうる側)は書き込み時にも引き続き報告される" "broken-path-ref-skipped" "$out_bps"
# bad-supersedes(base): global/ が実在するが、そこにも local にも無い id を supersedes: で指す
printf -- '---\nid: e-badsuper\ndate: 2026-01-03\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\nsupersedes: nonexistent-super-id-xyz\n---\nbody\n' \
  > "$t7/.claude/knowledge/api/2026-01-03-e-badsuper.md"
out_bs="$(json_file "$t7/.claude/knowledge/api/2026-01-03-e-badsuper.md" "$t7" | CLAUDE_PROJECT_DIR="$t7" bash "$t7scratch/hooks/knowledge-index.sh" 2>/dev/null)"
out_has "hook(一次レビュー): bad-supersedes(baseの前方一致元)は書き込み時にも引き続き報告される" "bad-supersedes" "$out_bs"
rm -rf "$t7" "$t7scratch"
# t8: global/ 自体を作らない(resolve_knowledge_id() が bad-supersedes-skipped を返す条件)。
t8="$(mktemp -d)"; mk_consumer "$t8"
mkdir -p "$t8/.claude/knowledge/api"
printf -- '---\nid: e-badsuper-skip\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\nsupersedes: store-only-super-id\n---\nbody\n' \
  > "$t8/.claude/knowledge/api/2026-01-01-e-badsuper-skip.md"
out_bss="$(json_file "$t8/.claude/knowledge/api/2026-01-01-e-badsuper-skip.md" "$t8" | CLAUDE_PROJECT_DIR="$t8" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_has "hook(一次レビュー): bad-supersedes-skipped(前方一致で巻き込まれうる側)は書き込み時にも引き続き報告される" "bad-supersedes-skipped" "$out_bss"
rm -rf "$t8"

echo "== knowledge-audit.sh: check3のgitignore判定基点は導入先(.claude/)自身が丸ごとgitignore対象かで切り替える(基点自己判定) =="
# tg1: 配布先ディレクトリ(harness/)を持たない本物の導入先(通常の consumer と同じ構成。git init のみで
# 独自ルート .gitignore は置かない=`.claude/` は丸ごと無視されていない)。
tg1="$(mktemp -d)"
(cd "$tg1" && git init -q)
mk_consumer "$tg1"
# 正当に gitignore された参照(review/criteria.md は導入先自身の .gitignore で無視される想定。
# 配布 payload の review/.gitignore は撤去済みなので、ここで直接その行を書いて確かめる。
# setup の Sub-issue が実際にこの行を書く=先取り)。
printf 'criteria.md\n' > "$tg1/.claude/review/.gitignore"
mkdir -p "$tg1/.claude/knowledge/api"
printf -- '---\nid: e-tg1-ignored\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `review/criteria.md`\n' \
  > "$tg1/.claude/knowledge/api/2026-01-01-e-tg1-ignored.md"
# 陽性対照1: 本当に壊れている参照(construct が正しく組めている=「発火しなかった」を「問題なし」と
# 誤読しないための対照。壊れていれば引き続き broken-path-ref のまま検出されるはず)。
printf -- '---\nid: e-tg1-broken\ndate: 2026-01-02\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `lib/totally-missing-file-tg1.sh`\n' \
  > "$tg1/.claude/knowledge/api/2026-01-02-e-tg1-broken.md"
# 陽性対照2: 同じ構成で別の check(check1: bare-issue-ref)が期待どおり発火すること(監査そのものが
# 空振りしていないことの別経路での確認)。
printf -- '---\nid: e-tg1-bare\ndate: 2026-01-03\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nissue '"$HSH"'999 with no repo.\n' \
  > "$tg1/.claude/knowledge/api/2026-01-03-e-tg1-bare.md"
tg1_out="$(bash "$H/lib/knowledge-audit.sh" "$tg1/.claude" 2>&1)"
if ka_has "knowledge/api/2026-01-01-e-tg1-ignored.md" "broken-path-ref" "$tg1_out"; then ng "受け入れ条件1: 通常の導入先で gitignore 済み参照(review/criteria.md)を欠陥として報告しない"; else ok "受け入れ条件1: 通常の導入先で gitignore 済み参照(review/criteria.md)を欠陥として報告しない"; fi
if ka_has "knowledge/api/2026-01-01-e-tg1-ignored.md" "broken-path-ref-skipped" "$tg1_out"; then ok "受け入れ条件1: 通常の導入先で gitignore 済み参照は skip 側として扱われる"; else ng "受け入れ条件1: 通常の導入先で gitignore 済み参照は skip 側として扱われる"; fi
if ka_has "knowledge/api/2026-01-02-e-tg1-broken.md" "broken-path-ref" "$tg1_out"; then ok "陽性対照: 同じ構成で本当に壊れている参照は引き続き検出される(construct が正しく組めている)"; else ng "陽性対照: 同じ構成で本当に壊れている参照は引き続き検出される(construct が正しく組めている)"; fi
if ka_has "knowledge/api/2026-01-03-e-tg1-bare.md" "bare-issue-ref" "$tg1_out"; then ok "陽性対照: 同じ構成で別の check(bare-issue-ref)も期待どおり発火する(監査が空振りしていない)"; else ng "陽性対照: 同じ構成で別の check(bare-issue-ref)も期待どおり発火する(監査が空振りしていない)"; fi
rm -rf "$tg1"

# tg2: 配布先ディレクトリ(.claude/)自身を丸ごと無視している導入先(この dev repo 固有の話ではなく、
# consumer が独自にそう運用している一般形。パターンは `/.claude/*` ではなく `.claude/` で書き、
# このリポジトリ自身の書き方への依存が無いことも兼ねて確認する)。
tg2="$(mktemp -d)"
(cd "$tg2" && git init -q)
printf '.claude/\n' > "$tg2/.gitignore"
mk_consumer "$tg2"
# review/criteria.md は mk_consumer が写す .claude/review/.gitignore で本来は無視されうる状態
# (基点自己判定で .claude/ が無視対象から除外されることの確認が本節の狙いのため)。
mkdir -p "$tg2/.claude/knowledge/api"
# 受け入れ条件2の本体: 基点(.claude/)を無条件に含める素朴な修正では skip されて検査が無効化される
# はずの、本当に壊れている参照(harness/ が無いこの構成では、gitignore 判定はどの基点からも
# 「無視されている」と誤判定されない状態を維持しなければならない)。
printf -- '---\nid: e-tg2-broken\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `lib/totally-missing-file-tg2.sh`\n' \
  > "$tg2/.claude/knowledge/api/2026-01-01-e-tg2-broken.md"
# 陽性対照: 同じ構成で別の check(bare-issue-ref)が期待どおり発火すること。
printf -- '---\nid: e-tg2-bare\ndate: 2026-01-02\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nissue '"$HSH"'998 with no repo.\n' \
  > "$tg2/.claude/knowledge/api/2026-01-02-e-tg2-bare.md"
# 基点の自己判定が働いていることの直接確認: この構成では `.claude/` 自身が丸ごと無視対象なので、
# review/criteria.md(harness/ が無いためどの基点からも解決できない)は「gitignore だから skip」とは
# 区別できず broken 側に倒れる(検査を無効化しないためのトレードオフとして受け入れ条件2が求める挙動。
# バグではない)。これが skip 側に倒れていたら、基点の自己判定(`.claude/` 除外)が効いていない証拠になる。
printf -- '---\nid: e-tg2-wouldbeskip\ndate: 2026-01-03\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `review/criteria.md`\n' \
  > "$tg2/.claude/knowledge/api/2026-01-03-e-tg2-wouldbeskip.md"
tg2_out="$(bash "$H/lib/knowledge-audit.sh" "$tg2/.claude" 2>&1)"
if ka_has "knowledge/api/2026-01-01-e-tg2-broken.md" "broken-path-ref-skipped" "$tg2_out"; then ng "受け入れ条件2: 配布先ディレクトリを丸ごと無視する構成でも、本当に壊れている参照が skip されない(検査が無効化されない)"; else ok "受け入れ条件2: 配布先ディレクトリを丸ごと無視する構成でも、本当に壊れている参照が skip されない(検査が無効化されない)"; fi
if ka_has "knowledge/api/2026-01-01-e-tg2-broken.md" "broken-path-ref" "$tg2_out"; then ok "受け入れ条件2: 配布先ディレクトリを丸ごと無視する構成でも、本当に壊れている参照は引き続き broken-path-ref として検出される"; else ng "受け入れ条件2: 配布先ディレクトリを丸ごと無視する構成でも、本当に壊れている参照は引き続き broken-path-ref として検出される"; fi
if ka_has "knowledge/api/2026-01-02-e-tg2-bare.md" "bare-issue-ref" "$tg2_out"; then ok "陽性対照: 同じ構成で別の check(bare-issue-ref)も期待どおり発火する(監査が空振りしていない)"; else ng "陽性対照: 同じ構成で別の check(bare-issue-ref)も期待どおり発火する(監査が空振りしていない)"; fi
if ka_has "knowledge/api/2026-01-03-e-tg2-wouldbeskip.md" "broken-path-ref" "$tg2_out"; then ok "基点の自己判定: 丸ごと無視構成では .claude/ 基点が gitignore 判定候補から除外されている(直接確認)"; else ng "基点の自己判定: 丸ごと無視構成では .claude/ 基点が gitignore 判定候補から除外されている(直接確認)"; fi
rm -rf "$tg2"

# tg3: このリポジトリ自身の自己監査と同じ形(harness/ 実体が実在し、ルート .gitignore が
# `/.claude/*` + `!/.claude/knowledge/` で .claude/ を丸ごと無視する dogfood 構成)を独立 fixture で
# 再現し、受け入れ条件3(自己監査は従来どおり偽陽性を出さない)を実corpusの内容に依存せず固定する。
tg3="$(mktemp -d)"
(cd "$tg3" && git init -q)
printf '/.claude/*\n!/.claude/knowledge/\n' > "$tg3/.gitignore"
mk_consumer "$tg3"
mkdir -p "$tg3/harness/review"
printf 'criteria.md\n' > "$tg3/harness/review/.gitignore"
# プラグインルートを fixture 自身の harness/ にするため、監査本体のコピーをそこへ置いて呼ぶ
# (mk_ka_copy。実物の harness/review/ は撤去済みで、プラグインルートは常に監査スクリプト自身の
# 位置から自己解決されるため、実体をそのまま呼んでも fixture の harness/ は使われない)。
mk_ka_copy "$tg3"
mkdir -p "$tg3/.claude/knowledge/api"
printf -- '---\nid: e-tg3-ignored\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `review/criteria.md`\n' \
  > "$tg3/.claude/knowledge/api/2026-01-01-e-tg3-ignored.md"
printf -- '---\nid: e-tg3-broken\ndate: 2026-01-02\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/lib/totally-missing-file-tg3.sh`\n' \
  > "$tg3/.claude/knowledge/api/2026-01-02-e-tg3-broken.md"
tg3_out="$(bash "$tg3/harness/lib/knowledge-audit.sh" "$tg3/.claude" 2>&1)"
if ka_has "knowledge/api/2026-01-01-e-tg3-ignored.md" "broken-path-ref" "$tg3_out"; then ng "受け入れ条件3: 自己監査と同型の dogfood 構成(harness/ 実在 + .claude/ 丸ごと無視)で、harness/ 基点経由の gitignore 判定は従来どおり skip する(偽陽性を出さない)"; else ok "受け入れ条件3: 自己監査と同型の dogfood 構成(harness/ 実在 + .claude/ 丸ごと無視)で、harness/ 基点経由の gitignore 判定は従来どおり skip する(偽陽性を出さない)"; fi
if ka_has "knowledge/api/2026-01-01-e-tg3-ignored.md" "broken-path-ref-skipped" "$tg3_out"; then ok "受け入れ条件3: 自己監査と同型の dogfood 構成で gitignore 済み参照は skip 側として扱われる"; else ng "受け入れ条件3: 自己監査と同型の dogfood 構成で gitignore 済み参照は skip 側として扱われる"; fi
if ka_has "knowledge/api/2026-01-02-e-tg3-broken.md" "broken-path-ref" "$tg3_out"; then ok "陽性対照: 自己監査と同型の dogfood 構成でも本当に壊れている参照は引き続き検出される(construct が正しく組めている)"; else ng "陽性対照: 自己監査と同型の dogfood 構成でも本当に壊れている参照は引き続き検出される(construct が正しく組めている)"; fi
rm -rf "$tg3"

echo "== knowledge-audit.sh: check3のgitignore判定は監査全体で1回にバッチ化され、未解決参照の件数に比例して外部プロセス呼び出しが増えない =="
# 実行時間の直接アサーションは環境で揺れるため避け、代わりに「外部プロセス(git)の呼び出し回数」を
# 固定する(測定手段は pyenv shim 回避で実体を解決する既存手法と同型: PATH に薄いラッパーを
# 差し込み、実 git へ委譲しつつ呼び出しを記録する)。PAYLOAD_SUBDIRS はスクリプト内蔵の固定
# サイズ(dogfood/自己監査と同型)なので、候補基点が1個だけの縮退構成でバッチ化の効果が
# 見えなくなることはない。
tp="$(mktemp -d)"
(cd "$tp" && git init -q)
mk_consumer "$tp"
mkdir -p "$tp/harness/review"
printf 'criteria.md\n' > "$tp/harness/review/.gitignore"
mkdir -p "$tp/.claude/knowledge/api"
tp_gitshim="$tp/gitshim"; mkdir -p "$tp_gitshim"
tp_realgit="$(command -v git)"
cat > "$tp_gitshim/git" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "\$GIT_SHIM_LOG"
exec "$tp_realgit" "\$@"
SHIM
chmod +x "$tp_gitshim/git"
_tp_mk_entries() {  # <n> <prefix> — 各エントリに1件、実在しない参照を持たせる(未解決参照=N件)
  local n="$1" prefix="$2" i
  rm -rf "$tp/.claude/knowledge/api"
  mkdir -p "$tp/.claude/knowledge/api"
  for i in $(seq 1 "$n"); do
    printf -- '---\nid: %s-%03d\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/lib/totally-missing-%s-%03d.sh`\n' \
      "$prefix" "$i" "$prefix" "$i" > "$tp/.claude/knowledge/api/2026-01-01-${prefix}-$(printf '%03d' "$i").md"
  done
}
_tp_mk_entries 3 small
tp_log_small="$tp/gitlog.small"
GIT_SHIM_LOG="$tp_log_small" PATH="$tp_gitshim:$PATH" bash "$H/lib/knowledge-audit.sh" "$tp/.claude" >/dev/null 2>/dev/null
tp_n_small=$(wc -l < "$tp_log_small")
_tp_mk_entries 15 big
tp_log_big="$tp/gitlog.big"
GIT_SHIM_LOG="$tp_log_big" PATH="$tp_gitshim:$PATH" bash "$H/lib/knowledge-audit.sh" "$tp/.claude" >/dev/null 2>/dev/null
tp_n_big=$(wc -l < "$tp_log_big")
tp_diff_calls=$((tp_n_big - tp_n_small))
# バッチ化前は未解決参照1件につき候補基点の数(実測9〜18)だけ git 呼び出しが増えるため、
# 12件の増分で少なくとも数十件は増えていたはず。バッチ化後は監査全体でまとめて1回になるため、
# 増分はごく僅少(基点自己判定のプローブ1回程度の誤差)に収まる。
if [ "$tp_diff_calls" -le 2 ]; then ok "check3: 未解決参照が3件→15件に増えても git 呼び出し回数の増分は僅少(バッチ化されている。実測差分=${tp_diff_calls})"; else ng "check3: 未解決参照12件増加で git 呼び出しが ${tp_diff_calls} 件増えた(バッチ化されていない可能性)"; fi
if [ "$tp_n_big" -le 5 ]; then ok "check3: 15件の未解決参照でも git 呼び出しは少数回に収まる(実測=${tp_n_big}件)"; else ng "check3: 15件の未解決参照で git 呼び出しが ${tp_n_big} 件(想定より多い)"; fi
# 陽性対照: バッチ化しても検出結果自体(何を欠陥とみなすか)は変わらない
tp_out_big="$(bash "$H/lib/knowledge-audit.sh" "$tp/.claude" 2>/dev/null)"
tp_n_reported=$(printf '%s\n' "$tp_out_big" | awk -F'\t' '$2=="broken-path-ref"' | wc -l | tr -d ' ')
if [ "$tp_n_reported" = "15" ]; then ok "陽性対照: バッチ化後も15件全件がbroken-path-refとして検出される(検査が空振りしていない)"; else ng "陽性対照: 15件中 ${tp_n_reported} 件しか検出されなかった(想定=15件)"; fi
rm -rf "$tp"

echo "== knowledge-audit.sh: check3のバッチ化されたgitignore一括呼び出しが失敗しても、キャッシュを汚さず個別呼び出しへフォールバックする(偽陽性を出さない・一次レビュー) =="
# 一括呼び出し(git check-ignore --stdin)が失敗すると、その回の候補が全件「無視されていない」として
# キャッシュへ溜め込まれ、正当に gitignore された参照が軒並み broken-path-ref(偽陽性)に転じる欠陥が
# 一次レビューで指摘された。この節はコードを改変せず(PATH に一括呼び出しだけを失敗させる git shim を
# 差し込むだけで)その欠陥を固定し、修正後は再現しないことを回帰として確認する。
tf="$(mktemp -d)"
(cd "$tf" && git init -q)
mk_consumer "$tf"
mkdir -p "$tf/harness/review"
printf 'criteria.md\n' > "$tf/harness/review/.gitignore"
# プラグインルートを fixture 自身の harness/ にするため、監査本体のコピーをそこへ置いて呼ぶ
# (mk_ka_copy。ka_out2/tg3 と同じ理由)。
mk_ka_copy "$tf"
mkdir -p "$tf/.claude/knowledge/api"
# 正当にgitignoreされた参照(review/criteria.mdはharness/review/.gitignoreで無視される)。
printf -- '---\nid: e-tf-ignored\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `review/criteria.md`\n' \
  > "$tf/.claude/knowledge/api/2026-01-01-e-tf-ignored.md"
# 陽性対照: 本当に壊れている参照(構成が正しく組めていることの確認)。
printf -- '---\nid: e-tf-broken\ndate: 2026-01-02\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\n## 根拠 / 実例\n- 内部: `harness/lib/totally-missing-tf.sh`\n' \
  > "$tf/.claude/knowledge/api/2026-01-02-e-tf-broken.md"
# 一括呼び出し(--stdin を含む git check-ignore 呼び出し)だけを想定外の終了コードで失敗させ、
# 個別呼び出し(-q)は実 git へ委譲して成功させる shim(タイムアウトを含む例外側の失敗も
# batch_check_ignored() 内では同じ `except Exception: return None` に合流するため、この
# 想定外終了コードの再現で失敗系全体を代表させる)。
tf_gitshim="$tf/gitshim"; mkdir -p "$tf_gitshim"
tf_realgit="$(command -v git)"
cat > "$tf_gitshim/git" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = "check-ignore" ]; then
  for a in "\$@"; do
    if [ "\$a" = "--stdin" ]; then
      exit 17
    fi
  done
fi
exec "$tf_realgit" "\$@"
SHIM
chmod +x "$tf_gitshim/git"
tf_out_normal="$(bash "$tf/harness/lib/knowledge-audit.sh" "$tf/.claude" 2>/dev/null)"
tf_out_fault="$(PATH="$tf_gitshim:$PATH" bash "$tf/harness/lib/knowledge-audit.sh" "$tf/.claude" 2>/dev/null)"
if ka_has "knowledge/api/2026-01-01-e-tf-ignored.md" "broken-path-ref-skipped" "$tf_out_normal"; then ok "前提: 通常時はgitignore済み参照がskip側として扱われる(construct確認)"; else ng "前提: 通常時にgitignore済み参照がskip側として扱われていない(construct不備)"; fi
if ka_has "knowledge/api/2026-01-01-e-tf-ignored.md" "broken-path-ref" "$tf_out_fault"; then ng "受け入れ条件: 一括呼び出し失敗時に正当なgitignore参照が偽陽性(broken-path-ref)に転じない"; else ok "受け入れ条件: 一括呼び出し失敗時に正当なgitignore参照が偽陽性(broken-path-ref)に転じない"; fi
if ka_has "knowledge/api/2026-01-01-e-tf-ignored.md" "broken-path-ref-skipped" "$tf_out_fault"; then ok "受け入れ条件: 一括呼び出し失敗時も個別呼び出しへフォールバックして正しくskip側になる"; else ng "受け入れ条件: 一括呼び出し失敗時にskip側として扱われていない(フォールバックが機能していない)"; fi
if ka_has "knowledge/api/2026-01-02-e-tf-broken.md" "broken-path-ref" "$tf_out_fault"; then ok "陽性対照: 一括呼び出し失敗時でも本当に壊れている参照は引き続き検出される(construct・フォールバック双方が正しく組めている)"; else ng "陽性対照: 一括呼び出し失敗時に本当に壊れている参照が検出されなかった"; fi
out_is_empty "受け入れ条件: 一括呼び出し失敗時の出力は通常時と完全一致する(結果が変わらず遅くなるだけ)" "$(diff <(printf '%s' "$tf_out_normal") <(printf '%s' "$tf_out_fault"))"
rm -rf "$tf"

echo "== knowledge-index フック: domain 食い違いは構造監査(check7)側だけが警告し生成器は診断を出さない =="
t4="$(mktemp -d)"; mk_consumer "$t4"
mkdir -p "$t4/.claude/knowledge/testing"
# frontmatter の domain(api) と配置ディレクトリ(testing)が食い違うエントリ。
# 生成器(lib/knowledge-index.sh)は診断を出さず解決(frontmatter 優先)だけを行い、検出は
# 構造監査(lib/knowledge-audit.sh の check7/domain-mismatch)だけが担う設計。生成器が独自に
# 警告を出す実装へ戻すと、project-local エントリ編集時にこのフックが両方を集約して同じ原因の
# 警告が2本出る(この境界を固定する回帰テスト)。
printf -- '---\nid: domain-mismatch-entry\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: frontmatterはapiだがtestingに置かれている\n---\n' \
  > "$t4/.claude/knowledge/testing/2026-01-01-domain-mismatch-entry.md"
out_dup="$(json_file "$t4/.claude/knowledge/testing/2026-01-01-domain-mismatch-entry.md" "$t4" | CLAUDE_PROJECT_DIR="$t4" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_dup_ctx="$(printf '%s' "$out_dup" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("hookSpecificOutput",{}).get("additionalContext",""))' 2>/dev/null)"
mismatch_count="$(printf '%s' "$out_dup_ctx" | grep -o '配置ディレクトリ' | wc -l | tr -d ' ')"
exit_is   "hook: domain 食い違いの警告は監査由来の1本だけ(重複しない)" 1 "$mismatch_count"
out_has   "hook: 構造監査(check7 domain-mismatch)側の警告は出る" "domain-mismatch" "$out_dup_ctx"
out_hasnt "hook: 生成器側の同種警告文言は出ない(検出は監査に一本化)" "frontmatter を採用します" "$out_dup_ctx"
file_isnt "hook: domain 食い違いの警告時にも INDEX.md は作られない(ローカル索引は廃止)" "$t4/.claude/knowledge/INDEX.md"
rm -rf "$t4"

echo "== knowledge-index フック: 自分の位置から lib を見つけるので、worktree(.claude/lib 不在)でもガードが届く =="
# harness 自身の dogfood worktree を模す: このリポジトリのルート .gitignore は `/.claude/*`
# (`knowledge/` だけ例外)で install 一式を無視しており、git worktree には `.claude/knowledge/` しか
# コピーされない(`.claude/lib/` 等は存在しない)。resolve_lib() は consumer 側の `.claude/lib` を
# 一切見ないため(常に自分の位置 `$(dirname BASH_SOURCE)/../lib/<name>` = 実行された hook 自身が
# 属する `lib/`)、`.claude/lib` の有無に関わらず同じ結果になることを確認する。
wt="$(mktemp -d)"
mkdir -p "$wt/.claude/knowledge/api"
printf -- '---\nid: wt-hook-test\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: worktree フック確認\n---\nissue '"$HSH"'556 with no repo.\n' \
  > "$wt/.claude/knowledge/api/2026-01-01-wt-hook-test.md"
out_wt="$(json_file "$wt/.claude/knowledge/api/2026-01-01-wt-hook-test.md" "$wt" | CLAUDE_PROJECT_DIR="$wt" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_has "hook(worktree): .claude/lib 不在でも構造監査の警告が届く(自分の位置から見つける)" "bare-issue-ref" "$out_wt"
file_isnt "hook(worktree): INDEX.md は作られない(ローカル索引は廃止)" "$wt/.claude/knowledge/INDEX.md"
rm -rf "$wt"

echo "== knowledge-index フック: 実際に \`git worktree add\` した作業ツリーで、file_path が作業ツリー内・CLAUDE_PROJECT_DIR が元のリポジトリを指す入力でも壊れた frontmatter の警告が出る =="
# 上の $wt テストは「worktree を模した単なる mktemp ディレクトリ」であり CLAUDE_PROJECT_DIR も
# file_path のルートと常に一致させていた(一次レビュー指摘)。ここでは実際に git worktree add で
# 作業ツリーを作り、CLAUDE_PROJECT_DIR には元のリポジトリ(作業ツリーではない側)を渡すことで、
# 「file_path がその作業ツリーの中・CLAUDE_PROJECT_DIR は元のリポジトリ」というシナリオそのものを
# 検証する。
wtreal_main="$(mktemp -d)"
gitc -C "$wtreal_main" init -q
gitc -C "$wtreal_main" commit -q --allow-empty -m init
wtreal_dir="$(mktemp -d)"
rmdir "$wtreal_dir"  # git worktree add に作業ツリー自身のディレクトリ作成を任せる(既存ディレクトリだと拒否する git 版があるため空にしてから渡す)
gitc -C "$wtreal_main" worktree add -q -b wtreal-branch "$wtreal_dir"
mkdir -p "$wtreal_dir/.claude/knowledge/process"
# 壊れた frontmatter(tags 欠落。既存の defaudit 検査と同じ壊し方)。
printf -- '---\nid: wtreal-defaudit\ndate: 2026-01-01\ndomain: process\nscope: local\nstatus: active\nsummary: 実際のgit worktreeでの構造監査確認\n---\nbody\n' \
  > "$wtreal_dir/.claude/knowledge/process/2026-01-01-wtreal-defaudit.md"
# file_path は作業ツリー($wtreal_dir)側、CLAUDE_PROJECT_DIR は元のリポジトリ($wtreal_main)側。
out_wtreal="$(json_file "$wtreal_dir/.claude/knowledge/process/2026-01-01-wtreal-defaudit.md" "$wtreal_main" | CLAUDE_PROJECT_DIR="$wtreal_main" bash "$H/hooks/knowledge-index.sh" 2>/dev/null)"
out_has   "hook(実際のgit worktree・CLAUDE_PROJECT_DIRが元repoを指す): 壊れたfrontmatter(tags欠落)の警告が出る(発火する)" "systemMessage" "$out_wtreal"
out_has   "hook(実際のgit worktree): frontmatter-missing-field として報告される" "frontmatter-missing-field" "$out_wtreal"
file_isnt "hook(実際のgit worktree): 作業ツリー側にも INDEX.md は作られない(ローカル索引は廃止)" "$wtreal_dir/.claude/knowledge/INDEX.md"
file_isnt "hook(実際のgit worktree): 元repo側には.claude/knowledge/INDEX.mdが作られない(誤射されない)" "$wtreal_main/.claude/knowledge/INDEX.md"

echo "== negative control: proj 導出を CLAUDE_PROJECT_DIR 基準に変えると、上のシナリオは発火しなくなる(発火の根拠が file_path 由来であることの確認) =="
wtreal_scratch="$(mktemp -d)"; _mk_ki_scratch_hooks "${wtreal_scratch}"
# proj 導出行(file_path から repo ルートを切り出す行)を CLAUDE_PROJECT_DIR 基準に書き換える前に、
# 置換対象の行が実在することを確認する(sed が黙って何もマッチしなかった場合の偽陰性を防ぐ)。
grep -qF 'proj="${file%/"$dir"/*}"' "$wtreal_scratch/hooks/knowledge-index.sh" \
  || ng "negative control: 前提(proj導出行)がスクラッチコピーに見つからない(construct不備)"
sed -i.bak 's#proj="\${file%/"\$dir"/\*}"#proj="\${CLAUDE_PROJECT_DIR:-.}"#' "$wtreal_scratch/hooks/knowledge-index.sh"
rm -f "$wtreal_scratch/hooks/knowledge-index.sh.bak"
# 壊す編集が実際に入ったことを確認してから結果を読む。
if grep -qF 'proj="${CLAUDE_PROJECT_DIR:-.}"' "$wtreal_scratch/hooks/knowledge-index.sh"; then
  ok "negative control: 壊す編集(proj導出をCLAUDE_PROJECT_DIR基準に置換)が実際に入った"
else
  ng "negative control: 壊す編集(proj導出をCLAUDE_PROJECT_DIR基準に置換)が実際に入った"
fi
out_wtreal_broken="$(json_file "$wtreal_dir/.claude/knowledge/process/2026-01-01-wtreal-defaudit.md" "$wtreal_main" | CLAUDE_PROJECT_DIR="$wtreal_main" bash "$wtreal_scratch/hooks/knowledge-index.sh" 2>/dev/null)"
out_hasnt "negative control: proj を CLAUDE_PROJECT_DIR 基準にすると同じ入力で警告が出なくなる(赤の確認)" "systemMessage" "$out_wtreal_broken"
rm -rf "$wtreal_scratch"

gitc -C "$wtreal_main" worktree remove --force "$wtreal_dir" >/dev/null 2>&1
rm -rf "$wtreal_main" "$wtreal_dir"

echo "== knowledge-audit.sh: 導入先に .claude/skills・.claude/agents・.claude/rules が無い状態でも [[...]] は実プラグインの実体で解決される =="
# プラグイン形では導入先(.claude/)に skills/agents/rules は存在しない(常に無い。旧CLIが作っていた
# worktree限定の欠落ではない)。監査スクリプトは自分の位置(BASH_SOURCE)からプラグインのルートを
# 自己解決するため、導入先に何も無くても実プラグイン(このリポジトリの harness/)の実在する
# skill/agent/rule 名で [[...]] が解決されることを確認する(本当に存在しない名前は引き続き
# dangling として検出されること=偽陽性を偽陰性にすり替えていないことも同じ fixture で確認する)。
kw="$(mktemp -d)"; mk_consumer "$kw"
mkdir -p "$kw/.claude/knowledge/harness-dev" "$kw/.claude/knowledge/global/testing"
if [ -e "$kw/.claude/skills" ] || [ -e "$kw/.claude/agents" ] || [ -e "$kw/.claude/rules" ]; then
  ng "前提: mk_consumer は .claude/skills・.claude/agents・.claude/rules を作らない"
else
  ok "前提: mk_consumer は .claude/skills・.claude/agents・.claude/rules を作らない"
fi
# グローバルミラーを実際に1件以上のエントリで「同期済み」にしておく(空ディレクトリのままだと、
# 空を不在と同じ扱いにする改修により global_present が偽になり、下の e-kw-link-missing の期待値が
# dangling-link ではなく dangling-link-skipped に変わってしまう)。
printf -- '---\nid: kw-store-only-id\ndate: 2026-01-01\ndomain: testing\nscope: global\nstatus: active\nsummary: synced global mirror entry for this fixture\n---\nbody\n' \
  > "$kw/.claude/knowledge/global/testing/2026-01-01-kw-gid.md"
printf -- '---\nid: e-kw-link-skill\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nSee [[capture-learning]].\n' \
  > "$kw/.claude/knowledge/harness-dev/2026-01-01-e-kw-link-skill.md"
printf -- '---\nid: e-kw-link-agent\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nSee [[implementer]].\n' \
  > "$kw/.claude/knowledge/harness-dev/2026-01-01-e-kw-link-agent.md"
printf -- '---\nid: e-kw-link-rule\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nSee [[pr-loop]].\n' \
  > "$kw/.claude/knowledge/harness-dev/2026-01-01-e-kw-link-rule.md"
printf -- '---\nid: e-kw-link-missing\ndate: 2026-01-01\ndomain: harness-dev\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nSee [[nonexistent-thing-xyz]].\n' \
  > "$kw/.claude/knowledge/harness-dev/2026-01-01-e-kw-link-missing.md"
kw_out="$(bash "$H/lib/knowledge-audit.sh" "$kw/.claude" 2>&1)"
if ka_has "knowledge/harness-dev/2026-01-01-e-kw-link-skill.md" "dangling-link" "$kw_out"; then ng "[[capture-learning]](実skill)は誤検知しない"; else ok "[[capture-learning]](実skill)は誤検知しない"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-kw-link-agent.md" "dangling-link" "$kw_out"; then ng "[[implementer]](実agent)は誤検知しない"; else ok "[[implementer]](実agent)は誤検知しない"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-kw-link-rule.md" "dangling-link" "$kw_out"; then ng "[[pr-loop]](実rule)は誤検知しない"; else ok "[[pr-loop]](実rule)は誤検知しない"; fi
if ka_has "knowledge/harness-dev/2026-01-01-e-kw-link-missing.md" "dangling-link" "$kw_out"; then ok "実在しない [[nonexistent-thing-xyz]] は引き続き検出される(偽陽性を偽陰性にすり替えていない)"; else ng "実在しない [[nonexistent-thing-xyz]] は引き続き検出される(偽陽性を偽陰性にすり替えていない)"; fi
rm -rf "$kw"

echo "== knowledge-audit.sh: 走査対象ゼロと報告ゼロを区別する =="
# ke1: 新規導入直後(project-local エントリ0件)。install が作る .claude/knowledge/ ディレクトリ自体は
# 実在するが、ドメインサブディレクトリ配下の *.md エントリは1つも無い。「正当にエントリが0件」の
# 状態であり、これを失敗として扱ってはならない(exit 0)。
ke1="$(mktemp -d)"; mk_consumer "$ke1"
ke1_stdout="$(bash "$H/lib/knowledge-audit.sh" "$ke1/.claude" 2>/dev/null)"
ke1_rc="$(bash "$H/lib/knowledge-audit.sh" "$ke1/.claude" >/dev/null 2>&1; echo $?)"
ke1_stderr="$(bash "$H/lib/knowledge-audit.sh" "$ke1/.claude" 2>&1 1>/dev/null)"
out_is_empty "受け入れ条件3: 正当にエントリ0件の新規導入先は標準出力が空(TSV契約は変えない)" "$ke1_stdout"
exit_is    "受け入れ条件3: 正当にエントリ0件の新規導入先は exit 0(失敗として扱わない)" 0 "$ke1_rc"
out_has    "受け入れ条件1: 走査0件が標準エラー出力に明示される" "0 件走査" "$ke1_stderr"

# ke2: 同じ導入先にエントリを1件追加(構造的欠陥の無いクリーンなエントリ)。走査対象は1件だが報告は
# 0件になる。この「1件走査・0件報告」は ke1(0件走査・0件報告)と標準出力だけでは区別できないが、
# 標準エラー出力の走査件数(0 件走査 / 1 件走査)では区別できなければならない。
mkdir -p "$ke1/.claude/knowledge/api"
printf -- '---\nid: ke-clean\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nno issues here.\n' \
  > "$ke1/.claude/knowledge/api/2026-01-01-ke-clean.md"
ke2_stdout="$(bash "$H/lib/knowledge-audit.sh" "$ke1/.claude" 2>/dev/null)"
ke2_stderr="$(bash "$H/lib/knowledge-audit.sh" "$ke1/.claude" 2>&1 1>/dev/null)"
out_is_empty "受け入れ条件1: 1件走査してクリーンでも標準出力は空(従来どおり無出力=クリーン)" "$ke2_stdout"
out_has    "受け入れ条件1: 走査1件・報告0件が標準エラー出力に明示される" "1 件走査" "$ke2_stderr"
out_hasnt  "受け入れ条件1: 0件走査(ke1)と1件走査(ke2)は標準エラー出力の走査件数で区別できる" "0 件走査" "$ke2_stderr"
rm -rf "$ke1"

# ke3: 実害の再現。引数を1階層深く渡す(`<install先>/knowledge` を渡す。正しくは `<install先>`)。
# 陽性対照として、まず正しい引数(.claude)では実際に欠陥(bare-issue-ref)が検出されることを確認し
# (construct が正しく組めている)、続けて誤った引数では無出力・exit 0で「クリーン」と誤読できていた
# ことの回帰を防ぐ。
ke3="$(mktemp -d)"; mk_consumer "$ke3"
mkdir -p "$ke3/.claude/knowledge/api"
printf -- '---\nid: ke3-entry\ndate: 2026-01-01\ndomain: api\ntags: []\nscope: local\nstatus: active\nsummary: s\n---\nissue '"$HSH"'123 with no repo.\n' \
  > "$ke3/.claude/knowledge/api/2026-01-01-ke3-entry.md"
ke3_correct_out="$(bash "$H/lib/knowledge-audit.sh" "$ke3/.claude" 2>/dev/null)"
if ka_has "knowledge/api/2026-01-01-ke3-entry.md" "bare-issue-ref" "$ke3_correct_out"; then ok "陽性対照: 正しい引数(.claude)では実際に欠陥が検出される(construct が正しく組めている)"; else ng "陽性対照: 正しい引数(.claude)では実際に欠陥が検出される(construct が正しく組めている)"; fi
ke3_wrong_stdout="$(bash "$H/lib/knowledge-audit.sh" "$ke3/.claude/knowledge" 2>/dev/null)"
ke3_wrong_rc="$(bash "$H/lib/knowledge-audit.sh" "$ke3/.claude/knowledge" >/dev/null 2>&1; echo $?)"
ke3_wrong_stderr="$(bash "$H/lib/knowledge-audit.sh" "$ke3/.claude/knowledge" 2>&1 1>/dev/null)"
out_is_empty "受け入れ条件2: 誤った引数(1階層深い)でも標準出力は空のまま(TSV契約は変えない)" "$ke3_wrong_stdout"
exit_is    "受け入れ条件2(実害の再現): 誤った引数(1階層深い)は非ゼロで終了する(以前は exit 0 で「クリーン」と誤読できた)" 1 "$ke3_wrong_rc"
out_has    "受け入れ条件2: 誤った引数は標準エラー出力で理由が分かる" "knowledge が無い" "$ke3_wrong_stderr"
rm -rf "$ke3"

