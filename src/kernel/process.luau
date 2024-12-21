local Types = require("./types")
local FiOne = require("@fione/source")
local Stream = require("@util/stream")

local GlobalProcessEnvironment = {
	table = table,
	string = string,
	bit32 = bit32,
	math = math,
	pairs = pairs,
	ipairs = ipairs,
}

GlobalProcessEnvironment.__index = GlobalProcessEnvironment

table.freeze(GlobalProcessEnvironment)

local ProcessRunner = {}

function ProcessRunner.create(): Types.ProcessRunner
	local processRunner: Types.ProcessRunner = {
		processCounter = 0,
		processesByThread = {},
		processesById = {},

		baseEnvironment = nil :: any,
	}

	local function getCurrentProcess(): Types.Process
		local currentThread = coroutine.running()
		local process = processRunner.processesByThread[currentThread]
		if not process then
			error("Did not find current process", 3)
		end
		return process
	end

	local ProcessEnvironment: Types.BaseProcessEnvironment = {
		write = function(str)
			if type(str) ~= "string" then
				error(`Invalid argument 1: string expected, got {type(str)}`, 2)
			end

			getCurrentProcess().stdout:write(buffer.fromstring(str))
		end,
	}
	local ProcessRunnerEnvironment: any = setmetatable(ProcessEnvironment, GlobalProcessEnvironment)

	ProcessRunnerEnvironment.__index = ProcessRunnerEnvironment

	table.freeze(ProcessRunnerEnvironment)

	processRunner.baseEnvironment = ProcessRunnerEnvironment :: Types.BaseProcessEnvironment

	return processRunner
end

function ProcessRunner.spawnProcess(runner: Types.ProcessRunner, bytecode: string, args: { string }): number
	local luaState = FiOne.bc_to_state(bytecode)
	local processEnvironment = setmetatable({}, runner.baseEnvironment)
	local wrappedProcess = FiOne.wrap_state(luaState :: any, processEnvironment :: any, {}) :: (...any) -> ...any

	runner.processCounter += 1

	local process: Types.Process = {
		id = runner.processCounter,
		luaState = luaState,
		thread = coroutine.create(wrappedProcess),
		stdin = Stream.createStream(),
		stdout = Stream.createStream(),
	}

	runner.processesById[process.id] = process
	runner.processesByThread[process.thread] = process

	return process.id
end

function ProcessRunner.getProcessById(runner: Types.ProcessRunner, id: number): Types.Process
	local process = runner.processesById[id]
	assert(process, `Process ID {id} not found`)
	return process
end

function ProcessRunner.runProcess(runner: Types.ProcessRunner, processId: number): (boolean, boolean, any)
	local process = runner.processesById[processId]
	assert(process, `Process ID {processId} not found`)

	local thread = process.thread
	local noErrors, result = coroutine.resume(thread)
	local finished = coroutine.status(thread) == "dead"

	return finished, noErrors, result
end

return ProcessRunner
