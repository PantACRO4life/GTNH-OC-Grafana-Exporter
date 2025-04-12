local computer = require("computer")
local component = require("component")
local config = require("config")
local internet = require("internet")
local event = require("event")

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

local function sanitize(s)
    s = string.gsub(s, " ", "\\ ")
    s = string.gsub(s, "=", "\\=")
    return string.gsub(s, ",", "\\,")
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

local function exportItems(interface)
    local itemIter = interface.allItems()
    local postString = ""
    local currLength = 0
    while true do
        currItem = itemIter()
        if currItem == nil then break end
        if currItem["size"] >= config.itemThreshold then
            if currItem["label"]:find("^drop of") == nil then
                currLength = currLength + 1
                postString = postString .. config.itemMeasurement .. ",item=" .. sanitize(currItem["label"]) .. " amount=" .. currItem["size"] .. "i\n"
                -- Used to ensure we don't have overly long requests
                if currLength >= config.itemMaxExport then
                    internet.request(config.dbURL .. config.itemDB, postString)()
                    currLength = 0
                    postString = ""
                end
            end
        end
    end
    if currLength > 0 then
        internet.request(config.dbURL .. config.itemDB, postString)()
    end
end

local function exportEssentia(interface)
    local essentia = interface.getEssentiaInNetwork()
    local postString = ""
    for _, essentia in pairs(essentia) do
        if essentia["amount"] >= config.essentiaThreshold then
            postString = postString .. config.essentiaMeasurement .. ",aspect=" .. sanitize(essentiaName(essentia["label"])) .. " amount=" .. essentia["amount"] .. "i\n"
        end
    end
    internet.request(config.dbURL .. config.essentiaDB, postString)()
end

local function exportFluids(interface)
    local fluids = interface.getFluidsInNetwork()
    local postString = ""
    for _, fluid in pairs(fluids) do
        if fluid["amount"] >= config.fluidThreshold then
            postString = postString .. config.fluidMeasurement .. ",fluid=" .. sanitize(fluid["label"]) .. " amount=" .. fluid["amount"] .. "i\n"
        end
    end
    internet.request(config.dbURL .. config.fluidDB, postString)()
end


-- Get the LSC machine based on UUID from config
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


-- Function to export energy from the LSC machine
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

    internet.request(config.dbURL .. config.energyDB, postString)()
end

local function parseSensorFields(sensorData, name, coord, owner)
    local fields = {}
    local function escape(str)
        return (str or "Unknown"):gsub('"', '\\"'):gsub("\\", "\\\\")
    end

    -- Always include these as fields
    table.insert(fields, string.format('machine="%s"', escape(name)))
    table.insert(fields, string.format('owner="%s"', escape(owner)))

    -- If sensorData is not a table, add fallback field
    if type(sensorData) ~= "table" then
        table.insert(fields, 'info="No_sensor_data"')
        return table.concat(fields, ",")
    end

    -- Problems
    local gtPlusPlus = string.match(sensorData[5] or "", "EU") and 7 or 5
    if gtPlusPlus == 7 then
        gtPlusPlus = string.match(sensorData[18] or "", "Problems") and 18 or 7
    end
    local problemsString = sensorData[gtPlusPlus] or ""
    local problems = "0"
    if string.match(problemsString, "Has Problems") then
        problems = "1"
    end
    local ok, result = pcall(function()
        local code = string.match(problemsString, "c(%d+)")
        if code then
            problems = code
        end
    end)
    table.insert(fields, string.format('problems=%s', tonumber(problems)))

    -- Efficiency
    local efficiency = "0.0"
    pcall(function()
        -- Remove Minecraft formatting codes
        local cleaned = sensorData[gtPlusPlus]:gsub("§.", "")
        -- Find the number before the % symbol
        local match = string.match(cleaned, "Efficiency:%s*(%d+%.?%d*)%%")
        if match then
            efficiency = match
        end
    end)
    table.insert(fields, string.format('efficiency=%s', tonumber((string.gsub(efficiency, "%%", "")))))

    -- Energy income and Tier

    return table.concat(fields, ",")
end

local displayNames = {
  ["industrialcentrifuge.controller.tier.single"] = "Centrifuge",
  ["industrialsalloyamelter.controller.tier.single"] = "Alloy Blast Smelter [ABS]",
  ["chemicalreactor"] = "Large Chemical Reactor [LCR]",
  ["supercapacitor"] = "Lapotronic Supercapacitor [LSC]",
  ["blastfurnace"] = "Electric Blast Furnace [EBF]",
  ["implosioncompressor"] = "Implosion Compressor",
  ["distillationtower"] = "Distillation Tower [DT]",
  ["industrialmacerator.controller.tier.single"] = "Macerator",
  ["cracker"] = "Oil Cracker",
  ["lathe"] = "Lathe",
  ["vacuumfreezer"] = "Vacuum Freezer",
  ["cleanroom"] = "Clean Room [CR]",
  ["industrialmixer.controller.tier.single"] = "Mixer",
  ["industrialwiremill.controller.tier.single"] = "Wiremill",
  ["preciseassembler"] = "Assembler",
  ["adv.blastfurnace"] = "Volcanus",
  ["industrialcuttingmachine.controller.tier.01"] = "Cutting Machine",
  ["research_completer"] = "TC Researcher",
  ["fluidextractor"] = "Fluid Extractor",
  ["industrialelectrolyzer.controller.tier.single"] = "Electrolyzer",
  ["engraver"] = "Laser Engraver",
  ["industrialbender.controller.tier.single"] = "Bending Machine",
  ["industrialextruder.controller.tier.single"] = "Extruder",
  ["basiccompressor"] = "Compressor",
  ["industrialcokeoven.controller.tier.single"] = "Coke Oven",
  ["pyro"] = "Pyrolyse Oven",
  ["brewery"] = "Brewery Barrel"
}

-- Export data for other GT machines
local function exportAllMachines()
    local postString = ""

    for addr, comp in pairs(component.list()) do
        if comp == "gt_machine" then
            local machine = component.proxy(addr)

            local rawName = machine.getName() or "Unknown"
            rawName = rawName:gsub("multimachine.", "")
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

    internet.request(config.dbURL .. config.multiblockDB, postString)()
end

local function exportCpus(interface)
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
    internet.request(config.dbURL .. config.cpuDB, postString)()
end

local function main()
    initEvents()
    hookEvents()
    startTime = os.time()
    lastFluidTime = startTime
    lastItemTime = startTime
    lastEssentiaTime = startTime
    lastEnergyTime = startTime
    lastCpuTime = startTime
    lastMultiblockTime = startTime
    local interface = nil
    local lsc = nil
    if config.enableCpus or config.enableEssentia or config.enableFluids or config.enableItems then
        interface = component.me_interface
    end
    -- if config.enableEnergy then
    --    lsc = component.gt_machine
    --    assert(lsc.getName() == "multimachine.supercapacitor", "A GT machine (maybe a cable) other than a LSC controller was found!")
    -- end
    while true do
        if needExitFlag then break end
        if config.enableItems and os.time() > lastItemTime + config.itemInterval then
            exportItems(interface)
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
        
        os.sleep(1)
    end
end

main()
