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

local BASE_URL = "https://raw.githubusercontent.com/borko17/sunfish.lua/main/modular/"
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

math.randomseed(os.time())
main()

-- CONFIG has moved to loader.lua (it runs first and sets USE_UNICODE_PIECES,
-- SHOW_ANNOTATIONS, CHALLENGE_MIN_PIECES, CHALLENGE_MAX_PIECES,
-- CHALLENGE_GEN_ATTEMPTS, CHALLENGE_HINTS_ENABLED, NODES_SEARCHED,
-- CHALLENGE_ENGINE_NODES, and TABLE_SIZE as globals before any part below runs).

MATE_VALUE = 30000 -- exceeds 8*queen+2*(rook+knight+bishop); king value is double this
MATE_UPPER = 60000 + (10 * 2529) -- search() scores mate near this, not MATE_VALUE - callers must match

A1, H1, A8, H8 = 91, 98, 21, 28 -- board is a 120-char padded string for cheap off-board checks
initial =
    '         \n' .. --   0 -  9
    '         \n' .. --  10 - 19
    ' rnbqkbnr\n' .. --  20 - 29
    ' pppppppp\n' .. --  30 - 39
    ' ........\n' .. --  40 - 49
    ' ........\n' .. --  50 - 59
    ' ........\n' .. --  60 - 69
    ' ........\n' .. --  70 - 79
    ' PPPPPPPP\n' .. --  80 - 89
    ' RNBQKBNR\n' .. --  90 - 99
    '         \n' .. -- 100 -109
    '          '     -- 110 -119

__1 = 1 -- 1-index correction

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



-- Move and evaluation tables
N, E, S, W = -10, 1, 10, -1
directions = {
    P = {N, 2*N, N+W, N+E},
    N = {2*N+E, N+2*E, S+2*E, 2*S+E, 2*S+W, S+2*W, N+2*W, 2*N+W},
    B = {N+E, S+E, S+W, N+W},
    R = {N, E, S, W},
    Q = {N, E, S, W, N+E, S+E, S+W, N+W},
    K = {N, E, S, W, N+E, S+E, S+W, N+W}
}

PROMOTION_PIECES = {"N", "B", "R", "Q"} -- hoisted out of genMoves_impl to avoid re-allocating per pawn

pst = {
    P = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 198, 198, 198, 198, 198, 198, 198, 198, 0,
        0, 178, 198, 198, 198, 198, 198, 198, 178, 0,
        0, 178, 198, 198, 198, 198, 198, 198, 178, 0,
        0, 178, 198, 208, 218, 218, 208, 198, 178, 0,
        0, 178, 198, 218, 238, 238, 218, 198, 178, 0,
        0, 178, 198, 208, 218, 218, 208, 198, 178, 0,
        0, 178, 198, 198, 198, 198, 198, 198, 178, 0,
        0, 198, 198, 198, 198, 198, 198, 198, 198, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    B = {
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 797, 824, 817, 808, 808, 817, 824, 797, 0,
        0, 814, 841, 834, 825, 825, 834, 841, 814, 0,
        0, 818, 845, 838, 829, 829, 838, 845, 818, 0,
        0, 824, 851, 844, 835, 835, 844, 851, 824, 0,
        0, 827, 854, 847, 838, 838, 847, 854, 827, 0,
        0, 826, 853, 846, 837, 837, 846, 853, 826, 0,
        0, 817, 844, 837, 828, 828, 837, 844, 817, 0,
        0, 792, 819, 812, 803, 803, 812, 819, 792, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    N = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 627, 762, 786, 798, 798, 786, 762, 627, 0,
        0, 763, 798, 822, 834, 834, 822, 798, 763, 0,
        0, 817, 852, 876, 888, 888, 876, 852, 817, 0,
        0, 797, 832, 856, 868, 868, 856, 832, 797, 0,
        0, 799, 834, 858, 870, 870, 858, 834, 799, 0,
        0, 758, 793, 817, 829, 829, 817, 793, 758, 0,
        0, 739, 774, 798, 810, 810, 798, 774, 739, 0,
        0, 683, 718, 742, 754, 754, 742, 718, 683, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    R = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 1258, 1263, 1268, 1272, 1272, 1268, 1263, 1258, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    Q = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 2529, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
    K = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 60098, 60132, 60073, 60025, 60025, 60073, 60132, 60098, 0,
        0, 60119, 60153, 60094, 60046, 60046, 60094, 60153, 60119, 0,
        0, 60146, 60180, 60121, 60073, 60073, 60121, 60180, 60146, 0,
        0, 60173, 60207, 60148, 60100, 60100, 60148, 60207, 60173, 0,
        0, 60196, 60230, 60171, 60123, 60123, 60171, 60230, 60196, 0,
        0, 60224, 60258, 60199, 60151, 60151, 60199, 60258, 60224, 0,
        0, 60287, 60321, 60262, 60214, 60214, 60262, 60321, 60287, 0,
        0, 60298, 60332, 60273, 60225, 60225, 60273, 60332, 60298, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
}

-- Endgame "mop-up" king table: rewards centralization so won K+R/Q vs K converges instead of hitting the 50-move limit
pst_K_endgame = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 59930, 59940, 59950, 59960, 59960, 59950, 59940, 59930, 0,
    0, 59940, 59950, 59960, 59970, 59970, 59960, 59950, 59940, 0,
    0, 59950, 59960, 59970, 59980, 59980, 59970, 59960, 59950, 0,
    0, 59960, 59970, 59980, 59990, 59990, 59980, 59970, 59960, 0,
    0, 59960, 59970, 59980, 59990, 59990, 59980, 59970, 59960, 0,
    0, 59950, 59960, 59970, 59980, 59980, 59970, 59960, 59950, 0,
    0, 59940, 59950, 59960, 59970, 59970, 59960, 59950, 59940, 0,
    0, 59930, 59940, 59950, 59960, 59960, 59950, 59940, 59930, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

pst_K_midgame = pst.K

-- Chess logic
function isspace(s)
   if s == ' ' or s == '\n' then
      return true
   else
      return false
   end
end

special = '. \n'

function isupper(s)
   if special:find(s) then return false end
   return s:upper() == s
end

function islower(s)
   if special:find(s) then return false end
   return s:lower() == s
end

-- Board representation: internally a Lua array (board[i] = byte at square i, 1-indexed), not a 120-char string - table index/write instead of string:sub()/rebuild. boardToArray() converts a string board on entry; arrayToBoard() converts back when printboard/save/UI need the string form.
function boardToArray(str)
   local arr = {}
   for i = 1, #str do
      arr[i] = string.byte(str, i)
   end
   return arr
end

function arrayToBoard(arr)
   local chars = {}
   for i = 1, #arr do
      chars[i] = string.char(arr[i])
   end
   return table.concat(chars)
end

-- metatable (__index) instead of per-instance methods: cheaper since search() creates thousands of Positions
Position = {}
Position.__index = Position

-- board: string (converted to array here) or already an array (fast path from move_impl/rotate)
function Position.new(board, score, wc, bc, ep, kp)
   local self = setmetatable({}, Position)
   self.board = (type(board) == "string") and boardToArray(board) or board
   self.score = score
   self.wc = wc
   self.bc = bc
   self.ep = ep
   self.kp = kp
   return self
end

function Position:genMoves_impl()
   local moves = {}
   local board = self.board -- array of byte values, 1-indexed

   local boardLen = #board

   for i = 1 - __1, boardLen - __1 do
      local pb = board[i + __1]

      -- Skip fast if not an uppercase piece byte; inlined (not a closure) since Luaj-jse allocates one per nested local function per call
      if pb and pb >= 65 and pb <= 90 then
         local p = string.char(pb)

         if directions[p] then
            for _, d in ipairs(directions[p]) do
               local j = i + d

               while true do
                  local qb = board[j + __1]

                  -- raw-byte checks, no string.char() alloc: isspace=32/10, uppercase=65-90
                  if qb == nil or qb == 32 or qb == 10 or (qb >= 65 and qb <= 90) then
                     break
                  end

                  if p == 'P' then
                     if (d == N or d == 2*N) and qb ~= 46 then -- not '.'
                        break
                     end

                     if d == 2*N and
                        (i < A1 + N or
                         board[i + N + __1] ~= 46) then -- '.'
                        break
                     end

                     if (d == N+W or d == N+E) and
                        qb == 46 and -- '.'
                        j ~= self.ep and
                        math.abs(j - self.kp) > 1 then
                        break
                     end
                  end

                  -- pawn-only promotion check (A8..H8 is a normal landing zone for other pieces too)
                  if p == 'P' and A8 <= j and j <= H8 then
                     for _, prom in ipairs(PROMOTION_PIECES) do
                        table.insert(moves, {i, j, prom})
                     end
                     break
                  end

                  table.insert(moves, {i, j, ""})

                  if p == 'P' or p == 'N' or p == 'K' then
                     break
                  end

                  if qb >= 97 and qb <= 122 then -- islower(q)
                     break
                  end

                  j = j + d
               end
            end
         end
      end
   end

-- Castling: rook on home square, right still available, squares between king and rook empty
   local kingIdx = nil
   for i = 1 - __1, boardLen - __1 do
      if board[i + __1] == 75 then -- 'K'
         kingIdx = i
         break
      end
   end

   if kingIdx then
      if self.wc[1] and board[A1 + __1] == 82 then -- 'R'
         local empty = true
         for sq = A1 + E, kingIdx - E, E do
            if board[sq + __1] ~= 46 then -- '.'
               empty = false
               break
            end
         end
         if empty then
            table.insert(moves, {kingIdx, kingIdx + 2*W, ""})
         end
      end

      if self.wc[2] and board[H1 + __1] == 82 then -- 'R'
         local empty = true
         for sq = kingIdx + E, H1 - E, E do
            if board[sq + __1] ~= 46 then -- '.'
               empty = false
               break
            end
         end
         if empty then
            table.insert(moves, {kingIdx, kingIdx + 2*E, ""})
         end
      end
   end

   return moves
end

-- Profiling counters (temporary)
PROFILE_genMoves_time = 0
PROFILE_genMoves_calls = 0
PROFILE_move_time = 0
PROFILE_move_calls = 0

function Position:genMoves()
   local t0 = os.clock()
   local result = self:genMoves_impl()
   PROFILE_genMoves_time = PROFILE_genMoves_time + (os.clock() - t0)
   PROFILE_genMoves_calls = PROFILE_genMoves_calls + 1
   return result
end

function Position:rotate(nullmove)
   nullmove = nullmove or false

   local ep = 0
   local kp = 0

   if not nullmove then
      if self.ep and self.ep ~= 0 then
         ep = 119 - self.ep
      end

      if self.kp and self.kp ~= 0 then
         kp = 119 - self.kp
      end
   end

   -- Reverse + swap case per byte in one pass (no string:reverse()/rebuild)
   local srcBoard = self.board
   local len = #srcBoard
   local newBoard = {}
   for idx = 1, len do
      local b = srcBoard[len - idx + 1]
      if b >= 65 and b <= 90 then
         newBoard[idx] = b + 32
      elseif b >= 97 and b <= 122 then
         newBoard[idx] = b - 32
      else
         newBoard[idx] = b
      end
   end

   return self.new(
      newBoard,
      -self.score,
      self.bc,
      self.wc,
      ep,
      kp
   )
end

function Position:move_impl(move)
   assert(move)

   local i = move[1]
   local j = move[2]
   local prom = move[3] or ""

   -- copy board array (no alias with parent), then edit directly by index
   local srcBoard = self.board
   local board = {}
   for idx = 1, #srcBoard do
      board[idx] = srcBoard[idx]
   end

   local pb = srcBoard[i + __1]
   local qb = srcBoard[j + __1]
   local p = string.char(pb)
   local q = string.char(qb)

   local wc = self.wc
   local bc = self.bc
   local ep = 0
   local kp = 0

   local score = self.score + self:value(move)

   local DOT = 46 -- '.'

   board[j + __1] = pb
   board[i + __1] = DOT

   if i == A1 then
      wc = {false, wc[2]}
   elseif i == H1 then
      wc = {wc[1], false}
   end

   if j == H8 then
      bc = {bc[1], false}
   elseif j == A8 then
      bc = {false, bc[2]}
   end

   if p == 'K' then
      wc = {false, false}

      if math.abs(j - i) == 2 then
         kp = math.floor((i + j) / 2)

         local rookSquare = (j < i) and A1 or H1

         board[rookSquare + __1] = DOT
         board[kp + __1] = 82 -- 'R'
      end
   end

   if p == 'P' then
      if A8 <= j and j <= H8 then
         if prom == '' then
            prom = 'Q' -- old UI sends no promotion field
         end
         board[j + __1] = string.byte(prom) -- overwrites the push above, same square
      end

      if j - i == 2 * N then
         ep = i + N
      end

      if j == self.ep then
         board[j + S + __1] = DOT
      end
   end

   return self.new(board, score, wc, bc, ep, kp):rotate()
end

function Position:move(move)
   local t0 = os.clock()
   local result = self:move_impl(move)
   PROFILE_move_time = PROFILE_move_time + (os.clock() - t0)
   PROFILE_move_calls = PROFILE_move_calls + 1
   return result
end

function Position:value(move)
   local i = move[1]
   local j = move[2]
   local prom = move[3] or ""

   local board = self.board
   local pb = board[i + __1]
   local qb = board[j + __1]
   local p = string.char(pb)

   local score = pst[p][j + __1] - pst[p][i + __1]

   -- Capture: PST already oriented via rotate(), so j is read directly. islower inlined as byte range (97-122).
   if qb >= 97 and qb <= 122 then
      score = score + pst[string.char(qb - 32)][j + __1]
   end

   if math.abs(j - self.kp) < 2 then
      score = score + pst['K'][j + __1]
   end

   if p == 'K' and math.abs(i - j) == 2 then
      score = score + pst['R'][math.floor((i + j) / 2) + __1]
      score = score - pst['R'][
         (j < i) and (A1 + __1) or (H1 + __1)
      ]
   end

   if p == 'P' then
      if A8 <= j and j <= H8 then
         if prom == '' then
            prom = 'Q'
         end

         score = score
            + pst[prom][j + __1]
            - pst['P'][j + __1]
      end

      if j == self.ep then
         score = score + pst['P'][j + S + __1]
      end
   end

   return score
end

-- Move capturing opponent king among pseudo-legal moves, if any; used by null-move pruning/mate detection. abs(j-self.kp)<2 also counts as check: kp is the square passed through on a recent castle, illegal to land near.
function Position:kingCapture()
   for _, move in ipairs(self:genMoves()) do
      local j = move[2]
      local targetByte = self.board[j + __1]

      if targetByte == 107 or math.abs(j - self.kp) < 2 then -- 'k'
         return move
      end
   end

   return nil
end

-- Insufficient material -> immediate draw. Covers K vs K, K+B/N vs K (either side); any P/R/Q is always sufficient; K+2N vs K also treated as insufficient (common engine convention).
function hasInsufficientMaterial(board)
   local whiteMinor, blackMinor = 0, 0

   for i = 1, #board do
      local b = board[i]
      if b ~= 46 and b ~= 32 and b ~= 10 then -- skip '.', space, newline
         local isUpper = b >= 65 and b <= 90
         local upperB = isUpper and b or (b - 32) -- uppercase byte form
         if upperB ~= 75 then -- not 'K'
            if upperB == 66 or upperB == 78 then -- 'B' or 'N'
               if isUpper then
                  whiteMinor = whiteMinor + 1
               else
                  blackMinor = blackMinor + 1
               end
            else
               return false -- P, R, or Q present: always sufficient
            end
         end
      end
   end

   if whiteMinor <= 1 and blackMinor == 0 then return true end
   if blackMinor <= 1 and whiteMinor == 0 then return true end

   return false
end

tp = {}
-- Ring buffer of hashes sized to TABLE_SIZE; tp_head is the next write slot, evicting the oldest entry in O(1) when full.
tp_index = {}
tp_count = 0
tp_head = 1        -- next slot to write (1-indexed)
tp_capacity = 0    -- slots currently allocated in tp_index

tp_popitem = nil -- forward-declared, used by tp_set() before its definition below

function tpKey(pos)
   if pos.key then
      return pos.key
   end

   local w1 = pos.wc[1] and '1' or '0'
   local w2 = pos.wc[2] and '1' or '0'
   local b1 = pos.bc[1] and '1' or '0'
   local b2 = pos.bc[2] and '1' or '0'

   -- table.concat on the raw byte array (separator avoids digit-run collisions) is cheaper than string.char()+concat per square
   local key = table.concat(pos.board, ",")
      .. ';' .. tostring(pos.score)
      .. ';' .. w1 .. w2
      .. ';' .. b1 .. b2
      .. ';' .. tostring(pos.ep or 0)
      .. ';' .. tostring(pos.kp or 0)

   pos.key = key

   return key
end

function tp_set_impl(pos, depth, canNull, lower, upper, move)
   local hash = tpKey(pos)

   local entry = tp[hash]

   if not entry then
      entry = {
         bounds = {},
         move = nil
      }

      tp[hash] = entry

      if tp_count < TABLE_SIZE then -- buffer has room: append
         tp_capacity = tp_capacity + 1
         tp_index[tp_capacity] = hash
         tp_count = tp_count + 1
      else -- buffer full: evict oldest slot (tp_head) in O(1)
         local evicted = tp_index[tp_head]
         if evicted and evicted ~= hash then
            tp[evicted] = nil
         end
         tp_index[tp_head] = hash
         tp_head = tp_head % TABLE_SIZE + 1
         -- tp_count stays at TABLE_SIZE
      end
   end

   if depth ~= nil and lower ~= nil and upper ~= nil then
-- Only write bounds when both lower and upper are supplied, so killer-only calls (tp_set(p, depth, true, nil, nil, move)) don't stomp an existing {lower, upper} pair with nils.
      local boundKey = tostring(depth) .. ":" ..
         (canNull and "1" or "0")

      entry.bounds[boundKey] = {
         lower = lower,
         upper = upper
      }
   end

   if move ~= nil then
      entry.move = move
   end

   -- eviction handled inline above via ring buffer; tp_popitem kept as no-op export for compatibility
end


function tp_get_impl(pos, depth, canNull)
   local hash = tpKey(pos)
   local entry = tp[hash]

   if not entry then
      return nil, nil, nil
   end

   local bound = nil

   if depth ~= nil then
      local boundKey = tostring(depth) .. ":" ..
         (canNull and "1" or "0")

      bound = entry.bounds[boundKey]
   end

   return entry, bound, entry.move
end

PROFILE_tp_time = 0
PROFILE_tp_calls = 0
PROFILE_tpKey_time = 0
PROFILE_tpKey_calls = 0

function tp_set(pos, depth, canNull, lower, upper, move)
   local t0 = os.clock()
   tp_set_impl(pos, depth, canNull, lower, upper, move)
   PROFILE_tp_time = PROFILE_tp_time + (os.clock() - t0)
   PROFILE_tp_calls = PROFILE_tp_calls + 1
end

function tp_get(pos, depth, canNull)
   local t0 = os.clock()
   local a, b, c = tp_get_impl(pos, depth, canNull)
   PROFILE_tp_time = PROFILE_tp_time + (os.clock() - t0)
   PROFILE_tp_calls = PROFILE_tp_calls + 1
   return a, b, c
end

tp_popitem = function(protectedHash)
   -- no-op: eviction handled inline (O(1)) inside tp_set via the ring buffer
end

-- Null-move pruning: true if any rook/bishop/knight/queen (either color) remains. Single pass, stops at first hit.
function hasMajorOrMinorPiece(board)
   for idx = 1, #board do
      local b = board[idx]
      -- R=82 r=114 B=66 b=98 N=78 n=110 Q=81 q=113
      if b == 82 or b == 114 or b == 66 or b == 98
         or b == 78 or b == 110 or b == 81 or b == 113 then
         return true
      end
   end
   return false
end

function findCheckers(p)
   local kingIdx = nil
   local board = p.board
   for i = 1 - __1, #board - __1 do
      if board[i + __1] == 75 then -- 'K'
         kingIdx = i
         break
      end
   end
   if not kingIdx then return {} end

   local rp = p:rotate()
   local targetJ = 119 - kingIdx
   local checkers = {}
   for _, move in ipairs(rp:genMoves()) do
      if move[1 + __1] == targetJ then
         checkers[119 - move[0 + __1]] = true
      end
   end
   return checkers
end

-- Search logic
nodes = 0 -- module-scoped: shared by search()'s loop and the inner bound() closure

-- Quiescence value floor: deeper nodes admit slightly weaker captures/threats before cutting off
QS = 40
QS_A = 140

function search(pos, maxn, history)
   maxn = maxn or NODES_SEARCHED
   history = history or {}

   nodes = 0

   PROFILE_genMoves_time = 0
   PROFILE_genMoves_calls = 0
   PROFILE_move_time = 0
   PROFILE_move_calls = 0
   PROFILE_tp_time = 0
   PROFILE_tp_calls = 0

   local startTime = os.clock()
   local reachedDepth = 0
   local finalScore = 0

   local MATE_LOWER = 60000 - (13 * 2529)
   local MATE_UPPER = 60000 + (10 * 2529)

   local EVAL_ROUGHNESS = 15

   -- endgame king table once queens are off (KRK/KQK convergence); pst.K restored after search() since pst is shared/global
   local prevPstK = pst.K

   local hasWhiteQueen = arrayToBoard(pos.board):find('Q', 1, true) ~= nil
   local hasBlackQueen = arrayToBoard(pos.board):find('q', 1, true) ~= nil

   if hasWhiteQueen and hasBlackQueen then
      pst.K = pst_K_midgame
   else
      pst.K = pst_K_endgame
   end

   -- fresh TT for every root search, as in upstream Sunfish
   tp = {}
   tp_index = {}
   tp_count = 0
   tp_head = 1
   tp_capacity = 0

   local function bound(p, gamma, depth, root)
      nodes = nodes + 1

      if depth < 0 then
         depth = 0
      end

      if p.score <= -MATE_LOWER then
         return -MATE_UPPER
      end

      local entry, storedBound, killer = tp_get(
         p,
         depth,
         true
      )

      -- Root probes intentionally don't consume a stored score bound.
      if not root and storedBound then
         if storedBound.lower >= gamma then
            return storedBound.lower
         end

         if storedBound.upper < gamma then
            return storedBound.upper
         end
      end

      -- Repetition detection: seen-before position scores as draw (0); skipped at root/depth 0, matching upstream
      if not root and depth > 0 and history[tpKey(p)] then
         return 0
      end

      local best = -MATE_UPPER
      local bestMove = nil
      local live = false

      -- Null-move pruning: not root, depth > 2, eval near equality, major/minor piece remains
      if not root
         and depth > 2
         and math.abs(p.score) < 500
         and hasMajorOrMinorPiece(p.board) then

         local nullScore = math.min(
            p.score + EVAL_ROUGHNESS,
            -bound(
               p:rotate(true),
               1 - gamma,
               depth - 3,
               false
            )
         )

         best = nullScore

         if nullScore >= gamma then
            local proof = killer or p:kingCapture()

            if proof and p:value(proof) >= MATE_LOWER then
               best = MATE_UPPER
               bestMove = proof
            else
               return best
            end
         end
      end

      if depth == 0 then
         if p.score > best then
            best = p.score
         end
      end

      if killer == nil and depth > 2 then
         bound(p, gamma, depth - 3, true)

         local _, _, iidMove = tp_get(
            p,
            depth,
            true
         )

         killer = iidMove
      end

      local valLower = QS - depth * QS_A

      if killer and p:value(killer) >= valLower then
         local childScore = -bound(
            p:move(killer),
            1 - gamma,
            depth - 1,
            false
         )

         if childScore > best then
            best = childScore
            bestMove = killer
         end

         if childScore > -MATE_UPPER then
            live = true
         end

         if best >= gamma then
            if depth > 0 then
               tp_set(
                  p,
                  depth,
                  true,
                  best,
                  storedBound and storedBound.upper or MATE_UPPER,
                  killer
               )
            end

            return best
         end
      end

      local ordered = {}

      for _, move in ipairs(p:genMoves()) do
         local val = p:value(move)

         if val >= valLower then
            table.insert(ordered, {
               value = val,
               move = move
            })
         end
      end

      table.sort(ordered, function(a, b)
         return a.value > b.value
      end)

      for _, item in ipairs(ordered) do
         local move = item.move
         local val = item.value

         if depth <= 1 and p.score + val < gamma then
            local futilityScore

            if val >= MATE_LOWER then
               futilityScore = MATE_UPPER
            else
               futilityScore = p.score + val
            end

            if futilityScore > best then
               best = futilityScore
            end

            break -- ordered by value: nothing later can improve it
         end

         local childScore = -bound(
            p:move(move),
            1 - gamma,
            depth - 1,
            false
         )

         if childScore > best then
            best = childScore
            bestMove = move
         end

         if childScore > -MATE_UPPER then
            live = true
         end

         if best >= gamma then
            break
         end
      end

      if depth > 0 and not live then
         local moves = p:genMoves()
         local noLegalMove = true

         for _, move in ipairs(moves) do
            local child = p:move(move)

            if not child:kingCapture() then
               noLegalMove = false
               break
            end
         end

         if noLegalMove then
            if p:rotate(true):kingCapture() then
               best = -MATE_LOWER
            else
               best = 0
            end

            bestMove = nil
         end
      end

      if best >= gamma and bestMove ~= nil and depth > 0 then
         tp_set(
            p,
            depth,
            true,
            nil,
            nil,
            bestMove
         )
      end

      if root and best >= gamma and bestMove ~= nil then -- root move needed after depth finishes
         tp_set(
            p,
            nil,
            nil,
            nil,
            nil,
            bestMove
         )
      end

      if not root then -- store lower/upper bound for non-root searches
         local oldLower = storedBound and
            storedBound.lower or -MATE_UPPER

         local oldUpper = storedBound and
            storedBound.upper or MATE_UPPER

         if best >= gamma then
            oldLower = best
         else
            oldUpper = best
         end

         tp_set(
            p,
            depth,
            true,
            oldLower,
            oldUpper,
            nil
         )
      end

      return best
   end

   -- Iterative deepening MTD-bi.
   for depth = 1, 98 do
      local lower = 1 - MATE_UPPER
      local upper = MATE_UPPER
      local gamma = 0
      local score = 0

      while lower < upper - EVAL_ROUGHNESS do
         score = bound(pos, gamma, depth, true)

         if score >= gamma then
            lower = score
         else
            upper = score
         end

         gamma = math.floor((lower + upper + 1) / 2)
      end

      finalScore = score
      reachedDepth = depth

      local nodeDisplay
      if maxn < 1000 then
         nodeDisplay = tostring(maxn)
      else
         nodeDisplay = string.format("%dk", math.floor(maxn / 1000))
      end
      echoW(string.format(
         "(depth %d, %d/%s nodes)",
         depth, nodes, nodeDisplay
      ))

      if nodes >= maxn or
         math.abs(score) >= MATE_UPPER then
         break
      end
   end

   local _, _, rootMove = tp_get(pos, nil, nil)

   local elapsed = os.clock() - startTime

-- Restore pst.K so code outside search() isn't affected by the picked king table
   pst.K = prevPstK

   return rootMove,
      finalScore,
      reachedDepth,
      nodes,
      elapsed
end

-- Display symbols

emptySquareSymbols_unicode = {
   dark = '\xe2\x80\xa2',
   light = '\xe2\x97\xa6'
}
emptySquareSymbols_letters = {
   dark = ':',
   light = '.'
}

whiteSymbols_unicode = {
   K = '\xe2\x99\x9a', Q = '\xe2\x99\x9b', R = '\xe2\x99\x9c',
   B = '\xe2\x99\x9d', N = '\xe2\x99\x9e', P = '\xe2\x99\x9f',
}
blackSymbols_unicode = {
   K = '\xe2\x99\x94', Q = '\xe2\x99\x95', R = '\xe2\x99\x96',
   B = '\xe2\x99\x97', N = '\xe2\x99\x98', P = '\xe2\x99\x99',
}

whiteSymbols_letters = {
   K = 'K', Q = 'Q', R = 'R', B = 'B', N = 'N', P = 'P',
}
blackSymbols_letters = {
   K = 'k', Q = 'q', R = 'r', B = 'b', N = 'n', P = 'p',
}

whiteSymbols = USE_UNICODE_PIECES and whiteSymbols_unicode or whiteSymbols_letters
blackSymbols = USE_UNICODE_PIECES and blackSymbols_unicode or blackSymbols_letters
emptySquareSymbols = USE_UNICODE_PIECES and emptySquareSymbols_unicode or emptySquareSymbols_letters


function updateDisplayMode()
   whiteSymbols = USE_UNICODE_PIECES and whiteSymbols_unicode or whiteSymbols_letters
   blackSymbols = USE_UNICODE_PIECES and blackSymbols_unicode or blackSymbols_letters
   emptySquareSymbols = USE_UNICODE_PIECES and emptySquareSymbols_unicode or emptySquareSymbols_letters
end

-- User interface

function parse(c)
   if not c then return nil end
   local p, v = c:sub(1,1), c:sub(2,2)
   if not (p and v and tonumber(v)) then return nil end

   local fil, rank = string.byte(p) - string.byte('a'), tonumber(v) - 1
   return A1 + fil - 10*rank
end

function render(i)
   local rank, fil = math.floor((i - A1) / 10), (i - A1) % 10
   return string.char(fil + string.byte('a')) .. tostring(-rank + 1)
end

function ttfind(t, k)
   assert(t)

   if not k or not k[1] or not k[2] then
      return false
   end

   for _, v in ipairs(t) do
      if k[1] == v[1] and k[2] == v[2] then
         if v[3] and v[3] ~= '' and -- existing UI sends no promo char; default to queen
            (k[3] == nil or k[3] == '') then
            k[3] = v[3]

            if v[3] ~= 'Q' then -- prefer queen when several promotion moves share i/j
               for _, candidate in ipairs(t) do
                  if candidate[1] == k[1]
                     and candidate[2] == k[2]
                     and candidate[3] == 'Q' then
                     k[3] = 'Q'
                     break
                  end
               end
            end
         end

         return true
      end
   end

   return false
end

strsplit = function(a)
   local out = {}
   while true do
      local pos, _ = a:find('\n')
      if pos then
         out[#out+1] = a:sub(1, pos-1)
         a = a:sub(pos+1)
      else
         out[#out+1] = a
         break
      end
   end
   return out
end

function printboard(board, lastMove, checkers, guards, isMate, hints)
   checkers = checkers or {}
   guards = guards or {}
   hints = hints or {}
   local highlight = {}
   if lastMove then
      highlight[lastMove[1]] = true
      highlight[lastMove[2]] = true
   end

   local l = strsplit(board, '\n')
   print("")
   local topBorder, sideBorder, bottomBorder
   if USE_UNICODE_PIECES then
      local horiz = '\xe2\x95\x90'  -- ═
      topBorder    = "  \xe2\x95\x94" .. string.rep(horiz, 26) .. "\xe2\x95\x97"  -- ╔ ... ╗
      sideBorder   = '\xe2\x95\x91'                                               -- ║
      bottomBorder = "  \xe2\x95\x9a" .. string.rep(horiz, 26) .. "\xe2\x95\x9d"  -- ╚ ... ╝
   else
      topBorder = "  +" .. string.rep("-", 26) .. "+"
      sideBorder = "|"
      bottomBorder = "  +" .. string.rep("-", 26) .. "+"
   end

   print(topBorder)
   for k = 3, 10 do
      local rank = 11 - k
      local v = l[k]
      local line = {}
      table.insert(line, tostring(rank) .. " " .. sideBorder .. "  ")
      for i = 2, 9 do
         local c = v:sub(i, i)
         local file = i - 1
         local idx = (k - 1) * 10 + (i - 1)
         local sym
         if c == '.' then
            if (file + rank) % 2 == 0 then
               sym = emptySquareSymbols.light
            else
               sym = emptySquareSymbols.dark
            end
         elseif USE_UNICODE_PIECES then
            if c == 'K' then sym = '\xe2\x99\x9a'
            elseif c == 'Q' then sym = '\xe2\x99\x9b'
            elseif c == 'R' then sym = '\xe2\x99\x9c'
            elseif c == 'B' then sym = '\xe2\x99\x9d'
            elseif c == 'N' then sym = '\xe2\x99\x9e'
            elseif c == 'P' then sym = '\xe2\x99\x9f'
            elseif c == 'k' then sym = '\xe2\x99\x94'
            elseif c == 'q' then sym = '\xe2\x99\x95'
            elseif c == 'r' then sym = '\xe2\x99\x96'
            elseif c == 'b' then sym = '\xe2\x99\x97'
            elseif c == 'n' then sym = '\xe2\x99\x98'
            elseif c == 'p' then sym = '\xe2\x99\x99'
            else sym = c
            end
         else
            sym = c
         end

         if checkers[idx] then
   if #line > 0 then
      line[#line] = line[#line]:gsub(" $", "")
   end
   if SHOW_ANNOTATIONS then
      local openChar = isMate and "!" or (highlight[idx] and "(" or " ")
      table.insert(line, openChar .. sym .. "! ")
   else
      table.insert(line, " " .. sym .. "  ")
   end
elseif hints[idx] then
   if #line > 0 then
      line[#line] = line[#line]:gsub(" $", "")
   end
   local q = hints[idx].quote
   table.insert(line, q .. sym .. q .. " ")
elseif guards[idx] then
   if #line > 0 then
      line[#line] = line[#line]:gsub(" $", "")
   end
   if SHOW_ANNOTATIONS then
      local openChar = highlight[idx] and "(" or " "
      table.insert(line, openChar .. sym .. "? ")
   else
      table.insert(line, " " .. sym .. "  ")
   end
elseif highlight[idx] then
   if #line > 0 then
      line[#line] = line[#line]:gsub(" $", "")
   end
   if SHOW_ANNOTATIONS then
      table.insert(line, "(" .. sym .. ") ")
   else
      table.insert(line, " " .. sym .. "  ")
   end
else
   table.insert(line, sym .. "  ")
end
      end
      table.insert(line, sideBorder)
      print(table.concat(line))
   end
   print(bottomBorder)
   print("     a  b  c  d  e  f  g  h")
   print("")
end

function renderCaptured(list, symbols)
   local out = {}
   for _, piece in ipairs(list) do
      table.insert(out, symbols[piece] or piece)
   end
   return table.concat(out)
end

function capturedAt(pos, move)
   local i, j = move[0 + __1], move[1 + __1]
   local board = pos.board
   local pb, qb = board[i + __1], board[j + __1]
   -- islower(q): byte in 97-122.
   if qb >= 97 and qb <= 122 then
      return string.char(qb - 32) -- q:upper()
   end
   if pb == 80 and (j - i == N+W or j - i == N+E) and qb == 46 and j == pos.ep then -- 'P', '.'
      return 'P'
   end
   return nil
end

-- True if the piece at move[1] is a pawn; used with captures to reset the 50-move-rule clock.
function isPawnMove(pos, move)
   local i = move[0 + __1]
   return pos.board[i + __1] == 80 -- 'P'
end

-- True if a pawn lands on rank 8 (White's orientation); used to prompt for promotion choice instead of defaulting to queen.
function isPromotionMove(pos, move)
   local i = move[0 + __1]
   local j = move[1 + __1]
   return pos.board[i + __1] == 80 and A8 <= j and j <= H8 -- 'P'
end


function findKingGuards(p, checkers)
   checkers = checkers or {}
   local board = p.board
   local kingIdx = nil
   for i = 1 - __1, #board - __1 do
      if board[i + __1] == 75 then -- 'K'
         kingIdx = i
         break
      end
   end
   if not kingIdx then return {} end

   local function attacks(boardArr, from, ptype, target)
      if ptype == 'P' then
         return target == from + S + W or target == from + S + E
      elseif ptype == 'N' or ptype == 'K' then
         local offs = (ptype == 'N') and directions.N or directions.K
         for _, d in ipairs(offs) do
            if from + d == target then return true end
         end
         return false
      else
         local offs = directions[ptype]
         for _, d in ipairs(offs) do
            local j = from + d
            while true do
               local cb = boardArr[j + __1]
               if cb == nil or cb == 32 or cb == 10 then break end -- isspace
               if j == target then return true end
               if cb ~= 46 then break end -- not '.'
               j = j + d
            end
         end
         return false
      end
   end

   local guards = {}
   for _, d in ipairs(directions.K) do
      local sq = kingIdx + d
      local cb = board[sq + __1]
      if cb and cb ~= 32 and cb ~= 10 and not (cb >= 65 and cb <= 90) then -- not isspace, not isupper
         for i = 1 - __1, #board - __1 do
            local pcb = board[i + __1]
            if pcb and pcb >= 97 and pcb <= 122 and not checkers[i] then -- islower
               if attacks(board, i, string.char(pcb - 32), sq) then
                  guards[i] = true
               end
            end
         end
      end
   end
   return guards
end

function isLegalMove(pos, move)
   local afterOwn = pos:move(move):rotate()
   return not next(findCheckers(afterOwn))
end

function hasLegalMove(pos)
   for _, move in ipairs(pos:genMoves()) do
      if isLegalMove(pos, move) then
         return true
      end
   end
   return false
end

function legalMovesOf(pos)
   local out = {}
   for _, move in ipairs(pos:genMoves()) do
      if isLegalMove(pos, move) then
         table.insert(out, move)
      end
   end
   return out
end

-- After a move that is NOT mate: squares the black king can legally escape to. pos is after the played move (rotated - black king is 'K'); mv[2] is converted back to absolute coordinates (119-x).
function findKingEscapeSquares(pos)
   local kIdx = nil
   local board = pos.board
   for i = 1 - __1, #board - __1 do
      if board[i + __1] == 75 then -- 'K'
         kIdx = i
         break
      end
   end
   if not kIdx then return {} end

   local squares = {}
   for _, mv in ipairs(pos:genMoves()) do
      if mv[1] == kIdx and isLegalMove(pos, mv) then
         table.insert(squares, render(119 - mv[2]))
      end
   end
   return squares
end

-- When the king has no free squares: whether black has a move that captures a checking piece. pos is after the move (rotated, black to move); checkerSquares are squares (same rotated system) from findCheckers(pos).
function findCapturingDefenders(pos, checkerSquares)
   local defenders = {}
   for _, mv in ipairs(pos:genMoves()) do
      local target = mv[2]
      if checkerSquares[target] and isLegalMove(pos, mv) then
         local fromSq = render(119 - mv[1])
         local toSq = render(119 - mv[2])
         table.insert(defenders, fromSq .. " x " .. toSq)
      end
   end
   return defenders
end

-- Save/Load game functions

function compressSaveRows(boardStr)
   local rows = {}
   for row in boardStr:gmatch("[^\r\n]+") do
      local out = {}
      local empty = 0
      for i = 1, #row do
         local c = row:sub(i, i)
         if c == "." then
            empty = empty + 1
         else
            if empty > 0 then out[#out + 1] = tostring(empty) end
            empty = 0
            out[#out + 1] = c
         end
      end
      if empty > 0 then out[#out + 1] = tostring(empty) end
      rows[#rows + 1] = table.concat(out)
   end
   return table.concat(rows, ";")
end

function expandSaveRows(compact)
   local rows = {}
   for row in tostring(compact):gmatch("[^;]+") do
      local out = {}
      local i = 1
      while i <= #row do
         local c = row:sub(i, i)
         if c >= '1' and c <= '8' then
            local num = tonumber(c)
            out[#out + 1] = string.rep(".", num)
         else
            out[#out + 1] = c
         end
         i = i + 1
      end
      rows[#rows + 1] = table.concat(out)
   end
   return rows
end

function saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, nextToMove, moveHistory, startingBoard, extra)
   local boardStr120 = arrayToBoard(pos.board)
   local boardLines = {}
   for rank = 8, 1, -1 do
      local line = {}
      for file = 0, 7 do
         local idx = A1 + file - 10*(rank-1)
         local c = boardStr120:sub(idx + __1, idx + __1)
         line[#line + 1] = isspace(c) and '.' or c
      end
      boardLines[#boardLines + 1] = table.concat(line)
   end
   local boardStr = table.concat(boardLines, '\n')
   local compactBoardStr = compressSaveRows(boardStr)

   local wcStr = (pos.wc[1] and '1' or '0') .. (pos.wc[2] and '1' or '0')
   local bcStr = (pos.bc[1] and '1' or '0') .. (pos.bc[2] and '1' or '0')
   local userCapStr = table.concat(capturedByUser, '')
   local engineCapStr = table.concat(capturedByEngine, '')
   if userCapStr == '' then userCapStr = '-' end
   if engineCapStr == '' then engineCapStr = '-' end
   local epStr = tostring(pos.ep or 0)
   local lastMoveStr = '--'
   if lastMove then lastMoveStr = render(lastMove[1]) .. render(lastMove[2]) end
   local nextStr = (nextToMove == 'w') and 'w' or 'b'

   local histStr = '-'
   if moveHistory and #moveHistory > 0 then
      local parts = {}
      for _, entry in ipairs(moveHistory) do parts[#parts + 1] = entry.notation end
      histStr = table.concat(parts, ',')
   end

   local startSource = startingBoard or initial -- always save the starting position (custom or standard initial)
   local startBoardStr = nil
   if startSource then
      local sbLines = {}
      for rank = 8, 1, -1 do
         local line = {}
         for file = 0, 7 do
            local idx = A1 + file - 10*(rank-1)
            local c = startSource:sub(idx + __1, idx + __1)
            line[#line + 1] = isspace(c) and '.' or c
         end
         sbLines[#sbLines + 1] = table.concat(line)
      end
      startBoardStr = compressSaveRows(table.concat(sbLines, '\n'))
   end

-- extra: optional metadata table embedded in the code, e.g. {mode="abc", hints="1"} for Challenge Game saves; unknown fields silently ignored by loadGame() for backward compat
   local extraStr = ''
   if extra then
      if extra.mode then extraStr = extraStr .. '|mode:' .. extra.mode end
      if extra.hints then extraStr = extraStr .. '|hints:' .. extra.hints end
   end

   local code = 'c:' .. wcStr .. '|bc:' .. bcStr .. '|ep:' .. epStr .. -- new compact one-line format; 'c' replaces old 'wc' field
                '|last:' .. lastMoveStr .. '|ucap:' .. userCapStr .. '|ecap:' .. engineCapStr ..
                '|wm:' .. whiteMoves .. '|bm:' .. blackMoves .. '|hc:' .. (halfmoveClock or 0) ..
                '|next:' .. nextStr .. '|hist:' .. histStr ..
                (startBoardStr and ('|start:' .. startBoardStr) or '') ..
                extraStr ..
                '|board:' .. compactBoardStr
   return code
end

function loadGame(code)
   if code:match("^board:") then -- kompresovani puzzle format (board:...)
      local compact = code:match("^board:(.+)$")
      if not compact then return nil end
      local boardLines = expandSaveRows(compact)
      if #boardLines ~= 8 then
         echoE("Invalid puzzle board! Expected 8 ranks.")
         return nil
      end
      local fullBoard = '         \n         \n '
      for rank = 1, 8 do
         if #boardLines[rank] ~= 8 then
            echoE("Invalid rank length in puzzle.")
            return nil
         end
         fullBoard = fullBoard .. boardLines[rank]
         if rank < 8 then fullBoard = fullBoard .. '\n ' end
      end
      fullBoard = fullBoard .. '\n         \n          '
      local pos = Position.new(fullBoard, 0, {false,false}, {false,false}, 0, 0)
      -- Return in the format expected by both puzzle and normal mode
      return pos, nil, {}, {}, 0, 0, 0, "w", nil, fullBoard
   end

   -- Check if code has metadata line (contains '|')
   if code:find('|') then -- new format: one line, board in board:...; old format: metadata line 1, 8x8 board line 2+
      local metadata, oldBoardStr = code:match("^(.-)\n(.*)$")
      if not metadata then metadata = code end

      local parts = {}
      for part in metadata:gmatch('[^|]+') do
         local key, value = part:match("([^:]+):(.*)")
         if key and value then parts[key] = value end
      end

      parts.c = parts.c or parts.wc -- accept both new c: and legacy wc: castling field names
      if not parts.c or not parts.bc or not parts.ep or not parts.last or
         not parts.ucap or not parts.ecap or not parts.wm or not parts.bm or
         not parts.hc or not parts.next then
         echoE("Invalid metadata! Missing required fields.")
         return nil
      end

      local boardLines = {}
      if parts.board then
         boardLines = expandSaveRows(parts.board)
      elseif oldBoardStr then
         for line in oldBoardStr:gmatch("[^\n]+") do
            boardLines[#boardLines + 1] = line
         end
      end

      if #boardLines ~= 8 then
         echoE("Invalid board! Expected 8 ranks, got " .. #boardLines)
         return nil
      end

      local fullBoard = '         \n         \n '
      for rank = 1, 8 do
         local line = boardLines[rank]
         if #line ~= 8 then
            echoE("Invalid rank! Expected 8 files, got " .. #line)
            return nil
         end
         fullBoard = fullBoard .. line
         if rank < 8 then fullBoard = fullBoard .. '\n ' end
      end
      fullBoard = fullBoard .. '\n         \n          '

      local wc1 = parts.c:sub(1,1) == '1'
      local wc2 = parts.c:sub(2,2) == '1'
      local bc1 = parts.bc:sub(1,1) == '1'
      local bc2 = parts.bc:sub(2,2) == '1'

      local ep = tonumber(parts.ep) or 0
      local whiteMoves = tonumber(parts.wm) or 0
      local blackMoves = tonumber(parts.bm) or 0
      local halfmoveClock = tonumber(parts.hc) or 0
      local nextToMove = parts.next or "b"

      local pos = Position.new(fullBoard, 0, {wc1, wc2}, {bc1, bc2}, ep, 0)

      local capturedByUser = {}
      if parts.ucap ~= '-' then
         for i = 1, #parts.ucap do
            table.insert(capturedByUser, parts.ucap:sub(i,i))
         end
      end

      local capturedByEngine = {}
      if parts.ecap ~= '-' then
         for i = 1, #parts.ecap do
            table.insert(capturedByEngine, parts.ecap:sub(i,i))
         end
      end

      local lastMove = nil
      if parts.last ~= '--' and #parts.last == 4 then
         lastMove = {parse(parts.last:sub(1,2)), parse(parts.last:sub(3,4))}
      end

      local histStr = parts.hist -- may be nil (old codes) or "-" (no moves yet)

-- May be nil: only set when the game started from a custom/puzzle position; decode saveGame()'s rank-joined format back into a padded board string.
      local startingBoard = nil
      if parts.start then
         local sbLines = expandSaveRows(parts.start)
         if #sbLines == 8 then
            local sb = '         \n         \n '
            for rank = 1, 8 do
               if #sbLines[rank] ~= 8 then
                  sbLines = nil
                  break
               end
               sb = sb .. sbLines[rank]
               if rank < 8 then sb = sb .. '\n ' end
            end
            if sbLines then
               sb = sb .. '\n         \n          '
               startingBoard = sb
            end
         end
      end

      return pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, nextToMove, histStr, startingBoard, parts.mode, parts.hints

   else -- simple format (board only, 8x8): resets everything else to initial state
      local boardLines = {}
      for line in code:gmatch("[^\n]+") do
         table.insert(boardLines, line)
      end

      if #boardLines ~= 8 then
         echoE("Invalid board! Expected 8 ranks, got " .. #boardLines)
         return nil
      end

      local fullBoard = '         \n         \n '
      for rank = 1, 8 do
         local line = boardLines[rank]
         if #line ~= 8 then
            echoE("Invalid rank! Expected 8 files, got " .. #line)
            return nil
         end
         fullBoard = fullBoard .. line
         if rank < 8 then
            fullBoard = fullBoard .. '\n '
         end
      end
      fullBoard = fullBoard .. '\n         \n          '

      local pos = Position.new(fullBoard, 0, {true, true}, {true, true}, 0, 0)
      local lastMove = nil
      local capturedByUser = {}
      local capturedByEngine = {}
      local whiteMoves = 0
      local blackMoves = 0
      local halfmoveClock = 0
      local nextToMove = "w"  -- White (human) to move

-- Simple-format loads are always a custom/puzzle start: this board is the game's starting position (no metadata/history yet).
      return pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, nextToMove, nil, fullBoard
   end
end

-- Replays comma-separated UCI history (e.g. "e2e4,e7e5,...") from initial position to rebuild gameHistory/positionCounts for threefold repetition across save/load. Falls back to seeding only fallbackPos if histStr is missing/empty/"-" or replay fails.
function rebuildHistoryFromMoves(histStr, fallbackPos, startBoard)
   local gameHistory = {}
   local positionCounts = {}

   local function seedFallback()
      gameHistory = { [tpKey(fallbackPos)] = true }
      positionCounts = { [tpKey(fallbackPos)] = 1 }
   end

   if not histStr or histStr == '-' or histStr == '' then
      seedFallback()
      return gameHistory, positionCounts
   end

   local ok, err = pcall(function()
-- startBoard lets replay start from a custom/puzzle position; old codes without it fall back to `initial`.
      local replayPos = Position.new(startBoard or initial, 0, {true,true}, {true,true}, 0, 0)
      gameHistory[tpKey(replayPos)] = true
      positionCounts[tpKey(replayPos)] = 1

      local ply = 0
      for notation in histStr:gmatch('[^,]+') do
         if #notation < 4 or #notation > 5 then
            error("bad notation length: " .. notation)
         end

         local from = parse(notation:sub(1,2))
         local to = parse(notation:sub(3,4))
         if not from or not to then
            error("unparseable move: " .. notation)
         end

-- 5th char, if present, is a promotion suffix (n/b/r/q) recorded only when promoted to non-Queen; see notation-building in main().
         local promo = nil
         if #notation == 5 then
            promo = notation:sub(5,5):upper()
            if promo ~= 'N' and promo ~= 'B' and promo ~= 'R' and promo ~= 'Q' then
               error("bad promotion suffix: " .. notation)
            end
         end

-- notation is always in absolute board coords (main()'s render() calls), but replayPos alternates perspective each ply. Odd plies (White) apply as-is; even plies (Black) mirror coords (119-x) like main() does for engine moves.
         ply = ply + 1
         local localFrom, localTo
         if ply % 2 == 1 then
            localFrom, localTo = from, to
         else
            localFrom, localTo = 119 - from, 119 - to
         end

         local move = {localFrom, localTo, promo}
         if not ttfind(replayPos:genMoves(), move) then
            error("illegal move during replay: " .. notation)
         end

         replayPos = replayPos:move(move)
         replayPos.score = 0

         local key = tpKey(replayPos)
         gameHistory[key] = true
         positionCounts[key] = (positionCounts[key] or 0) + 1
      end
   end)

   if not ok then
      echoW("Warning: could not replay move history (" .. tostring(err) .. "). Repetition tracking resets from this position.")
      seedFallback()
   end

   return gameHistory, positionCounts
end


function displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   if lastMove then
      local moveLabel = blackMoves and (blackMoves .. ". ") or ""
      print("Sunfish " .. moveLabel .. "move: \n" .. render(lastMove[1]) .. render(lastMove[2]))
      print("Captured: " .. renderCaptured(capturedByEngine, whiteSymbols))
   end
   local checkers = findCheckers(pos)
   local guards = findKingGuards(pos, checkers)
   local isMate = next(checkers) and not hasLegalMove(pos)
   if next(checkers) and not isMate then
      echoS("Check!")
   end
   printboard(arrayToBoard(pos.board), lastMove, checkers, guards, isMate)
   print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
end

-- Help
