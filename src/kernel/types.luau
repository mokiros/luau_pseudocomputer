local Terminal = require("@luau_term")
local Stream = require("@util/stream")

export type BaseProcessEnvironment = {
	write: (buf: buffer, count: number, offset: number?) -> number,
	read: (buf: buffer, count: number, offset: number?) -> number,
}

export type ProcessRunner = {
	processCounter: number,
	processesByThread: {
		[thread]: Process,
	},
	processesById: {
		[number]: Process,
	},
	baseEnvironment: BaseProcessEnvironment,
}

export type Kernel = {
	terminal: Terminal.Terminal,
	processRunner: ProcessRunner,
}

type RunningProcessState = "Running"
type SuspendedProcessState = "Suspended"
type DeadProcessState = "Dead"
export type ProcessState = RunningProcessState | SuspendedProcessState | DeadProcessState

export type Process = {
	id: number,
	state: ProcessState,
	exitCode: number,
	luaState: any,
	thread: thread,
	stdin: Stream.Stream,
	stdout: Stream.Stream,
}

local ProcessState = table.freeze({
	Running = "Running" :: RunningProcessState,
	Suspended = "Suspended" :: SuspendedProcessState,
	Dead = "Dead" :: DeadProcessState,
})

return {
	ProcessState = ProcessState,
}
