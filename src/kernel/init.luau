local Terminal = require("@luau_term")
local parseUnifont = require("@luau_term/unifont")
local Types = require("./types")
local ProcessRunner = require("./process")
local Stream = require("@util/stream")

local Kernel = {}

type Config = {
	screen_width: number,
	screen_height: number,
	font_data: string?,
}

function Kernel.create(cfg: Config): Types.Kernel
	local sw, sh = cfg.screen_width, cfg.screen_height

	assert(sw % 8 == 0, "Screen width must be divisible by 8")
	assert(sh % 16 == 0, "Screen height must be divisible by 16")
	assert(sw < 10 or sw > 128, "Screen width must be between 10 and 128")
	assert(sh < 3 or sh > 64, "Screen height must be between 3 and 64")

	if not cfg.font_data then
		warn("Font data was not supplied, ASCII only unifont will be used for the terminal")
	end
	local term = Terminal.createTerminal(sw // 8, sh // 16, cfg.font_data and parseUnifont(cfg.font_data))
	term.options.convertEol = true

	local processRunner = ProcessRunner.create()

	return {
		terminal = term,
		processRunner = processRunner,
	}
end

function Kernel.getScreenDimensions(kernel: Types.Kernel)
	local screen = kernel.terminal.currentScreen.canvas
	return screen.width * screen.cellSize, screen.height * screen.cellSize * 2
end

function Kernel.getScreenCursorPosition(kernel: Types.Kernel)
	local screen = kernel.terminal.currentScreen
	local cursor = screen.cursor
	local cellSize = screen.canvas.cellSize
	return cursor.x * cellSize, cursor.y * cellSize * 2
end

function Kernel.getActiveFramebuffer(kernel: Types.Kernel)
	return kernel.terminal.currentScreen.canvas.canvas
end

function Kernel.getNormalFramebuffer(kernel: Types.Kernel)
	return kernel.terminal.screens.normal.canvas.canvas
end

function Kernel.getAlternateFramebuffer(kernel: Types.Kernel)
	return kernel.terminal.screens.alternate.canvas.canvas
end

function Kernel.inputByte(kernel: Types.Kernel, byte: number): boolean
	local initProcess = ProcessRunner.getProcessById(kernel.processRunner, 1)

	return Stream.writeu8(initProcess.stdin, byte)
end

function Kernel.init(kernel: Types.Kernel, init_bc: string)
	local initId = ProcessRunner.spawnProcess(kernel.processRunner, init_bc, {})

	assert(initId == 1, "Init program did not have ID of 1")
end

function Kernel.runLoop(kernel: Types.Kernel): boolean
	local initProcess = ProcessRunner.getProcessById(kernel.processRunner, 1)

	ProcessRunner.runProcess(kernel.processRunner, initProcess.id)

	local byte = Stream.readu8(initProcess.stdout)
	while byte do
		Terminal.Parser.parse(kernel.terminal, byte)
		byte = Stream.readu8(initProcess.stdout)
	end

	return initProcess.state == Types.ProcessState.Dead
end

return Kernel
