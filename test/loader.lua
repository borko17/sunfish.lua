-- CONFIG: Options at the top
USE_UNICODE_PIECES = false
SHOW_ANNOTATIONS = true

CHALLENGE_MIN_PIECES = 10
CHALLENGE_MAX_PIECES = 20
CHALLENGE_GEN_ATTEMPTS = 400
CHALLENGE_HINTS_ENABLED = false -- shows suggested move; toggle with 'th'
NODES_SEARCHED = 2000 -- node budget/search; soft limit, checked only between depths
CHALLENGE_ENGINE_NODES = 600 -- separate, weaker budget for Sunfish's replies in Challenge mode
TABLE_SIZE = NODES_SEARCHED * 25 -- scaled off NODES_SEARCHED so it doesn't thrash; upstream's 1e6 too heavy for Luaj-jse on phone

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

local BASE_URL = "https://raw.githubusercontent.com/borko17/sunfish.lua/main/test/"
local PARTS = {"core.lua", "search.lua", "ui.lua", "help.lua", "mate1.lua", "challenge.lua", "main.lua"}
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
   binding.exec("echo -e Failed to download " .. MANIFEST_NAME .. ". Check your connection and try again.")
   return
end

local chunks = {}

for _, partName in ipairs(PARTS) do
   local content = fetchURL(BASE_URL .. partName)

   if not content or content == '' then
      binding.exec("echo -e Failed to download " .. partName .. ". Check your connection and try again.")
      return
   end

   local chunk, err = load(content, partName)
   if not chunk then
      binding.exec("echo -e Syntax error in " .. partName .. ": " .. tostring(err))
      return
   end
   chunks[#chunks + 1] = {name = partName, chunk = chunk}
end

-- Execute every part in order, in this same global scope.
for _, part in ipairs(chunks) do
   local ok, err = pcall(part.chunk)
   if not ok then
      binding.exec("echo -e Error running " .. part.name .. ": " .. tostring(err))
      return
   end
end

math.randomseed(os.time())
main()
