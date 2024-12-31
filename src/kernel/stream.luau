--- Circular (FIFO) buffer implementation
export type Stream = {
	buf: buffer,
	size: number,
	startPos: number,
	endPos: number,
}

local Stream = {}

function Stream.new(size: number): Stream
	local stream = {
		buf = buffer.create(size),
		size = size,
		startPos = 0,
		endPos = 0,
	}

	return stream
end

--- Reads from stream `count` bytes and writes to the specified buffer `buf` at the offset `offset`.
--- Returns the amount of bytes actually read and written to `buf`
function Stream.read(stream: Stream, buf: buffer, count: number, offset: number): number
	local bytesToRead = (stream.endPos - stream.startPos) % stream.size
	if bytesToRead == 0 then
		return 0
	elseif bytesToRead > count then
		bytesToRead = count
	end
	local endPos = (stream.startPos + bytesToRead) % stream.size
	if stream.startPos > endPos then
		local bytesToEnd = stream.size - stream.startPos
		buffer.copy(buf, offset, stream.buf, stream.startPos, bytesToEnd)
		if endPos > 0 then
			buffer.copy(buf, offset + bytesToEnd, stream.buf, 0, endPos)
		end
	else
		buffer.copy(buf, offset, stream.buf, stream.startPos, bytesToRead)
	end

	stream.startPos = endPos

	return bytesToRead
end

--- Writes to the stream `count` bytes from specified buffer `buf` at the offset `offset`.
--- Returns the amount of bytes actually written to the stream
function Stream.write(stream: Stream, buf: buffer, count: number, offset: number): number
	local bytesToWrite = stream.size - (stream.endPos - stream.startPos) % stream.size - 1
	if bytesToWrite == 0 then
		return 0
	elseif bytesToWrite > count then
		bytesToWrite = count
	end
	local endPos = (stream.endPos + bytesToWrite) % stream.size
	if stream.endPos > endPos then
		local bytesToEnd = stream.size - stream.endPos
		buffer.copy(stream.buf, stream.endPos, buf, offset, bytesToEnd)
		if endPos > 0 then
			buffer.copy(stream.buf, 0, buf, offset + bytesToEnd, endPos)
		end
	else
		buffer.copy(stream.buf, stream.endPos, buf, offset, bytesToWrite)
	end

	stream.endPos = endPos

	return bytesToWrite
end

function Stream.readu8(stream: Stream): number?
	if stream.startPos == stream.endPos then
		return nil
	end
	local n = buffer.readu8(stream.buf, stream.startPos)
	stream.startPos = (stream.startPos + 1) % stream.size
	return n
end

function Stream.writeu8(stream: Stream, byte: number): boolean
	if (stream.endPos + 1) % stream.size == stream.startPos then
		return false
	end
	buffer.writeu8(stream.buf, stream.endPos, byte)
	stream.endPos = (stream.endPos + 1) % stream.size
	return true
end

return Stream
