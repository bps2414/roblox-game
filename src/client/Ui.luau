--!strict
-- Tiny UI toolkit: an instance builder plus the game's pixel-dungeon look.
-- Everything is laid out on a fixed 1280x720 canvas that is scaled to the screen.

local Sfx = require(script.Parent.Sfx)

local Ui = {}

Ui.WIDTH = 1280
Ui.HEIGHT = 720

Ui.color = {
	bg = Color3.fromHex("0d0b14"),
	panel = Color3.fromHex("17131f"),
	panelLight = Color3.fromHex("221c2d"),
	border = Color3.fromHex("2b2238"),
	borderLight = Color3.fromHex("3a3150"),
	feed = Color3.fromHex("2c2536"),
	text = Color3.fromHex("e8e2d0"),
	muted = Color3.fromHex("9a8fb0"),
	green = Color3.fromHex("7ed957"),
	darkGreen = Color3.fromHex("1f4d12"),
	gold = Color3.fromHex("e8c547"),
	darkGold = Color3.fromHex("6b4f0c"),
	red = Color3.fromHex("e03a3a"),
	darkRed = Color3.fromHex("3a1616"),
	caption = Color3.fromHex("ffe46b"),
	purple = Color3.fromHex("5a3a8a"),
	black = Color3.new(0, 0, 0),
}

Ui.font = {
	pixel = Enum.Font.Arcade,
	body = Enum.Font.Code,
}

type Props = { [string]: any }

-- Ui.new("Frame", { Size = ..., Activated = function() end }, { children })
-- Function-valued props are connected as events. Parent is applied last.
function Ui.new(className: string, props: Props?, children: { any }?): any
	local instance = Instance.new(className) :: any
	local parent = nil
	for key, value in (props or {}) :: Props do
		if key == "Parent" then
			parent = value
		elseif type(value) == "function" then
			instance[key]:Connect(value)
		else
			instance[key] = value
		end
	end
	for _, child in (children or {}) :: { any } do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function Ui.stroke(color: Color3?, thickness: number?): Instance
	return Ui.new("UIStroke", {
		Color = color or Ui.color.border,
		Thickness = thickness or 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Miter,
	})
end

function Ui.padding(all: number, horizontal: number?): Instance
	local h = UDim.new(0, horizontal or all)
	local v = UDim.new(0, all)
	return Ui.new("UIPadding", { PaddingLeft = h, PaddingRight = h, PaddingTop = v, PaddingBottom = v })
end

function Ui.list(direction: Enum.FillDirection?, gap: number?, props: Props?): Instance
	local layout = Ui.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	for key, value in (props or {}) :: Props do
		layout[key] = value
	end
	return layout
end

function Ui.panel(props: Props, children: { any }?): Frame
	local frame = Ui.new("Frame", {
		BackgroundColor3 = Ui.color.panel,
		BorderSizePixel = 0,
	}, children)
	for key, value in props do
		frame[key] = value
	end
	Ui.stroke(props.BorderColor3 or Ui.color.border).Parent = frame
	return frame
end

function Ui.label(text: string, props: Props?): TextLabel
	local label = Ui.new("TextLabel", {
		Text = text,
		BackgroundTransparency = 1,
		Font = Ui.font.body,
		TextSize = 20,
		TextColor3 = Ui.color.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, 24),
		RichText = true,
	})
	for key, value in (props or {}) :: Props do
		if type(value) == "function" then
			label[key]:Connect(value)
		else
			label[key] = value
		end
	end
	return label
end

-- Pixel-font heading.
function Ui.title(text: string, props: Props?): TextLabel
	local label: any = Ui.label(text, { Font = Ui.font.pixel, TextSize = 14, TextColor3 = Ui.color.muted })
	for key, value in (props or {}) :: Props do
		label[key] = value
	end
	return label
end

function Ui.button(text: string, onClick: () -> (), props: Props?): TextButton
	local color = (props and props.BackgroundColor3) or Ui.color.borderLight
	local enabled = not (props and props.Enabled == false)
	local button = Ui.new("TextButton", {
		Text = text,
		AutoButtonColor = enabled,
		Active = enabled,
		BackgroundColor3 = if enabled then color else Ui.color.border,
		BorderSizePixel = 0,
		Font = Ui.font.pixel,
		TextSize = 12,
		TextColor3 = if enabled then Ui.color.text else Ui.color.muted,
		Size = UDim2.fromOffset(100, 32),
	})
	Ui.stroke(Ui.color.black, 2).Parent = button
	for key, value in (props or {}) :: Props do
		if key ~= "Enabled" and key ~= "BackgroundColor3" then
			button[key] = value
		end
	end
	if enabled then
		button.Activated:Connect(function()
			Sfx.play("click")
			onClick()
		end)
	end
	return button
end

function Ui.bar(fraction: number, color: Color3, props: Props?): Frame
	local bar = Ui.new("Frame", {
		BackgroundColor3 = Ui.color.darkRed,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(120, 12),
	}, {
		Ui.new("Frame", {
			Name = "Fill",
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1),
		}),
	})
	Ui.stroke(Ui.color.black, 2).Parent = bar
	for key, value in (props or {}) :: Props do
		bar[key] = value
	end
	return bar
end

function Ui.setBar(bar: Frame, fraction: number)
	local fill = bar:FindFirstChild("Fill") :: Frame?
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	end
end

function Ui.scroll(props: Props, children: { any }?): ScrollingFrame
	local frame = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Ui.color.borderLight,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, children)
	for key, value in props do
		frame[key] = value
	end
	return frame
end

-- Hex colors in RichText.
function Ui.hex(color: Color3): string
	return "#" .. color:ToHex()
end

function Ui.paint(text: string, color: Color3): string
	return `<font color="{Ui.hex(color)}">{text}</font>`
end

return Ui
