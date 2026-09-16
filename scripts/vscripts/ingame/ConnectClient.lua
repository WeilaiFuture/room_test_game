-- 收到服务器的 connect 指令后，执行 password; connect。
-- 本地 wait -> 专服 wait，以及 wait 分配到 room 专服，都走这里。

print("[room_test] connect client loaded")

local pending = nil
local attempts = 0
local ticks_since = 999
local MAX_ATTEMPTS = 8
local RETRY_TICKS = 32
local attached = {}

local function flag_on(value)
    return value == true or value == 1 or value == "1" or value == "true" or tonumber(value) == 1
end

local function valid_address(value)
    if value ~= nil and type(value) ~= "string" then
        value = tostring(value)
    end
    if type(value) ~= "string" or #value < 3 or #value > 255 then
        return nil
    end
    local host, port_text = value:match("^(.+):(%d+)$")
    local port = tonumber(port_text)
    if not host or not port or port < 1 or port > 65535 then
        return nil
    end
    return value
end

local function merge_pending(event)
    local net = nil
    if CustomNetTables and CustomNetTables.GetTableValue then
        local ok, config = pcall(function()
            return CustomNetTables:GetTableValue("clrb_redirect", "config")
        end)
        if ok and type(config) == "table" then
            net = config
        end
    end
    if type(event) ~= "table" and not net then
        return pending
    end
    local merged = {}
    if type(pending) == "table" then
        for k, v in pairs(pending) do
            merged[k] = v
        end
    end
    if net then
        for k, v in pairs(net) do
            merged[k] = v
        end
    end
    if type(event) == "table" then
        for k, v in pairs(event) do
            if v ~= nil and v ~= "" then
                merged[k] = v
            end
        end
    end
    return merged
end

local function setup_ready()
    if not GameRules or not GameRules.State_Get then
        return false
    end
    local ok, state = pcall(function()
        return GameRules:State_Get()
    end)
    if not ok or state == nil then
        return false
    end
    local setup = rawget(_G, "DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP") or 2
    local wait_load = rawget(_G, "DOTA_GAMERULES_STATE_WAIT_FOR_PLAYERS_TO_LOAD")
    if wait_load ~= nil and state == wait_load then
        return false
    end
    return state >= setup
end

local function try_connect()
    if not SendToConsole then
        return
    end
    if attempts >= MAX_ATTEMPTS then
        return
    end
    if attempts > 0 and ticks_since < RETRY_TICKS then
        return
    end
    if not setup_ready() then
        return
    end

    local config = merge_pending(nil)
    if type(config) ~= "table" then
        return
    end
    if not flag_on(config.enabled) or flag_on(config.stay_local) then
        return
    end

    local address = valid_address(config.address)
    if not address then
        print("[room_test] skip connect bad address=" .. tostring(config.address))
        return
    end

    local password = tostring(config.password or "")
    attempts = attempts + 1
    ticks_since = 0
    print("[room_test] connect " .. address .. " attempt=" .. tostring(attempts))
    if password ~= "" then
        if Convars and Convars.SetStr then
            pcall(function()
                Convars:SetStr("password", password)
            end)
        end
        SendToConsole('password "' .. password .. '"; connect ' .. address)
    else
        SendToConsole("connect " .. address)
    end
end

local function tick()
    ticks_since = ticks_since + 1
    pcall(try_connect)
    if attempts >= MAX_ATTEMPTS then
        return nil
    end
    return 0.25
end

local function bind_think(entity, label)
    if not entity or attached[label] then
        return
    end
    if entity.SetContextThink then
        local ok = pcall(function()
            entity:SetContextThink("RoomTestConnect", tick, 0.25)
        end)
        if ok then
            attached[label] = true
        end
    end
end

local function start_poll()
    if GameRules and GameRules.GetGameModeEntity then
        pcall(function()
            bind_think(GameRules:GetGameModeEntity(), "mode")
        end)
    end
    if Entities and Entities.GetLocalPlayer then
        bind_think(Entities:GetLocalPlayer(), "player")
    end
end

local function on_event(_, event)
    if type(event) == "table" then
        pending = merge_pending(event)
    end
    start_poll()
    pcall(try_connect)
end

if CustomGameEventManager and CustomGameEventManager.RegisterListener then
    CustomGameEventManager:RegisterListener("clrb_room_connect", on_event)
end
if CustomNetTables and CustomNetTables.SubscribeNetTableListener then
    pcall(function()
        CustomNetTables:SubscribeNetTableListener("clrb_redirect", function()
            pending = merge_pending(nil)
            start_poll()
            pcall(try_connect)
        end)
    end)
end

ListenToGameEvent("game_rules_state_change", function()
    start_poll()
    pcall(try_connect)
end, nil)

print("[room_test] connect client ready")
