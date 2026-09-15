#!/usr/bin/env python3
"""Prepare SQL bytes only. No database access or migration execution."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

REPO = Path('/Users/jacksonsweet/Projects/OPS/.worktrees/ios-bugs-p9-expense-release')
REVISION = '53d334378cd0d61adec387a8580d569a46cf5d33'
OUT = Path(__file__).resolve().parent
PATHS = [
    'supabase/migrations/20260912012607_expense_decision_company_authority.sql',
    'supabase/migrations/20260912203328_expense_accounting_lifecycle.sql',
    'supabase/migrations/20260914200910_expense_payroll_reimbursement_projection.sql',
    'supabase/migrations/20260914214748_expense_admin_correction_review.sql',
]

def statements(sql):
    """Locate semicolon statements outside comments, strings and dollar bodies."""
    i, start, n = 0, None, len(sql)
    while i < n:
        if sql[i].isspace():
            i += 1
            continue
        if sql.startswith('--', i):
            end = sql.find('\n', i + 2)
            i = n if end < 0 else end + 1
            continue
        if sql.startswith('/*', i):
            depth = 1
            i += 2
            while depth:
                if i >= n:
                    raise ValueError('Unclosed SQL comment')
                if sql.startswith('/*', i): depth, i = depth + 1, i + 2
                elif sql.startswith('*/', i): depth, i = depth - 1, i + 2
                else: i += 1
            continue
        if start is None:
            start = i
        if sql[i] in "'\"":
            quote = sql[i]
            i += 1
            while True:
                if i >= n:
                    raise ValueError('Unclosed SQL quote')
                if sql[i] == quote:
                    if i + 1 < n and sql[i + 1] == quote:
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
            continue
        tag = re.match(r'\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$', sql[i:])
        if tag:
            delimiter = tag.group()
            end = sql.find(delimiter, i + len(delimiter))
            if end < 0:
                raise ValueError('Unclosed SQL dollar body')
            i = end + len(delimiter)
            continue
        if sql[i] == ';':
            yield start, i + 1
            start = None
        i += 1
    if start is not None:
        raise ValueError('Non-comment text without final semicolon')

def strip_outer_transaction(source):
    spans = list(statements(source))
    controls = [(a, b) for a, b in spans if re.match(r'(?i)(?:begin|commit|rollback|start\s+transaction)\b', source[a:b])]
    if not controls:
        return source, []
    expected = [spans[0], spans[-1]]
    if controls != expected or source[spans[0][0]:spans[0][1]].lower() != 'begin;' or source[spans[-1][0]:spans[-1][1]].lower() != 'commit;':
        raise ValueError('Only exact outer BEGIN/COMMIT statements may be removed')
    transformed = source
    for a, b in reversed(controls):
        transformed = transformed[:a] + transformed[b:]
    return transformed, [{'startByte': a, 'endByte': b, 'removed': source[a:b]} for a, b in controls]

def digest(body):
    return hashlib.sha256(body).hexdigest()

manifest = {'prepareOnly': True, 'candidateRevision': REVISION, 'sources': [], 'ledger': {'mechanism': 'Supabase apply_migration once', 'actualVersion': None, 'constituentVersionsAreSuperseded': True}}
guard = (OUT / 'baseline-guard.sql').read_bytes()
manifest['baselineGuardSha256'] = digest(guard)
parts = ['-- PREPARE ONLY. Requires separate migration authorization.\nBEGIN;\n', guard.decode('ascii'), '\n']
for path in PATHS:
    raw = subprocess.check_output(['git', '-C', str(REPO), 'show', f'{REVISION}:{path}'])
    # Byte offsets below are exact because these migration files are ASCII.
    source = raw.decode('ascii')
    body, removed = strip_outer_transaction(source)
    source_path = OUT / 'constituent-sources' / Path(path).name
    source_path.parent.mkdir(parents=True, exist_ok=True)
    source_path.write_bytes(raw)
    manifest['sources'].append({'path': path, 'version': Path(path).name.split('_')[0], 'sourceSha256': digest(raw), 'bodySha256': digest(body.encode('ascii')), 'removedOuterStatements': removed})
    parts.append(f'\n-- Constituent: {path}\n-- Source SHA256: {digest(raw)}\n')
    parts.append(body)
    parts.append('\n')
parts.append('\nCOMMIT;\n')
bundle = ''.join(parts).encode('ascii')
outer = list(statements(bundle.decode('ascii')))
assert bundle[outer[0][0]:outer[0][1]] == b'BEGIN;'
assert bundle[outer[-1][0]:outer[-1][1]] == b'COMMIT;'
assert sum(bool(re.match(rb'(?i)(?:begin|commit|rollback|start\s+transaction)\b', bundle[a:b])) for a,b in outer) == 2
manifest['bundleSha256'] = digest(bundle)
manifest['bundleByteCount'] = len(bundle)
manifest['sqlExecutionPerformed'] = False
(OUT / 'expense-release-atomic.sql').write_bytes(bundle)
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps({'bundleSha256': digest(bundle), 'bytes': len(bundle), 'constituents': len(PATHS), 'topLevelTransactionStatements': 2}))
