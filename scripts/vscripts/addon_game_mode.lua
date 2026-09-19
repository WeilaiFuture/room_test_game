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

function Precache(_context)
end

function Activate()
    local map = map_name()
    print("[HALL] Activate map=" .. map)
    require("bootstrap"):Activate()
end
