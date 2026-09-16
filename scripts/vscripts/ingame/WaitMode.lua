local Config = require("ingame.LobbyConfig")
local LobbyClient = require("ingame.LobbyClient")

if WaitMode == nil then
    WaitMode = {}
end

local function log(message)
    print("[WAIT] " .. tostring(message))
end

local function set_ui(phase, message)
    if not CustomNetTables or not CustomNetTables.SetTableValue then
        return
    end
    pcall(function()
        CustomNetTables:SetTableValue("lobby_rooms", "ui", {
            phase = tostring(phase or ""),
            message = tostring(message or ""),
            host = tostring(Config.host or ""),
            port = tonumber(Config.port) or 8100,
        })
    end)
end

local function steam64(pid)
    if pid == nil or not PlayerResource or not PlayerResource.GetSteamID then
        return ""
    end
    local ok, sid = pcall(function()
        return tostring(PlayerResource:GetSteamID(pid) or "")
    end)
    if not ok or sid == nil or sid == "0" then
        return ""
    end
    return sid
end

local function player_name(pid)
    if pid == nil or not PlayerResource or not PlayerResource.GetPlayerName then
        return "Player" .. tostring(pid or "?")
    end
    local ok, name = pcall(function()
        return PlayerResource:GetPlayerName(pid)
    end)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return "Player" .. tostring(pid)
end

local function assign_team(pid)
    if pid == nil or pid < 0 or not PlayerResource or not PlayerResource.SetCustomTeamAssignment then
        return
    end
    pcall(function()
        PlayerResource:SetCustomTeamAssignment(pid, DOTA_TEAM_GOODGUYS)
    end)
end

local function wait_server_address()
    local ws = Config.waitServer
    if type(ws) ~= "table" then
        return "", ""
    end
    return tostring(ws.address or ""), tostring(ws.password or "")
end

local function should_jump_to_wait_server()
    local address = wait_server_address()
    if address == "" then
        return false
    end
    if IsDedicatedServer and IsDedicatedServer() then
        return false
    end
    return true
end

local function push_connect(address, password, status)
    local event = {
        enabled = 1,
        stay_local = 0,
        local_lobby = 1,
        allow_host = 1,
        status = status or "allocated",
        address = address or "",
        password = password or "",
        command = "",
    }
    if password ~= "" then
        event.command = 'password "' .. password .. '"; connect ' .. address
    else
        event.command = "connect " .. address
    end
    if CustomNetTables and CustomNetTables.SetTableValue then
        pcall(function()
            CustomNetTables:SetTableValue("clrb_redirect", "config", event)
        end)
    end
    if CustomGameEventManager and CustomGameEventManager.Send_ServerToAllClients then
        CustomGameEventManager:Send_ServerToAllClients("clrb_room_connect", event)
    end
end

function WaitMode:_HideDefaultHud()
    local mode = GameRules:GetGameModeEntity()
    if not mode or not mode.SetHUDVisible then
        return
    end
    for i = 0, 40 do
        pcall(function()
            mode:SetHUDVisible(i, false)
        end)
    end
end

function WaitMode:_ConfigureRules()
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, Config.maxPlayers or 10)
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
    GameRules:SetPostGameTime(0)
    GameRules:SetGoldPerTick(0)
    pcall(function()
        GameRules:SetCreepSpawningEnabled(false)
    end)
    if GameRules.SetCustomGameAllowHeroPickMusic then
        GameRules:SetCustomGameAllowHeroPickMusic(false)
        GameRules:SetCustomGameAllowMusicAtGameStart(false)
        GameRules:SetCustomGameAllowBattleMusic(false)
    end
    local mode = GameRules:GetGameModeEntity()
    if mode then
        mode:SetAnnouncerDisabled(true)
        mode:SetBuybackEnabled(false)
        mode:SetFogOfWarDisabled(true)
        if mode.SetDaynightCycleDisabled then
            mode:SetDaynightCycleDisabled(true)
        end
        if mode.SetKillingSpreeAnnouncerDisabled then
            mode:SetKillingSpreeAnnouncerDisabled(true)
        end
        if mode.SetTopBarTeamValuesVisible then
            mode:SetTopBarTeamValuesVisible(false)
        end
        if mode.SetRecommendedItemsDisabled then
            mode:SetRecommendedItemsDisabled(true)
        end
        if mode.SetStashPurchasingDisabled then
            mode:SetStashPurchasingDisabled(true)
        end
    end
    self:_HideDefaultHud()
end

function WaitMode:_JumpToWaitServer()
    local address, password = wait_server_address()
    log("local wait -> dedicated wait " .. address)
    set_ui("jump_wait", "正在连接听服 " .. address)
    push_connect(address, password, "wait_server")
end

function WaitMode:_CollectPlayers(roomId)
    local players = {}
    local steamIds = {}
    local hostSteamId = ""
    local snap = LobbyClient._snapshot
    local hostUid = nil
    if type(snap) == "table" and type(snap.rooms) == "table" then
        for i = 1, #snap.rooms do
            local room = snap.rooms[i]
            if type(room) == "table" and tonumber(room.id) == tonumber(roomId) then
                hostUid = tostring(room.host or "")
                local pids = room.pids
                if type(pids) == "table" then
                    for j = 1, #pids do
                        local pid = tonumber(pids[j])
                        if pid ~= nil then
                            local sid = steam64(pid)
                            local row = {
                                playerId = pid,
                                steamId = sid,
                                name = player_name(pid),
                            }
                            table.insert(players, row)
                            if sid ~= "" then
                                table.insert(steamIds, sid)
                            end
                            if hostUid ~= "" and tostring(pid) == hostUid then
                                hostSteamId = sid
                            end
                        end
                    end
                end
            end
        end
    end
    if hostSteamId == "" and steamIds[1] then
        hostSteamId = steamIds[1]
    end
    return players, steamIds, hostSteamId
end

function WaitMode:_StartRoom(pid, roomId)
    if self._starting then
        log("start ignored, already starting")
        return
    end
    local players, steamIds, hostSteamId = self:_CollectPlayers(roomId)
    if #steamIds == 0 then
        set_ui("lobby", "开始失败：没有 Steam ID")
        log("start missing steam ids")
        return
    end
    local addonId, mapName, gameMode = "", "", tonumber(Config.gameMode) or 15
    local snap = LobbyClient._snapshot
    if type(snap) == "table" and type(snap.rooms) == "table" then
        for i = 1, #snap.rooms do
            local room = snap.rooms[i]
            if type(room) == "table" and tonumber(room.id) == tonumber(roomId) then
                addonId = tostring(room.addonId or "")
                mapName = tostring(room.map or "")
                gameMode = tonumber(room.gameMode) or gameMode
            end
        end
    end
    self._starting = true
    set_ui("starting", "正在向游戏管理申请房间...")
    local body = {
        requestId = "wait_" .. tostring(pid) .. "_" .. tostring(math.floor(Time() * 1000)) .. "_" .. tostring(RandomInt(1000, 9999)),
        addonId = addonId,
        map = mapName,
        gameMode = gameMode,
        maxPlayers = tonumber(Config.maxPlayers) or 10,
        region = tostring(Config.region or "china"),
        players = players,
        steamIds = steamIds,
        hostSteamId = hostSteamId,
    }
    LobbyClient:Start(roomId, body, function(decoded, status)
        self._starting = false
        if type(decoded) == "table" and decoded.allocated == true then
            set_ui("allocated", "已分配 " .. tostring(decoded.address))
            push_connect(decoded.address, decoded.password, "allocated")
            return
        end
        local reason = "allocation_failed"
        if type(decoded) == "table" then
            reason = tostring(decoded.reason or reason)
        end
        set_ui("lobby", "申请房间失败: " .. reason .. " http=" .. tostring(status))
        log("start failed " .. reason)
    end)
end

function WaitMode:_OnJoin(_, event)
    local pid = event and event.PlayerID
    local room = tonumber(event and event.room)
    if pid == nil or room == nil then
        return
    end
    self._playerRoom[pid] = room
    LobbyClient:Join(room, pid, {
        steamId = steam64(pid),
        name = player_name(pid),
    })
    set_ui("lobby", "加入房间 " .. tostring(room))
end

function WaitMode:_OnLeave(_, event)
    local pid = event and event.PlayerID
    local room = tonumber(event and event.room) or self._playerRoom[pid]
    if pid == nil or room == nil then
        return
    end
    self._playerRoom[pid] = nil
    LobbyClient:Leave(room, pid)
    set_ui("lobby", "已离开房间")
end

function WaitMode:_OnStart(_, event)
    local pid = event and event.PlayerID
    local room = tonumber(event and event.room) or self._playerRoom[pid]
    if pid == nil or room == nil then
        return
    end
    local snap = LobbyClient._snapshot
    if type(snap) == "table" and type(snap.rooms) == "table" then
        for i = 1, #snap.rooms do
            local row = snap.rooms[i]
            if type(row) == "table" and tonumber(row.id) == tonumber(room) then
                if tostring(row.host or "") ~= tostring(pid) then
                    set_ui("lobby", "只有房主可以开始游戏")
                    return
                end
            end
        end
    end
    self:_StartRoom(pid, room)
end

function WaitMode:_BindEvents()
    CustomGameEventManager:RegisterListener("lobby_join", function(...)
        self:_OnJoin(...)
    end)
    CustomGameEventManager:RegisterListener("lobby_leave", function(...)
        self:_OnLeave(...)
    end)
    CustomGameEventManager:RegisterListener("lobby_start", function(...)
        self:_OnStart(...)
    end)
    ListenToGameEvent("player_connect_full", function(keys)
        assign_team(keys.PlayerID)
    end, nil)
    ListenToGameEvent("player_disconnect", function(keys)
        local pid = keys.PlayerID
        if pid == nil then
            return
        end
        self._playerRoom[pid] = nil
        LobbyClient:Disconnect(pid, { steamId = steam64(pid), name = player_name(pid) })
    end, nil)
end

function WaitMode:Init()
    self._playerRoom = {}
    self._starting = false
    self:_ConfigureRules()
    log("wait map dedicated=" .. tostring(IsDedicatedServer and IsDedicatedServer()))
    set_ui("lobby", "正在连接大厅...")
    self:_BindEvents()
    LobbyClient:Init()
    set_ui("lobby", "选择房间前请确认已订阅对应工坊地图")
end

return WaitMode
