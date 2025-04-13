--server script
local component = require("component")
local event = require("event")
local fs = require("filesystem")
local modem = component.modem
local computer = require("computer")

local port = 1234
local basePath = "/nas/"
local universalFiles = { "exporter.lua" }
local configPrefix = "config_enabled_"

local clients = {} -- [hostname] = { address = "", role = "", lastSent = {} }
modem.open(port)

print("[NAS] Chunked push server running on port " .. port)

-- Helpers
local function readTimestamp(file)
  local f = io.open(file, "r")
  if f then
    local ts = tonumber(f:read("*l"))
    f:close()
    return ts
  end
  return 0
end

local function getClientLastSent(hostname, filename)
  clients[hostname].lastSent = clients[hostname].lastSent or {}
  return clients[hostname].lastSent[filename] or 0
end

local function updateClientLastSent(hostname, filename, ts)
  if not clients[hostname] then
    clients[hostname] = { lastSent = {} }
  elseif not clients[hostname].lastSent then
    clients[hostname].lastSent = {}
  end
  clients[hostname].lastSent[filename] = ts
end


local function readFileInChunks(path, chunkSize)
  local f = io.open(path, "rb")
  if not f then return nil end
  local content = f:read("*a")
  f:close()

  local chunks = {}
  for i = 1, #content, chunkSize do
    table.insert(chunks, content:sub(i, i + chunkSize - 1))
  end
  return chunks
end

local function sendChunkedFile(address, filename, chunks)
  local total = #chunks
  modem.send(address, port, "file_start", filename, total)
  for i, chunk in ipairs(chunks) do
    modem.send(address, port, "file_chunk", filename, i, chunk)
    os.sleep(0.05)
  end
  modem.send(address, port, "file_end", filename)
  print("[PUSH] Sent " .. filename .. " (" .. total .. " chunks) to " .. address)
end

local function sendConfigIfUpdated(role, hostname, address)
  local sourceFile = configPrefix .. role .. ".lua"
  local targetFile = "config.lua"

  local tsPath = basePath .. sourceFile .. ".ts"
  local filePath = basePath .. sourceFile

  if not fs.exists(filePath) then
    print("[WARN] No config found for role: " .. role)
    return
  end

  local serverTS = readTimestamp(tsPath)
  local clientTS = getClientLastSent(hostname, targetFile)

  if serverTS > clientTS then
    print("[UPDATE] Sending updated config for " .. hostname .. " (" .. role .. ")")
    local chunks = readFileInChunks(filePath, 4096)
    if chunks then
      sendChunkedFile(address, targetFile, chunks)
      updateClientLastSent(hostname, targetFile, serverTS)
    end
  else
    print("[SKIP] Config for " .. hostname .. " is up to date.")
  end
end

local function sendUniversalIfUpdated(hostname, address)
  for _, filename in ipairs(universalFiles) do
    local tsPath = basePath .. filename .. ".ts"
    local filePath = basePath .. filename

    local serverTS = readTimestamp(tsPath)
    local clientTS = getClientLastSent(hostname, filename)

    if fs.exists(filePath) and serverTS > clientTS then
      local chunks = readFileInChunks(filePath, 4096)
      if chunks then
        sendChunkedFile(address, filename, chunks)
        updateClientLastSent(hostname, filename, serverTS)
      end
    else
      print("[SKIP] " .. filename .. " for " .. hostname .. " is up to date.")
    end
  end
end

local function handleClientSync(hostname, address)
  local client = clients[hostname]

  -- Diagnostic logging
  if not client then
    print("[ERROR] handleClientSync: No client data for " .. tostring(hostname))
    return
  end
  if not client.address then
    print("[ERROR] handleClientSync: No address for " .. tostring(hostname))
    return
  end
  if not client.role then
    print("[ERROR] handleClientSync: No role for " .. tostring(hostname))
    return
  end

  local role = client.role
  local allUpToDate = true

  -- Config sync
  local configFile = "config.lua"
  local configSource = configPrefix .. role .. ".lua"
  local configTS = readTimestamp(basePath .. configSource .. ".ts")
  local configClientTS = getClientLastSent(hostname, configFile)

  if configTS > configClientTS then
    sendConfigIfUpdated(role, hostname, address)
    allUpToDate = false
  end

  -- Exporter sync
  for _, filename in ipairs(universalFiles) do
    local serverTS = readTimestamp(basePath .. filename .. ".ts")
    local clientTS = getClientLastSent(hostname, filename)
    if serverTS > clientTS then
      sendUniversalIfUpdated(hostname, address)
      allUpToDate = false
    end
  end

  -- Only start if everything is up to date
  if allUpToDate then
    print("[INFO] All files up to date for " .. hostname)
    print("[INFO] Attempting to send start_exporter to: " .. tostring(client.address))
    modem.send(address, port, "start_exporter")
    print("[START] Told " .. hostname .. " to run exporter")
  end
end


-- Main loop
while true do
  local evt = { event.pull(0.5, "modem_message") }
  local from = evt[3]
  local msg = evt[6]
  local hostname = evt[7]

  if msg == "hello" and hostname then
    local role = hostname:match("^([a-zA-Z]+)%d+") or "unknown"
    clients[hostname] = clients[hostname] or { address = from, role = role, lastSent = {} }
    clients[hostname].address = from
    clients[hostname].role = role
    print("[HELLO] " .. hostname .. " (" .. role .. ") at " .. from)
    handleClientSync(hostname, from)

    -- Register acknowledgment
    modem.send(from, port, "hello_ack")

    sendConfigIfUpdated(role, hostname, from)
    sendUniversalIfUpdated(hostname, from)

  elseif msg == "check_update" then
    print("[SYNC] " .. hostname .. " asked for update check")

    local client = clients[hostname]
    if not client then
      print("[WARN] Unknown client requested update check: " .. hostname)
      clients[hostname] = { address = from, role = "default", lastSent = {} } -- fallback
      client = clients[hostname]
    end

    local needsUpdate = false

    for _, filename in ipairs(universalFiles) do
      local tsPath = basePath .. filename .. ".ts"
      local serverTS = readTimestamp(tsPath)
      local clientTS = getClientLastSent(hostname, filename)
      if serverTS > clientTS then
        needsUpdate = true
        break
      end
    end

    local configFile = configPrefix .. client.role .. ".lua"
    local configTS = readTimestamp(basePath .. configFile .. ".ts")
    local clientConfigTS = getClientLastSent(hostname, "config.lua")
    if configTS > clientConfigTS then
      needsUpdate = true
    end

    if needsUpdate then
      modem.send(from, port, "update_required")
    else
      modem.send(from, port, "up_to_date")
    end
  end
end

