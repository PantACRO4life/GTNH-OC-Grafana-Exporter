local config = {
    -- Database:
    --- The hostname your InfluxDB is hosted on
    dbHostname = "http://10.3.47.231:8086",
    --- Probably don't edit this
    dbEndpoint = "/write?db=",
    
    --- Toggles Flags
    --- Whether to export item data
    enableItems = false,
    --- Whether to export fluid data
    enableFluids = true,
    --- Whether to export essentia data
    enableEssentia = false,
    --- Whether to export energy data
    enableEnergy = false,
    --- Whether to export wireless data (beta)
    enableWireless = false,
    --- Whether to export crafting CPU data
    enableCpus = false,
    --- Whether to export multiblock machine data
    enableMultiblocks = false,

    -- Items:
    --- The DB to export item data into
    itemDB = "gtnh",
    --- Name of the item measurement to export to
    itemMeasurement = "items",
    --- Interval (in seconds) between item exports
    itemInterval = 60,
    --- Minimum quantity for an item to be exported
    itemThreshold = 500,
    -- Number of items to export at once; try lowering if you're having memory issues (200 maybe for 256 KB?)
    itemMaxExport = 2500,
    --- Interval (in seconds) between using allItems to update the list of items to export (attempting to fix a crash)
    allItemsInterval = 1800,
    -- Item Filtering:
    enableCustomItems = true,
    customItemFile = "/home/Custom_Items.txt",

    -- Fluids:
    --- The DB to export fluid data into
    fluidDB = "gtnh",
    --- Name of the fluid measurement to export to
    fluidMeasurement = "fluids",
    --- Interval (in seconds) between fluid exports
    fluidInterval = 300, -- 5 minutes
    --- Minimum quantity (in liters) for a fluid to be exported
    fluidThreshold = 0,

    -- Essentia:
    --- The DB to export essentia data into
    essentiaDB = "gtnh",
    --- Name of the essentia measurement to export to
    essentiaMeasurement = "essentia",
    --- Interval (in seconds) between essentia exports
    essentiaInterval = 0.250,
    --- Minimum quantity for an essentia to be exported
    essentiaThreshold = 0,

    -- Energy:
    -- The UUID of the LSC machine
    lscUUID = "bb0ea24e-c009-46fe-9de5-b8c444bb071c",
    --- The DB to export energy data into
    energyDB = "gtnh",
    --- Name of the energy measurement to export to
    energyMeasurement = "energy",
    --- Interval (in seconds) between energy exports
    energyInterval = 0.250,

    -- Crafting CPUs:
    --- The DB to export crafting CPU data into
    cpuDB = "gtnh",
    --- Name of the crafting CPU measurement to export to
    cpuMeasurement = "cpus",
    --- Interval (in seconds) between crafting CPU exports
    cpuInterval = 0.250,

    -- Multiblock Machines:
    --- The DB to export multiblock data into
    multiblockDB = "gtnh",
    --- Name of the multiblock measurement to export to
    multiblockMeasurement = "multiblocks",
    --- Interval (in seconds) between multiblock exports
    multiblockInterval = 0.250,

    -- Misc:
    --- Whether to print log messages (containing timestamps and free RAM)
    enableLogging = true,

}

config.dbURL = config.dbHostname .. config.dbEndpoint
config.itemInterval = config.itemInterval * 72
config.fluidInterval = config.fluidInterval * 72
config.essentiaInterval = config.essentiaInterval * 72
config.energyInterval = config.energyInterval * 72
config.cpuInterval = config.cpuInterval * 72
config.multiblockInterval = config.multiblockInterval * 72
config.allItemsInterval = config.allItemsInterval * 72

return config
