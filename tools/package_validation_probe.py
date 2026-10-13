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
