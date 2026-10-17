#!/usr/bin/env bash
# catalog-gen.sh — skill/agent/rule/hook の機械一覧(Markdown)を生成する。
#
# knowledge-index.sh(frontmatter→INDEX.md 生成)と同型のパターン: SSOT は各ファイル自身で、
# 手書き台帳を持たない(手書きは drift 源になる)。
# 使い方: catalog-gen.sh <base-dir>
#   <base>/skills/*/SKILL.md ・ <base>/agents/*.md ・ <base>/rules/*.md ・ <base>/hooks/*.sh ・
#   <base>/bin/* を走査し、Markdown 一覧を stdout に生成する。<base> は payload レイアウト
#   (skills/agents/hooks/rules/bin)を持つディレクトリなら何でもよい(配布 payload の harness/ 自身にも使える)。
# 前提(メタデータ形は4種、いずれも決定論的に抽出できる形のみ対応):
#   - skill/agent = frontmatter `name:`/`description:`(1行 key: value。knowledge-index.sh と同じ制約)
#   - rule        = frontmatter無し。先頭の `# 見出し` から導出(見出し直後の `>` 行があっても抽出しない。
#                   配布するルールは取り決めを述べる書き方に統一しており、見出し直後の管理注記は
#                   受け取る側には出さない設計になっている)
#   - hook        = シェバン直後に連続する `#` ヘッダコメント行から導出
#   - 実行ファイル(bin) = シェバン直後の最初の `#` コメント行から導出(1行のみ。hook と違い
#                   複数行を連結しない——bin の先頭コメントは1行の要約に統一されているため)
# 前提: python3 が無ければ何もしない(knowledge-index.sh と同じ安全側フォールバック)。
set -uo pipefail

cg_log() { printf 'catalog-gen: %s\n' "$1" >&2; }

catalog_gen() {  # <base-dir>
  local base="${1:-.}"
  [ -n "$base" ] && [ -d "$base" ] || { cg_log "ディレクトリが不正: ${base:-(空)}"; return 1; }
  command -v python3 >/dev/null 2>&1 || { cg_log "python3 が無い → catalog 生成を skip"; return 0; }
  python3 - "$base" <<'PY'
import sys, os, glob

base = sys.argv[1]

def frontmatter(path):
    try:
        lines = open(path, encoding='utf-8').read().splitlines()
    except Exception:
        return {}
    if not lines or lines[0].strip() != '---':
        return {}
    d = {}
    for ln in lines[1:]:
        if ln.strip() == '---':
            break
        if ':' not in ln:
            continue
        k, v = ln.split(':', 1)
        # 1行 key: value のみ対応(knowledge-index.sh と同じ制約。値中の : や # はそのまま保持)。
        d[k.strip()] = v.strip()
    return d

def cell(s):
    return (s or '').replace('|', '/').replace('\n', ' ')

def skills_rows():
    rows = []
    for f in sorted(glob.glob(os.path.join(base, 'skills', '*', 'SKILL.md'))):
        d = frontmatter(f)
        name = d.get('name') or os.path.basename(os.path.dirname(f))
        rows.append((name, d.get('description', '')))
    return rows

def agents_rows():
    rows = []
    for f in sorted(glob.glob(os.path.join(base, 'agents', '*.md'))):
        d = frontmatter(f)
        name = d.get('name') or os.path.splitext(os.path.basename(f))[0]
        rows.append((name, d.get('description', '')))
    return rows

def rules_rows():
    rows = []
    for f in sorted(glob.glob(os.path.join(base, 'rules', '*.md'))):
        try:
            lines = open(f, encoding='utf-8').read().splitlines()
        except Exception:
            continue
        heading = ''
        for ln in lines:
            if ln.startswith('# '):
                heading = ln[2:].strip()
                break
        name = os.path.splitext(os.path.basename(f))[0]
        rows.append((name, heading))
    return rows

def hooks_rows():
    rows = []
    for f in sorted(glob.glob(os.path.join(base, 'hooks', '*.sh'))):
        try:
            lines = open(f, encoding='utf-8').read().splitlines()
        except Exception:
            continue
        desc = []
        for ln in lines[1:]:   # lines[0] はシェバン
            s = ln.strip()
            if not s.startswith('#'):
                break
            text = s.lstrip('#').strip()
            if text:
                desc.append(text)
        name = os.path.basename(f)
        rows.append((name, ' '.join(desc)))
    return rows

def bin_rows():
    rows = []
    for f in sorted(glob.glob(os.path.join(base, 'bin', '*'))):
        if not os.path.isfile(f):
            continue
        try:
            lines = open(f, encoding='utf-8').read().splitlines()
        except Exception:
            continue
        desc = ''
        for ln in lines[1:]:   # lines[0] はシェバン
            s = ln.strip()
            if s.startswith('#'):
                text = s.lstrip('#').strip()
                if text:
                    desc = text
                break
            if s:
                break
        name = os.path.basename(f)
        rows.append((name, desc))
    return rows

out = [
    '<!-- 生成物: scripts/catalog-gen.sh が生成。手編集しない(各ファイルの frontmatter/ヘッダを直す) -->',
    '',
    '### skills',
    '',
    '| skill | description |',
    '|---|---|',
]
for name, desc in skills_rows():
    out.append('| `%s` | %s |' % (name, cell(desc)))
out += ['', '### agents', '', '| agent | description |', '|---|---|']
for name, desc in agents_rows():
    out.append('| `%s` | %s |' % (name, cell(desc)))
out += ['', '### rules (harness)', '', '| rule | 見出し |', '|---|---|']
for name, heading in rules_rows():
    out.append('| `%s` | %s |' % (name, cell(heading)))
out += ['', '### hooks', '', '| hook | description |', '|---|---|']
for name, desc in hooks_rows():
    out.append('| `%s` | %s |' % (name, cell(desc)))
out += ['', '### 実行ファイル', '', '| コマンド | description |', '|---|---|']
for name, desc in bin_rows():
    out.append('| `%s` | %s |' % (name, cell(desc)))

print('\n'.join(out))
PY
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then catalog_gen "${1:-.}"; fi
