--!strict
-- What the cameras show `elapsed` seconds into a run. Used by the client to replay a
-- result; pure so it can be tested.

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

function Playback.feed(events: { Expedition.Event }, elapsed: number): FeedState
	local state: FeedState = { status = "delving", hp = nil, gold = 0, room = 0, shown = 0, last = nil }
	for index, event in events do
		if event.t > elapsed then
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

function Playback.isFinished(result: Expedition.Result, elapsed: number): boolean
	return elapsed >= result.duration
end

return Playback
