-- loader.lua =======

-- sunfish.lua bootstrap loader
-- This is the ONLY file you paste into Yantra's `scripts` editor.
-- Every /run downloads the LATEST core.lua, search.lua, ui.lua, help.lua,
-- mate1.lua, challenge.lua, main.lua from GitHub (in that order), load()s
-- each one into this same script's global scope, then runs main().
--
-- Because every run always fetches fresh code, you are always on the latest
-- version already. The in-game 'u' command (defined in core.lua) just checks
-- the manifest and reports the version/changelog -- any newer version takes
-- effect the next time you run this loader, not live during the current game.


local BASE_URL = "https://raw.githubusercontent.com/borko17/sunfish.lua/main/modular/"

local PARTS = {
"core.lua", 
"search.lua", 
"ui.lua", 
"help.lua", 
"mate1.lua", 
"challenge.lua", 
--"debug.lua", 
--"debug2.lua",
"main.lua"
}

local MANIFEST_NAME = "manifest.txt" -- fetched alongside the parts below, but it's plain text (not Lua) - kept raw in MANIFEST_CONTENT for checkForUpdate() to read, not load()ed as code

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

print("Loading sunfish.lua...")

-- Manifest is plain text, not Lua code: fetched once here and stashed globally
-- so checkForUpdate() (in core.lua) can just read it instead of fetching it again.
MANIFEST_CONTENT = fetchURL(BASE_URL .. MANIFEST_NAME)
if not MANIFEST_CONTENT or MANIFEST_CONTENT == '' then
   echoErr("Failed to download " .. MANIFEST_NAME .. ". Check your connection and try again.")
   return
end

local chunks = {}

for _, partName in ipairs(PARTS) do
   local content = fetchURL(BASE_URL .. partName)

   if not content or content == '' then
      echoErr("Failed to download " .. partName .. ". Check your connection and try again.")
      return
   end

   local chunk, err = load(content, partName)
   if not chunk then
      echoErr("Syntax error in " .. partName .. ": " .. tostring(err))
      return
   end
   chunks[#chunks + 1] = {name = partName, chunk = chunk}
end

-- Execute every part in order, in this same global scope.
for _, part in ipairs(chunks) do
   local ok, err = pcall(part.chunk)
   if not ok then
      echoErr("Error running " .. part.name .. ": " .. tostring(err))
      return
   end
end

-- Console output helpers (wrap binding.exec("echo -X " .. msg) calls for readability)
function echoE(msg) binding.exec("echo -e " .. msg) end -- error
function echoS(msg) binding.exec("echo -s " .. msg) end -- success
function echoW(msg) binding.exec("echo -w " .. msg) end -- warning/heading

-- Update info
-- loader.lua fetches manifest.txt once at startup (alongside the 7 code parts)
-- and stores its raw text in the global MANIFEST_CONTENT. checkForUpdate() below
-- just reads that instead of fetching it again over the network.

-- Low-level GET, same java.net.URL / BufferedReader approach already proven to work
-- from the original single-file checkForUpdate().
function fetchURL(url)
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

-- Extracts CHANGELOG table from raw manifest text (list of quoted strings inside CHANGELOG = { ... })
function parseChangelog(text)
   local body = text:match('CHANGELOG%s*=%s*{(.-)}')
   if not body then return nil end
   local list = {}
   for entry in body:gmatch('"(.-)"') do
      table.insert(list, entry)
   end
   if #list == 0 then return nil end
   return list
end

function printChangelog(list, versionLabel)
   print("")
   print("What's new in v" .. versionLabel .. ":")
   for _, line in ipairs(list) do
      print("• " .. line)
   end
end

function checkForUpdate()
   local result = MANIFEST_CONTENT

   if not result or result == '' then
      echoE("Manifest not available (failed to download at startup).")
      return
   end

   local remoteVersion = result:match('SCRIPT_VERSION%s*=%s*"([%d%.]+)"')
   if not remoteVersion then
      echoE("Could not find a version number in the manifest.")
      return
   end

   echoS("Running version: " .. remoteVersion)
   local remoteChangelog = parseChangelog(result)
   if remoteChangelog then
      printChangelog(remoteChangelog, remoteVersion)
   end
end

math.randomseed(os.time())
main()

-- loader.lua ======= end