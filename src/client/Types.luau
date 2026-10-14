--!strict
-- Shared client types (kept apart from App to avoid circular requires).

local Net = require(script.Parent.Net)

export type Screen = {
	destroy: () -> (),
	refresh: (() -> ())?,
}

export type Ctx = {
	root: Frame,
	profile: any,
	party: { [string]: boolean },
	known: { [string]: boolean }, -- goblins already seen (new ones auto-join the party)
	depth: number,
	busy: boolean,
	call: (action: string, payload: { [string]: any }?) -> Net.Response,
	toast: (text: string, color: Color3?) -> (),
	refresh: () -> (),
	showBase: () -> (),
	showRun: (run: any, result: any, serverNow: number) -> (),
	showResults: (summary: any, party: { any }) -> (),
}

return {}
