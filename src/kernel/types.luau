local Terminal = require("@luau_term")
local Stream = require("./stream")

local PIPE_SIZE = 4096

export type ProcessId = number
export type InodeId = number
export type FD = number

export type DirectoryInodeType = "directory"
export type PipeInodeType = "pipe"
export type InodeType = DirectoryInodeType | PipeInodeType

export type ReadyProcessState = "ready"
export type RunningProcessState = "running"
export type BlockedReadProcessState = "blocked_read"
export type BlockedWriteProcessState = "blocked_write"
export type TerminatedProcessState = "terminated"
export type ProcessState =
	ReadyProcessState
	| RunningProcessState
	| BlockedReadProcessState
	| BlockedWriteProcessState
	| TerminatedProcessState

export type PipeData = {
	stream: Stream.Stream,
	readWaiters: { ProcessId },
	writeWaiters: { ProcessId },
}

export type DirectoryInode = {
	id: InodeId,
	type: DirectoryInodeType,
	entries: { [string]: InodeId },
}

export type PipeInode = {
	id: InodeId,
	type: PipeInodeType,
	data: PipeData,
}

export type Inode = DirectoryInode | PipeInode

export type Process = {
	pid: ProcessId,
	parentPid: ProcessId,
	thread: thread,
	luaState: any,
	state: ProcessState,
	fds: { [FD]: InodeId },
	nextFd: FD,
}

export type VFS = {
	inodes: { [InodeId]: Inode },
	nextInode: InodeId,
	rootInode: InodeId,
}

export type Kernel = {
	processes: { [ProcessId]: Process },
	processThreadLookup: { [thread]: ProcessId },
	nextPid: ProcessId,
	readyQueue: { ProcessId },
	vfs: VFS,
	syscalls: KernelSyscalls,
	terminal: Terminal.Terminal,
}

export type KernelSyscalls = {
	read: (fd: FD, buf: buffer, count: number, offset: number?) -> number,
	write: (fd: FD, buf: buffer, count: number, offset: number?) -> number,
}

local InodeType = table.freeze({
	Directory = "directory" :: DirectoryInodeType,
	Pipe = "pipe" :: PipeInodeType,
})

local ProcessState = table.freeze({
	Ready = "ready" :: ReadyProcessState,
	Running = "running" :: RunningProcessState,
	BlockedRead = "blocked_read" :: BlockedReadProcessState,
	BlockedWrite = "blocked_write" :: BlockedWriteProcessState,
	Terminated = "terminated" :: TerminatedProcessState,
})

return {
	PIPE_SIZE = PIPE_SIZE,
	InodeType = InodeType,
	ProcessState = ProcessState,
}
