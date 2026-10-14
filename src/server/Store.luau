--!strict
-- Minimal DataStore wrapper. Session locking / retries on save come in M4.
-- If DataStores aren't available (Studio without API access) progress lives in memory
-- and is lost when the server stops.

local DataStoreService = game:GetService("DataStoreService")

local Store = {}

local STORE_NAME = "SendGoblins_v1"

local available, dataStore = pcall(function()
	return DataStoreService:GetDataStore(STORE_NAME)
end)

local memory: { [number]: any } = {}

local function key(userId: number): string
	return `player_{userId}`
end

-- Returns (data or nil, canSave). canSave is false when loading failed, so a temporary
-- outage never overwrites a real save with a fresh profile.
function Store.load(userId: number): (any, boolean)
	if not available then
		return memory[userId], true
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return (dataStore :: DataStore):GetAsync(key(userId))
		end)
		if ok then
			return result, true
		end
		warn(`[Store] load failed ({attempt}/3): {result}`)
		if string.find(tostring(result), "Studio", 1, true) then
			warn("[Store] Enable 'Studio Access to API Services' to save progress in Studio.")
			available = false
			return memory[userId], true
		end
		task.wait(attempt)
	end
	return nil, false
end

function Store.save(userId: number, data: any)
	if not available then
		memory[userId] = data
		return
	end
	local ok, err = pcall(function()
		(dataStore :: DataStore):SetAsync(key(userId), data, { userId })
	end)
	if not ok then
		warn(`[Store] save failed: {err}`)
	end
end

return Store
