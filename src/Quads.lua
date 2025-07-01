local Map = require(script.Parent.Map)
local Block = require(script.Parent.Block)
local Event = require(script.Parent.Event)

export type Quad = {
	pos: Vector3,
	size: Vector3,
	block: Block.Block,
}

export type Quads = {
	map: Map.Map,
	Quads: { Quad },

	new: (map: Map.Map) -> Quads,
	getQuads: (self: Quads) -> { Quad },
	updateBlock: (self: Quads, x: number, y: number, z: number, blockType: string?) -> nil,
	getQuadsAtY: (self: Quads, y: number) -> { Quad },
	getQuadAt: (self: Quads, x: number, y: number, z: number) -> Quad?,
	getBounds: (self: Quads) -> (Vector3, Vector3),
	countQuadsByBlockType: (self: Quads) -> { [string]: number },
	Destroy: (self: Quads) -> nil,
}

local Quads = {}
Quads.__index = Quads

function Quads.new(map: Map.Map): Quads
	local self = setmetatable({}, Quads) :: any
	self.map = map
	self.visited = {}

	self:_init()

	return self
end

function Quads:_isVisited(y: number, x: number, z: number): boolean
	return self.visited[y] and self.visited[y][x] and self.visited[y][x][z] == true
end

function Quads:_setVisited(y: number, x: number, z: number)
	self.visited[y] = self.visited[y] or {}
	self.visited[y][x] = self.visited[y][x] or {}
	self.visited[y][x][z] = true
end

function Quads:_greedyMergeLayer(y: number): { Quad }
	self.visited[y] = {} :: { [number]: { [number]: boolean } }
	local quads: { Quad } = {}

	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge

	for x, yz in self.map._map do
		for _y, zmap in yz do
			if _y == y then
				for z, _ in zmap do
					minX = math.min(minX, x)
					maxX = math.max(maxX, x)
					minZ = math.min(minZ, z)
					maxZ = math.max(maxZ, z)
				end
			end
		end
	end

	for x = minX, maxX do
		self.visited[y][x] = self.visited[y][x] or {}
	end

	for x = minX, maxX do
		for z = minZ, maxZ do
			if self:_isVisited(y, x, z) then
				continue
			end

			local blockInstance = self.map:getBlock(x, y, z)
			if not blockInstance then
				continue
			end

			local w = 1
			while true do
				local nextBlock = self.map:getBlock(x + w, y, z)
				if not nextBlock or self:_isVisited(y, x + w, z) then
					break
				end
				if nextBlock.blockType ~= blockInstance.blockType then
					break
				end
				w += 1
			end

			local h = 1
			while true do
				local canExpand = true
				for dx = 0, w - 1 do
					local nextBlock = self.map:getBlock(x + dx, y, z + h)
					if
						not nextBlock
						or nextBlock.blockType ~= blockInstance.blockType
						or self:_isVisited(y, x + dx, z + h)
					then
						canExpand = false
						break
					end
				end
				if not canExpand then
					break
				end
				h += 1
			end

			for dx = 0, w - 1 do
				for dz = 0, h - 1 do
					self:_setVisited(y, x + dx, z + dz)
				end
			end

			table.insert(quads, {
				pos = Vector3.new(x, y, z),
				size = Vector3.new(w, 1, h),
				block = blockInstance,
			})
		end
	end

	return quads
end

function Quads:_init()
	local allQuadsByLayer: { [number]: { Quad } } = {}
	local minY, maxY = math.huge, -math.huge

	for _, yz in self.map._map do
		for y, _ in yz do
			minY = math.min(minY, y)
			maxY = math.max(maxY, y)
		end
	end

	for y = minY, maxY do
		allQuadsByLayer[y] = self:_greedyMergeLayer(y)
	end

	local mergedQuads: { Quad } = {}
	local used: { [number]: { [number]: boolean } } = {}

	for y = minY, maxY do
		local layer = allQuadsByLayer[y]
		if not layer then
			continue
		end

		for i, quad in ipairs(layer) do
			if used[y] and used[y][i] then
				continue
			end

			local pos, size, block = quad.pos, quad.size, quad.block
			local height = 1
			used[y] = used[y] or {}
			used[y][i] = true

			local nextY = y + 1
			while nextY <= maxY and allQuadsByLayer[nextY] do
				local foundMatch = false
				for j, nextQuad in allQuadsByLayer[nextY] do
					if used[nextY] and used[nextY][j] then
						continue
					end

					if
						nextQuad.block.blockType == block.blockType
						and nextQuad.pos.X == pos.X
						and nextQuad.pos.Z == pos.Z
						and nextQuad.size.X == size.X
						and nextQuad.size.Z == size.Z
					then
						used[nextY] = used[nextY] or {}
						used[nextY][j] = true
						height += 1
						foundMatch = true
						break
					end
				end
				if not foundMatch then
					break
				end
				nextY += 1
			end

			table.insert(mergedQuads, {
				pos = Vector3.new(pos.X, y, pos.Z),
				size = Vector3.new(size.X, height, size.Z),
				block = block,
			})
		end
	end

	for _, quad in mergedQuads do
		quad.pos = quad.pos * self.map.VOXEL_SIZE
		quad.size = quad.size * self.map.VOXEL_SIZE
	end

	self.Quads = mergedQuads
end

function Quads:getQuads(): { Quad }
	return self.Quads
end

function Quads:updateBlock(x: number, y: number, z: number, blockType: string?)
	self.map:setBlock(x, y, z, blockType)
	self:_init()
end

function Quads:getQuadsAtY(y: number): { Quad }
	local layerQuads = {}
	for _, quad in self.Quads do
		if quad.pos.Y <= y and (quad.pos.Y + quad.size.Y - 1) >= y then
			table.insert(layerQuads, quad)
		end
	end
	return layerQuads
end

function Quads:getQuadAt(x: number, y: number, z: number): Quad?
	for _, quad in self.Quads do
		local minX, minY, minZ = quad.pos.X, quad.pos.Y, quad.pos.Z
		local maxX = minX + quad.size.X - 1
		local maxY = minY + quad.size.Y - 1
		local maxZ = minZ + quad.size.Z - 1

		if x >= minX and x <= maxX and y >= minY and y <= maxY and z >= minZ and z <= maxZ then
			return quad
		end
	end
	return nil
end

function Quads:getBounds(): (Vector3, Vector3)
	local min = Vector3.new(math.huge, math.huge, math.huge)
	local max = Vector3.new(-math.huge, -math.huge, -math.huge)

	for _, quad in self.Quads do
		local p1 = quad.pos
		local p2 = quad.pos + quad.size

		min = Vector3.new(math.min(min.X, p1.X), math.min(min.Y, p1.Y), math.min(min.Z, p1.Z))

		max = Vector3.new(math.max(max.X, p2.X), math.max(max.Y, p2.Y), math.max(max.Z, p2.Z))
	end

	return min, max
end

function Quads:countQuadsByBlockType(): { [string]: number }
	local counts = {}
	for _, quad in self.Quads do
		local blockType = quad.block.blockType
		counts[blockType] = (counts[blockType] or 0) + 1
	end
	return counts
end

function Quads:Destroy()
	self.map = nil
	self.Quads = nil
	self.visited = nil

	setmetatable(self, nil)
end

return Quads
