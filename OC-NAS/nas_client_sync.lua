local component = require("component")
local event = require("event")
local modem = component.modem
local fs = require("filesystem")
local computer = require("computer")

local port = 1234
local hostname = os.getenv("HOSTNAME") or "unknown"
local registered = false
local lastHelloTime = computer.uptime()

modem.open(port)
print("[Client] Hostname is " .. hostname)

-- Send hello on start
modem.broadcast(port, "hello", hostname)

local fileBuffer = {}

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

local function saveFile(filename, content)
  local path = "/home/" .. filename
  local f = io.open(path, "wb")
  if f then
    f:write(content)
    f:close()
    print("[SAVED] " .. filename)
  else
    print("[ERROR] Could not write file: " .. filename)
  end
end

local function joinChunks(chunks)
  return table.concat(chunks)
end

local function checkRegistration()
  local now = computer.uptime()

  -- Resend hello every 5s if not registered
  if not registered and (now - lastHelloTime > 2) then
    print("[RETRY] Resending hello...")
    modem.broadcast(port, "hello", hostname)
    lastHelloTime = now
  end

  -- After registration, still send hello every 30s to re-confirm with server
  if registered and (now - lastHelloTime > 3) then
    print("[HEARTBEAT] Sending periodic hello to server...")
    modem.broadcast(port, "hello", hostname)
    lastHelloTime = now
  end
end


print("[Client] Waiting for file commands...")

while true do
  if needExitFlag then break end
  local ev = { event.pull(1, "modem_message") }
  checkRegistration()

  if #ev == 0 then
    -- timeout, keep looping
  else
    local exporterRunning = false
    local _, _, from, _, _, cmd, filename, a, b = table.unpack(ev)

    if cmd == "file_start" then
      fileBuffer[filename] = { total = a, chunks = {} }
      print("[RECV] Start " .. filename .. " (" .. a .. " chunks)")
    elseif cmd == "file_chunk" then
      if fileBuffer[filename] then
        fileBuffer[filename].chunks[a] = b
      end
    elseif cmd == "file_end" then
      if fileBuffer[filename] then
        local content = joinChunks(fileBuffer[filename].chunks)
        saveFile(filename, content)
        fileBuffer[filename] = nil
      end
    elseif cmd == "hello_ack" then
      registered = true
      print("[REGISTERED] Successfully registered with server.")
    elseif cmd == "start_exporter" and not exporterRunning then
      exporterRunning = true
      print("[START] Executing exporter.lua...")
      os.execute("/home/exporter.lua &")
    elseif cmd == "quit" then
      print("[EXIT] Server asked to quit.")
      break
    end
  end
end
