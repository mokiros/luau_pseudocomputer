local Terminal = require("@luau_term")
local FiOne = require("@fione")
local Types = require("./types")
local Common = require("./common")
local VFS = require("./vfs")

local Kernel = {}

local GlobalProcessEnvironment = {
	table = table,
	string = string,
	buffer = buffer,
	bit32 = bit32,
	math = math,
	pairs = pairs,
	ipairs = ipairs,
	pcall = pcall,
	assert = assert,
}
GlobalProcessEnvironment.__index = GlobalProcessEnvironment
table.freeze(GlobalProcessEnvironment)

type KernelConfig = {
	screen_width: number,
	screen_height: number,
	font_data: string?,
}

function Kernel.new(config: KernelConfig): Types.Kernel
	assert(config.screen_width % 8 == 0, "Screen width must be divisible by 8")
	assert(config.screen_height % 16 == 0, "Screen height must be divisible by 16")

	local fontData = config.font_data and Terminal.parseUnifont(config.font_data)

	local kernel: Types.Kernel = {
		processes = {},
		processThreadLookup = {},
		nextPid = 1,
		readyQueue = {},
		vfs = {
			inodes = {},
			nextInode = 1,
			rootInode = -1,
		},
		syscalls = {} :: Types.KernelSyscalls,
		terminal = Terminal.createTerminal(config.screen_width / 8, config.screen_height / 16, fontData),
	}

	kernel.terminal.options.convertEol = true

	local function getRunningProcess(): Types.Process
		local thread = coroutine.running()
		local processId = kernel.processThreadLookup[thread]
		return assert(processId and kernel.processes[processId], "No running process")
	end

	function kernel.syscalls.read(fd, buf, count, offset)
		assert(typeof(fd) == "number", `Invalid argument #1 to 'read' (number expected, got {typeof(fd)})`)
		assert(typeof(buf) == "buffer", `Invalid argument #2 to 'read' (buffer expected, got {typeof(buf)})`)
		assert(typeof(count) == "number", `Invalid argument #3 to 'read' (number expected, got {typeof(count)})`)
		assert(
			not offset or typeof(offset) == "number",
			`Invalid argument #4 to 'read' (number expected, got {typeof(offset)})`
		)
		local process = getRunningProcess()
		local pid = process.pid
		local inode = Common.getInodeFromFd(kernel, pid, fd)
		local currentOffset = offset or 0
		local currentCount = count

		while currentCount > 0 do
			local bytesProcessed = VFS.read(kernel, pid, fd, buf, currentCount, currentOffset)
			currentOffset += bytesProcessed
			currentCount -= bytesProcessed
			if bytesProcessed == 0 then
				if inode.type == Types.InodeType.Pipe then
					table.insert(inode.data.readWaiters, pid)
					coroutine.yield(Types.ProcessState.BlockedRead)
				else
					error("Error reading")
				end
			end
		end

		return count - currentCount
	end

	function kernel.syscalls.write(fd, buf, count, offset)
		assert(typeof(fd) == "number", `Invalid argument #1 to 'write' (number expected, got {typeof(fd)})`)
		assert(typeof(buf) == "buffer", `Invalid argument #2 to 'write' (buffer expected, got {typeof(buf)})`)
		assert(typeof(count) == "number", `Invalid argument #3 to 'write' (number expected, got {typeof(count)})`)
		assert(
			not offset or typeof(offset) == "number",
			`Invalid argument #4 to 'write' (number expected, got {typeof(offset)})`
		)
		local process = getRunningProcess()
		local pid = process.pid
		local inode = Common.getInodeFromFd(kernel, pid, fd)
		local currentOffset = offset or 0
		local currentCount = count

		while currentCount > 0 do
			local bytesProcessed = VFS.write(kernel, pid, fd, buf, currentCount, currentOffset)
			currentOffset += bytesProcessed
			currentCount -= bytesProcessed
			if bytesProcessed == 0 then
				if inode.type == Types.InodeType.Pipe then
					table.insert(inode.data.writeWaiters, pid)
					coroutine.yield(Types.ProcessState.BlockedWrite)
				else
					error("Error writing")
				end
			end
		end

		return count - currentCount
	end

	local syscalls: any = kernel.syscalls
	syscalls.__index = syscalls
	setmetatable(syscalls, GlobalProcessEnvironment)

	local rootInode = Common.createDirectoryInode()
	kernel.vfs.rootInode = Common.allocateInode(kernel, rootInode)

	VFS.create(kernel, "/pipes", Common.createDirectoryInode())

	return kernel
end

function Kernel.getScreenDimensions(kernel: Types.Kernel): (number, number)
	local screen = kernel.terminal.currentScreen.canvas
	return screen.width * screen.cellSize, screen.height * screen.cellSize * 2
end

function Kernel.getScreenCursorPosition(kernel: Types.Kernel): (number, number)
	local screen = kernel.terminal.currentScreen
	local cursor = screen.cursor
	local cellSize = screen.canvas.cellSize
	return cursor.x * cellSize, cursor.y * cellSize * 2
end

function Kernel.getActiveFramebuffer(kernel: Types.Kernel): buffer
	return kernel.terminal.currentScreen.canvas.canvas
end

function Kernel.getNormalFramebuffer(kernel: Types.Kernel): buffer
	return kernel.terminal.screens.normal.canvas.canvas
end

function Kernel.getAlternateFramebuffer(kernel: Types.Kernel): buffer
	return kernel.terminal.screens.alternate.canvas.canvas
end

function Kernel.inputByte(kernel: Types.Kernel, byte: number): boolean
	return VFS.writeu8(kernel, 1, 1, byte)
end

function Kernel.spawn(kernel: Types.Kernel, bytecode: string): Types.ProcessId
	local pid = kernel.nextPid
	kernel.nextPid += 1

	local programEnvironment: any = setmetatable({}, kernel.syscalls)

	local programState: any = FiOne.bc_to_state(bytecode)
	local program = FiOne.wrap_state(programState, programEnvironment, {})

	local process: Types.Process = {
		pid = pid,
		parentPid = -1,
		thread = coroutine.create(program),
		luaState = programState,
		state = Types.ProcessState.Ready,
		fds = {},
		nextFd = 1,
	}

	kernel.processes[pid] = process
	kernel.processThreadLookup[process.thread] = pid

	Common.allocateFd(kernel, pid, VFS.create(kernel, `/pipes/stdin_{pid}`, Common.createPipeInode()))
	Common.allocateFd(kernel, pid, VFS.create(kernel, `/pipes/stdout_{pid}`, Common.createPipeInode()))

	table.insert(kernel.readyQueue, pid)

	return pid
end

local function consumeStdoutForTerminal(kernel: Types.Kernel)
	local byte = VFS.readu8(kernel, 1, 2)
	while byte do
		Terminal.Parser.parse(kernel.terminal, byte)
		byte = VFS.readu8(kernel, 1, 2)
	end
end

function Kernel.step(kernel: Types.Kernel)
	for i = 1, 10 do
		local pid = table.remove(kernel.readyQueue, 1)
		if not pid then
			break
		end
		local process = kernel.processes[pid]
		if process.state == Types.ProcessState.Ready then
			process.state = Types.ProcessState.Running

			local status, result = coroutine.resume(process.thread)

			if not status then
				warn(`Process {pid} crashed: {tostring(result)}`)
				process.state = Types.ProcessState.Terminated
			elseif coroutine.status(process.thread) == "dead" then
				process.state = Types.ProcessState.Terminated
			else
				if result ~= Types.ProcessState.BlockedRead and result ~= Types.ProcessState.BlockedWrite then
					error(`Process returned invalid yield result: {tostring(result)}`)
				end
				process.state = result
			end
		end
	end

	consumeStdoutForTerminal(kernel)

	return true
end

return Kernel
