"""Negative controls for the pinned Forever API inventory."""
import json
from pathlib import Path
import tempfile
import forever_schema_audit as checker

original = checker.ROOT
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / 'tools/fixtures').mkdir(parents=True)
    (root / 'tools/fixtures/forever-70532.json').write_bytes((original / 'tools/fixtures/forever-70532.json').read_bytes())
    source = root / 'Feature.lua'
    checker.ROOT = root
    source.write_text('C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator("Name Surname")\n-- C_Fake.DoesNotExist()\n')
    assert not checker.audit()['errors']
    source.write_text('C_NameUtil.GetSurname("player")\n')
    report = checker.audit()
    assert len(report['errors']) == 1 and 'GetSurname' in report['errors'][0]
checker.ROOT = original
print('Forever schema negative controls: PASS (valid API, comments, invented getter rejected)')
