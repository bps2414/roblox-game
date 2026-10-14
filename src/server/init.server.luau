local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hello = require(ReplicatedStorage.Shared.Hello)

Players.PlayerAdded:Connect(function(player)
	print(Hello.greet(player.Name))
end)
