local Types = require("./types")
local Common = require("./common")
local Stream = require("./stream")

local VFS = {}

function VFS.create(kernel: Types.Kernel, path: string, inode: Types.Inode): Types.InodeId
	local parentPath, filename = string.match(path, "^(.*)/([^/]*)")
	assert(parentPath and filename and filename ~= "", "Invalid path")
	local parentInode = Common.resolvePath(kernel, parentPath)

	assert(parentInode and parentInode.type == Types.InodeType.Directory, "Invalid path")

	local inodeId = Common.allocateInode(kernel, inode)
	parentInode.entries[filename] = inodeId
	return inode.id
end

function VFS.open(kernel: Types.Kernel, pid: Types.ProcessId, path: string): Types.InodeId
	local inode = Common.resolvePath(kernel, path)
	return assert(inode and Common.allocateFd(kernel, pid, inode.id), "File not found")
end

function VFS.read(
	kernel: Types.Kernel,
	pid: Types.ProcessId,
	fd: Types.FD,
	buf: buffer,
	count: number,
	offset: number
): number
	local inode = Common.getInodeFromFd(kernel, pid, fd)
	if inode.type == Types.InodeType.Pipe then
		local pipeData = inode.data
		local bytesRead = Stream.read(pipeData.stream, buf, count, offset)
		if #pipeData.writeWaiters ~= 0 then
			Common.wakeProcesses(kernel, pipeData.writeWaiters)
		end
		return bytesRead
	end

	error("Read operation not supported for this file descriptor")
end

function VFS.readu8(kernel: Types.Kernel, pid: Types.ProcessId, fd: Types.FD): number?
	local inode = Common.getInodeFromFd(kernel, pid, fd)
	if inode.type == Types.InodeType.Pipe then
		local pipeData = inode.data
		local byte = Stream.readu8(pipeData.stream)
		if #pipeData.writeWaiters ~= 0 then
			Common.wakeProcesses(kernel, pipeData.writeWaiters)
		end
		return byte
	end

	error("Read operation not supported for this file descriptor")
end

function VFS.write(
	kernel: Types.Kernel,
	pid: Types.ProcessId,
	fd: Types.FD,
	buf: buffer,
	count: number,
	offset: number
): number
	local inode = Common.getInodeFromFd(kernel, pid, fd)
	if inode.type == Types.InodeType.Pipe then
		local pipeData = inode.data
		local bytesWritten = Stream.write(pipeData.stream, buf, count, offset)
		if #pipeData.readWaiters ~= 0 then
			Common.wakeProcesses(kernel, pipeData.readWaiters)
		end
		return bytesWritten
	end

	error("Write operation not supported for this file descriptor")
end

function VFS.writeu8(kernel: Types.Kernel, pid: Types.ProcessId, fd: Types.FD, u8: number): boolean
	local inode = Common.getInodeFromFd(kernel, pid, fd)
	if inode.type == Types.InodeType.Pipe then
		local pipeData = inode.data
		local result = Stream.writeu8(pipeData.stream, u8)
		if #pipeData.readWaiters ~= 0 then
			Common.wakeProcesses(kernel, pipeData.readWaiters)
		end
		return result
	end

	error("Write operation not supported for this file descriptor")
end

function VFS.vfsClose(kernel: Types.Kernel, pid: Types.ProcessId, fd: Types.FD): ()
	Common.releaseFd(kernel, pid, fd)
end

return VFS
