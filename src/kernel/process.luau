local Types = require("./types")
local FiOne = require("@fione/source")
local Stream = require("@util/stream")

local GlobalProcessEnvironment = {
	table = table,
	string = string,
	buffer = buffer,
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

	local ProcessEnvironment: Types.BaseProcessEnvironment = {
		write = function(buf, count, offset)
			local process = ProcessRunner.getCurrentProcess(processRunner)

			local bytesToWrite = count
			while bytesToWrite > 0 do
				local writtenBytes = Stream.write(process.stdout, buf, count, offset or 0 + count - bytesToWrite)
				if writtenBytes == 0 then
					coroutine.yield()
				else
					bytesToWrite -= writtenBytes
				end
			end

			return count
		end,

		read = function(buf, count, offset)
			local process = ProcessRunner.getCurrentProcess(processRunner)

			local bytesToRead = count
			while bytesToRead > 0 do
				local readBytes = Stream.read(process.stdin, buf, count, offset or 0 + count - bytesToRead)
				if readBytes == 0 then
					coroutine.yield()
				else
					bytesToRead -= readBytes
				end
			end

			return count
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
		state = Types.ProcessState.Running,
		exitCode = 0,
		luaState = luaState,
		thread = coroutine.create(wrappedProcess),
		stdin = Stream.new(4096),
		stdout = Stream.new(4096),
	}

	runner.processesById[process.id] = process
	runner.processesByThread[process.thread] = process

	return process.id
end

function ProcessRunner.getCurrentProcess(runner: Types.ProcessRunner): Types.Process
	local currentThread = coroutine.running()
	local process = runner.processesByThread[currentThread]
	if not process then
		error("Did not find current process", 3)
	end
	return process
end

function ProcessRunner.getProcessById(runner: Types.ProcessRunner, id: number): Types.Process
	local process = runner.processesById[id]
	assert(process, `Process ID {id} not found`)
	return process
end

function ProcessRunner.runProcess(runner: Types.ProcessRunner, processId: number): ()
	local process = runner.processesById[processId]
	assert(process, `Process ID {processId} not found`)

	if process.state == Types.ProcessState.Dead then
		error("Tried to run a Dead process")
	end

	process.state = Types.ProcessState.Running

	local thread = process.thread
	local noErrors, result = coroutine.resume(thread)
	local finished = coroutine.status(thread) == "dead"

	if finished then
		process.state = Types.ProcessState.Dead
		if noErrors then
			if typeof(result) == "number" then
				process.exitCode = result
			else
				if result ~= nil then
					warn("Process returned invalid type: " .. typeof(result))
				end
				process.exitCode = 0
			end
		else
			warn("Process exited with error: " .. result)
			process.exitCode = 1
		end
	else
		process.state = Types.ProcessState.Suspended
	end
end

return ProcessRunner
