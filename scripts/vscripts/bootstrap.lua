local Config = require("hall_config")
local Hold = require("hold")

if HallBootstrap == nil then
    HallBootstrap = class({})
end

local function map_name()
    if not GetMapName then
        return ""
    end
    local ok, name = pcall(GetMapName)
    if not ok or type(name) ~= "string" then
        return ""
    end
    return name:gsub("^maps/", ""):gsub("%.vpk$", ""):gsub("%.bsp$", ""):gsub("%.vmap_c$", ""):gsub("%.vmap$", "")
end

local function parse_address(text)
    local host, port = tostring(text or ""):match("^(.+):(%d+)$")
    return tostring(host or ""), tonumber(port) or 0
end

local function in_setup()
    local setup = rawget(_G, "DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP")
    local state = GameRules and GameRules.State_Get and GameRules:State_Get() or nil
    return setup ~= nil and state == setup
end

local function player_id_from(keys)
    keys = keys or {}
    local pid = tonumber(keys.PlayerID or keys.player_id)
    if pid and pid >= 0 then
        return math.floor(pid)
    end
    return nil
end

function HallBootstrap:_SendEntry(pid)
    pid = tonumber(pid)
    if pid == nil or pid < 0 or not PlayerResource then
        return
    end
    local player = PlayerResource.GetPlayer and PlayerResource:GetPlayer(pid)
    if not player then
        return
    end
    self._entryAt = self._entryAt or {}
    local now = Time() or 0
    if now < (self._entryAt[pid] or 0) then
        return
    end
    self._entryAt[pid] = now + 3
    local host, port = parse_address(Config.loadAddress)
    local event = {
        player_id = pid,
        host = host,
        port = port,
        address = tostring(Config.loadAddress or ""),
        password = tostring(Config.loadPassword or ""),
        enabled = 1,
        status = "wait_jump",
        mode = "entry",
    }
    print("[HALL] enter send load=" .. tostring(event.address))
    if CustomGameEventManager and CustomGameEventManager.Send_ServerToPlayer then
        pcall(function()
            CustomGameEventManager:Send_ServerToPlayer(player, "hall_connect", event)
        end)
    end
end

function HallBootstrap:_SendEntryAll()
    if not PlayerResource then
        return
    end
    local connected = rawget(_G, "DOTA_CONNECTION_STATE_CONNECTED") or 2
    for pid = 0, 59 do
        local ok, yes = pcall(function()
            if not PlayerResource:IsValidPlayerID(pid) then
                return false
            end
            if PlayerResource.IsFakeClient and PlayerResource:IsFakeClient(pid) then
                return false
            end
            if not PlayerResource.GetConnectionState then
                return true
            end
            return PlayerResource:GetConnectionState(pid) == connected
        end)
        if ok and yes then
            self:_SendEntry(pid)
        end
    end
end

function HallBootstrap:_PublishEntry()
    local host, port = parse_address(Config.loadAddress)
    local event = {
        mode = "entry",
        status = "wait_jump",
        enabled = 1,
        address = tostring(Config.loadAddress or ""),
        password = tostring(Config.loadPassword or ""),
        host = host,
        port = port,
    }
    if CustomNetTables and CustomNetTables.SetTableValue then
        pcall(function()
            CustomNetTables:SetTableValue("hall_redirect", "config", event)
        end)
    end
    print("[HALL] enter -> load " .. tostring(event.address))
end

function HallBootstrap:Activate()
    Hold.Apply()
    local mode = GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
    if mode then
        pcall(function()
            mode:SetAnnouncerDisabled(true)
            mode:SetDaynightCycleDisabled(true)
            mode:SetBuybackEnabled(false)
        end)
    end
    ListenToGameEvent("game_rules_state_change", function()
        Hold.Apply()
        if not in_setup() then
            Hold.Force("state_change")
        end
    end, nil)
    ListenToGameEvent("player_connect", function()
        Hold.Apply()
    end, nil)
    ListenToGameEvent("player_connect_full", function(keys)
        Hold.Apply()
        if map_name() == Config.entryMap then
            self:_SendEntry(player_id_from(keys))
        end
    end, nil)
    ListenToGameEvent("player_disconnect", function()
        Hold.Apply()
    end, nil)
    if mode and mode.SetContextThink then
        mode:SetContextThink("hall_hold", function()
            Hold.Apply()
            if not in_setup() then
                Hold.Force("think")
            end
            if map_name() == Config.entryMap then
                self:_SendEntryAll()
            end
            return 1
        end, 0.2)
    end
    local map = map_name()
    print("[HALL] bootstrap map=" .. map)
    if map == Config.waitMap then
        Hold.Force("wait_boot")
        require("wait_hall").Init()
        return self
    end
    if map == Config.loadMap then
        Hold.Force("load_boot")
        require("load_jump").Init()
        return self
    end
    self:_PublishEntry()
    return self
end

return HallBootstrap
