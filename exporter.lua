local computer = require("computer")
local component = require("component")
local config = require("config")
local internet = require("internet")
local event = require("event")
local modem = component.modem
local hostname = os.getenv("HOSTNAME") or "unknown"
local port = 1234
modem.open(port)
maxInt = 9223372036854775807

local function keyboardEvent(eventName, keyboardAddress, charNum, codeNum, playerName)
    if charNum == 113 then
        needExitFlag = true
        return false
    end
end
local function initEvents()
    needExitFlag = false
end
local function hookEvents()
    event.listen("key_up", keyboardEvent)
end
hookEvents()
local function sanitize(str)
    if type(str) ~= "string" then return "N/A" end
    str = str:gsub("\\", "\\\\")
    str = str:gsub('"', '\\"')
    str = str:gsub(" ", "\\ ")
    str = str:gsub("=", "\\=")
    str = str:gsub(",", "\\,")
    return str
end
local function capInt(num)
    if num < maxInt then
        return num
    end
    return maxInt
end
local function capIntStr(numStr)
    if tonumber(numStr) < maxInt then
        return numStr
    end
    return maxInt
end
local function safeComponent(name)
    if component.isAvailable(name) then
        return component[name]
    else
        return nil
    end
end
local function safeRequest(url, body)
    local success, err = pcall(function()
        internet.request(url, body)()
    end)
    if not success then
        print("ERROR: Failed to send data to " .. url .. " -> " .. tostring(err))
    end
end
local function essentiaName(label)
    for token in string.gmatch(label, "[^%s]+") do
        return token
    end
end
local function scientific(s)
    local exp = ""
    local i = 1
    local base = s:gmatch("[%d.]+")()
    local exp = s:gmatch("^[%d]+")():sub(2)
    return base, exp
end
local function checkForUpdate()
    modem.broadcast(port, "check_update", hostname)

    -- Wait up to 5 seconds for server reply
    local deadline = computer.uptime() + 5
    while computer.uptime() < deadline do
        local _, _, _, _, _, cmd = event.pull(1, "modem_message")
        if cmd == "update_required" then
            print("[UPDATE] Server says update required. Rebooting...")
            os.sleep(1)
            computer.shutdown(true)
        elseif cmd == "up_to_date" then
            print("[UPDATE] All files are up to date.")
            return true
        end
    end

    print("[WARNING] No update status received, continuing anyway.")
end
local function exportItems()
    local interface = safeComponent("me_interface")
    if not interface then return end
    local itemIter = interface.allItems()
    local postString = ""
    local currLength = 0
    while true do
        local currItem = itemIter()
        if currItem == nil then break end

        if currItem["size"] >= config.itemThreshold then
            if currItem["label"]:find("^drop of") == nil then
                currLength = currLength + 1
                postString = postString .. config.itemMeasurement .. ",item=" .. sanitize(currItem["label"]) .. " amount=" .. currItem["size"] .. "i\n"

                if currLength >= config.itemMaxExport then
                    safeRequest(config.dbURL .. config.itemDB, postString)
                    currLength = 0
                    postString = ""
                end
            end
        end
    end
    if currLength > 0 then
        safeRequest(config.dbURL .. config.itemDB, postString)
    end
end
local function exportItems2(interface, allItemIds)
    local postString = ""
    local currLength = 0
    for id, _ in pairs(allItemIds) do
        local currReturn = interface.getItemsInNetworkById({id})
        for _, item in pairs(currReturn) do
            if item["size"] >= config.itemThreshold then
                if item["label"]:find("^drop of") == nil then
                    currLength = currLength + 1
                    postString = postString .. config.itemMeasurement .. ",item=" .. sanitize(item["label"]) .. " amount=" .. capInt(item["size"]) .. "i\n"
                    -- Used to ensure we don't have overly long requests
                    if currLength >= config.itemMaxExport then
                        if config.enableDebug then
                            print(postString)
                        end
                        internet.request(config.dbURL .. config.itemDB, postString)()
                        currLength = 0
                        postString = ""
                    end
                end
            end
        end
    end
    if currLength > 0 then
        if config.enableDebug then
            print(postString)
        end
        internet.request(config.dbURL .. config.itemDB, postString)()
    end
end
local function updateItemIds(arr, interface)
    local itemIter = interface.allItems()
    local currIdx = 1
    while true do
        local currItem = itemIter()
        if currItem == nil then break end
        if currItem["size"] >= config.itemThreshold then
            if currItem["label"]:find("^drop of") == nil then
                arr[currItem["name"]] = true
                currIdx = currIdx + 1
            end
        end
    end
end
local function exportEssentia()
    local interface = safeComponent("me_interface")
    if not interface then return end
    local essentia = interface.getEssentiaInNetwork()
    local postString = ""
    for _, e in pairs(essentia) do
        if e["amount"] >= config.essentiaThreshold then
            postString = postString .. config.essentiaMeasurement .. ",aspect=" .. sanitize(essentiaName(e["label"])) .. " amount=" .. e["amount"] .. "i\n"
        end
    end
    safeRequest(config.dbURL .. config.essentiaDB, postString)
end
local function exportFluids()
    local interface = safeComponent("me_interface")
    if not interface then return end

    local fluids = interface.getFluidsInNetwork()
    local postString = ""

    for _, f in pairs(fluids) do
        if f["amount"] >= config.fluidThreshold then
            postString = postString .. config.fluidMeasurement .. ",fluid=" .. sanitize(f["label"]) .. " amount=" .. f["amount"] .. "i\n"
        end
    end
    safeRequest(config.dbURL .. config.fluidDB, postString)
end
local function getLSC()
    -- Check if the lscUUID exists in the config
    if not config.lscUUID then
        print("Error: lscUUID is not defined in the config file!")
        return nil
    end
    local targetUUID = config.lscUUID
    -- Iterate through components and look for the matching UUID
    for addr, comp in pairs(component.list()) do
        if addr == targetUUID then
            -- Found the LSC machine with the matching UUID
            return component.proxy(addr)
        end
    end
    -- If no machine with the UUID is found
    print("Error: No GT machine with UUID " .. targetUUID .. " found.")
    return nil
end
local function exportEnergy()
    -- Get the LSC machine
    local lsc = getLSC()
    -- Check if lsc is nil
    if not lsc then
        print("Error: LSC machine not found. Cannot proceed with energy export.")
        return
    end
    -- Proceed with the energy export logic if LSC is found
    local currentEU = lsc.getEUStored()
    local maxEU = lsc.getEUMaxStored()
    local sensorData = lsc.getSensorInformation() 
    -- Continue with the export logic (same as before)
    local input5s = sensorData[10]:sub(12, #sensorData[10] - 17):gsub(",", "")
    local output5s = sensorData[11]:sub(13, #sensorData[11] - 17):gsub(",", "")
    local input5m = sensorData[12]:sub(12, #sensorData[12] - 17):gsub(",", "")
    local output5m = sensorData[13]:sub(13, #sensorData[13] - 17):gsub(",", "")
    local input1h = sensorData[14]:sub(12, #sensorData[14] - 14):gsub(",", "")
    local output1h = sensorData[15]:sub(13, #sensorData[15] - 14):gsub(",", "")
    local wirelessExp, wirelessBase = 0
    local wirelessEU = ""
    if config.enableWireless then
        wirelessEU = sensorData[23]:sub(23, #sensorData[23] - 3):gsub(",", "")
        wirelessSci = sensorData[24]:sub(23, #sensorData[24] - 3)
        wirelessBase, wirelessExp = scientific(wirelessSci)
    end
    local postString = config.energyMeasurement ..
        " current=" .. currentEU .. "i,max=" .. maxEU .. "i,input5s=" .. input5s .. "i," ..
        "output5s=" .. output5s .. "i,input5m=" .. input5m .. "i,output5m=" .. output5m .. "i," ..
        "input1h=" .. input1h .. "i,output1h=" .. output1h .. "i"
    if config.enableWireless then
        postString = postString .. ",wirelesseu=\"" .. wirelessEU .. "\",wirelessbase=" ..
            wirelessBase .. ",wirelessexp=" .. wirelessExp .. "i"
    end
    safeRequest(config.dbURL .. config.energyDB, postString)
end
local function exportCpus()
    local interface = safeComponent("me_interface")
    if not interface then return end
    local cpus = interface.getCpus()
    postString = ""
    for _, cpu in pairs(cpus) do
        if #cpu.name > 0 then
            postString = postString .. config.cpuMeasurement .. ",cpuname=" .. sanitize(cpu.name) .. " storage=" .. cpu.storage .. "i,coprocessors=" .. cpu.coprocessors .. "i,busy=" .. tostring(cpu.busy)
            local output = cpu.cpu.finalOutput()
            if output ~= nil then
                postString = postString .. ",craftingItem=\"" .. output.label .. "\",craftingCount=" .. output.size .. "i"
            else
                postString = postString .. ",craftingItem=" .. "\"N/A\"" .. ",craftingCount=" .. 0 .. "i"
            end
            postString = postString .. "\n"
        end
    end
    safeRequest(config.dbURL .. config.cpuDB, postString)
end
local displayNames = {
    ["algaefarm.controller.tier.single"] = "Algae Farm (AF)",
    ["amazonprime.controller.tier.single"] = "Amazon Prime Controller (APC)",
    ["chemicalplant.controller.tier.single"] = "Chemical Processing Plant (CPP)",
    ["cyclotron.tier.single"] = "COMET - Compact Cyclotron (CCC)",
    ["fusioncomputer.tier.06"] = "Fusion Control Computer Mark I (FCCMI)",
    ["fusioncomputer.tier.07"] = "Fusion Control Computer Mark II (FCCMII)",
    ["fusioncomputer.tier.08"] = "Fusion Control Computer Mark III (FCCMIII)",
    ["fusioncomputer.tier.09"] = "FusionTech MK IV (FTIV)",
    ["fusioncomputer.tier.10"] = "FusionTech MK V (FTV)",
    ["industrial.fishpond.controller.tier.single"] = "Industrial Fishpond (IF)",
    ["industrialalloysmelter.controller.tier.single"] = "Industrial Alloy Smelter (IAS)",
    ["industrialarcfurnace.controller.tier.single"] = "Industrial Arc Furnace (IAF)",
    ["industrialbender.controller.tier.single"] = "Industrial Bender (IB)",
    ["industrialcentrifuge.controller.tier.single"] = "Industrial Centrifuge (IC)",
    ["industrialcokeoven.controller.tier.single"] = "Industrial Coke Oven (ICO)",
    ["industrialcuttingmachine.controller.tier.01"] = "Industrial Cutting Machine (ICM)",
    ["industrialelectrolyzer.controller.tier.single"] = "Industrial Electrolyzer (IE)",
    ["industrialextruder.controller.tier.single"] = "Industrial Extruder (IE)",
    ["industrialfluidheater.controller.tier.single"] = "Industrial Fluid Heater (IFH)",
    ["industrialhammer.controller.tier.single"] = "Industrial Hammer (IH)",
    ["industrialmacerator.controller.tier.single"] = "Industrial Macerator (IM)",
    ["industrialmassfab.controller.tier.single"] = "Industrial Mass Fabricator (IMF)",
    ["industrialmixer.controller.tier.single"] = "Industrial Mixer (IM)",
    ["industrialmultimachine.controller.tier.single"] = "Industrial Multimachine (IMM)",
    ["industrialrefinery.controller.tier.single"] = "Industrial Refinery (IR)",
    ["industrialrockcrusher.controller.tier.single"] = "Industrial Rock Crusher (IRC)",
    ["industrialsalloyamelter.controller.tier.mega"] = "Mega Alloy Smelter (MAS)",
    ["industrialsalloyamelter.controller.tier.single"] = "Industrial Alloy Smelter (IAS)",
    ["industrialsifter.controller.tier.single"] = "Industrial Sifter (IS)",
    ["industrialthermalcentrifuge.controller.tier.single"] = "Industrial Thermal Centrifuge (ITC)",
    ["industrialwashplant.controller.tier.single"] = "Industrial Wash Plant (IWP)",
    ["industrialwiremill.controller.tier.single"] = "Industrial Wiremill (IW)",
    ["Mega_AlloyBlastSmelter"] = "Mega Alloy Blast Smelter (MABS)",
    ["MegaBlastFurnace"] = "Mega Blast Furnace (MBF)",
    ["MegaChemicalReactor"] = "Mega Chemical Reactor (MCR)",
    ["MegaDistillationTower"] = "Mega Distillation Tower (MDT)",
    ["MegaOilCracker"] = "Mega Oil Cracker (MOC)",
    ["MegaUltimateBuckConverter"] = "Mega Ultimate Buck Converter (MUBC)",
    ["MegaVacuumFreezer"] = "Mega Vacuum Freezer (MVF)",
    ["moleculartransformer.controller.tier.single"] = "Molecular Transformer (MT)",
    ["multimachine.adv.blastfurnace"] = "Volcanus (ABF)",
    ["multimachine.adv.chisel"] = "Industrial 3D Copying Machine (I3DCM)",
    ["multimachine.assemblyline"] = "Assembly Line (AL)",
    ["multimachine.autoclave"] = "Industrial Autoclave (IA)",
    ["multimachine.basiccompressor"] = "Large Electric Compressor (LEC)",
    ["multimachine.blackholecompressor"] = "Pseudostable Black Hole Containment Field (PBHCF)",
    ["multimachine.blastfurnace"] = "Electric Blast Furnace (EBF)",
    ["multimachine.boiler.bronze"] = "Large Bronze Boiler (LBB)",
    ["multimachine.boiler.steel"] = "Large Steel Boiler (LSB)",
    ["multimachine.boiler.titanium"] = "Large Titanium Boiler (LTB)",
    ["multimachine.boiler.tungstensteel"] = "Large Tungstensteel Boiler (LTB)",
    ["multimachine.brewery"] = "Big Barrel Brewery (BBB)",
    ["multimachine.brickedblastfurnace"] = "Bricked Blast Furnace (BBF)",
    ["multimachine.canner"] = "TurboCan Pro (TCP)",
    ["multimachine.charcoalpile"] = "Charcoal Pile Igniter (CPI)",
    ["multimachine.chemicalreactor"] = "Large Chemical Reactor (LCR)",
    ["multimachine.cleanroom"] = "Cleanroom Controller (CC)",
    ["multimachine.concretebackfiller1"] = "Concrete Backfiller (CBF)",
    ["multimachine.concretebackfiller3"] = "Advanced Concrete Backfiller (ACBF)",
    ["multimachine.cracker"] = "Oil Cracking Unit (OCU)",
    ["multimachine.dieselengine"] = "Large Combustion Engine (LCE)",
    ["multimachine.distillationtower"] = "Distillation Tower (DT)",
    ["multimachine.electromagneticseparator"] = "Magnetic Flux Exhibitor (MFE)",
    ["multimachine.engraver"] = "Hyper-Intensity Laser Engraver (HILE)",
    ["multimachine.extractor"] = "Dissection Apparatus (DA)",
    ["multimachine.extremedieselengine"] = "Extreme Combustion Engine (ECE)",
    ["multimachine.fluidextractor"] = "Large Fluid Extractor (LFE)",
    ["multimachine.heatexchanger"] = "Large Heat Exchanger (LHE)",
    ["multimachine.hipcompressor"] = "Hot Isostatic Pressurization Unit (HIPU)",
    ["multimachine.implosioncompressor"] = "Implosion Compressor (IC)",
    ["multimachine.largeadvancedgasturbine"] = "Large Advanced Gas Turbine (LAGT)",
    ["multimachine.largegasturbine"] = "Large Gas Turbine (LGT)",
    ["multimachine.largehpturbine"] = "Large HP Steam Turbine (LHPT)",
    ["multimachine.largeplasmaturbine"] = "Large Plasma Turbine (LPT)",
    ["multimachine.largeturbine"] = "Large Steam Turbine (LST)",
    ["multimachine.lathe"] = "Industrial Precision Lathe (IPL)",
    ["multimachine.multifurnace"] = "Multi Smelter (MS)",
    ["multimachine.nanoforge"] = "Nano Forge (NF)",
    ["multimachine.neutroniumcompressor"] = "Neutronium Compressor (NC)",
    ["multimachine.oildrill1"] = "Oil/Gas/Fluid Drilling Rig (OGFDR)",
    ["multimachine.oildrill2"] = "Oil/Gas/Fluid Drilling Rig II (OGFDRII)",
    ["multimachine.oildrill3"] = "Oil/Gas/Fluid Drilling Rig III (OGFDRIII)",
    ["multimachine.oildrill4"] = "Oil/Gas/Fluid Drilling Rig IV (OGFDRIV)",
    ["multimachine.oildrillinfinite"] = "Infinite Oil/Gas/Fluid Drilling Rig (IOGFDR)",
    ["multimachine.oredrill1"] = "Ore Drilling Plant (ODP)",
    ["multimachine.oredrill2"] = "Ore Drilling Plant II (ODPII)",
    ["multimachine.oredrill3"] = "Ore Drilling Plant III (ODPIII)",
    ["multimachine.oredrill4"] = "Ore Drilling Plant IV (ODPIV)",
    ["multimachine.oreprocessor"] = "Integrated Ore Factory (IOF)",
    ["multimachine.pcbfactory"] = "PCB Factory (PCBF)",
    ["multimachine.plasmaforge"] = "Dimensionally Transcendent Plasma Forge (DTPF)",
    ["multimachine.processingarray"] = "Processing Array (PA)",
    ["multimachine.purificationplant"] = "Water Purification Plant (WPP)",
    ["multimachine.purificationunitclarifier"] = "Clarifier Purification Unit (CPU)",
    ["multimachine.purificationunitdegasifier"] = "Residual Decontaminant Degasser Purification Unit (RDDPU)",
    ["multimachine.purificationunitextractor"] = "Absolute Baryonic Perfection Purification Unit (ABPPU)",
    ["multimachine.purificationunitflocculator"] = "Flocculation Purification Unit (FPU)",
    ["multimachine.purificationunitozonation"] = "Ozonation Purification Unit (OPU)",
    ["multimachine.purificationunitphadjustment"] = "pH Neutralization Purification Unit (PHPU)",
    ["multimachine.purificationunitplasmaheater"] = "Extreme Temperature Fluctuation Purification Unit (ETFPU)",
    ["multimachine.purificationunituvtreatment"] = "High Energy Laser Purification Unit (HELPU)",
    ["multimachine.pyro"] = "Pyrolyse Oven (PO)",
    ["multimachine.solidifier"] = "Fluid Shaper (FS)",
    ["multimachine.transcendentplasmamixer"] = "Transcendent Plasma Mixer (TPM)",
    ["multimachine.vacuumfreezer"] = "Vacuum Freezer (VF)",
    ["multimachine.wormhole"] = "Miniature Wormhole Generator (MWG)",
    ["multimachine_DroneCentre"] = "Drone Centre (DC)",
    ["nuclearsaltprocessingplant.controller.tier.single"] = "Nuclear Salt Processing Plant (NSPP)",
    ["preciseassembler"] = "Precise Auto-Assembler MT-3662 (PrAss)",
    ["quantumforcetransformer.controller.tier.single"] = "Quantum Force Transformer (QFT)",
    ["research_completer"] = "Research Completer (RC)",
    ["solartower.controller.tier.single"] = "Solar Tower (ST)",
    ["treefarm.controller.tier.single"] = "Tree Growth Simulator (TGS)",
    ["waterpump.controller.tier.single"] = "Water Pump (WP)"
}

local function parseSensorFields(sensorData, name, coord, owner)
    local fields = {}

    local function escape(str)
        return (str or "Unknown"):gsub('"', '\\"'):gsub("\\", "\\\\")
    end

    -- Always include name and owner
    table.insert(fields, string.format('machine="%s"', escape(name)))
    table.insert(fields, string.format('owner="%s"', escape(owner)))

    -- Fallback if no data
    if type(sensorData) ~= "table" then
        table.insert(fields, 'info="No_sensor_data"')
        return table.concat(fields, ",")
    end

    local problems = "0"
    local energyIncome, amperage, tier = nil, nil, "N/A"

    for i = 1, #sensorData do
        local line = sensorData[i]:gsub("§.", "") -- strip formatting codes

        -- Problems
        if line:find("Problems") then
            if line:find("Has Problems") then problems = "1" end
            local code = line:match("c(%d+)")
            if code then problems = code end
        end

        -- Energy Income, Amperage, Tier
        if line:find("Max Energy Income") then
            local nextLine = sensorData[i + 1] and sensorData[i + 1]:gsub("§.", "") or ""
            local combined = line .. " " .. nextLine
            energyIncome = combined:match("([%d,]+)%s*EU/t")
            amperage = combined:match("%(%*%s*(%d+)%s*A%)") or combined:match("(%d+)%s*A")
            tier = combined:match("Tier:%s*(%a+)")
        end

        -- Parallel support
        if line:find("Maximum Parallel") then
            local parallel = line:match("Maximum Parallel:%s*(%d+)")
            if parallel then
                table.insert(fields, string.format("max_parallel=%s", tonumber(parallel)))
            end
        end
    end

    -- Final cleanup and insertion
    local energy = energyIncome and tonumber((energyIncome:gsub(",", ""))) or 0
    local ampNum = amperage and tonumber(amperage) or 0
    table.insert(fields, string.format("problems=%s", tonumber(problems) or 0))
    table.insert(fields, string.format("energyIncome=%s", energy))
    table.insert(fields, string.format("amperage=%s", ampNum))
    table.insert(fields, string.format('tier="%s"', escape(tier or "N/A")))

    return table.concat(fields, ",")
end

local function exportAllMachines()
    local postString = ""
    for addr, comp in pairs(component.list()) do
        if comp == "gt_machine" then
            local machine = component.proxy(addr)

            local rawName = machine.getName() or "Unknown"
            local name = displayNames[rawName] or rawName

            local owner = machine.getOwnerName() or "Unknown"
            local x, y, z = machine.getCoordinates()
            local coord = string.format("%s|%s|%s", x, y, z)
            coord = coord:gsub(" ", "\\ "):gsub(",", "\\,"):gsub("=", "\\=")

            local sensorData = machine.getSensorInformation()
            local sensorFields = parseSensorFields(sensorData, name, coord, owner)

            local line = string.format(
                "multiblocks,coord=%s %s",
                coord,
                sensorFields
            )
            postString = postString .. line .. "\n"
        end
    end
    safeRequest(config.dbURL .. config.multiblockDB, postString)
end
local function main()
    initEvents()
    checkForUpdate()
    hookEvents()
    startTime = os.time()
    lastFluidTime = startTime
    lastItemTime = startTime
    lastEssentiaTime = startTime
    lastEnergyTime = startTime
    lastCpuTime = startTime
    lastMultiblockTime = startTime
    lastChecktTime = startTime
    checkInterval = 5 * 72
    if config.allItemsInterval then
        lastAllItemsTime = startTime - config.allItemsInterval
    else
        lastAllItemsTime = startTime
    end
    local interface = nil
    local lsc = nil
    if config.enableCpus or config.enableEssentia or config.enableFluids or config.enableItems then
        interface = component.me_interface
    end
    -- if config.enableEnergy then
    --    lsc = component.gt_machine
    --    assert(lsc.getName() == "multimachine.supercapacitor", "A GT machine (maybe a cable) other than a LSC controller was found!")
    -- end
    local allItemIds = {}
    while true do
        if needExitFlag then break end    
        while not needExitFlag do
            if os.time() > lastChecktTime + checkInterval then
                checkForUpdate()
                lastChecktTime = os.time()
            end
            if config.enableItems and os.time() > lastAllItemsTime + config.allItemsInterval then
                allItemIds = {}
                updateItemIds(allItemIds, interface)
                lastAllItemsTime = os.time()
                if config.enableLogging then
                    print("[" .. os.time() .. "] Set item IDs; free RAM: " .. computer.freeMemory() .. " bytes")
                end
            end
            if config.enableItems and os.time() > lastItemTime + config.itemInterval then
                --exportItems(interface)
                exportItems2(interface, allItemIds)
                lastItemTime = os.time()
                if config.enableLogging then
                    print("[" .. os.time() .. "] Exported items; free RAM: " .. computer.freeMemory() .. " bytes")
                end
            end
            if config.enableFluids and os.time() > lastFluidTime + config.fluidInterval then
                exportFluids(interface)
                lastFluidTime = os.time()
                if config.enableLogging then
                    print("[" .. os.time() .. "] Exported fluids; free RAM: " .. computer.freeMemory() .. " bytes")
                end
            end
            if config.enableEssentia and os.time() > lastEssentiaTime + config.essentiaInterval then
                exportEssentia(interface)
                lastEssentiaTime = os.time()
                if config.enableLogging then
                    print("[" .. os.time() .. "] Exported essentia; free RAM: " .. computer.freeMemory() .. " bytes")
                end
            end
            if config.enableEnergy and os.time() > lastEnergyTime + config.energyInterval then
                exportEnergy(lsc)
                lastEnergyTime = os.time()
                if config.enableLogging then
                    print("[" .. os.time() .. "] Exported energy; free RAM: " .. computer.freeMemory() .. " bytes")
                end
            end
            if config.enableCpus and os.time() > lastCpuTime + config.cpuInterval then
                exportCpus(interface)
                lastCpuTime = os.time()
                if config.enableLogging then
                    print("[" .. os.time() .. "] Exported CPUs; free RAM: " .. computer.freeMemory() .. " bytes")
                end
            end
            if config.enableMultiblocks and os.time() > lastMultiblockTime + config.multiblockInterval then
                exportAllMachines()
                lastMultiblockTime = os.time()
                if config.enableLogging then
                    print("[" .. os.time() .. "] Exported multiblock; free RAM: " .. computer.freeMemory() .. " bytes")
                end
            end
            os.sleep(config.pollDelay or 0.250)
        end
    end
end
main()
