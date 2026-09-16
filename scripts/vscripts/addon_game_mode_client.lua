-- 客户端独立 VM，不会跑 addon_game_mode.lua。
print("[room_test] client activate map=" .. tostring(GetMapName()))
require("ingame.ConnectClient")
