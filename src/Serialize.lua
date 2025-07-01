local function encodeKey(key)
	if typeof(key) == "string" then
		return "str{" .. key .. "}"
	elseif typeof(key) == "number" then
		return "n{" .. key .. "}"
	elseif typeof(key) == "boolean" then
		return "b{" .. tostring(key) .. "}"
	else
		warn("Unsupported key type: " .. typeof(key))
		return "unsupported{" .. tostring(key) .. "}"
	end
end

function serialize(t: { [string]: any }): string
	local new = {}
	local count = 0

	for key, value in pairs(t) do
		table.insert(new, { key = key, value = value })

		count = count + 1
		if count % 100 == 0 then
			task.wait()
		end
	end

	table.sort(new, function(a, b)
		return a.key < b.key
	end)

	local str = ""
	count = 0

	for i, data in new do
		local value = data.value
		local key = data.key

		if typeof(value) == "table" then
			value = serialize(value)
		elseif typeof(value) == "Color3" then
			value = string.format("Color3{%f,%f,%f}", value.R, value.G, value.B)
		elseif typeof(value) == "BrickColor" then
			value = string.format("BrickColor{%s}", value.Name)
		elseif typeof(value) == "Vector3" then
			value = string.format("Vector3{%f,%f,%f}", value.X, value.Y, value.Z)
		elseif typeof(value) == "CFrame" then
			value = string.format("CFrame{%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f}", value:GetComponents())
		elseif typeof(value) == "EnumItem" then
			value = string.format("EnumItem{%s,%s}", tostring(value.EnumType), value.Name)
		elseif typeof(value) == "Instance" then
			value = string.format("Instance{%s}", value:GetFullName())
		elseif typeof(value) == "boolean" then
			value = tostring(value)
		elseif typeof(value) == "number" then
			value = tostring(value)
		elseif typeof(value) == "string" then
			value = value
		else
			warn("Unsupported value type: " .. typeof(value))
			value = ""
		end

		key = encodeKey(data.key)
		value = tostring(value)

		if i > 1 then
			str = str .. "|" .. key .. ":" .. value
		else
			str = key .. ":" .. value
		end

		count = count + 1
		if count % 100 == 0 then
			task.wait()
		end
	end

	return "(" .. str .. ")"
end

local function decodeKey(encoded)
	local keyType, keyValue = encoded:match("^(%a+)%{(.*)%}$")
	if keyType == "str" then
		return keyValue
	elseif keyType == "n" then
		return tonumber(keyValue)
	elseif keyType == "b" then
		return keyValue == "true"
	elseif keyType == "unsupported" then
		return keyValue
	else
		warn("Unknown key type: " .. tostring(keyType))
		return keyValue
	end
end

function convertValue(value)
	if value == "true" then
		return true
	elseif value == "false" then
		return false
	elseif tonumber(value) then
		return tonumber(value)
	elseif value:find("^%(") and value:find("%)$") then
		return decodeNestedTable(value:sub(2, -2))
	elseif value:find("^Color3%{") then
		local r, g, b = value:match("^Color3%{([%d.]+),([%d.]+),([%d.]+)%}$")
		return Color3.new(tonumber(r), tonumber(g), tonumber(b))
	elseif value:find("^BrickColor%{") then
		local colorName = value:match("^BrickColor%{(.-)%}$")
		return BrickColor.new(colorName)
	elseif value:find("^Vector3%{") then
		local x, y, z = value:match("^Vector3%{([%d.eE+-]+),([%d.eE+-]+),([%d.eE+-]+)%}$")
		if x and y and z then
			return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
		end
	elseif value:find("^CFrame%{") then
		local components = {}
		for num in value:gmatch("([%d.-]+)") do
			table.insert(components, tonumber(num))
		end
		return CFrame.new(table.unpack(components))
	elseif value:find("^EnumItem%{") then
		local enumType, enumName = value:match("^EnumItem%{([%w_]+),([%w_]+)%}$")
		local success, enumItem = pcall(function()
			return Enum[enumType][enumName]
		end)
		if success then
			return enumItem
		else
			warn("Invalid EnumItem: " .. enumType .. ", " .. enumName)
			return nil
		end
	elseif value:find("^Instance%{") then
		local instancePath = value:match("^Instance%{(.-)%}$")
		local instance = game
		for segment in instancePath:gmatch("[^%.]+") do
			instance = instance[segment]
			if not instance then
				warn("Instance not found: " .. instancePath)
				return nil
			end
		end
		return instance
	else
		return value
	end
end

function decodeNestedTable(str)
	local result = {}
	local function splitKeyValue(segment)
		local key, value = segment:match("^(.-):(.*)$")
		if not key or not value then
			warn("Malformed key-value segment: " .. segment)
			return nil
		end
		return decodeKey(key), convertValue(value)
	end

	local segments = {}
	local bracketLevel = 0
	local buffer = ""

	for i = 1, #str do
		local char = str:sub(i, i)
		if char == "(" then
			bracketLevel += 1
			buffer ..= char
		elseif char == ")" then
			bracketLevel -= 1
			buffer ..= char
		elseif char == "|" and bracketLevel == 0 then
			table.insert(segments, buffer)
			buffer = ""
		else
			buffer ..= char
		end
	end

	if buffer ~= "" then
		table.insert(segments, buffer)
	end

	for _, segment in ipairs(segments) do
		local key, value = splitKeyValue(segment)
		if key ~= nil then
			result[key] = value
		end
	end

	return result
end

function deserialize(serialized)
	local startIdx, endIdx = serialized:find("%b()")
	if not startIdx or not endIdx then
		error("Invalid encoded string format")
	end

	local content = serialized:sub(startIdx + 1, endIdx - 1)

	return decodeNestedTable(content)
end

return {
	Deserialize = deserialize,
	Serialize = serialize,
}
