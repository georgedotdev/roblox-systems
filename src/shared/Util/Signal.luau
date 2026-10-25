--!strict
--[[
	Signal
	Minimal synchronous signal for server-side service events.
	Handlers run in order on the firing thread, so a handler that writes to
	Profile.Data inside DataService.Saving is guaranteed to save.
	Handlers must not yield.
]]

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new<T...>(): Signal<T...>
	return setmetatable({ _handlers = {} }, Signal) :: any
end

function Signal.Connect(self: any, handler)
	local connection = { Connected = true }
	self._handlers[connection] = handler
	function connection.Disconnect(conn)
		conn.Connected = false
		self._handlers[conn] = nil
	end
	return connection :: any
end

function Signal.Fire(self: any, ...)
	-- Copy first, so a handler may disconnect itself during Fire.
	local handlers = table.clone(self._handlers)
	for _, handler in handlers do
		local ok, err = pcall(handler, ...)
		if not ok then
			warn(`[Signal] handler error: {err}`)
		end
	end
end

function Signal.DisconnectAll(self: any)
	for connection in self._handlers do
		connection.Connected = false
	end
	table.clear(self._handlers)
end

return Signal
