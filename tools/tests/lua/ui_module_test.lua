-- Offline tests for gamedata/scripts/soc_sleeping_bag_ui.script.
-- Usage: lua5.1 tools/tests/lua/ui_module_test.lua <repo root>
-- tools/tests/ui_test.ps1 runs this automatically.

local root = arg[1] or "."
local passed, failed = 0, 0

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. name .. ": " .. tostring(err))
	end
end

local function eq(actual, expected, what)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
	end
end

local MODULE_PATH = root .. "/gamedata/scripts/soc_sleeping_bag_ui.script"

-- Builds a sandbox environment whose globals stand in for the engine UI
-- stack: the SoC class system, CUIScriptWnd, CScriptXmlInit, ui_events,
-- DIK_keys, level, db, get_hud, game, news_manager, and printf.
local function new_env()
	local env = setmetatable({}, { __index = _G })
	env.mock = {
		registered = {},
		callbacks = {},
		xml_inits = {},
		menu_toggles = {},
		tips = {},
		logs = {},
	}
	local mock = env.mock

	-- The engine's class system registers the global class table itself and
	-- wires super(...) inside __init to the base constructor.
	env.class = function(name)
		return function(base)
			local cls = { __classname = name }
			setmetatable(cls, {
				__call = function(_, ...)
					local inst = {}
					setmetatable(inst, {
						__index = function(_, key)
							local value = cls[key]
							if value == nil and type(base) == "table" then
								value = base[key]
							end
							return value
						end,
					})
					local previous_super = env.super
					env.super = function(...)
						if type(base) == "table" and base.__init ~= nil then
							base.__init(inst, ...)
						end
					end
					cls.__init(inst, ...)
					env.super = previous_super
					return inst
				end,
			})
			env[name] = cls
			return cls
		end
	end

	env.ui_events = {
		BUTTON_CLICKED = "BUTTON_CLICKED",
		WINDOW_KEY_PRESSED = "WINDOW_KEY_PRESSED",
	}
	env.DIK_keys = { DIK_ESCAPE = 1, DIK_UP = 200, DIK_DOWN = 208 }

	env.hud_holder = {
		start_stop_menu = function(_, dialog, flag)
			table.insert(mock.menu_toggles, { dialog = dialog, flag = flag })
		end,
	}
	env.CUIScriptWnd = {
		Init = function(self, x, y, width, height)
			mock.dialog_rect = { x = x, y = y, width = width, height = height }
		end,
		Register = function(self, ctrl, name)
			mock.registered[name] = ctrl
			return ctrl
		end,
		AddCallback = function(self, name, event, fn, owner)
			mock.callbacks[name] = { event = event, fn = fn, owner = owner }
		end,
		OnKeyboard = function(self, dik, action) end,
		GetHolder = function(self) return env.hud_holder end,
	}

	env.CScriptXmlInit = function()
		local xml = {}
		function xml:ParseFile(name)
			env.mock.parsed_file = name
		end
		function xml:InitStatic(id, owner)
			table.insert(mock.xml_inits, { kind = "static", id = id })
			return { id = id }
		end
		function xml:Init3tButton(id, owner)
			table.insert(mock.xml_inits, { kind = "button", id = id })
			return { id = id }
		end
		return xml
	end

	env.level = {
		start_stop_menu = function(dialog, flag)
			table.insert(mock.menu_toggles, { dialog = dialog, flag = flag })
		end,
	}
	env.get_hud = function() return "hud" end
	env.db = { actor = { health = 1.0 } }
	-- The UI imports only the pure bounded calculation, never gameplay state.
	env.soc_sleeping_bag = {
		healing_hours = function(health)
			return math.max(1, math.min(9, math.ceil((1 - health) * 9)))
		end,
	}
	env.game = {
		translate_string = function(id)
			return "T:" .. tostring(id)
		end,
	}
	env.news_manager = {
		send_tip = function(actor, text)
			table.insert(mock.tips, text)
		end,
	}
	env.printf = function(fmt, ...)
		table.insert(mock.logs, string.format(fmt, ...))
	end

	return env
end

local function load_module(env)
	local chunk = assert(loadfile(MODULE_PATH), "module file not found: " .. MODULE_PATH)
	setfenv(chunk, env)
	chunk()
	return env
end

local function click(env, button_id)
	local callback = env.mock.callbacks[button_id]
	assert(callback ~= nil, "no callback registered for " .. tostring(button_id))
	callback.fn(callback.owner)
end

test("show: parses the owned layout and registers each button once", function()
	local env = load_module(new_env())
	eq(env.show(function() end), true)
	eq(env.mock.parsed_file, "ui_soc_sleeping_bag.xml", "layout file")
	eq(env.mock.dialog_rect.x, 362, "centered x")
	eq(env.mock.dialog_rect.y, 234, "centered y")
	local buttons = 0
	for _, init in ipairs(env.mock.xml_inits) do
		if init.kind == "button" then
			buttons = buttons + 1
		end
	end
	eq(buttons, 5, "3t buttons")
	for _, id in ipairs({ "btn_sleep_1", "btn_sleep_3", "btn_sleep_9", "btn_sleep_heal", "btn_cancel" }) do
		eq(env.mock.registered[id] ~= nil, true, "registered " .. id)
		eq(env.mock.callbacks[id] ~= nil, true, "callback " .. id)
		eq(env.mock.callbacks[id].event, "BUTTON_CLICKED", "event for " .. id)
	end
	eq(env.is_open(), true, "menu open")
	eq(#env.mock.menu_toggles, 1, "one show toggle")
end)

test("show: refuses to open twice", function()
	local env = load_module(new_env())
	eq(env.show(function() end), true)
	eq(env.show(function() end), false)
	eq(#env.mock.menu_toggles, 1, "still one toggle")
end)

test("fixed choices: map 1, 3, and 9 hours exactly once each", function()
	local env = load_module(new_env())
	local received = {}
	env.show(function(hours, heal)
		table.insert(received, { hours = hours, heal = heal })
	end)
	click(env, "btn_sleep_1")
	click(env, "btn_sleep_3")
	click(env, "btn_sleep_9")
	eq(#received, 3, "choices")
	eq(received[1].hours, 1, "first")
	eq(received[1].heal, false, "first heal")
	eq(received[2].hours, 3, "second")
	eq(received[3].hours, 9, "third")
	eq(env.is_open(), false, "menu closed after a choice")
end)

test("heal choice: passes the bounded healing duration", function()
	local env = load_module(new_env())
	env.db.actor.health = 0.5
	local hours, heal
	env.show(function(h, flag)
		hours = h
		heal = flag
	end)
	click(env, "btn_sleep_heal")
	eq(hours, 5, "healing duration for half health")
	eq(heal, true, "heal flag")
end)

test("cancel and escape: close without a duration and without sleeping", function()
	local env = load_module(new_env())
	local calls = 0
	env.show(function(hours)
		calls = calls + 1
		eq(hours, nil, "no duration")
	end)
	click(env, "btn_cancel")
	eq(calls, 1, "cancel callback")
	eq(env.is_open(), false, "closed after cancel")

	calls = 0
	env.show(function()
		calls = calls + 1
	end)
	local dialog = env.mock.menu_toggles[#env.mock.menu_toggles].dialog
	dialog:OnKeyboard(env.DIK_keys.DIK_ESCAPE, env.ui_events.WINDOW_KEY_PRESSED)
	eq(calls, 1, "escape callback")
	eq(env.is_open(), false, "closed after escape")

	-- A non-escape key must not close the menu.
	env.show(function() end)
	local open_dialog = env.mock.menu_toggles[#env.mock.menu_toggles].dialog
	open_dialog:OnKeyboard(env.DIK_keys.DIK_UP, env.ui_events.WINDOW_KEY_PRESSED)
	eq(env.is_open(), true, "directional key keeps the menu open")
end)

test("close: hides through the dialog holder and reports closed", function()
	local env = load_module(new_env())
	env.show(function() end)
	eq(env.is_open(), true, "open before close")
	env.close()
	eq(env.is_open(), false, "closed")
	eq(#env.mock.menu_toggles, 2, "show and hide toggles")
end)

test("show_refusal: shows the translated reason as a tip", function()
	local env = load_module(new_env())
	env.show_refusal("st_soc_sleeping_bag_talking")
	eq(env.mock.tips[1], "T:st_soc_sleeping_bag_talking", "translated refusal")
	eq(env.is_open(), false, "refusal never opens the menu")
end)

test("show_interrupted: shows the localized interruption message", function()
	local env = load_module(new_env())
	env.show_interrupted()
	eq(env.mock.tips[1], "T:st_soc_sleeping_bag_interrupted", "interruption tip")
end)

test("show_refusal: falls back to the log without news_manager", function()
	local env = load_module(new_env())
	env.news_manager = nil
	env.show_refusal("st_soc_sleeping_bag_dead")
	eq(#env.mock.logs, 1, "log fallback")
end)

test("choice_for: unknown buttons are ignored", function()
	local env = load_module(new_env())
	local hours, heal = env.choice_for("btn_unknown")
	eq(hours, nil, "no hours")
	eq(heal, nil, "no heal flag")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
