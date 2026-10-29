"""Small Lua lexer for audits; preserve offsets and line numbers while masking.

Handles quoted escapes and arbitrary [=[...]=] delimiters. This is not a parser;
syntax validity remains the responsibility of both luac versions.
"""
import re

LONG = re.compile(r'\[(=*)\[')


def mask_lua(text, *, strings=False):
    out = list(text)
    index = 0
    while index < len(text):
        start = index
        comment = text.startswith('--', index)
        if comment:
            index += 2
        long = LONG.match(text, index)
        if long:
            closing = ']' + long.group(1) + ']'
            end = text.find(closing, long.end())
            index = len(text) if end < 0 else end + len(closing)
        elif comment:
            end = text.find('\n', index)
            index = len(text) if end < 0 else end
        elif text[index] in ('"', "'"):
            quote = text[index]
            index += 1
            while index < len(text):
                if text[index] == '\\':
                    index += 2
                elif text[index] == quote:
                    index += 1
                    break
                else:
                    index += 1
        else:
            index += 1
            continue
        if comment or strings:
            for pos in range(start, min(index, len(text))):
                if out[pos] not in '\r\n':
                    out[pos] = ' '
    return ''.join(out)
