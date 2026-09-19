-- Small strict JSON codec; no dependency on an optional engine-global `json`.
local J = {}
local function quote(s)
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
        return ({['"']='\\"', ['\\']='\\\\', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'})[c]
            or string.format("\\u%04x", c:byte())
    end) .. '"'
end
local function encode(v, stack)
    if v == nil then return "null" end
    if type(v) == "string" then return quote(v) end
    if type(v) == "boolean" then return tostring(v) end
    if type(v) == "number" then
        assert(v == v and math.abs(v) < math.huge, "invalid number")
        return tostring(v)
    end
    assert(type(v) == "table" and not stack[v], "invalid JSON value")
    stack[v] = true
    local n, max, array, out = 0, 0, true, {}
    for k in pairs(v) do
        n = n + 1
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then array = false
        else max = math.max(max, k) end
    end
    array = array and n == max
    if array then for i = 1, n do out[#out+1] = encode(v[i], stack) end
    else for k, x in pairs(v) do
        assert(type(k) == "string", "JSON object key")
        out[#out+1] = quote(k) .. ":" .. encode(x, stack)
    end end
    stack[v] = nil
    return (array and "[" or "{") .. table.concat(out, ",") .. (array and "]" or "}")
end
function J.Encode(v) return encode(v, {}) end
local function utf8(n)
    if n < 128 then return string.char(n) end
    if n < 2048 then return string.char(192+math.floor(n/64),128+n%64) end
    if n < 65536 then return string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64) end
    return string.char(240+math.floor(n/262144),128+math.floor(n/4096)%64,128+math.floor(n/64)%64,128+n%64)
end
function J.Decode(s)
    local function parse()
        local i, depth = 1, 0
        local value
        local function ws() i = s:find("[^ \r\n\t]", i) or (#s+1) end
        local function hex()
            local h = s:sub(i,i+3); assert(h:match("^%x%x%x%x$")); i=i+4; return tonumber(h,16)
        end
        local function str()
            assert(s:sub(i,i)=='"'); i=i+1
            local out = {}
            while i <= #s do
                local c=s:sub(i,i); i=i+1
                if c=='"' then return table.concat(out) end
                assert(c:byte() >= 32)
                if c=='\\' then
                    c=s:sub(i,i); i=i+1
                    if c=='u' then
                        local n=hex()
                        if n>=55296 and n<=56319 then
                            assert(s:sub(i,i+1)=='\\u'); i=i+2
                            local lo=hex(); assert(lo>=56320 and lo<=57343)
                            n=65536+(n-55296)*1024+lo-56320
                        else assert(n<56320 or n>57343) end
                        c=utf8(n)
                    else c=({['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'})[c]; assert(c) end
                end
                out[#out+1]=c
            end
            error("unterminated JSON string")
        end
        value=function()
            ws(); depth=depth+1; assert(depth<=64)
            local c=s:sub(i,i); local v
            if c=='"' then v=str()
            elseif c=='{' or c=='[' then
                i=i+1; v={}; ws()
                local close=c=='{' and '}' or ']'; local index=1
                if s:sub(i,i)~=close then
                    while true do
                        local k=index
                        if c=='{' then ws(); k=str(); ws(); assert(s:sub(i,i)==':'); i=i+1 end
                        v[k]=value(); index=index+1; ws()
                        if s:sub(i,i)==close then break end
                        assert(s:sub(i,i)==','); i=i+1
                    end
                end
                i=i+1
            elseif s:sub(i,i+3)=='true' then v=true; i=i+4
            elseif s:sub(i,i+4)=='false' then v=false; i=i+5
            elseif s:sub(i,i+3)=='null' then v=nil; i=i+4
            else
                local start=i
                if c=='-' then i=i+1 end
                if s:sub(i,i)=='0' then i=i+1
                else assert(s:sub(i,i):match('[1-9]')); repeat i=i+1 until not s:sub(i,i):match('%d') end
                if s:sub(i,i)=='.' then i=i+1; assert(s:sub(i,i):match('%d')); repeat i=i+1 until not s:sub(i,i):match('%d') end
                if s:sub(i,i):match('[eE]') then
                    i=i+1; if s:sub(i,i):match('[+-]') then i=i+1 end
                    assert(s:sub(i,i):match('%d')); repeat i=i+1 until not s:sub(i,i):match('%d')
                end
                v=tonumber(s:sub(start,i-1)); assert(v and math.abs(v)<math.huge)
            end
            depth=depth-1; return v
        end
        local result=value(); ws(); assert(i>#s); return result
    end
    if type(s)~='string' then return nil end
    local ok, v=pcall(parse); if ok then return v end
    return nil
end
return J
