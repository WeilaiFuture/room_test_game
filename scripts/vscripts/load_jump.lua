-- load：connect_full 后向中心要 wait，拿到再 connect。没有就重试，不建房。
local Config = require("hall_config")
local Identity = require("identity")
local Json = require("json")

local LoadJump = {
    pending = {},
    attempt = {},
    last = {},
    http = {},
}

local HOP_DELAY = 3
local HOP_REPEAT = 5
local HOP_MAX = 6

local function log(msg)
    print("[HALL] " .. tostring(msg))
end

local function now()
    return Time() or 0
end

local function control_url()
    return tostring(Config.controlUrl or ""):gsub("/+$", "")
end

local function connected(pid)
    if not PlayerResource or not PlayerResource.IsValidPlayerID or not PlayerResource:IsValidPlayerID(pid) then
        return false
    end
    if PlayerResource.IsFakeClient and PlayerResource:IsFakeClient(pid) then
        return false
    end
    if not PlayerResource.GetConnectionState then
        return true
    end
    return PlayerResource:GetConnectionState(pid) == (rawget(_G, "DOTA_CONNECTION_STATE_CONNECTED") or 2)
end

local function player_id_from(keys)
    local pid = tonumber(keys and (keys.PlayerID or keys.player_id))
    if pid and pid >= 0 then
        return math.floor(pid)
    end
    return nil
end

local function emit(pid, event)
    local player = PlayerResource and PlayerResource.GetPlayer and PlayerResource:GetPlayer(pid)
    if not player or not CustomGameEventManager or not CustomGameEventManager.Send_ServerToPlayer then
        return false
    end
    pcall(function()
        CustomGameEventManager:Send_ServerToPlayer(player, "hall_connect", event)
    end)
    if CustomNetTables and CustomNetTables.SetTableValue then
        pcall(function()
            CustomNetTables:SetTableValue("hall_redirect", "jump_" .. tostring(pid), event)
        end)
    end
    return true
end

local function send(pid, data)
    if type(data) ~= "table" then
        return false
    end
    local n = tonumber(LoadJump.attempt[pid]) or 0
    if n >= HOP_MAX then
        return false
    end
    local address = tostring(data.address or "")
    local host = tostring(data.host or "")
    local port = tonumber(data.port) or 0
    if address == "" and host ~= "" and port > 0 then
        address = host .. ":" .. tostring(port)
    end
    if address == "" then
        return false
    end
    local event = {
        player_id = pid,
        host = host,
        port = port,
        address = address,
        password = tostring(data.password or ""),
        enabled = 1,
        status = "allocated",
        mode = "load",
        reason = "TO_LOBBY",
    }
    if emit(pid, event) then
        LoadJump.attempt[pid] = n + 1
        LoadJump.last[pid] = now()
        log("load send pid=" .. tostring(pid) .. " wait=" .. address .. " " .. tostring(LoadJump.attempt[pid]) .. "/" .. tostring(HOP_MAX))
        return true
    end
    return false
end

local function request(pid)
    if not connected(pid) or LoadJump.pending[pid] or LoadJump.http[pid] then
        return
    end
    local url = control_url()
    if url == "" then
        log("load no controlUrl")
        return
    end
    local steam = Identity.PlayerSteam64(pid) or ""
    log("load request pid=" .. tostring(pid) .. " steam=" .. steam)
    local ok = pcall(function()
        local req = CreateHTTPRequestScriptVM("POST", url .. "/v1/jump/wait")
        req:SetHTTPRequestHeaderValue("Content-Type", "application/json")
        req:SetHTTPRequestHeaderValue("Authorization", "Bearer " .. tostring(Config.token or ""))
        req:SetHTTPRequestAbsoluteTimeoutMS(8000)
        local body = { player_id = pid }
        if steam ~= "" then
            body.steam_id = steam
        end
        req:SetHTTPRequestRawPostBody("application/json", Json.Encode(body))
        LoadJump.http[pid] = true
        req:Send(function(result)
            LoadJump.http[pid] = nil
            if not connected(pid) or LoadJump.pending[pid] then
                return
            end
            local data = Json.Decode(tostring(result and result.Body or ""))
            local status = tonumber(result and result.StatusCode) or 0
            if status == 200 and type(data) == "table" and (data.address or data.port) and tostring(data.status or "") ~= "wait" then
                LoadJump.pending[pid] = data
                log("load got wait pid=" .. tostring(pid) .. " " .. tostring(data.address or data.port))
                return
            end
            log("load wait empty pid=" .. tostring(pid) .. " status=" .. tostring(status))
        end)
    end)
    if not ok then
        LoadJump.http[pid] = nil
        log("load http error pid=" .. tostring(pid))
    end
end

function LoadJump.Init()
    LoadJump.pending = {}
    LoadJump.attempt = {}
    LoadJump.last = {}
    LoadJump.http = {}
    ListenToGameEvent("player_connect_full", function(keys)
        local pid = player_id_from(keys)
        if not pid then
            return
        end
        LoadJump.pending[pid] = nil
        LoadJump.attempt[pid] = 0
        LoadJump.last[pid] = now() + HOP_DELAY
        request(pid)
    end, nil)
    ListenToGameEvent("player_disconnect", function(keys)
        local pid = player_id_from(keys)
        if pid then
            LoadJump.pending[pid] = nil
            LoadJump.attempt[pid] = nil
            LoadJump.http[pid] = nil
        end
    end, nil)
    local mode = GameRules and GameRules.GetGameModeEntity and GameRules:GetGameModeEntity()
    if mode and mode.SetContextThink then
        mode:SetContextThink("hall_load_jump", function()
            for pid = 0, 59 do
                if connected(pid) then
                    if not LoadJump.pending[pid] then
                        request(pid)
                    elseif now() >= (LoadJump.last[pid] or 0) then
                        send(pid, LoadJump.pending[pid])
                        LoadJump.last[pid] = now() + HOP_REPEAT
                    end
                end
            end
            return 0.5
        end, 0.5)
    end
    log("load jump " .. control_url())
end

return LoadJump
