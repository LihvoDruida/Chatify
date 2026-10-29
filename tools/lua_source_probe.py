"""Adversarial controls for shared audit masking (not Lua syntax validation)."""
from lua_source import mask_lua

text = '''local url = "https://host/--still-string" -- ns.fake()
--[==[ ns.hidden()\n fake = { broken } ]==]
local example = [=[ns.notCode() -- literal]=]
local escaped = "a\\\"--b" -- ns.alsoHidden()
ns.real() --[=[ end ]=]
'''
comments = mask_lua(text)
code = mask_lua(text, strings=True)
assert 'https://host/--still-string' in comments
assert 'a\\"--b' in comments
for masked in (comments, code):
    assert len(masked) == len(text)
    assert [i for i, c in enumerate(masked) if c == '\n'] == [i for i, c in enumerate(text) if c == '\n']
    assert 'ns.fake' not in masked and 'ns.hidden' not in masked and 'ns.alsoHidden' not in masked
assert 'ns.notCode' not in code and 'ns.real()' in code
assert 'ns.notCode' in comments
assert not mask_lua('--[=[unterminated\nbody').strip()
print('Lua audit lexer negative controls: PASS')
