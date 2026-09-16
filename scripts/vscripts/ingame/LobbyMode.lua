local Config = require("ingame.LobbyConfig")

if LobbyMode == nil then
    LobbyMode = {}
end

local function log(message)
    print("[LAUNCHER] " .. tostring(message))
end

local function wait_address()
    local ws = Config.waitServer or {}
    return tostring(ws.address or ""), tostring(ws.password or "")
end

function LobbyMode:_HideHud()
    local mode = GameRules:GetGameModeEntity()
    if mode and mode.SetHUDVisible then
        for i = 0, 40 do
            pcall(function()
                mode:SetHUDVisible(i, false)
            end)
        end
    end
end

function LobbyMode:_ConfigureRules()
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 10)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 0)
    GameRules:EnableCustomGameSetupAutoLaunch(false)
    GameRules:SetCustomGameSetupAutoLaunchDelay(99999)
    if GameRules.SetCustomGameSetupTimeout then
        GameRules:SetCustomGameSetupTimeout(-1)
    end
    GameRules:SetHeroSelectionTime(0)
    GameRules:SetStrategyTime(0)
    GameRules:SetShowcaseTime(0)
    GameRules:SetPreGameTime(0)
    self:_HideHud()
end

function LobbyMode:_PublishIdle()
    local address, password = wait_address()
    if CustomNetTables and CustomNetTables.SetTableValue then
        pcall(function()
            CustomNetTables:SetTableValue("clrb_redirect", "config", {
                enabled = 0,
                stay_local = 1,
                address = address,
                password = password,
            })
            CustomNetTables:SetTableValue("lobby_rooms", "ui", {
                phase = "launcher",
                message = "启动器已就绪。点「进入大厅」才会跳到专服 wait。",
                wait_address = address,
                host = tostring(Config.host or ""),
                port = tonumber(Config.port) or 8100,
            })
        end)
    end
end

function LobbyMode:_Jump()
    local address, password = wait_address()
    if address == "" then
        log("waitServer.address is empty")
        return
    end
    local event = {
        enabled = 1,
        stay_local = 0,
        local_lobby = 1,
        allow_host = 1,
        status = "wait_server",
        address = address,
        password = password,
        command = password ~= "" and ('password "' .. password .. '"; connect ' .. address) or ("connect " .. address),
    }
    if CustomNetTables and CustomNetTables.SetTableValue then
        pcall(function()
            CustomNetTables:SetTableValue("clrb_redirect", "config", event)
            CustomNetTables:SetTableValue("lobby_rooms", "ui", {
                phase = "launcher",
                message = "正在连接 " .. address,
                wait_address = address,
                host = tostring(Config.host or ""),
                port = tonumber(Config.port) or 8100,
            })
        end)
    end
    if CustomGameEventManager and CustomGameEventManager.Send_ServerToAllClients then
        CustomGameEventManager:Send_ServerToAllClients("clrb_room_connect", event)
    end
    log("connect wait " .. address)
end

function LobbyMode:Init()
    self:_ConfigureRules()
    self:_PublishIdle()
    CustomGameEventManager:RegisterListener("lobby_enter_wait", function()
        self:_Jump()
    end)
end

return LobbyMode
