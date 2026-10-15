--!strict
-- Sound effects and music. Each sound is one Sound in SoundService, created once and reused.
-- All ids are free Creator Store audio (uploads by Roblox, ProSoundEffects, APM, DistroKid and
-- public creators); every one was loaded in Studio with ContentProvider before being added here.

local SoundService = game:GetService("SoundService")

type Entry = { id: number, volume: number, pitch: number? }

local SOUNDS: { [string]: Entry } = {
	click = { id = 15675059323, volume = 0.5 }, -- Roblox_UI_Bright_Click (Roblox)
	coin = { id = 130378474223829, volume = 0.6 }, -- Coin Pickup (Daily Sounds)
	buy = { id = 9113728049, volume = 0.5 }, -- Cash Register 2 (ProSoundEffects)
	hire = { id = 15675055424, volume = 0.6 }, -- Roblox_UI_Cute_Pop (Roblox)
	send = { id = 9126144495, volume = 0.7 }, -- Heavy Rear Door Slam (ProSoundEffects)
	step = { id = 133325104274958, volume = 0.5 }, -- Stone Footstep 1 (YuvoNet)
	door = { id = 109033795658503, volume = 0.5 }, -- Creaky Door (Daily Sounds)
	trap = { id = 94978851787238, volume = 0.6 }, -- Deep Impact Boom (Daily Sounds)
	bite = { id = 78790588708780, volume = 0.7 }, -- chomp (BennyBean2012)
	hit = { id = 9119072660, volume = 0.5 }, -- Shield Clang As Hit Metal Sword (ProSoundEffects)
	hurt = { id = 9114029889, volume = 0.6, pitch = 1.5 }, -- Pained Gasp (ProSoundEffects), pitched up to sound goblin-ish
	death = { id = 9126000399, volume = 0.7 }, -- Static Bursts Of Interference (ProSoundEffects)
	levelup = { id = 112485797063762, volume = 0.6 }, -- UI - Level Up (SodaBreadle)
	shrine = { id = 106443875576213, volume = 0.5 }, -- Twinkle (ElianMaster87)
	whoosh = { id = 15675024286, volume = 0.4 }, -- Roblox_UI_Whoosh_01 (Roblox)
	heartbeat = { id = 132163421525060, volume = 0.5 }, -- Fast Heartbeat (Daily Sounds)
	fanfare = { id = 9047103106, volume = 0.6 }, -- All It Takes Sting 2 (APM)
	fail = { id = 96795857757261, volume = 0.6 }, -- Power Down (Daily Sounds)
}

local MUSIC: { [string]: Entry } = {
	base = { id = 138384771239589, volume = 0.3 }, -- Cozy Tavern Ambience VII (DistroKid)
	dungeon = { id = 133804416597931, volume = 0.3 }, -- Shadows in the Cellar (DistroKid)
}

-- Timeline event kind (Sim/Narration) → sound. Kinds left out are silent.
local EVENT_SOUND: { [string]: string } = {
	enter = "door",
	doors = "door",
	room = "step",
	lost = "step",
	loot = "coin",
	item = "coin",
	trap_avoided = "whoosh",
	trap = "trap",
	hardhat = "hit",
	mimic_spotted = "whoosh",
	mimic = "bite",
	mimic_escape = "whoosh",
	combat = "hit",
	hit = "hit",
	hurt = "hurt",
	flee = "whoosh",
	sneak = "whoosh",
	shrine = "shrine",
	starving = "heartbeat",
	death = "death",
	["return"] = "fanfare",
	levelup = "levelup",
}

local PITCH_JITTER = 0.06 -- ±6% so repeated sounds don't feel canned
local FADE_TIME = 1.5

local Sfx = {}

local group = Instance.new("SoundGroup")
group.Name = "Game"
group.Parent = SoundService

local function make(name: string, entry: Entry, looped: boolean): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = `rbxassetid://{entry.id}`
	sound.Volume = entry.volume
	sound.Looped = looped
	sound.SoundGroup = group
	sound.Parent = group
	return sound
end

local sounds: { [string]: Sound } = {}
for name, entry in SOUNDS do
	sounds[name] = make(name, entry, false)
end
local music: { [string]: Sound } = {}
for name, entry in MUSIC do
	music[name] = make(`Music_{name}`, entry, true)
	music[name].Volume = 0
end

function Sfx.play(name: string, props: { volume: number?, pitch: number? }?)
	local sound, entry = sounds[name], SOUNDS[name]
	if not sound then
		return
	end
	local jitter = 1 + (math.random() * 2 - 1) * PITCH_JITTER
	sound.Volume = (props and props.volume) or entry.volume
	sound.PlaybackSpeed = ((props and props.pitch) or entry.pitch or 1) * jitter
	sound.TimePosition = 0
	sound:Play()
end

function Sfx.event(event: { kind: string })
	local name = EVENT_SOUND[event.kind]
	if name then
		Sfx.play(name)
	end
end

local currentMusic: string? = nil
local fadeId = 0

-- Crossfades to a looped track ("base" or "dungeon"); nil fades everything out.
function Sfx.music(name: string?)
	if name == currentMusic then
		return
	end
	currentMusic = name
	fadeId += 1
	local id = fadeId

	local from: { [string]: number } = {}
	for key, sound in music do
		from[key] = sound.Volume
	end
	local target = name and music[name]
	if target and not target.IsPlaying then
		target:Play()
	end

	task.spawn(function()
		local start = os.clock()
		local alpha = 0
		while alpha < 1 do
			task.wait()
			if fadeId ~= id then
				return -- a newer crossfade took over
			end
			alpha = math.min(1, (os.clock() - start) / FADE_TIME)
			for key, sound in music do
				local goal = if key == name then MUSIC[key].volume else 0
				sound.Volume = from[key] + (goal - from[key]) * alpha
			end
		end
		for key, sound in music do
			if key ~= name then
				sound:Stop()
			end
		end
	end)
end

function Sfx.isMuted(): boolean
	return group.Volume == 0
end

function Sfx.setMuted(muted: boolean)
	group.Volume = if muted then 0 else 1
end

return Sfx
