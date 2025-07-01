local Event = require(script.Parent.Event)

type Vector3 = { X: number, Y: number, Z: number }

export type Block = {
	blockType: string,
	gridXYZ: { number },
	size: number,

	Destroying: Event.Event,

	getGridPosition: (self: Block) -> (number, number, number),
	getWorldPosition: (self: Block) -> Vector3,
	getNeighbors: (self: Block) -> { Block },
	Destroy: (self: Block) -> (),
	__tostring: (self: Block) -> string,
}

local Block = {}
Block.__index = Block
Block.__tostring = Block.__tostring

function Block.new(blockType: string, map: any, x: number, y: number, z: number): Block
	local self = setmetatable({}, Block)
	self._map = map
	self.blockType = blockType
	self.gridXYZ = { x, y, z }
	self.size = map.VOXEL_SIZE

	self.Destroying = Event.new()

	return self
end

function Block.fromGridPosition(x: number, y: number, z: number, map: any): Block?
	return map:getBlock(x, y, z)
end

function Block.fromWorldPosition(worldPosition: Vector3, map: any): Block?
	local x, y, z = map:convertToGridXYZ(worldPosition.X, worldPosition.Y, worldPosition.Z)
	return Block.fromGridPosition(x, y, z, map)
end

function Block:getGridPosition(): (number, number, number)
	return table.unpack(self.gridXYZ)
end

function Block:getWorldPosition(): Vector3
	return self._map:gridToWorldPosition(self:getGridPosition())
end

function Block:getNeighbors(): { Block }
	return self._map:getNeighbors(self:getGridPosition())
end

function Block:__tostring(): string
	local x, y, z = self:getGridPosition()
	return ("Block %s at (%d, %d, %d)"):format(self.blockType, x, y, z)
end

function Block:Destroy(): ()
	self.Destroying:Fire()
	self.Destroying:Destroy()
	if self.TypeChanged then
		self.TypeChanged:Destroy()
	end
	self._map = nil
	self.gridXYZ = nil
	self.blockType = nil
	self.size = nil
	setmetatable(self, nil)
end

return Block
