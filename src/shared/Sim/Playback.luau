--!strict
-- What the cameras show `elapsed` seconds into a run. Used by the client to replay a
-- result; pure so it can be tested.
--
-- The simulation stamps every event of a room with the same time. For the camera they are
-- spread out (display times) so each beat gets a moment: door choice, room reveal, outcome.

local Expedition = require("./Expedition")

export type FeedState = {
	status: "delving" | "dead" | "returned",
	hp: number?,
	gold: number,
	room: number,
	shown: number, -- how many of this goblin's events are visible
	last: Expedition.Event?,
}

local Playback = {}

Playback.GAP = 0.5 -- seconds between beats stamped with the same time
Playback.AFTER_DOORS = 1.0 -- suspense between picking a door and seeing the room

-- Display time of each event: never before its own time, never on top of the previous one.
function Playback.schedule(events: { Expedition.Event }): { number }
	local times = {}
	local previous, previousKind = -math.huge, nil
	for index, event in events do
		local gap = if previousKind == "doors" then Playback.AFTER_DOORS else Playback.GAP
		local at = math.max(event.t, previous + gap)
		times[index] = at
		previous, previousKind = at, event.kind
	end
	return times
end

function Playback.feed(events: { Expedition.Event }, elapsed: number, times: { number }?): FeedState
	local at = times or Playback.schedule(events)
	local state: FeedState = { status = "delving", hp = nil, gold = 0, room = 0, shown = 0, last = nil }
	for index, event in events do
		if at[index] > elapsed then
			break
		end
		state.shown = index
		state.last = event
		state.room = event.room
		if event.hp then
			state.hp = event.hp
		end
		if event.kind == "loot" then
			state.gold += event.amount or 0
		elseif event.kind == "death" then
			state.status = "dead"
		elseif event.kind == "return" then
			state.status = "returned"
		end
	end
	return state
end

function Playback.all(result: Expedition.Result, elapsed: number): { [string]: FeedState }
	local states = {}
	for _, goblin in result.goblins do
		states[goblin.id] = Playback.feed(result.timelines[goblin.id], elapsed)
	end
	return states
end

-- When the last beat is on screen (a bit after result.duration, never before).
function Playback.endTime(result: Expedition.Result): number
	local finish = result.duration
	for _, goblin in result.goblins do
		local times = Playback.schedule(result.timelines[goblin.id])
		finish = math.max(finish, times[#times] or 0)
	end
	return finish
end

function Playback.isFinished(result: Expedition.Result, elapsed: number): boolean
	return elapsed >= Playback.endTime(result)
end

return Playback
