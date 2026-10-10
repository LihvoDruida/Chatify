-- Explicit client fixtures. These describe test inputs, not live certification.
local M = {}
M.order = {
    "retail", "retail-ptr", "retail-12.0", "retail-11", "retail-no-project",
    "era", "hardcore", "sod", "tbc", "wrath", "titan", "cata", "mists",
    "mists-reused-project", "future-era", "future-mists",
    "forever", "forever-generic", "forever-project", "forever-marker",
    "plunderstorm", "minimal-classic", "unknown",
}
-- interface, project, expected identity, TOC, protected, legacy APIs
M.cases = {
    retail = { 120100, 1, "retail", "Chatify.toc", true },
    ["retail-ptr"] = { 120105, 1, "retail", "Chatify.toc", true },
    ["retail-12.0"] = { 120007, 1, "retail", "Chatify.toc", true },
    ["retail-11"] = { 110207, 1, "retail", "Chatify.toc", false, true },
    ["retail-no-project"] = { 110100, false, "retail", "Chatify.toc", false },
    era = { 11509, 2, "vanilla", "Chatify_Vanilla.toc", false },
    hardcore = { 11509, 2, "vanilla", "Chatify_Vanilla.toc", false },
    sod = { 11509, 2, "vanilla", "Chatify_Vanilla.toc", false },
    tbc = { 20506, 5, "tbc", "Chatify_TBC.toc", false },
    wrath = { 30405, 11, "wrath", "Chatify_Wrath.toc", false, true },
    titan = { 38002, 11, "titan", "Chatify_Wrath.toc", false },
    cata = { 40402, 14, "cata", "Chatify_Cata.toc", false, true },
    mists = { 50504, 19, "mists", "Chatify_Mists.toc", false },
    ["mists-reused-project"] = { 50504, 14, "mists", "Chatify_Mists.toc", false },
    ["future-era"] = { 11600, 2, "vanilla", "Chatify_Vanilla.toc", false },
    ["future-mists"] = { 50600, 19, "mists", "Chatify_Mists.toc", false },
    forever = { 16001, 18, "forever", "Chatify_Camelot.toc", true },
    ["forever-generic"] = { 16001, 1, "forever", "Chatify.toc", true },
    ["forever-project"] = { 0, 18, "forever", "Chatify.toc", true },
    ["forever-marker"] = { 0, 1, "forever", "Chatify_Camelot.toc", true },
    plunderstorm = { 120100, 3, "plunderstorm", "Chatify.toc", true },
    ["minimal-classic"] = { 11509, 2, "vanilla", "Chatify.toc", false, true },
    unknown = { 0, 999, "unknown", "Chatify.toc", false, true },
}

function M.install(env, name)
    if name == "classic" then name = "era" end
    local fixture = assert(M.cases[name], "unknown fixture: " .. tostring(name))
    env.install(fixture[5] and "retail" or "classic")
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_CLASSIC = 1, 2
    _G.WOW_PROJECT_WOWLABS, _G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 3, 5
    _G.WOW_PROJECT_WRATH_CLASSIC, _G.WOW_PROJECT_CATACLYSM_CLASSIC = 11, 14
    _G.WOW_PROJECT_CAMELOT, _G.WOW_PROJECT_MISTS_CLASSIC = 18, 19
    _G.WOW_PROJECT_ID = fixture[2] or nil
    _G.GetBuildInfo = function() return "fixture", "test", "fixture", fixture[1] end
    _G.Settings, _G.InterfaceOptions_AddCategory = nil, nil
    _G.C_Secrets = nil
    _G.GetAddOnMetadata = function(_, key) return key == "Version" and "2.18.2" or nil end
    _G.IsAddOnLoaded = function() return false end
    _G.LoadAddOn = function() return true end
    _G.BNSendWhisper = function() end
    if fixture[6] then
        _G.C_AddOns, _G.C_FriendList, _G.C_BattleNet = nil, nil, nil
    else
        _G.C_ChatInfo.SendChatMessage = function() end
        _G.C_BattleNet.SendWhisper = function() end
        _G.SendChatMessage, _G.BNSendWhisper = nil, nil
        _G.C_FriendList.GetFriendInfo = function() return nil end
        _G.C_FriendList.GetFriendInfoByIndex = function() return nil end
        _G.GetAddOnMetadata, _G.IsAddOnLoaded, _G.LoadAddOn = nil, nil, nil
    end
    if name == "minimal-classic" then _G.C_Timer = nil end
    if name == "plunderstorm" then
        _G.C_ChatInfo, _G.C_BattleNet, _G.C_Club = nil, nil, nil
        _G.SendChatMessage, _G.BNSendWhisper, _G.GetChannelList = nil, nil, nil
        _G.ChatFrame_OpenChat, _G.ChatEdit_ParseText = nil, nil
        _G.ChatFrameUtil.OpenChat = nil
    end
    return fixture
end

if arg and arg[0] and arg[0]:match("client_fixtures%.lua$") then
    print(table.concat(M.order, " "))
end
return M
