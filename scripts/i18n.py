#!/usr/bin/env python3
"""i18n tool for cdda-termux-builder.

Runtime (get_txt / log_* / send_notification in bash) does NOT depend on
Python. This tool is only needed when maintaining locales/*.po files
(pkg install python).

Usage:
  i18n.sh extract [lang]     Extract msgids, merge existing translations,
                             and write them back to .po
  i18n.sh check [lang ...]   Check missing / untranslated / obsolete /
                             duplicates / format errors / printf spec mismatch
  i18n.sh init <lang>        Create a new language .po (all msgstr empty)
  i18n.sh stats              Translation progress per language
  i18n.sh list               List all msgids found in source
  i18n.sh lint               Report hardcoded English echo bypassing log_*/get_txt
"""
import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent
PO  = SRC.parent / "locales"


# ================= Extract msgids from .sh =================

def extract_var(text, name):
    """Extract VAR='...' (supports multi-line values such as HELP_EN)."""
    m = re.search(rf"^{re.escape(name)}='", text, re.MULTILINE)
    if not m:
        return None
    rest = text[m.end():]
    end = re.search(r"^([^\n]*)'$", rest, re.MULTILINE)
    if not end:
        return None
    return rest[:end.start()] + end.group(1)


def msgids_in(path):
    t = path.read_text(encoding="utf-8")
    out = []

    # get_txt "literal" (skip strings starting with $)
    out += re.findall(r'get_txt\s+"([^"$][^"]*)"', t)

    # get_txt "$VAR" -> VAR='...'
    for var in dict.fromkeys(
        re.findall(r'get_txt\s+"\$([A-Za-z_][A-Za-z0-9_]*)"', t)
    ):
        v = extract_var(t, var)
        if v is not None:
            out.append(v)

    # log_* "literal" (log_* now auto-translates and formats)
    out += re.findall(
        r'\blog_(?:info|warn|error|step)\s+"([^"$][^"]*)"', t
    )

    # send_notification "title" "content"
    for m in re.finditer(
        r'send_notification\s+"([^"$][^"]*)"\s+"([^"$][^"]*)"', t
    ):
        out += [m.group(1), m.group(2)]

    return out


def all_msgids():
    seen, out = set(), []
    for p in sorted(SRC.glob("*.sh")):
        for m in msgids_in(p):
            if m not in seen:
                seen.add(m)
                out.append(m)
    return out


# ================= .po read / write =================

def unescape(s):
    return (s.replace('\\n', '\n').replace('\\t', '\t')
             .replace('\\"', '"').replace('\\\\', '\\'))


def esc(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')


def emit(kw, s):
    if '\n' not in s:
        return f'{kw} "{esc(s)}"\n'
    parts = s.split('\n')
    lines = [f'{kw} ""\n']
    for i, p in enumerate(parts):
        e = esc(p)
        if i < len(parts) - 1:
            lines.append(f'"{e}\\n"\n')
        elif p:
            lines.append(f'"{e}"\n')
    return ''.join(lines)


def parse(path):
    """Return (entries, duplicates, errors).

    entries:    {msgid: {"msgstr": str, "comments": [str]}}
    duplicates: [msgid, ...]
    errors:     [desc, ...]
    """
    if not path.exists():
        return {}, [], []

    entries, duplicates, errors = {}, [], []
    text = path.read_text(encoding='utf-8')

    for block in re.split(r'\n\s*\n', text):
        if not block.strip():
            continue

        comments, mid, mstr, mode = [], '', '', None
        has_id = False

        for line in block.splitlines():
            s = line.strip()
            if s.startswith('#'):
                comments.append(s)
                continue
            if not s:
                continue

            m = re.match(r'^msgid\s+"(.*)"$', s)
            if m:
                mode, mid, has_id = 'id', unescape(m.group(1)), True
                continue

            m = re.match(r'^msgstr\s+"(.*)"$', s)
            if m:
                mode, mstr = 'str', unescape(m.group(1))
                continue

            m = re.match(r'^"(.*)"$', s)
            if m:
                if mode == 'id':
                    mid += unescape(m.group(1))
                elif mode == 'str':
                    mstr += unescape(m.group(1))
                else:
                    errors.append(f'orphan string: {s[:50]}')
                continue

            errors.append(f'unrecognized line: {s[:50]}')

        if not has_id:
            if comments:
                errors.append('block with comments but no msgid')
            continue

        if mid == '':
            continue  # header

        if mid in entries:
            duplicates.append(mid)
            continue

        entries[mid] = {'msgstr': mstr, 'comments': comments}

    return entries, duplicates, errors


def write_po(path, lang, msgids, entries):
    out = [
        'msgid ""\nmsgstr ""\n'
        '"Project-Id-Version: cdda-termux-builder\\n"\n'
        f'"Language: {lang}\\n"\n'
        '"MIME-Version: 1.0\\n"\n'
        '"Content-Type: text/plain; charset=UTF-8\\n"\n'
        '"Content-Transfer-Encoding: 8bit\\n"\n\n'
    ]
    for m in msgids:
        info = entries.get(m) or {'msgstr': '', 'comments': []}
        for c in info['comments']:
            out.append(c + '\n')
        out.append(emit('msgid', m))
        out.append(emit('msgstr', info['msgstr']))
        out.append('\n')
    path.write_text(''.join(out), encoding='utf-8')


# ================= printf format specifier =================

_FMT_RE = re.compile(r'%(\d+\$)?[-+ #0]*\d*(?:\.\d+)?[hljztL]?([diouxXeEfgGaAcspn])')


def format_types(s):
    """Return the sequence of printf conversion types, ignoring %%."""
    out, i = [], 0
    while i < len(s):
        if s[i] != '%':
            i += 1
            continue
        if i + 1 < len(s) and s[i + 1] == '%':
            i += 2
            continue
        m = _FMT_RE.match(s, i)
        if m:
            out.append(m.group(2))
            i = m.end()
        else:
            i += 1
    return out


# ================= Commands =================

def cmd_extract(lang=None):
    msgids = all_msgids()
    pool = set(msgids)
    print(f'source: {len(msgids)} msgids', file=sys.stderr)

    langs = [lang] if lang else [p.stem for p in sorted(PO.glob('*.po'))]
    if not langs:
        print('no .po files; run: i18n.sh extract <lang>', file=sys.stderr)
        return 1

    for lg in langs:
        p = PO / f'{lg}.po'
        old, dups, errs = parse(p)

        if dups:
            print(f'[{lg}] WARN: {len(dups)} duplicate msgid(s), keeping first',
                  file=sys.stderr)
        if errs:
            print(f'[{lg}] WARN: {len(errs)} parse error(s), see check',
                  file=sys.stderr)

        translated = sum(1 for m in msgids if old.get(m, {}).get('msgstr'))
        new        = sum(1 for m in msgids if m not in old)
        obsolete   = sum(1 for m in old if m not in pool)

        write_po(p, lg, msgids, old)

        bits = [f'{translated}/{len(msgids)} translated']
        if new:      bits.append(f'{new} new')
        if obsolete: bits.append(f'{obsolete} obsolete dropped')
        print(f'[{lg}] ' + ', '.join(bits), file=sys.stderr)
    return 0


def cmd_check(langs=None):
    msgids = all_msgids()
    pool = set(msgids)
    langs = langs or [p.stem for p in sorted(PO.glob('*.po'))]
    if not langs:
        print('no .po files', file=sys.stderr)
        return 1

    rc = 0
    for lg in langs:
        p = PO / f'{lg}.po'
        if not p.exists():
            print(f'== {lg}: FILE NOT FOUND ==', file=sys.stderr)
            rc = 1
            continue

        entries, dups, errs = parse(p)
        issues = []

        missing = [m for m in msgids if m not in entries]
        if missing:
            issues.append(f'  missing ({len(missing)}):')
            issues += [f'    - {m[:70]!r}' for m in missing]

        untranslated = [m for m in msgids if m in entries and not entries[m]['msgstr']]
        if untranslated:
            issues.append(f'  untranslated ({len(untranslated)}):')
            issues += [f'    - {m[:70]!r}' for m in untranslated]

        obsolete = [m for m in entries if m not in pool]
        if obsolete:
            issues.append(f'  obsolete ({len(obsolete)}):')
            issues += [f'    - {m[:70]!r}' for m in obsolete]

        if dups:
            issues.append(f'  duplicate ({len(dups)}):')
            issues += [f'    - {m[:70]!r}' for m in dups]

        if errs:
            issues.append(f'  format errors ({len(errs)}):')
            issues += [f'    - {e}' for e in errs]

        # printf conversion-type consistency (translated entries only)
        fmt_bad = []
        for m in msgids:
            if m not in entries or not entries[m]['msgstr']:
                continue
            a = format_types(m)
            b = format_types(entries[m]['msgstr'])
            if a != b:
                fmt_bad.append(f'    - {m[:60]!r}: msgid={a} msgstr={b}')
        if fmt_bad:
            issues.append(f'  printf spec mismatch ({len(fmt_bad)}):')
            issues += fmt_bad

        if issues:
            print(f'== {lg}: ISSUES ==', file=sys.stderr)
            for line in issues:
                print(line, file=sys.stderr)
            rc = 1
        else:
            print(f'== {lg}: OK ==', file=sys.stderr)
    return rc


def cmd_init(lang):
    p = PO / f'{lang}.po'
    if p.exists():
        print(f'{p} already exists; use "extract {lang}" to update.',
              file=sys.stderr)
        return 1
    msgids = all_msgids()
    write_po(p, lang, msgids, {})
    print(f'created {p} with {len(msgids)} entries', file=sys.stderr)
    return 0


def cmd_stats():
    msgids = all_msgids()
    pool = set(msgids)
    print(f'source: {len(msgids)} msgids\n')

    po_files = sorted(PO.glob('*.po'))
    if not po_files:
        print('no .po files')
        return 0

    for p in po_files:
        lg = p.stem
        entries, dups, _ = parse(p)
        total      = len(msgids)
        translated = sum(1 for m in msgids if m in entries and entries[m]['msgstr'])
        untrans    = sum(1 for m in msgids if m in entries and not entries[m]['msgstr'])
        missing    = sum(1 for m in msgids if m not in entries)
        obsolete   = sum(1 for m in entries if m not in pool)
        pct = translated / total * 100 if total else 0
        extras = []
        if dups:     extras.append(f'dup={len(dups)}')
        if obsolete: extras.append(f'obsolete={obsolete}')
        tail = ('  ' + ' '.join(extras)) if extras else ''
        print(f'{lg}: {translated}/{total} ({pct:.1f}%) '
              f'missing={missing} untranslated={untrans}{tail}')
    return 0


def cmd_list():
    for m in all_msgids():
        print(f'- {m!r}')
    return 0


def _has_file_redirect(args):
    """True if `args` contains a file redirect (>file or >>file),
    excluding fd duplication (>&N, >>&N, N>&M)."""
    stripped = re.sub(r'"(?:[^"\\]|\\.)*"', '""', args)
    stripped = re.sub(r"'(?:[^'\\]|\\.)*'", "''", stripped)
    for m in re.finditer(r'>>?', stripped):
        pos = m.end()
        if pos < len(stripped) and stripped[pos] == '&':
            continue  # >& or >>& (fd duplication, not a file)
        return True
    return False


def _has_hardcoded_english(lit):
    """True if the string has hardcoded English after removing variables."""
    # Fragmented match crossing a $( boundary (e.g. quoting inside command
    # substitution); skip it — the fragment cannot be analyzed reliably.
    if '$(' in lit:
        after = lit.split('$(', 1)[1]
        if ')' not in after:
            return False
    tmp = re.sub(r'\$\([^()]*\)', '', lit)          # $(...)
    tmp = re.sub(r'\$\{[^}]*\}', '', tmp)           # ${...}
    tmp = re.sub(r'\$[A-Za-z_][A-Za-z0-9_]*', '', tmp)  # $VAR
    tmp = re.sub(r'\$[0-9@*#?$!-]', '', tmp)        # $1, $@, ...
    return bool(re.search(r'[A-Za-z]{3,}', tmp))


ECHO_RE = re.compile(
    r'\becho\b((?:[^|;&\n]|"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')*)'
)
STR_RE = re.compile(r'"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\'')


def cmd_lint():
    skip_call = re.compile(
        r'\b(?:log_info|log_warn|log_error|log_step|send_notification|get_txt)\b'
    )
    findings = []
    for sh in sorted(SRC.glob('*.sh')):
        name = sh.name
        if name in ('i18n.sh', 'i18n.py'):
            continue  # rule 5: do not scan ourselves
        for lineno, line in enumerate(sh.read_text(encoding='utf-8').splitlines(), 1):
            s = line.strip()
            if not s or s.startswith('#'):
                continue
            if skip_call.search(line):
                continue
            if 'echo' not in line:
                continue
            for m in ECHO_RE.finditer(line):
                args = m.group(1)
                rest = line[m.end():]
                # rule 4: only skip this echo if it pipes into sha256sum
                if re.match(r'\s*\|\s*sha256sum\b', rest):
                    continue
                # rule 1: skip this echo if it redirects to a file
                if _has_file_redirect(args):
                    continue
                # rules 2 + 3: analyze each string literal independently
                hit = None
                for sm in STR_RE.finditer(args):
                    lit = sm.group(1) if sm.group(1) is not None else sm.group(2)
                    if _has_hardcoded_english(lit):
                        hit = lit
                        break
                if hit is not None:
                    findings.append((name, lineno, s, hit))
    if not findings:
        print('lint: OK', file=sys.stderr)
        return 0
    print(f'lint: {len(findings)} finding(s):', file=sys.stderr)
    for name, lineno, line, hint in findings:
        print(f'  {name}:{lineno}: {line}', file=sys.stderr)
        print(f'      English literal {hint!r} bypasses log_*/get_txt '
              f'and cannot be translated', file=sys.stderr)
    return 1


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip())
        return 1

    cmd, args = sys.argv[1], sys.argv[2:]

    if cmd == 'extract':
        return cmd_extract(args[0] if args else None)
    if cmd == 'check':
        return cmd_check(args or None)
    if cmd == 'init':
        if not args:
            print('usage: i18n.sh init <lang>', file=sys.stderr)
            return 1
        return cmd_init(args[0])
    if cmd == 'stats':
        return cmd_stats()
    if cmd == 'list':
        return cmd_list()
    if cmd == 'lint':
        return cmd_lint()
    if cmd in ('help', '-h', '--help'):
        print(__doc__.strip())
        return 0

    print(f'unknown command: {cmd}', file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())