-- 听服大厅客户端：hello / 加入 / 离开 / 开始游戏。
-- 用户状态一变，大厅会回整份快照；这里再广播给所有玩家。
-- 用法：local LobbyClient = require("ingame.LobbyClient")
--       LobbyClient:Init()

local Config = require("ingame.LobbyConfig")

if LobbyClient == nil then
    _G.LobbyClient = {}
end

local function create_http(method, url)
    local req = nil
    if CreateHTTPRequestScriptVM then
        local ok, got = pcall(CreateHTTPRequestScriptVM, method, url)
        if ok then req = got end
    end
    if not req and CreateHTTPRequest then
        local ok, got = pcall(CreateHTTPRequest, method, url)
        if ok then req = got end
    end
    return req
end

local function log(message)
    print("[LOBBY] " .. tostring(message))
end

local function json_encode(tab)
    if JSON and JSON.encode then
        return JSON.encode(tab)
    end
    return nil
end

local function json_decode(raw)
    if type(raw) ~= "string" or raw == "" or not JSON or not JSON.decode then
        return nil
    end
    local ok, tab = pcall(JSON.decode, raw)
    if ok then return tab end
    return nil
end

local function base_url()
    local host = tostring(Config.host or "127.0.0.1")
    local port = tonumber(Config.port) or 8100
    return "http://" .. host .. ":" .. tostring(port)
end

local function apply_key(req)
    if not req or not req.SetHTTPRequestHeaderValue then return end
    pcall(function()
        req:SetHTTPRequestHeaderValue("X-Map-Key", tostring(Config.mapKey or ""))
    end)
end

function LobbyClient:_Broadcast(snap)
    if type(snap) ~= "table" then
        return
    end
    local payload = json_encode(snap) or ""
    if CustomNetTables and CustomNetTables.SetTableValue then
        pcall(function()
            CustomNetTables:SetTableValue("lobby_rooms", "meta", {
                revision = tonumber(snap.revision) or 0,
                room_count = tonumber(snap.roomCount) or 0,
            })
        end)
        local rooms = snap.rooms
        if type(rooms) == "table" then
            for i = 1, #rooms do
                local room = rooms[i]
                if type(room) == "table" then
                    local names = {}
                    local pids = room.pids
                    if type(room.names) == "table" then
                        names = room.names
                    elseif type(pids) == "table" then
                        for j = 1, #pids do
                            local pid = tonumber(pids[j])
                            local name = "Player" .. tostring(pid or "?")
                            if pid ~= nil and PlayerResource and PlayerResource.GetPlayerName then
                                local ok, got = pcall(function()
                                    return PlayerResource:GetPlayerName(pid)
                                end)
                                if ok and type(got) == "string" and got ~= "" then
                                    name = got
                                end
                            end
                            names[j] = name
                        end
                    end
                    pcall(function()
                        CustomNetTables:SetTableValue("lobby_rooms", "room_" .. tostring(room.id), {
                            id = tonumber(room.id) or 0,
                            host = tostring(room.host or "0"),
                            status = tostring(room.status or ""),
                            count = tonumber(room.count) or (type(pids) == "table" and #pids or 0),
                            max_players = tonumber(room.maxPlayers) or 10,
                            pids = json_encode(pids) or "",
                            names = json_encode(names) or "",
                            game_id = tostring(room.gameId or ""),
                            game_name = tostring(room.gameName or ""),
                            workshop_id = tostring(room.workshopId or ""),
                            addon_id = tostring(room.addonId or ""),
                            map = tostring(room.map or ""),
                            cover = tostring(room.cover or ""),
                        })
                    end)
                end
            end
        end
    end
    if CustomGameEventManager and CustomGameEventManager.Send_ServerToAllClients then
        pcall(function()
            CustomGameEventManager:Send_ServerToAllClients("lobby_sync", {
                revision = tonumber(snap.revision) or 0,
                room_count = tonumber(snap.roomCount) or 0,
                payload = payload,
            })
        end)
    end
end

function LobbyClient:_ApplySync(snap, source)
    if type(snap) ~= "table" then
        return
    end
    if snap.snapshot and type(snap.snapshot) == "table" then
        snap = snap.snapshot
    end
    local revision = tonumber(snap.revision) or 0
    if self._revision and revision > 0 and revision < self._revision then
        return
    end
    self._revision = math.max(tonumber(self._revision) or 0, revision)
    self._snapshot = snap
    log((source or "sync") .. " revision=" .. tostring(self._revision) .. " rooms=" .. tostring(snap.roomCount))
    self:_Broadcast(snap)
end

function LobbyClient:_Send(path, body, content_type, timeout, cb)
    local url = base_url() .. path
    local req = create_http("POST", url)
    if not req then
        log("http unavailable " .. url)
        return
    end
    apply_key(req)
    if req.SetHTTPRequestHeaderValue then
        pcall(function()
            req:SetHTTPRequestHeaderValue("Content-Type", content_type or "application/json")
            req:SetHTTPRequestHeaderValue("Accept", "application/json")
        end)
    end
    if type(body) == "string" then
        req:SetHTTPRequestRawPostBody(content_type or "text/plain", body)
    end
    req:SetHTTPRequestAbsoluteTimeoutMS(math.floor((timeout or 15) * 1000))
    req:Send(function(keys)
        local raw = keys and keys.Body
        local status = keys and keys.StatusCode
        local decoded = json_decode(raw)
        if decoded then
            self:_ApplySync(decoded, path)
        end
        if cb then cb(decoded or raw, status) end
    end)
end

function LobbyClient:_WatchOnce()
    local url = base_url() .. "/api/v1/map/watch?since=" .. tostring(self._revision or 0) .. "&timeout=25000"
    local req = create_http("GET", url)
    if not req then
        log("watch unavailable")
        self:_ScheduleWatch(3)
        return
    end
    apply_key(req)
    if req.SetHTTPRequestHeaderValue then
        pcall(function()
            req:SetHTTPRequestHeaderValue("Accept", "application/json")
        end)
    end
    req:SetHTTPRequestAbsoluteTimeoutMS(28000)
    req:Send(function(keys)
        local decoded = json_decode(keys and keys.Body)
        if decoded then
            self:_ApplySync(decoded, "watch")
        end
        self:_ScheduleWatch(0.05)
    end)
end

function LobbyClient:_ScheduleWatch(delay)
    delay = tonumber(delay) or 0.05
    local thinker = self._watchThinker
    if not thinker or thinker:IsNull() then
        if SpawnEntityFromTableSynchronous then
            thinker = SpawnEntityFromTableSynchronous("info_target", { targetname = "lobby_watch_thinker" })
            self._watchThinker = thinker
        end
    end
    if thinker and thinker.SetContextThink then
        thinker:SetContextThink("lobby_watch", function()
            self:_WatchOnce()
            return nil
        end, delay)
        return
    end
    self:_WatchOnce()
end

function LobbyClient:Hello(cb)
    self:_Send("/api/v1/map/hello", json_encode({ type = "hello" }) or "{}", "application/json", 15, cb)
end

function LobbyClient:Join(room, uid, extra, cb)
    extra = extra or {}
    local body = {
        op = 1,
        room = tonumber(room),
        uid = tostring(uid),
        steamId = extra.steamId,
        name = extra.name,
    }
    self:_Send("/api/v1/map/join", json_encode(body) or ("1," .. tostring(room) .. "," .. tostring(uid)), extra.steamId and "application/json" or "text/plain", 15, cb)
end

function LobbyClient:Leave(room, uid, cb)
    local line = "2," .. tostring(room) .. "," .. tostring(uid)
    self:_Send("/api/v1/map/leave", line, "text/plain", 15, cb)
end

function LobbyClient:Disconnect(uid, extra, cb)
    extra = extra or {}
    local body = {
        uid = tostring(uid or ""),
        steamId = extra.steamId,
        name = extra.name,
    }
    self:_Send("/api/v1/map/disconnect", json_encode(body) or "{}", "application/json", 15, cb)
end

function LobbyClient:Start(room, clrb_body, cb)
    local body = clrb_body or {}
    body.lobbyRoom = tonumber(room)
    body.room = tonumber(room)
    self:_Send("/api/v1/map/start", json_encode(body) or "{}", "application/json", Config.startTimeoutSeconds or 60, function(decoded, status)
        if type(decoded) == "table" and decoded.allocated == true then
            self:_TellPlayersConnect(decoded)
        end
        if cb then cb(decoded, status) end
    end)
end

function LobbyClient:_TellPlayersConnect(result)
    if not CustomGameEventManager or not CustomGameEventManager.Send_ServerToPlayer then
        return
    end
    local event = {
        enabled = 1,
        stay_local = 0,
        local_lobby = 1,
        allow_host = 1,
        status = "allocated",
        address = result.address or "",
        password = result.password or "",
        command = result.command or "",
        lobby_room = result.lobbyRoom or 0,
        host_player_id = tonumber(result.host) or -1,
    }
    local pids = result.pids
    if type(pids) ~= "table" then
        CustomGameEventManager:Send_ServerToAllClients("clrb_room_connect", event)
        return
    end
    for i = 1, #pids do
        local pid = tonumber(pids[i])
        if pid ~= nil and PlayerResource and PlayerResource.GetPlayer then
            local player = PlayerResource:GetPlayer(pid)
            if player then
                CustomGameEventManager:Send_ServerToPlayer(player, "clrb_room_connect", event)
            end
        end
    end
end

function LobbyClient:Init()
    self._revision = 0
    self:Hello(function()
        self:_ScheduleWatch(0.05)
    end)
end

return LobbyClient
