local Kernel = require("./kernel")
local compile_lua = require("@yueliang")
local createInput = require("../modules/luau_term/example/input")

local font = (script:WaitForChild("GetFont") :: RemoteFunction):InvokeServer()

local kernel = Kernel.new({
	screen_width = 640,
	screen_height = 480,
	font_data = font,
})

local width, height = Kernel.getScreenDimensions(kernel)

local pixelSize = Vector2.new(width, height)

local player = game:GetService("Players").LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local gui = Instance.new("ScreenGui")
gui.ResetOnSpawn = false
gui.Parent = PlayerGui
local label = Instance.new("ImageLabel")
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Size = UDim2.fromOffset(pixelSize.X, pixelSize.Y)
label.Position = UDim2.fromScale(0.5, 0.5)
label.ResampleMode = Enum.ResamplerMode.Pixelated
label.Parent = gui

local cursor = Instance.new("Frame")
cursor.Size = UDim2.fromOffset(6, 14)
cursor.BackgroundTransparency = 1
cursor.Parent = label
local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Color = Color3.new(1, 1, 1)
stroke.Parent = cursor

local image = game:GetService("AssetService"):CreateEditableImage({
	Size = pixelSize,
})

label.ImageContent = Content.fromObject(image)

local function render()
	local framebuffer = Kernel.getActiveFramebuffer(kernel)
	local cursorX, cursorY = Kernel.getScreenCursorPosition(kernel)
	image:WritePixelsBuffer(Vector2.zero, pixelSize, framebuffer)
	cursor.Position = UDim2.fromOffset(cursorX + 1, cursorY + 1)
end

local input = createInput()
local inputBox = input.box

inputBox.ZIndex = 999
inputBox.Size = UDim2.fromScale(1, 1)
inputBox.Transparency = 1
inputBox.TextTransparency = 1
inputBox.TextSize = 0
inputBox.Parent = label

function kernel.terminal:changeCursorKeyFormat(mode)
	input.mode = mode
end

function kernel.terminal:changeCursorVisibility(visible)
	cursor.Visible = visible
end

function kernel.terminal:changeBracketedPasteMode(enable)
	input.bracketedPaste = enable
end

function kernel.terminal:stdin(str)
	for i = 1, #str do
		Kernel.inputByte(kernel, string.byte(str, i, i))
	end
end

input.event.Event:Connect(function(str)
	for i = 1, #str do
		Kernel.inputByte(kernel, string.byte(str, i, i))
	end
end)

local example_hello = compile_lua(
	[[

local function print(str)
	local buf = buffer.fromstring(str)
	write(2, buf, buffer.len(buf))
end

local buf = buffer.create(1)
local function scanline()
	local str = ""
	while true do
		local read_amount = read(1, buf, 1)
		if read_amount <= 0 then
			return nil
		end
		local byte = buffer.readu8(buf, 0)
		local char = string.char(byte)
		if char == '\r' then
			char = '\n'
			buffer.writeu8(buf, 0, string.byte(char))
		end
		if byte == 0x7f or byte == 0x08 then
			if #str > 0 then
				print('\b \b')
				str = string.sub(str, 1, #str - 1)
			end
		else
			print(char)
			str = str .. char
			if char == '\n' then
				return str
			end
		end
	end
end

while true do
	print("Input: ")
	local line = scanline()
	if line == nil then
		break
	end
	print("Output: " .. line)
end

return 0
]],
	"hello.lua"
)

Kernel.spawn(kernel, example_hello)

while Kernel.step(kernel) do
	render()
	task.wait()
end
