MODELS = {
    { txd = "vehicle/sapd/596.txd", dff = "vehicle/sapd/596.dff", model = 596 },
	{ txd = "vehicle/sapd/598.txd", dff = "vehicle/sapd/598.dff", model = 598 },
	{ txd = "vehicle/sapd/599.txd", dff = "vehicle/sapd/599.dff", model = 599 }
}

addEventHandler("onClientResourceStart", resourceRoot, function()
	for _, v in ipairs(MODELS) do
		if v.txd then
			local txd = engineLoadTXD(v.txd)
			engineImportTXD(txd, model or v.model)
		end
				
		if v.dff then
			local dff = engineLoadDFF(v.dff)
			engineReplaceModel(dff, model or v.model)
		end
	end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
	for _, v in ipairs(MODELS) do
		engineRestoreModel(v.model)
		engineRestoreCOL(v.model)
	end
end)