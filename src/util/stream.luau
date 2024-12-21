type IStream = {
	reader: (buf: buffer) -> (),
}

type StreamImpl = {
	__index: StreamImpl,
	write: (self: Stream, buf: buffer) -> (),
}

export type Stream = typeof(setmetatable({} :: IStream, {} :: StreamImpl))

local StreamMT = {} :: StreamImpl

StreamMT.__index = StreamMT

function StreamMT:write(buf: buffer)
	self.reader(buf)
end

local function noop() end

local function createStream(): Stream
	return (setmetatable({
		reader = noop,
	}, StreamMT) :: any) :: Stream
end

return {
	createStream = createStream,
}
