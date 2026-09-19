-- 客户端只做一件事：收到 hall_connect / hall_redirect 就 connect。
if not IsClient() then
    return {}
end

local Config = require("hall_config")
local last = ""
local next_ms = 0
local attempts = 0

local function wall_ms()
    if GetSystemTimeMS then
        local ok, ms = pcall(GetSystemTimeMS)
        if ok and type(ms) == "number" then
            return ms
        end
    end
    return (Time and Time() or 0) * 1000
end

local function map_name()
    if not GetMapName then
        return ""
    end
    local ok, name = pcall(GetMapName)
    if not ok or type(name) ~= "string" then
        return ""
    end
    return name:gsub("^maps/", ""):gsub("%.vpk$", ""):gsub("%.bsp$", ""):lower()
end

local function local_pid()
    local p = Entities and Entities.GetLocalPlayer and Entities:GetLocalPlayer()
    if p and p.GetPlayerID then
        local ok, id = pcall(function()
            return tonumber(p:GetPlayerID())
        end)
        if ok and id and id >= 0 then
            return id
        end
    end
    return -1
end

local function connect(e)
    if type(e) ~= "table" then
        return false
    end
    if tonumber(e.enabled) == 0 then
        return false
    end
    local addr = tostring(e.address or "")
    if addr == "" then
        local host, port = tostring(e.host or ""), tonumber(e.port) or 0
        if host ~= "" and port > 0 then
            addr = host .. ":" .. tostring(port)
        end
    end
    if addr == "" or not SendToConsole then
        return false
    end
    local me = local_pid()
    local pid = tonumber(e.player_id)
    if me >= 0 and pid ~= nil and pid >= 0 and pid ~= me then
        return false
    end
    if addr == last and wall_ms() < next_ms then
        return false
    end
    if addr ~= last then
        last = addr
        attempts = 0
    end
    attempts = attempts + 1
    if attempts > 12 then
        return false
    end
    next_ms = wall_ms() + 3000
    local password = tostring(e.password or "")
    local cmd = "connect " .. addr
    if password ~= "" then
        cmd = 'password "' .. password .. '"; ' .. cmd
        if Convars and Convars.SetStr then
            pcall(function()
                Convars:SetStr("password", password)
            end)
        end
    end
    print("[HALL] CLIENT connect " .. addr .. " map=" .. map_name())
    pcall(function()
        SendToConsole(cmd)
    end)
    return true
end

local function entry()
    if map_name() ~= tostring(Config.entryMap or "enter"):lower() then
        return
    end
    if local_pid() < 0 then
        return
    end
    local addr = tostring(Config.loadAddress or "")
    if addr == "" then
        return
    end
    local host, port = addr:match("^(.+):(%d+)$")
    connect({
        player_id = local_pid(),
        host = host,
        port = tonumber(port),
        address = addr,
        password = tostring(Config.loadPassword or ""),
        enabled = 1,
        status = "wait_jump",
    })
end

local bound = false
local function bind()
    if bound then
        return
    end
    bound = true
    if CustomGameEventManager and CustomGameEventManager.RegisterListener then
        pcall(function()
            CustomGameEventManager:RegisterListener("hall_connect", function(_, e)
                connect(e)
            end)
        end)
    end
    if CustomNetTables and CustomNetTables.SubscribeNetTableListener then
        pcall(function()
            CustomNetTables:SubscribeNetTableListener("hall_redirect", function(_, _key, value)
                connect(value)
            end)
        end)
    end
end

local function pump()
    bind()
    if CustomNetTables and CustomNetTables.GetTableValue then
        local pid = local_pid()
        if pid >= 0 then
            local row = CustomNetTables:GetTableValue("hall_redirect", "jump_" .. tostring(pid))
            if type(row) == "table" then
                connect(row)
            end
        end
        local cfg = CustomNetTables:GetTableValue("hall_redirect", "config")
        if type(cfg) == "table" then
            connect(cfg)
        end
    end
    entry()
end

pcall(function()
    ListenToGameEvent("player_connect_full", function()
        pump()
    end, nil)
end)
pcall(function()
    ListenToGameEvent("game_rules_state_change", function()
        pump()
    end, nil)
end)
local mode = nil
pcall(function()
    mode = GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
end)
if mode and mode.SetContextThink then
    mode:SetContextThink("hall_client", function()
        pump()
        return 1
    end, 0.2)
end
pump()
print("[HALL] CLIENT loaded map=" .. map_name())
return { Connect = connect }
