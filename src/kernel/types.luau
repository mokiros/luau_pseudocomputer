local Terminal = require("@luau_term")
local Stream = require("@util/stream")

export type BaseProcessEnvironment = {
	write: (str: string) -> (),
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

export type Process = {
	id: number,
	luaState: any,
	thread: thread,
	stdin: Stream.Stream,
	stdout: Stream.Stream,
}

return {}
