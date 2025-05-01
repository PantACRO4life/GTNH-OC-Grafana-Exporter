local files = {
    "exporter.lua",
    "Custom_Items.txt",
    "config_enabled_energy.lua",
    "config_enabled_fluids.lua",
    "config_enabled_items.lua",
    "config_enabled_essentia.lua",
    "config_enabled_multi.lua",
    "config_enabled_cpus.lua"
  }
  
  local baseUrl = "https://raw.githubusercontent.com/PantACRO4life/GTNH-OC-Grafana-Exporter/refs/heads/main/"
  local basePath = "/home/"
  
  for _, file in ipairs(files) do
    local fullUrl = baseUrl .. file
    local localPath = basePath .. file
    local cmd = 'wget -f "' .. fullUrl .. '" ' .. localPath
    print("[GET] " .. file)
    os.execute(cmd)
  
    -- Write the timestamp file
    local tsFile = io.open(localPath .. ".ts", "w")
    tsFile:write(os.time())
    tsFile:close()
    print("[TS] Updated timestamp for " .. file)
  end
  
