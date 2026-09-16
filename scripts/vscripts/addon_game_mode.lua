JSON = require("util.dkjson")

if CAddonTemplateGameMode == nil then
    CAddonTemplateGameMode = class({})
end

function Precache(context)
end

function Activate()
    GameRules.AddonTemplate = CAddonTemplateGameMode()
    GameRules.AddonTemplate:InitGameMode()
end

local function map_is(name)
    local mapName = GetMapName() or ""
    return mapName == name or string.find(mapName, name, 1, true) ~= nil
end

function CAddonTemplateGameMode:InitGameMode()
    local mapName = GetMapName() or ""
    print("[room_test] activate map=" .. mapName)

    if map_is("lobby") then
        require("ingame.LobbyMode"):Init()
        return
    end

    if map_is("wait") then
        require("ingame.WaitMode"):Init()
        return
    end

    if map_is("room") then
        require("ingame.RoomMode"):Init()
        return
    end

    print("[room_test] unknown map, fallback to room mode")
    require("ingame.RoomMode"):Init()
end
