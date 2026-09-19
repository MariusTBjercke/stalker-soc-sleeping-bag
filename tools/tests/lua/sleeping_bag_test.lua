-- Offline tests for gamedata/scripts/soc_sleeping_bag.script.
-- Usage: lua5.1 tools/tests/lua/sleeping_bag_test.lua <repo root>
-- tools/tests/gameplay_test.ps1 runs this automatically.

local root = arg[1] or "."
local mocks = dofile(root .. "/tools/tests/lua/xray_mocks.lua")
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

local MODULE_PATH = root .. "/gamedata/scripts/soc_sleeping_bag.script"
local SLEEP_HOUR = 3600

-- Loads the module into a fresh mock environment and returns the environment.
-- The module's public functions are globals on the returned environment.
local function load_module(env)
	local chunk = assert(loadfile(MODULE_PATH), "module file not found: " .. MODULE_PATH)
	setfenv(chunk, env)
	chunk()
	return env
end

-- A fresh module with a live, safe actor and clean engine state.
local function fresh(opts)
	opts = opts or {}
	local env = mocks.new_env(opts)
	env.db.actor = mocks.make_actor(env, opts.actor)
	load_module(env)
	return env
end

-- Installs a fake UI module and returns a spy over the calls it received.
local function make_menu_spy(env)
	local spy = { shown = 0, refusals = {}, interrupted = 0, choices = {}, open_flag = false }
	env.soc_sleeping_bag_ui = {
		show = function(on_choice)
			spy.shown = spy.shown + 1
			table.insert(spy.choices, on_choice)
		end,
		show_refusal = function(reason_id)
			table.insert(spy.refusals, reason_id)
		end,
		show_interrupted = function()
			spy.interrupted = spy.interrupted + 1
		end,
		is_open = function()
			return spy.open_flag
		end,
	}
	return spy
end

local function make_item(section)
	return { section = function() return section end }
end

-- ---------------------------------------------------------- healing_hours

test("healing_hours: full health returns the 1 hour floor", function()
	eq(fresh().healing_hours(1.0), 1)
end)

test("healing_hours: half health returns 5 hours", function()
	eq(fresh().healing_hours(0.5), 5)
end)

test("healing_hours: empty health returns the 9 hour cap", function()
	eq(fresh().healing_hours(0.0), 9)
end)

test("healing_hours: clamps out-of-range values safely", function()
	local m = fresh()
	eq(m.healing_hours(2.0), 1, "above full")
	eq(m.healing_hours(-1.0), 9, "below empty")
	eq(m.healing_hours(0.94), 1, "near full rounds to the floor")
	eq(m.healing_hours(0.88), 2, "just under the floor rounds to 2")
end)

-- ------------------------------------------------------ eligibility_reason

test("eligibility: rejects a missing level", function()
	local m = fresh({ level_missing = true })
	eq(m.eligibility_reason(m.db.actor, 0), "st_soc_sleeping_bag_no_level")
end)

test("eligibility: rejects an absent level global", function()
	local m = fresh({ level_absent = true })
	eq(m.eligibility_reason(m.db.actor, 0), "st_soc_sleeping_bag_no_level")
end)

test("eligibility: rejects a missing actor", function()
	local m = fresh()
	m.db.actor = nil
	eq(m.eligibility_reason(nil, 0), "st_soc_sleeping_bag_no_actor")
end)

test("eligibility: rejects a dead actor", function()
	local m = fresh({ actor = { alive = false } })
	eq(m.eligibility_reason(m.db.actor, 0), "st_soc_sleeping_bag_dead")
end)

test("eligibility: rejects a talking actor", function()
	local m = fresh({ actor = { talking = true } })
	eq(m.eligibility_reason(m.db.actor, 0), "st_soc_sleeping_bag_talking")
end)

test("eligibility: rejects a bleeding actor", function()
	local m = fresh({ actor = { bleeding = 1 } })
	eq(m.eligibility_reason(m.db.actor, 0), "st_soc_sleeping_bag_bleeding")
end)

test("eligibility: rejects radiation at the severe threshold", function()
	local m = fresh({ actor = { radiation = 0.7 } })
	eq(m.eligibility_reason(m.db.actor, 0), "st_soc_sleeping_bag_radiation")
end)

test("eligibility: permits radiation below the severe threshold", function()
	local m = fresh({ actor = { radiation = 0.69 } })
	eq(m.eligibility_reason(m.db.actor, 0), nil)
end)

test("eligibility: rejects a hit less than 10 seconds ago", function()
	local m = fresh()
	m.now_ms = 1000
	m.on_actor_hit()
	eq(m.eligibility_reason(m.db.actor, 1000 + 9999), "st_soc_sleeping_bag_recent_hit")
end)

test("eligibility: permits a hit exactly 10 seconds ago", function()
	local m = fresh()
	m.now_ms = 1000
	m.on_actor_hit()
	eq(m.eligibility_reason(m.db.actor, 1000 + 10000), nil)
end)

-- ------------------------------------------------------------ start_sleep

test("start_sleep: captures the old factor once and applies the fast transition", function()
	local m = fresh({ time_factor = 10 })
	local actor = m.db.actor
	eq(m.start_sleep(1, false), true)
	eq(m.level.factor, 10000, "fast time factor selected")
	eq(m.mock.input_disabled, true, "input disabled")
	eq(actor.weapon_hidden, true, "weapon hidden")
	eq(mocks.count_calls(m, "level.disable_input"), 1, "single disable")

	-- A second start during an active sleep is refused and must not
	-- overwrite the captured factor with the fast value.
	eq(m.start_sleep(2, false), false)
	eq(mocks.count_calls(m, "level.disable_input"), 1, "no second disable")

	eq(m.finish_sleep(), true)
	eq(m.level.factor, 10, "captured factor restored, not the fast value")
	eq(m.mock.input_disabled, false, "input enabled again")
	eq(actor.weapon_hidden, false, "weapon shown again")
end)

test("start_sleep: refuses when no actor exists", function()
	local m = fresh()
	m.db.actor = nil
	eq(m.start_sleep(1, false), false)
end)

-- -------------------------------------------------------- sleep completion

test("completion: restores captured state only at the game-time deadline", function()
	local m = fresh({ game_time = 0 })
	eq(m.start_sleep(3, false), true)
	m.game_time = 3 * SLEEP_HOUR - 1
	m.update(0)
	eq(m.mock.input_disabled, true, "still sleeping before the deadline")
	m.game_time = 3 * SLEEP_HOUR
	m.update(0)
	eq(m.mock.input_disabled, false, "input restored at completion")
	eq(m.level.factor, 10, "factor restored at completion")
	eq(m.db.actor.weapon_hidden, false, "weapon restored at completion")
end)

test("healing: health reaches full only after successful completion", function()
	local m = fresh({ game_time = 0, actor = { health = 0.5 } })
	local actor = m.db.actor
	eq(m.start_sleep(1, true), true)
	eq(actor.health, 0.5, "not healed before completion")
	m.game_time = SLEEP_HOUR
	m.update(0)
	eq(actor.health, 1.0, "healed at completion")
end)

test("sleep until healed: uses the bounded healing duration", function()
	local m = fresh({ game_time = 0, actor = { health = 0.5 } })
	eq(m.start_sleep(m.healing_hours(0.5), true), true)
	m.game_time = 5 * SLEEP_HOUR - 1
	m.update(0)
	eq(m.mock.input_disabled, true, "five hours are still short of the deadline")
	m.game_time = 5 * SLEEP_HOUR
	m.update(0)
	eq(m.mock.input_disabled, false, "completed after the healing duration")
	eq(m.db.actor.health, 1.0, "healed after the healing duration")
end)

test("sleep until healed: full health sleeps the 1 hour floor", function()
	local m = fresh({ game_time = 0, actor = { health = 1.0 } })
	eq(m.start_sleep(m.healing_hours(1.0), true), true)
	m.game_time = SLEEP_HOUR - 1
	m.update(0)
	eq(m.mock.input_disabled, true, "still sleeping one second before the floor")
	m.game_time = SLEEP_HOUR
	m.update(0)
	eq(m.mock.input_disabled, false, "completed at the floor duration")
end)

-- ------------------------------------------------------------ abort paths

test("hit during sleep: aborts without healing", function()
	local m = fresh({ game_time = 0, actor = { health = 0.5 } })
	eq(m.start_sleep(1, true), true)
	m.on_actor_hit()
	eq(m.level.factor, 10, "aborted sleep restored the factor")
	eq(m.mock.input_disabled, false, "aborted sleep re-enabled input")
	eq(m.db.actor.health, 0.5, "aborted sleep must not heal")
end)

test("update: aborts when the actor dies during sleep", function()
	local m = fresh({ game_time = 0 })
	eq(m.start_sleep(1, false), true)
	m.db.actor._alive = false
	m.update(0)
	eq(m.mock.input_disabled, false, "death aborted the sleep")
	eq(m.level.factor, 10, "death restored the factor")
end)

test("cleanup: repeated cleanup and late transitions are harmless", function()
	local m = fresh()
	eq(m.start_sleep(1, false), true)
	eq(m.abort_sleep("test"), true)
	local sets = mocks.count_calls(m, "level.set_time_factor")
	local enables = mocks.count_calls(m, "level.enable_input")
	local restores = mocks.count_calls(m, "actor.restore_weapon")

	-- Every path is safe to repeat once nothing is active.
	eq(m.abort_sleep("again"), false)
	eq(m.finish_sleep(), false)
	m.cleanup()
	m.cleanup()
	m.recover()
	m.on_actor_net_destroy()

	eq(mocks.count_calls(m, "level.set_time_factor"), sets, "no extra factor writes")
	eq(mocks.count_calls(m, "level.enable_input"), enables, "no extra input writes")
	eq(mocks.count_calls(m, "actor.restore_weapon"), restores, "no extra weapon writes")
end)

-- ---------------------------------------------------------- recovery paths

test("recover: clears a stale transition before scheduling provisioning", function()
	local m = fresh({ game_time = 0 })
	local actor = m.db.actor
	eq(m.start_sleep(1, false), true)
	m.on_actor_net_spawn()

	eq(m.level.factor, 10, "stale transition restored the factor")
	eq(m.mock.input_disabled, false, "stale transition re-enabled input")
	eq(actor.weapon_hidden, false, "stale transition restored the weapon")

	m.update(0)
	eq(#m.mock.created_items, 0, "no bag before the provisioning delay")
	m.now_ms = 1000
	m.update(0)
	eq(#m.mock.created_items, 1, "one bag after the provisioning delay")
end)

test("recover: restores the normal factor when a stale fast factor has no capture", function()
	local m = fresh({ time_factor = 10000 })
	m.recover()
	eq(m.level.factor, 10, "stale fast factor without capture resets to normal")
end)

-- ----------------------------------------------------------- provisioning

test("provisioning: creates one bag when absent and never duplicates", function()
	local m = fresh()
	m.on_actor_net_spawn()
	m.now_ms = 1000
	m.update(0)
	eq(#m.mock.created_items, 1, "one bag created")
	eq(m.mock.created_items[1].section, "soc_sleeping_bag", "bag section")
	eq(m.mock.created_items[1].parent_id, m.db.actor:id(), "bag goes into the actor inventory")
	m.update(0)
	m.update(0)
	eq(#m.mock.created_items, 1, "repeated updates do not duplicate")
end)

test("provisioning: creates none when the actor already has the bag", function()
	local m = fresh({ actor = { items = { "soc_sleeping_bag" } } })
	m.on_actor_net_spawn()
	m.now_ms = 1000
	m.update(0)
	eq(#m.mock.created_items, 0, "no bag created when present")
	eq(m.ensure_item(), false)
end)

test("on_actor_net_destroy: cancels pending provisioning", function()
	local m = fresh()
	m.on_actor_net_spawn()
	m.on_actor_net_destroy()
	m.now_ms = 5000
	m.update(0)
	eq(#m.mock.created_items, 0, "destroyed actor must not be provisioned")
end)

-- -------------------------------------------------------------- item use

test("item use: ignores every section except the sleeping bag", function()
	local m = fresh()
	local spy = make_menu_spy(m)
	eq(m.on_item_use(make_item("wpn_knife")), false, "other section")
	eq(m.on_item_use(make_item("medkit")), false, "other section")
	eq(m.on_item_use(nil), false, "missing object")
	eq(spy.shown, 0, "menu never opened")
	eq(#spy.refusals, 0, "no refusal shown")
end)

test("item use: refuses with a localized reason and keeps the menu closed", function()
	local m = fresh({ actor = { talking = true } })
	local spy = make_menu_spy(m)
	eq(m.on_item_use(make_item("soc_sleeping_bag")), true, "the use is handled even when refused")
	eq(#spy.refusals, 1, "one refusal shown")
	eq(spy.refusals[1], "st_soc_sleeping_bag_talking", "localized reason")
	eq(spy.shown, 0, "menu never opened")
end)

test("item use: opens the menu only after eligibility succeeds", function()
	local m = fresh()
	local spy = make_menu_spy(m)
	eq(m.on_item_use(make_item("soc_sleeping_bag")), true)
	eq(spy.shown, 1, "menu opened once")
	eq(#spy.refusals, 0, "no refusal shown")
end)

test("item use: skips a second open while the menu is visible", function()
	local m = fresh()
	local spy = make_menu_spy(m)
	spy.open_flag = true
	eq(m.on_item_use(make_item("soc_sleeping_bag")), true, "handled without action")
	eq(spy.shown, 0, "menu not opened again")
end)

test("menu choice: starts the sleep with the chosen duration", function()
	local m = fresh({ game_time = 0 })
	local spy = make_menu_spy(m)
	eq(m.on_item_use(make_item("soc_sleeping_bag")), true)
	eq(#spy.choices, 1, "one choice callback")
	spy.choices[1](3, false)
	eq(m.mock.input_disabled, true, "input disabled by the chosen sleep")
	eq(m.level.factor, 10000, "fast factor selected by the chosen sleep")
	eq(mocks.count_calls(m, "level.disable_input"), 1, "one transition")
end)

test("menu cancel: returns to idle without touching engine state", function()
	local m = fresh({ game_time = 0 })
	local spy = make_menu_spy(m)
	eq(m.on_item_use(make_item("soc_sleeping_bag")), true)
	spy.choices[1](nil, false)
	eq(m.mock.input_disabled, false, "input untouched")
	eq(m.level.factor, 10, "factor untouched")
	eq(spy.interrupted, 0, "a cancel is not an interruption")
	-- The module is idle again and can start a fresh sleep.
	eq(m.start_sleep(1, false), true)
end)

test("menu heal choice: sleeps the bounded healing duration", function()
	local m = fresh({ game_time = 0, actor = { health = 0.5 } })
	local spy = make_menu_spy(m)
	eq(m.on_item_use(make_item("soc_sleeping_bag")), true)
	spy.choices[1](5, true)
	m.game_time = 5 * SLEEP_HOUR - 1
	m.update(0)
	eq(m.mock.input_disabled, true, "still sleeping near the healing deadline")
	m.game_time = 5 * SLEEP_HOUR
	m.update(0)
	eq(m.db.actor.health, 1.0, "healed after the healing choice")
end)

test("hit abort: notifies the UI exactly once", function()
	local m = fresh()
	local spy = make_menu_spy(m)
	eq(m.start_sleep(1, false), true)
	m.on_actor_hit()
	eq(spy.interrupted, 1, "one interruption notice")
	m.on_actor_hit()
	eq(spy.interrupted, 1, "no notice once idle")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
