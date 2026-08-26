-- FILE: mapEditorScriptingExtension_s.lua
-- PURPOSE: Prevent the map editor feature set being limited by what MTA can load from a map file by adding a script file to maps
-- VERSION: RemoveWorldObjects (v1) AutoLOD (v3)

local usedLODModels = {}
local LOD_MAP = {}

function onResourceStartOrStop(startedResource)
	local startEvent = eventName == "onResourceStart"
	local removeObjects = getElementsByType("removeWorldObject", source)

	for removeID = 1, #removeObjects do
		local objectElement = removeObjects[removeID]
		local objectModel = getElementData(objectElement, "model")
		local objectLODModel = getElementData(objectElement, "lodModel")
		local posX = getElementData(objectElement, "posX")
		local posY = getElementData(objectElement, "posY")
		local posZ = getElementData(objectElement, "posZ")
		local objectInterior = getElementData(objectElement, "interior") or 0
		local objectRadius = getElementData(objectElement, "radius")

		if startEvent then
			removeWorldModel(objectModel, objectRadius, posX, posY, posZ, objectInterior)
			removeWorldModel(objectLODModel, objectRadius, posX, posY, posZ, objectInterior)
		else
			restoreWorldModel(objectModel, objectRadius, posX, posY, posZ, objectInterior)
			restoreWorldModel(objectLODModel, objectRadius, posX, posY, posZ, objectInterior)
		end
	end

	if startEvent then
		local resourceName = getResourceName(startedResource)
		local useLODs = get(resourceName..".useLODs")

		if useLODs then
			local objectsTable = getElementsByType("object", source)

			for objectID = 1, #objectsTable do
				local objectElement = objectsTable[objectID]
				local objectModel = getElementModel(objectElement)
				local lodModel = LOD_MAP[objectModel]

				if lodModel then
					local objectX, objectY, objectZ = getElementPosition(objectElement)
					local objectRX, objectRY, objectRZ = getElementRotation(objectElement)
					local objectInterior = getElementInterior(objectElement)
					local objectDimension = getElementDimension(objectElement)
					local lodObject = createObject(lodModel, objectX, objectY, objectZ, objectRX, objectRY, objectRZ, true)

					setElementInterior(lodObject, objectInterior)
					setElementDimension(lodObject, objectDimension)

					setElementParent(lodObject, objectElement)
					setLowLODElement(objectElement, lodObject)

					usedLODModels[lodModel] = true
				end
			end
		end
	end
end
addEventHandler("onResourceStart", resourceRoot, onResourceStartOrStop)
addEventHandler("onResourceStop", resourceRoot, onResourceStartOrStop)

local function onPlayerResourceStart(resourceElement)
	local mapResource = resourceElement == resource

	if not mapResource then
		return
	end
	
	triggerClientEvent(source, "setLODsClient", resourceRoot, usedLODModels)
end
addEventHandler("onPlayerResourceStart", root, onPlayerResourceStart)

-- MTA LOD Table [object] = [lodmodel] trimmed to only include objects used in map

LOD_MAP = {

}
