local getUnifont = Instance.new("RemoteFunction")
getUnifont.Name = "GetFont"
getUnifont.Parent = script.client

local cachedUnifont: string? = nil

getUnifont.OnServerInvoke = function(plr)
	if cachedUnifont then
		return cachedUnifont
	end

	local unifont = game:GetService("HttpService"):GetAsync(
		"https://gist.githubusercontent.com/mokiros/b55a8a64ac100fe737450343f5ef3d85/raw/6835baa97d7cbb7431fb05faa6d41269c3c929b8/unifont-15.1.04.hex"
	)
	cachedUnifont = unifont

	return unifont
end
