#!/usr/bin/env python3
"""Reject missing or unused bundled strings and check printf argument contracts."""
from pathlib import Path
import json
import re
import subprocess

root = Path(__file__).resolve().parent.parent
locales = ['en', 'zh-Hans', 'zh-Hant', 'ja', 'ko']
tables = {}
for locale in locales:
    path = root / 'packaging' / f'{locale}.lproj' / 'Localizable.strings'
    subprocess.run(['plutil', '-lint', str(path)], check=True)
    raw = path.read_text()
    entries = re.findall(r'^"([^"\n]+)"\s*=', raw, re.M)
    assert len(entries) == len(set(entries)), f'{locale}: duplicate key'
    tables[locale] = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))
base = tables['en']
placeholder = re.compile(r'%(?!%)(?:\d+\$)?(?:[-+0 #]*\d*(?:\.\d+)?)?(?:l{1,2}|z)?[@diuoxXfFeEgGcCsSp]')
for locale, table in tables.items():
    assert table.keys() == base.keys(), f'{locale}: mismatched keys'
    for key, text in table.items():
        assert placeholder.findall(text) == placeholder.findall(base[key]), f'{locale}: incompatible arguments for {key}'
references = set()
for path in (root / 'Sources').rglob('*.swift'):
    references.update(re.findall(r'"((?:app|panel|ui|state|status|warn|enf|agent|cli|lang|menu|setup|about)\.[a-zA-Z0-9.-]+)"', path.read_text()))
references = {key for key in references if not key.startswith('app.keypin')}
assert references <= base.keys(), f'Missing source keys: {sorted(references - base.keys())}'
assert base.keys() <= references, f'Unused localization keys: {sorted(base.keys() - references)}'
for locale, table in tables.items():
    assert table['app.name'] == 'KeyPin', f'{locale}: stale product name'
    info = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(root / 'packaging' / f'{locale}.lproj' / 'InfoPlist.strings')]))
    assert info['CFBundleName'] == info['CFBundleDisplayName'] == 'KeyPin', f'{locale}: stale bundle name'
    assert all(value.lstrip().startswith('keypin') for key, value in table.items() if key.startswith('cli.usage.') and key != 'cli.usage.header'), f'{locale}: invalid command name'
print(f'PASS: {len(locales)} locales, {len(base)} keys each, {len(references)} source references; printf contracts match.')
print('PASS: all localized app names, bundle names and CLI references use KeyPin/keypin.')
