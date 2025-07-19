local threads: { thread } = {}

type Connection = {
	Function: (...any) -> (),
	Next: Connection?,
	Previous: Connection?,
	Parallel: boolean?,
	Disconnect: () -> (),
}
local Connection = {}
Connection.__index = Connection
Connection.IsConnected = true

function Connection:Disconnect(): ()
	self.Previous.Next = self.Next
	if self.Next ~= nil then
		self.Next.Previous = self.Previous
	end

	self.IsConnected = false
end

export type Event = {
	Connect: (self: Event, func: (...any) -> ()) -> Connection,
	Once: (self: Event, func: (...any) -> ()) -> Connection,
	Wait: (self: Event) -> ...any,
	ConnectParallel: (self: Event, func: (...any) -> ()) -> Connection,
	Fire: (self: Event, ...any) -> (),
	Destroy: (self: Event) -> (),
}

local Event = {}
Event.__index = Event
Event.__tostring = function(): string
	return "EVENT"
end

function Thread(func: (...any) -> (), ...: any): ()
	func(...)
	while true do
		table.insert(threads, coroutine.running())
		Call(coroutine.yield())
	end
end

function Call(func: (...any) -> (), ...: any): ()
	func(...)
end

function Event.new(): Event
	return setmetatable({}, Event)
end

function Event:Connect(func: (...any) -> ()): Connection
	local connection: Connection = { Function = func, Next = self.Next, Previous = self }
	if self.Next ~= nil then
		self.Next.Previous = connection
	end
	self.Next = connection
	return setmetatable(connection, Connection)
end

function Event:Once(func: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...: any)
		connection:Disconnect()
		func(...)
	end)
	return connection
end

function Event:Wait(): ...any
	local thread = coroutine.running()
	local connection: Connection
	connection = self:Connect(function(...: any)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Event:ConnectParallel(func: (...any) -> ()): Connection
	local connection: Connection = { Function = func, Next = self.Next, Previous = self, Parallel = true }
	if self.Next ~= nil then
		self.Next.Previous = connection
	end
	self.Next = connection
	return setmetatable(connection, Connection)
end

function Event:Fire(...: any): ()
	local link = self.Next
	while link do
		if link.Parallel then
			task.spawn(link.Function, ...)
		else
			task.spawn(table.remove(threads) or Thread, link.Function, ...)
		end
		link = link.Next
	end
end

function Event:Destroy(): ()
	setmetatable(self, nil)
end

return Event
