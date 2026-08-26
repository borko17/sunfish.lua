-- sunfish.lua bootstrap loader
-- This is the ONLY file you paste into Yantra's `scripts` editor.
-- It downloads core.lua, search.lua, ui.lua, help.lua, mate1.lua,
-- challenge.lua, main.lua (in that order) from GitHub, load()s each
-- one into this same script's global scope, then runs main().
--
-- Everything after this point (fetchURL, checkForUpdate, applyHotPatch,
-- MANIFEST_PARTS, etc.) is defined inside core.lua and becomes available
-- globally once core.lua loads below -- that's how the in-game 'u' command
-- is able to re-fetch and hot-patch all 7 parts later without a restart.

local BASE_URL = "https://raw.githubusercontent.com/borko17/sunfish.lua/main/test/"
local PARTS = {"core.lua", "search.lua", "ui.lua", "help.lua", "mate1.lua", "challenge.lua", "main.lua"}
local CACHE_PREFIX = "sunfish_cache_"

local function fetchURL(url)
   local ok, result = pcall(function()
      local URL = luajava.bindClass("java.net.URL")
      local u = URL.new(url)
      local conn = u:openConnection()
      conn:setConnectTimeout(8000)
      conn:setReadTimeout(8000)
      conn:setRequestMethod("GET")

      local BufferedReader = luajava.bindClass("java.io.BufferedReader")
      local InputStreamReader = luajava.bindClass("java.io.InputStreamReader")
      local reader = BufferedReader.new(InputStreamReader.new(conn:getInputStream()))

      local sb = {}
      local line = reader:readLine()
      while line ~= nil do
         table.insert(sb, line)
         line = reader:readLine()
      end
      reader:close()
      return table.concat(sb, "\n")
   end)
   if ok then return result end
   return nil
end

-- Best-effort local cache read, used only if the network fetch below fails
-- (e.g. no connection on startup). Silently returns nil if io.open isn't
-- available in this Luaj/Yantra sandbox.
local function cacheRead(name)
   local ok, content = pcall(function()
      local f = io.open(CACHE_PREFIX .. name, "r")
      if not f then error("no io") end
      local c = f:read("*a")
      f:close()
      return c
   end)
   if ok then return content end
   return nil
end

local function cacheWrite(name, content)
   pcall(function()
      local f = io.open(CACHE_PREFIX .. name, "w")
      if not f then error("no io") end
      f:write(content)
      f:close()
   end)
end

print("Loading sunfish.lua...")

local chunks = {}
local usedCache = false

for _, partName in ipairs(PARTS) do
   local content = fetchURL(BASE_URL .. partName)
   if not content or content == '' then
      -- Network failed for this part -- fall back to local cache if we have one.
      content = cacheRead(partName)
      if content then
         usedCache = true
      end
   end

   if not content or content == '' then
      binding.exec("echo -e Failed to load " .. partName .. " (no network and no local cache). Cannot start.")
      return
   end

   local chunk, err = load(content, partName)
   if not chunk then
      binding.exec("echo -e Syntax error in " .. partName .. ": " .. tostring(err))
      return
   end
   chunks[#chunks + 1] = {name = partName, chunk = chunk, content = content}
end

if usedCache then
   print("(Some parts loaded from local cache -- check your connection for the latest version.)")
end

-- Execute every part in order, in this same global scope.
for _, part in ipairs(chunks) do
   local ok, err = pcall(part.chunk)
   if not ok then
      binding.exec("echo -e Error running " .. part.name .. ": " .. tostring(err))
      return
   end
   cacheWrite(part.name, part.content)
end

math.randomseed(os.time())
main()
