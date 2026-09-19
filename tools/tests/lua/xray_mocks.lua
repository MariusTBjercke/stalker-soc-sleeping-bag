-- Reusable X-Ray engine mocks for offline Lua 5.1 tests.
-- Usage inside a test file:
--   local mocks = dofile(root .. "/tools/tests/lua/xray_mocks.lua")
--   local env = mocks.new_env()
--   env.db.actor = mocks.make_actor(env, {})

local M = {}

-- Builds a sandbox environment whose globals stand in for the X-Ray engine.
-- opts fields (all optional):
--   now_ms        initial time_global() value        (default 0)
--   game_time     initial game.get_game_time() value (default 0)
--   time_factor   initial level time factor          (default 10)
--   level_name    name returned by level.name()      (default "l01_escape")
--   level_missing level.name() returns nil
--   level_absent  the level global is nil entirely
-- Every engine call is recorded in env.mock.calls in order.
function M.new_env(opts)
	opts = opts or {}
	local env = setmetatable({}, { __index = _G })
	local calls = {}
	env.mock = {
		calls = calls,
		created_items = {},
		input_disabled = false,
	}

	local function record(name)
		table.insert(calls, name)
	end

	env.now_ms = opts.now_ms or 0
	env.time_global = function()
		record("time_global")
		return env.now_ms
	end

	env.game_time = opts.game_time or 0
	env.game = {
		get_game_time = function()
			record("game.get_game_time")
			-- The engine returns a CTime object: no arithmetic or numeric
			-- comparison, only diffSec.
			local now = env.game_time
			return setmetatable({ seconds = now }, {
				__index = {
					diffSec = function(self, other)
						return self.seconds - other.seconds
					end,
				},
			})
		end,
	}

	local level_name = "l01_escape"
	if opts.level_missing then
		level_name = nil
	elseif opts.level_name ~= nil then
		level_name = opts.level_name
	end
	env.level = {
		factor = opts.time_factor or 10,
		name = function()
			record("level.name")
			return level_name
		end,
		get_time_factor = function()
			record("level.get_time_factor")
			return env.level.factor
		end,
		set_time_factor = function(factor)
			record("level.set_time_factor")
			env.level.factor = factor
		end,
		disable_input = function()
			record("level.disable_input")
			env.mock.input_disabled = true
		end,
		enable_input = function()
			record("level.enable_input")
			env.mock.input_disabled = false
		end,
	}
	if opts.level_absent then
		env.level = nil
	end

	env.db = { actor = nil }

	local next_item_id = 1000
	env.mock.next_actor_id = function()
		next_item_id = next_item_id + 1
		return next_item_id
	end

	env.alife = function()
		record("alife")
		return {
			create = function(self, section, position, level_vertex_id, game_vertex_id, parent_id)
				record("alife.create")
				table.insert(env.mock.created_items, {
					section = section,
					position = position,
					level_vertex_id = level_vertex_id,
					game_vertex_id = game_vertex_id,
					parent_id = parent_id,
				})
			end,
		}
	end

	return env
end

-- A fake actor game object covering the surface the sleep module uses.
-- opts fields (all optional):
--   items     section names the inventory iterates (default {})
--   radiation actor.radiation property             (default 0)
--   health    actor.health property                (default 1.0)
--   alive     actor:alive() result                 (default true)
--   talking   actor:is_talking() result            (default false)
--   bleeding  actor:get_bleeding() result          (default 0)
function M.make_actor(env, opts)
	opts = opts or {}
	local actor = {
		radiation = opts.radiation or 0,
		health = opts.health ~= nil and opts.health or 1.0,
		weapon_hidden = false,
	}
	actor._alive = opts.alive ~= false
	actor._talking = opts.talking or false
	actor._bleeding = opts.bleeding or 0
	actor._items = opts.items or {}
	actor._id = env.mock.next_actor_id()

	function actor:id() return self._id end
	function actor:position() return { x = 0, y = 0, z = 0 } end
	function actor:level_vertex_id() return 1 end
	function actor:game_vertex_id() return 1 end
	function actor:alive() return self._alive end
	function actor:is_talking() return self._talking end
	function actor:get_bleeding() return self._bleeding end
	function actor:hide_weapon()
		self.weapon_hidden = true
		table.insert(env.mock.calls, "actor.hide_weapon")
	end
	function actor:restore_weapon()
		self.weapon_hidden = false
		table.insert(env.mock.calls, "actor.restore_weapon")
	end
	function actor:iterate_inventory(fn, owner)
		for _, section in ipairs(self._items) do
			fn(owner, { section = function() return section end })
		end
	end

	return actor
end

-- Number of recorded engine calls whose name matches exactly.
function M.count_calls(env, name)
	local count = 0
	for _, entry in ipairs(env.mock.calls) do
		if entry == name then
			count = count + 1
		end
	end
	return count
end

return M
