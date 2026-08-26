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
