"""The legacy API audit must distinguish modern calls, strings and real aliases."""
import tempfile
from pathlib import Path
import audit

with tempfile.TemporaryDirectory() as temp:
    sample = Path(temp) / 'Feature.lua'
    audit.LUA = [sample]
    sample.write_text('C_ChatInfo.SendChatMessage("hello")\nlocal text = "SendChatMessage"\n-- BNSendWhisper()\n')
    assert not audit.check_legacy_api_isolation()
    sample.write_text('pcall(SendChatMessage, "hello")\n')
    assert len(audit.check_legacy_api_isolation()) == 1
    sample.write_text('local send = _G.BNSendWhisper\n')
    assert len(audit.check_legacy_api_isolation()) == 1
print('Legacy API audit negative controls: PASS')
