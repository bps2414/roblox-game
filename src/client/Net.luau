--!strict
-- One RemoteFunction for every action. Responses always carry the fresh profile.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Request = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Request") :: RemoteFunction

local Net = {}

export type Response = { [string]: any }

function Net.call(action: string, payload: { [string]: any }?): Response
	local ok, response = pcall(function()
		return Request:InvokeServer(action, payload or {})
	end)
	if not ok or type(response) ~= "table" then
		return { ok = false, err = "Connection problem, try again" }
	end
	return response
end

return Net
