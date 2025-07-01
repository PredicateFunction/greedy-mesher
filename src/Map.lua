local HttpService = game:GetService("HttpService")

local Event = require(script.Parent.Event)
local Block = require(script.Parent.Block)
local Serialize = require(script.Parent.Serialize)

export type BlockType = string
export type BlockInstance = Block.Block
export type EventInstance = Event.Event

export type GeneratedMap = {

	setBlock: (self, x: number, y: number, z: number, blockType: BlockType) -> (),
	convertToGridVector3: (self, worldPosition: Vector3) -> Vector3,
	convertToGridXYZ: (self, worldX: number, worldY: number, worldZ: number) -> (number, number, number),
	getBlock: (self, x: number, y: number, z: number) -> BlockInstance?,
	getBlockFromWorld: (self, worldPosition: Vector3) -> BlockInstance?,
	getNeighbors: (
		self,
		x: number,
		y: number,
		z: number
	) -> { { x: number, y: number, z: number, block: BlockInstance? } },
	isOccupied: (self, x: number, y: number, z: number) -> boolean,
	gridToWorldPosition: (self, x: number, y: number, z: number) -> Vector3,
	getAllBlocks: (self) -> { { x: number, y: number, z: number, type: BlockType } },
	serialize: (self) -> string,
	Destroy: (self) -> (),
}

export type MapConstructor = {

	blockTypeGetter: (self, fn: (Instance) -> BlockType?) -> (),
	Generate: (self) -> GeneratedMap,
}

export type Map = {
	new: (parts: { Instance }, VOXEL_SIZE: Vector3) -> MapConstructor,
	fromSerialized: (serialized: string) -> GeneratedMap,
}

local function roundToVoxel(n: number, size: number): number
	return math.floor(n / size)
end

local GeneratedMap = {}
GeneratedMap.__index = GeneratedMap

function GeneratedMap:new(): GeneratedMap
	local self = setmetatable({}, GeneratedMap)
	self:_init()
	return self
end

function GeneratedMap:_init(): nil
	self._map = {}

	for _, part in self.parts or {} do
		if not part:IsA("BasePart") then
			continue
		end

		local blockType = self._blockTypeGetter(part)
		if not blockType then
			warn("Applying 'Neutral' block type to ", part)
			blockType = "Neutral"
		end

		local size = part.Size
		local steps = Vector3.new(
			roundToVoxel(size.X, self.VOXEL_SIZE.X),
			roundToVoxel(size.Y, self.VOXEL_SIZE.Y),
			roundToVoxel(size.Z, self.VOXEL_SIZE.Z)
		)

		local basePos = part.Position
		local half = Vector3.new(steps.X - 1, steps.Y - 1, steps.Z - 1) * 0.5 * self.VOXEL_SIZE

		for x = 0, steps.X - 1 do
			for y = 0, steps.Y - 1 do
				for z = 0, steps.Z - 1 do
					local offset = Vector3.new(x + 0.5, y + 0.5, z + 0.5) * self.VOXEL_SIZE
					local worldPos = basePos - half + offset
					local gridX = roundToVoxel(worldPos.X, self.VOXEL_SIZE.X)
					local gridY = roundToVoxel(worldPos.Y, self.VOXEL_SIZE.Y)
					local gridZ = roundToVoxel(worldPos.Z, self.VOXEL_SIZE.Z)

					self:setBlock(gridX, gridY, gridZ, blockType)
				end
			end
		end
	end
end

function GeneratedMap:setBlock(x: number, y: number, z: number, blockType: BlockType): ()
	self._map[x] = self._map[x] or {}
	self._map[x][y] = self._map[x][y] or {}

	local existingBlock = self._map[x][y][z]
	if existingBlock and existingBlock.blockType == blockType then
		return
	elseif existingBlock then
		existingBlock:Destroy()
	end

	local block = Block.new(blockType, self, x, y, z)
	self._map[x][y][z] = block
end

function GeneratedMap:convertToGridVector3(worldPosition: Vector3): Vector3
	local x = roundToVoxel(worldPosition.X, self.VOXEL_SIZE.X)
	local y = roundToVoxel(worldPosition.Y, self.VOXEL_SIZE.Y)
	local z = roundToVoxel(worldPosition.Z, self.VOXEL_SIZE.Z)
	return Vector3.new(x, y, z)
end

function GeneratedMap:convertToGridXYZ(worldX: number, worldY: number, worldZ: number): (number, number, number)
	local x = roundToVoxel(worldX, self.VOXEL_SIZE.X)
	local y = roundToVoxel(worldY, self.VOXEL_SIZE.Y)
	local z = roundToVoxel(worldZ, self.VOXEL_SIZE.Z)
	return x, y, z
end

function GeneratedMap:getBlock(x: number, y: number, z: number): BlockInstance?
	return self._map[x] and self._map[x][y] and self._map[x][y][z] or nil
end

function GeneratedMap:getBlockFromWorld(worldPosition: Vector3): BlockInstance?
	local x, y, z = self:convertToGridXYZ(worldPosition.X, worldPosition.Y, worldPosition.Z)
	return self:getBlock(x, y, z)
end

function GeneratedMap:getNeighbors(
	x: number,
	y: number,
	z: number
): { { x: number, y: number, z: number, block: BlockInstance? } }
	local neighbors = {}
	for _, offset in
		{
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 1, 0),
			Vector3.new(0, -1, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
		}
	do
		local nx, ny, nz = x + offset.X, y + offset.Y, z + offset.Z
		table.insert(neighbors, {
			x = nx,
			y = ny,
			z = nz,
			block = self:getBlock(nx, ny, nz),
		})
	end
	return neighbors
end

function GeneratedMap:isOccupied(x: number, y: number, z: number): boolean
	return self:getBlock(x, y, z) ~= nil
end

function GeneratedMap:gridToWorldPosition(x: number, y: number, z: number): Vector3
	return Vector3.new(x * self.VOXEL_SIZE.X, y * self.VOXEL_SIZE.Y, z * self.VOXEL_SIZE.Z)
end

function GeneratedMap:getAllBlocks(): { { x: number, y: number, z: number, type: BlockType } }
	local blocks = {}
	for x, yz in pairs(self._map) do
		for y, zTable in pairs(yz) do
			for z, block in pairs(zTable) do
				table.insert(blocks, { x = x, y = y, z = z, type = block.blockType })
			end
		end
	end
	return blocks
end

function GeneratedMap:serialize(): string
	local t = {}

	t.VOXEL_SIZE = tostring(self.VOXEL_SIZE)
	t._map = {}
	for x, yzTable in self._map do
		t._map[x] = {}
		for y, zTable in yzTable do
			t._map[x][y] = {}
			for z, block in zTable do
				t._map[x][y][z] = {
					blockType = block.blockType,
					gridPos = { block:getGridPosition() },
					worldPos = block:getWorldPosition(),
				}
			end
		end
	end

	return Serialize.Serialize(t)
end

function GeneratedMap:Destroy(): ()
	if not self._map then
		return
	end

	for x, yz in pairs(self._map) do
		for y, zTable in pairs(yz) do
			for z, block in pairs(zTable) do
				if block and typeof(block.Destroy) == "function" then
					block:Destroy()
				end
				zTable[z] = nil
			end
			yz[y] = nil
		end
		self._map[x] = nil
	end
	self._map = nil

	self.parts = nil
	self._blockTypeGetter = nil
	setmetatable(self, nil)
end

local MapConstructor = {}
MapConstructor.__index = MapConstructor

function MapConstructor:blockTypeGetter(fn: (Instance) -> BlockType?): ()
	if typeof(fn) ~= "function" then
		error("Expected function as argument to blockTypeGetter")
	end

	self._blockTypeGetter = fn
end

function MapConstructor:Generate(): GeneratedMap
	local generated = setmetatable({}, GeneratedMap)

	generated.parts = self.parts
	generated.VOXEL_SIZE = self.VOXEL_SIZE or Vector3.new(1, 1, 1)
	generated._blockTypeGetter = self._blockTypeGetter or function(part)
		return part.Name
	end

	generated:_init()
	return generated
end

local Map = {}
Map.__index = Map

function Map.new(parts: { Instance }, VOXEL_SIZE: Vector3): MapConstructor
	local self = setmetatable({}, MapConstructor)
	self.parts = parts
	self.VOXEL_SIZE = VOXEL_SIZE
	self._blockTypeGetter = function(part: Instance): BlockType
		return part.Name
	end
	return self
end

function Map.fromSerialized(serialized: string): GeneratedMap
	local self = setmetatable({}, GeneratedMap)
	local deserializedMap = Serialize.Deserialize(serialized)

	if type(deserializedMap) ~= "table" then
		error("Failed to deserialize Map: invalid format")
	end

	self._map = {}

	for x, yz in (deserializedMap._map or {}) do
		self._map[x] = {}
		for y, zTable in yz do
			self._map[x][y] = {}
			for z, block in zTable do
				local blockType = block.blockType
				local gridPos = block.gridPos
				local block = Block.new(blockType, self, gridPos[1], gridPos[2], gridPos[3])
				self._map[x][y][z] = block
			end
		end
	end

	local voxelStr = deserializedMap.VOXEL_SIZE or "1, 1, 1"
	local x, y, z = voxelStr:match("([^,]+),%s*([^,]+),%s*([^,]+)")
	self.VOXEL_SIZE = Vector3.new(x, y, z)

	return self
end

return Map
