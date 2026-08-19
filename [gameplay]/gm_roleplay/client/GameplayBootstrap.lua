addEventHandler("onClientResourceStart", resourceRoot, function()
	setPedTargetingMarkerEnabled(false)
	setBlurLevel(0)
	setHeatHaze ( 0 )
	engineSetAsynchronousLoading(true, true)
	setAmbientSoundEnabled("gunfire", false)
	setOcclusionsEnabled(false)

	for _, object in pairs(getElementsByType("removeWorldObject")) do
		local posX = getElementData ( object, "posX" )
		local posY = getElementData ( object, "posY" )
		local posZ = getElementData ( object, "posZ" )
		local model = getElementData ( object, "model" )
		local radius = getElementData ( object, "radius" )
		local lodModel = getElementData ( object, "lodModel" )
		local interior = getElementData ( object, "interior" ) or 0
		removeWorldModel ( model, radius, posX, posY, posZ, interior )
		removeWorldModel ( lodModel, radius, posX, posY, posZ, interior )
	end
end)