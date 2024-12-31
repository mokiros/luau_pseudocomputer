local Types = require("./types")
local Stream = require("./stream")

local Common = {}

function Common.getInode(kernel: Types.Kernel, inodeId: Types.InodeId): Types.Inode
	return assert(kernel.vfs.inodes[inodeId], `Tried to get non-allocated inode id: {inodeId}`)
end

function Common.getProcess(kernel: Types.Kernel, pid: Types.ProcessId): Types.Process
	return assert(kernel.processes[pid], `Tried to get non-allocated process id: {pid}`)
end

function Common.getInodeFromFd(kernel: Types.Kernel, pid: Types.ProcessId, fd: Types.FD): Types.Inode
	local inodeId = Common.getProcess(kernel, pid).fds[fd]
	return assert(inodeId and Common.getInode(kernel, inodeId), `Process's fd {fd} points to incorrect inode {inodeId}`)
end

function Common.allocateInode(kernel: Types.Kernel, inode: Types.Inode): Types.InodeId
	assert(kernel.vfs.inodes[inode.id] == nil, `Inode {inode.id} is already allocated`)
	local inodeId = kernel.vfs.nextInode
	kernel.vfs.nextInode += 1
	(inode :: any).id = inodeId
	kernel.vfs.inodes[inodeId] = inode

	return inodeId
end

function Common.allocateFd(kernel: Types.Kernel, pid: Types.ProcessId, inodeId: Types.InodeId): Types.FD
	local process = Common.getProcess(kernel, pid)
	local fd = process.nextFd
	process.nextFd += 1
	process.fds[fd] = inodeId
	return fd
end

function Common.releaseFd(kernel: Types.Kernel, pid: Types.ProcessId, fd: Types.FD): ()
	local process = Common.getProcess(kernel, pid)
	process.fds[fd] = nil
end

function Common.createPipeInode(): Types.PipeInode
	return  {
		id = -1,
		type = Types.InodeType.Pipe,
		data = {
			stream = Stream.new(Types.PIPE_SIZE),
			readWaiters = {},
			writeWaiters = {},
		},
	}
end

function Common.createDirectoryInode(): Types.DirectoryInode
	return {
		id = -1,
		type = Types.InodeType.Directory,
		entries = {},
	}
end

function Common.resolvePath(kernel: Types.Kernel, path: string): Types.Inode?
	local currentEntry = kernel.vfs.inodes[kernel.vfs.rootInode]
	for i, name in string.split(path, "/") do
		if i == 1 then
			assert(name == "", "Path must start with /")
			continue
		end
		if currentEntry.type ~= Types.InodeType.Directory then
			return nil
		end
		local entry = currentEntry.entries[name]
		if not entry then
			return nil
		end
		currentEntry = Common.getInode(kernel, entry)
	end
	return currentEntry
end

function Common.wakeProcesses(kernel: Types.Kernel, waiters: { Types.ProcessId }): ()
	for _, pid in waiters do
		local process = Common.getProcess(kernel, pid)
		process.state = Types.ProcessState.Ready
		table.insert(kernel.readyQueue, pid)
	end
	table.clear(waiters)
end

return Common
