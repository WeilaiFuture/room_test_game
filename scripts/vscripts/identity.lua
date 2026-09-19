local Identity = {}
local STEAM_ID64_BASE = "76561197960265728"

local function add_decimal(left, right)
    local i, j, carry, out = #left, #right, 0, {}
    while i > 0 or j > 0 or carry > 0 do
        local a = i > 0 and string.byte(left, i) - 48 or 0
        local b = j > 0 and string.byte(right, j) - 48 or 0
        local sum = a + b + carry
        table.insert(out, 1, tostring(sum % 10))
        carry, i, j = math.floor(sum / 10), i - 1, j - 1
    end
    return table.concat(out)
end

function Identity.PlayerSteam64(player_id)
    if type(player_id) ~= "number" or player_id < 0 or not PlayerResource then
        return nil
    end
    if PlayerResource.IsValidPlayerID and not PlayerResource:IsValidPlayerID(player_id) then
        return nil
    end
    if PlayerResource.IsFakeClient and PlayerResource:IsFakeClient(player_id) then
        return nil
    end
    local account_id = PlayerResource.GetSteamAccountID
        and tonumber(PlayerResource:GetSteamAccountID(player_id)) or 0
    if account_id > 0 and account_id == math.floor(account_id) then
        return add_decimal(STEAM_ID64_BASE, string.format("%.0f", account_id))
    end
    return nil
end

return Identity
