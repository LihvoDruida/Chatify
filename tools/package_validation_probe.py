"""Negative controls: missing libraries, wrong versions and missing XML includes."""
import importlib.util
import io
import pathlib
import tempfile
import zipfile

spec = importlib.util.spec_from_file_location('packagecheck', 'tools/validate_package.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = pathlib.Path('Chatify.toc').read_bytes()
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    f = root / 'source-only.zip'
    with zipfile.ZipFile(f, 'w') as z:
        for toc in pathlib.Path('.').glob('*.toc'):
            z.write(toc, 'Chatify/' + toc.name)
        z.write('libs/_manifest.xml', 'Chatify/libs/_manifest.xml')
    result = module.validate(str(f), '9.9.9')
    assert result['status'] == 'FAIL'
    assert any('library:' in message for message in result['errors']), result['errors']
    assert any('Version=' in message for message in result['errors']), result['errors']
    assert any('Unresolved' in message for message in result['errors']), result['errors']
    # Same ZIP must not become green solely because expected version was omitted.
    result = module.validate(str(f))
    assert result['status'] == 'FAIL'
    assert any('Missing expected version' in message for message in result['errors'])
print('package validator negative controls: PASS')

# A structurally complete synthetic package must pass before negative controls
# can establish that the validator rejects the particular defect under test.
# This fixture tests archive validation only; these are not real addon libraries.
files = {}
for toc in pathlib.Path('.').glob('*.toc'):
    files['Chatify/' + toc.name] = toc.read_bytes()
for path in list(pathlib.Path('.').glob('*.lua')) + list(pathlib.Path('locale').glob('*.lua')) + list(pathlib.Path('assets').rglob('*')):
    if path.is_file():
        files['Chatify/' + path.as_posix()] = path.read_bytes()
files['Chatify/libs/_manifest.xml'] = pathlib.Path('libs/_manifest.xml').read_bytes()
for relative in module.CORE_LIBS:
    name = 'Chatify/libs/' + relative
    files[name] = b'<Ui><script file="implementation.lua"/></Ui>' if relative.endswith('.xml') else b'-- validator fixture\n'
    if relative.endswith('.xml'):
        files[name.rsplit('/', 1)[0] + '/implementation.lua'] = b'-- validator fixture\n'
version = next(line.split(':', 1)[1].strip() for line in pathlib.Path('Chatify.toc').read_text().splitlines() if line.startswith('## Version:'))
with tempfile.TemporaryDirectory() as tmp:
    target = pathlib.Path(tmp) / 'fixture.zip'
    def evaluate(entries):
        with zipfile.ZipFile(target, 'w') as archive:
            for name, data in entries.items():
                archive.writestr(name, data)
        return module.validate(str(target), version)
    assert evaluate(files)['status'] == 'PASS'
    controls = [
        ({key: value for key, value in files.items() if key != 'Chatify/assets/icons/CopyChat.png'}, 'required asset'),
        ({key: value for key, value in files.items() if key != 'Chatify/libs/AceDB-3.0/implementation.lua'}, 'Unresolved'),
        ({**files, 'Chatify/chatify.toc': files['Chatify/Chatify.toc']}, 'case-insensitive'),
        ({**files, 'Chatify/../escape.lua': b''}, 'unsafe'),
        ({**files, 'Chatify/Chatify.toc': files['Chatify/Chatify.toc'].replace(b'## Interface:', b'## BadInterface:')}, 'Interface metadata'),
    ]
    for entries, expected in controls:
        report = evaluate(entries)
        assert report['status'] == 'FAIL' and any(expected in message for message in report['errors']), report['errors']
print('package validator positive fixture and targeted negative controls: PASS')
