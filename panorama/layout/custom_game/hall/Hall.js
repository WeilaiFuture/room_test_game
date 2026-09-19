function mapName() {
	if (typeof Game === "undefined" || !Game.GetMapInfo) {
		return "";
	}
	var info = Game.GetMapInfo();
	var name = (info && (info.map_display_name || info.map_name)) || "";
	return String(name).replace(/^maps\//, "").replace(/\.vpk$/i, "").toLowerCase();
}

function isWait() {
	return mapName() === "wait" || mapName() === "wait_hall";
}

function sendHall(data) {
	if (typeof GameEvents === "undefined" || !GameEvents.SendCustomGameEventToServer) {
		return;
	}
	GameEvents.SendCustomGameEventToServer("Lua_Hall", data);
}

function HallRefreshMaps() {
	sendHall({ tp: "refresh" });
}

function pickMap(addon, map) {
	sendHall({ tp: "pick", addon: addon, map: map });
	var hint = $("#HallHint");
	if (hint) hint.text = "正在申请 " + map + " …";
}

function renderMaps() {
	var box = $("#HallMaps");
	if (!box || typeof CustomNetTables === "undefined") {
		return;
	}
	box.RemoveAndDeleteChildren();
	for (var i = 1; i <= 32; i++) {
		var row = CustomNetTables.GetTableValue("hall_maps", "map_" + i);
		if (!row || !row.map) {
			continue;
		}
		var btn = $.CreatePanel("Button", box, "hall-map-" + i);
		btn.AddClass("HallMap");
		var title = $.CreatePanel("Label", btn, "");
		title.text = String(row.map);
		var meta = $.CreatePanel("Label", btn, "");
		meta.AddClass("HallMapMeta");
		meta.text = String(row.addon || "") + " · " + String(row.max_players || 10) + " 人";
		btn.SetPanelEvent("onactivate", (function (addon, map) {
			return function () {
				pickMap(addon, map);
			};
		})(String(row.addon || ""), String(row.map)));
	}
}

function showHall() {
	var panel = $("#HallPanel");
	if (!panel) {
		return;
	}
	var wait = isWait();
	panel.SetHasClass("HallHidden", !wait);
	panel.visible = wait;
	panel.hittest = wait;
	if (wait) {
		renderMaps();
	}
}

(function () {
	showHall();
	if (typeof CustomNetTables !== "undefined" && CustomNetTables.SubscribeNetTableListener) {
		CustomNetTables.SubscribeNetTableListener("hall_maps", renderMaps);
		CustomNetTables.SubscribeNetTableListener("hall_redirect", function () {
			var hint = $("#HallHint");
			if (!hint || typeof CustomNetTables.GetTableValue !== "function") {
				return;
			}
			var pid = Game.GetLocalPlayerID ? Game.GetLocalPlayerID() : -1;
			var row = CustomNetTables.GetTableValue("hall_redirect", "jump_" + pid);
			if (row && row.status === "wait") {
				hint.text = "现在没有空闲游戏房，稍后再点。";
			} else if (row && row.address) {
				hint.text = "正在进入 " + row.address;
			}
		});
	}
	if (typeof GameEvents !== "undefined" && GameEvents.Subscribe) {
		GameEvents.Subscribe("game_rules_state_change", showHall);
	}
	$.Schedule(1.0, showHall);
})();
