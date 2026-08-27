-- sunfish.lua Chess engine, Lua port chain: 1. Original algorithm: Sunfish (Python) by Thomas Ahle https://github.com/thomasahle/sunfish - BSD license 2. Initial Lua transpilation attributed to Soumith Chintala 3. Extended for Yantra Launcher / Android (Luaj-jse 3.0.1), with UI, save/load, puzzle mode, and search tuning, by borko17 (https://github.com/borko17/sunfish-lua) (with help from Claude AI).

-- CONFIG: Options at the top
local USE_UNICODE_PIECES = false
local SHOW_ANNOTATIONS = true

-- Challenge ('cg'): random position, N pieces, play until mate/draw/quit
local CHALLENGE_MIN_PIECES = 10
local CHALLENGE_MAX_PIECES = 20
local CHALLENGE_GEN_ATTEMPTS = 400
local CHALLENGE_HINTS_ENABLED = false -- shows suggested move; toggle with 'th'

local NODES_SEARCHED = 2000 -- node budget/search; soft limit, checked only between depths
local CHALLENGE_ENGINE_NODES = 600 -- separate, weaker budget for Sunfish's replies in Challenge mode
local TABLE_SIZE = NODES_SEARCHED * 25 -- scaled off NODES_SEARCHED so it doesn't thrash; upstream's 1e6 too heavy for Luaj-jse on phone
local MATE_VALUE = 30000 -- exceeds 8*queen+2*(rook+knight+bishop); king value is double this
local MATE_UPPER = 60000 + (10 * 2529) -- search() scores mate near this, not MATE_VALUE - callers must match


-- Console output helpers (wrap binding.exec("echo -X " .. msg) calls for readability)
local function echoE(msg) binding.exec("echo -e " .. msg) end -- error
local function echoS(msg) binding.exec("echo -s " .. msg) end -- success
local function echoW(msg) binding.exec("echo -w " .. msg) end -- warning/heading

-- Update
local SCRIPT_VERSION = "2.608270635"
local CHANGELOG = {
   "Fixed: the GAME CODE re-printed right after loading a code now keeps the correct next:b/next:w instead of always showing next:w (this was breaking sN reloads in Challenge Game)",
   "Fixed: board no longer missing after 'Invalid code' message",
   "Fixed: 's0' now works in both normal game and Challenge Game (saves the starting position)",
   "Fixed: Challenge Game now auto-plays Sunfish's reply after loading a code where it's Sunfish's turn",
   "sN save codes now correctly record whose turn it is (fixes confusion around whose move sN saves)",
}
local GITHUB_RAW_URL = "https://raw.githubusercontent.com/borko17/sunfish.lua/main/docs/update.txt"

-- Extracts CHANGELOG table from raw script text (so 'u' shows the remote version's changelog)
local function parseChangelog(text)
   local body = text:match('CHANGELOG%s*=%s*{(.-)}')
   if not body then return nil end
   local list = {}
   for entry in body:gmatch('"(.-)"') do
      table.insert(list, entry)
   end
   if #list == 0 then return nil end
   return list
end

local function printChangelog(list, versionLabel)
   print("")
   print("What's new in v" .. versionLabel .. ":")
   for _, line in ipairs(list) do
      print("• " .. line)
   end
end

local function fallbackToLocalChangelog()
   print("Showing changelog for your installed version instead:")
   printChangelog(CHANGELOG, SCRIPT_VERSION)
end

local function checkForUpdate()
   print("Checking version on GitHub...")

   local ok, result = pcall(function()
      local URL = luajava.bindClass("java.net.URL")
      local url = URL.new(GITHUB_RAW_URL)
      local conn = url:openConnection()
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

   if not ok or not result or result == '' then
      echoE("No response from GitHub. Check your connection.")
      fallbackToLocalChangelog()
      return
   end

   local remoteVersion = result:match('SCRIPT_VERSION%s*=%s*"([%d%.]+)"')
   if not remoteVersion then
      echoE("Could not find a version number in the GitHub file.")
      fallbackToLocalChangelog()
      return
   end

   if remoteVersion == SCRIPT_VERSION then
      echoS("You have the latest version: " .. SCRIPT_VERSION)
   else
      echoW("New version available: " .. remoteVersion .. " (current: " .. SCRIPT_VERSION .. ")")
      print("Download at: https://github.com/borko17/sunfish-lua/blob/main/sunfish.lua")
   end

   local remoteChangelog = parseChangelog(result)
   if remoteChangelog then
      printChangelog(remoteChangelog, remoteVersion)
   else
      fallbackToLocalChangelog()
   end
end

-- core.lua ======= 

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

-- core.lua ======= end

-- search.lua =======

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

-- search.lua ======= end

-- ui.lua =======

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

-- ui.lua ======= end

-- help.lua =======

function showHelp()
   print("")
   echoW("=== CHESS.LUA HELP ===")
   print("")
   echoW("COMMANDS FOR CHESS:")
   print("-------------")
   print("moves - Enter moves in format 'e2e4'")
   print("'h' - Show this help screen")
   print("'?' - Show About screen")
   print("'d' - Toggle display mode")
   print("    • Unicode symbols <-> Letters.")
   print("'a' - Toggle annotations")
   print("    • show/hide board markers.")
   print("'s' - Save current game")
   print("      (generate code)")
   print("'sN' - Save position")
   print("       after history move N")
   print("     • e.g. 's15' saves the position")
   print("       after move 15, even if")
   print("       you have played further.")
   print("'l' - Load saved game")
   print("'nN' - Change engine node budget")
   print("     • e.g. 'n4000'")
   print("     • higher N = harder/slower")
   print("     • lower N = easier/faster")
   print("     • default: n2000")
   print("'m' - Show move history")
   print("'r' - Resign current game")
   print("'n' - Start a new game")
   print("'u' - Check sunfish.lua for updates")
   print("'q' - Quit chess.lua")
   print("")
   echoW("COMMANDS FOR PUZZLE MODE:")
   print("-------------")
   print("'m1' - Enter Mate-in-1 puzzle mode")
   print("'h1' - Hint: which piece type mates")
   print("'h2' - Hint: which square to move from")
   print("'h3' - Hint: which square to mate on")
   print("'h4' - Full solution")
   print("'s' - Save current puzzle")
   print("'l' - Load saved puzzle")
   print("'n' - Generate a new puzzle")
   print("'d' - Toggle Unicode / letter display")
   print("'a' - Toggle annotations")
   print("'u' - Check sunfish.lua for updates")
   print("'h' - Show this help screen")
   print("'?' - Show About screen")
   print("'q' - Leave puzzle mode")
   print("")
   echoW("COMMANDS FOR CHALLENGE GAME:")
   print("-------------")
   print("'cg' - Enter Challenge Game mode")
   print("     • " .. CHALLENGE_MIN_PIECES .. "-" .. CHALLENGE_MAX_PIECES .. " random pieces,")
   print("       play freely vs Sunfish,")
   print("       no move limit")
   print("     • shows a suggested move")
   print("       as an on-board hint")
   print("       to help you learn")
   print("'th' - Toggle hints on/off")
   print("'r' - Resign this attempt")
   print("'n' - New position")
   print("'q' - Leave Challenge Game mode")
   print("")
   print("• All other commands work the same as in a normal game (s/sN/l/m/h/a/d/u/?)")
   print("")
   echoW("SAVE-GAME FORMATS:")
   print("-------------")
   print("Load accepts these")
   print("save-game formats (Examples):")
   print("")
   print("1) Full save:")
   print("-------------")
   print("c:11|bc:11|ep:0|last:e7e6|ucap:-|ecap:-|wm:2|bm:2|hc:0|next:w|hist:b1c3,g8f6,g1f3,e7e6|start:rnbqkbnr;pppppppp;8;8;8;8;PPPPPPPP;RNBQKBNR|board:rnbqkb1r;pppp1ppp;4pn2;8;8;2N2N2;PPPPPPPP;R1BQKB1R")
   print("-------------")
   print("• Full format restores game state and history.")
   print("")
   print("2) Board save:")
   print("-------------")
   print("board:rnbqkb1r;pppp1ppp;4pn2;8;8;2N2N2;PPPPPPPP;R1BQKB1R")
   print("-------------")
   print("")
   print("3) Plain 8x8 board")
   print("-------------")
   print("rnbqkb.r\npppp.ppp\n....pn..\n........\n........\n..N..N..\nPPPPPPPP\nR.BQKB.R")
   print("-------------")
   print("• Formats 2 and 3 load a board position only.")
   print("• Puzzle load accepts formats 2 and 3.")
   print("")
   echoW("GAME RULES / DRAW DETECTION:")
   print("-------------")
   print("• Check, checkmate and stalemate are detected")
   print("• 50-move no-progress draw is automatic")
   print("• Threefold repetition draw is automatic")
   print("• Insufficient-material draws are detected")
   print("• Pawn promotion allows Q, R, B or N")
   print("")
   echoW("DISPLAY MODES:")
   print("-------------")
   print("Unicode mode:")
   print("• Your pieces:    ♚ ♛ ♜ ♝ ♞ ♟")
   print("• Sunfish pieces: ♔ ♕ ♖ ♗ ♘ ♙")
   print("• Empty squares:  • light ◦ dark")
   print("")
   print("Letter mode:")
   print("• Your pieces:    K Q R B N P")
   print("• Sunfish pieces: k q r b n p")
   print("• Empty squares:  : light . dark")
   print("")
   echoW("DEFAULT CONFIGURATION can be changed in CONFIG - section at top of LUA script:")
   print("-------------")
   print("USE_UNICODE_PIECES = true/false")
   print("SHOW_ANNOTATIONS = true/false")
   print("local NODES_SEARCHED = 2000")
   print("local CHALLENGE_ENGINE_NODES = 600")
   print("")
   echoW("PIECE SYMBOLS:")
   print("-------------")
   print("K = King   Q = Queen  R = Rook")
   print("B = Bishop N = Knight P = Pawn")
   print("")
   print("uppercase = Your pieces,")
   print("lowercase = Sunfish.")
   print("")
   echoW("BOARD MARKERS")
   print("(what symbols mean):")
   print("-------------")
   print(" sym! - piece is giving CHECK")
   print("!sym! - piece delivers CHECKMATE")
   print(" sym? - piece GUARDS escape square")
   print("(sym) - piece just moved here")
   print("'sym' - CG hint: suggested move") 
   print("      • shown on both")
   print("        the piece to move")
   print("        and its target square")
   print("")
   print("Combined markers:")
   print("(sym! - piece moved AND gives check")
   print("(sym? - piece moved AND guards escape")
   print("")
   print("Note: ( ) shows last move")
   print("!  shows check/checkmate")
   print("?  shows guard")
   print("' ' shows Challenge Game hint")
   print("")
   echoW("RECOMMENDED FONTS:")
   print("-------------")
   print("For Unicode symbols:")
   print("• DejaVu Sans Mono")
   print("• Julia Mono")
   print("• Everson Mono")
   print("• Unifont")
   print("")
   print("For letter mode:")
   print("• Any monospaced font")
   print("")
   print("")
   echoW("↑↑↑ CHESS.LUA HELP ↑↑↑")
end

-- About

function showAbout()
   print("")
   echoW("=== ABOUT SUNFISH.LUA ===")
   print("")
   print("Sunfish.lua is a Lua adaptation of Sunfish,")
   print("the compact chess engine originally written")
   print("in Python by Thomas Ahle.")
   print("github.com/thomasahle/sunfish")
   print("")
   print("The original Lua port was made by")
   print("Soumith Chintala.")
   print("github.com/soumith/sunfish.lua")
   print("")
   print("This version is substantially extended")
   print("for Yantra Launcher on Android")
   print("(Luaj-jse 3.0.1) by borko17")
   print("(github.com/borko17), with help from")
   print("Claude AI.")
   print("")
   echoW("PROJECT HERITAGE / LICENSING:")
   print("-------------")
   print("• Thomas Ahle Sunfish: GNU GPL v3")
   print("• Soumith Chintala Lua port: source identifies")
   print("  its code license as BSD")
   print("• This version contains substantial")
   print("  independent modifications and extensions")
   print("")
   echoW("ENGINE EXTENSIONS:")
   print("-------------")
   print("• Node-budget search instead of a timer")
   print("• Adjustable engine strength via 'nN'")
   print("• Smaller, budget-scaled transposition table")
   print("• Zugzwang guard on null-move pruning")
   print("• Endgame king-centralization table")
   print("• Depth-scaled quiescence threshold")
   print("")
   echoW("CHESS FEATURES:")
   print("-------------")
   print("• Legal-move validation")
   print("• Check, checkmate and stalemate detection")
   print("• 50-move-rule draw detection")
   print("• Threefold-repetition draw detection")
   print("• Insufficient-material draw detection")
   print("• Choice of Q, R, B or N on promotion")
   print("• Captured-piece tracking")
   print("• Move history and position snapshots")
   print("")
   echoW("SAVE / DISPLAY:")
   print("-------------")
   print("• Save and load games via text codes")
   print("• Compact save format")
   print("• Compatibility with the older 8x8 save format")
   print("• Save/load of individual historical positions")
   print("• Unicode or letter piece display")
   print("• Check, guard and last-move board markers")
   print("")
   echoW("PUZZLES / TOOLS:")
   print("-------------")
   print("• Mate-in-1 puzzle generator")
   print("• Puzzle hints and full solutions")
   print("• Puzzle save/load")
   print("• Automatic verification of generated mates")
   print("• Online update checker ('u')")
   print("")
   print("Sunfish.lua remains a compact chess engine,")
   print("but this version also provides a complete")
   print("interactive chess environment for Yantra.")
   print("")
   echoW("↑↑↑ ABOUT SUNFISH.LUA ↑↑↑")
end

-- help.lua ======= End

-- mate1.lua =======

-- AI puzzle mode ("m1")

emptyBoard =
    '         \n' ..
    '         \n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    ' ........\n' ..
    '         \n' ..
    '          '

aiWhitePool = {"Q","R","B","N","P"}
aiBlackPool = {"q","r","b","n","p"}
aiPieceCaps = {Q = 1, R = 2, B = 2, N = 2, P = 8}
AI_MATE1_ATTEMPTS = 600


function pickCappedPieceType(pool, counts)
   local candidates = {}
   for _, pc in ipairs(pool) do
      local base = pc:upper()
      if (counts[base] or 0) < (aiPieceCaps[base] or 0) then
         table.insert(candidates, pc)
      end
   end
   if #candidates == 0 then return nil end
   return candidates[math.random(#candidates)]
end

function aiPut(board, i, ch)
   return board:sub(1, i-1) .. ch .. board:sub(i+1)
end

function randomFreeSquare(occupied, avoidBackRanks, forcedColor)
   for _ = 1, 40 do
      local f, r = math.random(0,7), math.random(0,7)
      if not (avoidBackRanks and (r == 0 or r == 7)) then
         local idx = A1 + f - 10*r
         local fieldColor = (f + r) % 2  -- 0=white, 1=black

         if forcedColor and fieldColor ~= forcedColor then
            goto continue
         end

         if not occupied[idx] then
            return idx
         end
      end
      ::continue::
   end
   return nil
end

function findMateIn1Move(pos)
   for _, mv in ipairs(pos:genMoves()) do
      if isLegalMove(pos, mv) then
         local newPos = pos:move(mv)
         local checkers = findCheckers(newPos)
         if next(checkers) and not hasLegalMove(newPos) then
            return mv
         end
      end
   end
   return nil
end

function genAiMateIn1(maxAttempts)
   maxAttempts = maxAttempts or AI_MATE1_ATTEMPTS

   for _ = 1, maxAttempts do
      local bkFile, bkRank = math.random(0,7), math.random(0,7)
      local bkIdx = A1 + bkFile - 10*bkRank

      local wkIdx = nil
      for _ = 1, 30 do
         local f, r = math.random(0,7), math.random(0,7)
         local idx = A1 + f - 10*r
         if idx ~= bkIdx and math.max(math.abs(f-bkFile), math.abs(r-bkRank)) > 1 then
            wkIdx = idx
            break
         end
      end

      if wkIdx then
         local occupied = {[bkIdx]=true, [wkIdx]=true}
         local board, ok = emptyBoard, true
         board = aiPut(board, bkIdx + __1, 'k')
         board = aiPut(board, wkIdx + __1, 'K')

         local numWhiteExtra = math.random(2,10)
         local numBlackExtra = math.random(1,10)
         local whiteCounts = {}
         local blackCounts = {}
         local whiteBishopColor = nil
         local blackBishopColor = nil

         for _ = 1, numWhiteExtra do
            local pc = pickCappedPieceType(aiWhitePool, whiteCounts)
            if not pc then break end

            local forcedColor = nil
            if pc == 'B' then
               if not whiteBishopColor then
                  whiteBishopColor = math.random(0, 1)
                  forcedColor = whiteBishopColor
               else
                  forcedColor = 1 - whiteBishopColor
               end
            end

            local idx = randomFreeSquare(occupied, pc == "P", forcedColor)
            if not idx then ok = false; break end
            occupied[idx] = true
            board = aiPut(board, idx + __1, pc)
            whiteCounts[pc] = (whiteCounts[pc] or 0) + 1
         end

         if ok then
            for _ = 1, numBlackExtra do
               local pc = pickCappedPieceType(aiBlackPool, blackCounts)
               if not pc then break end

               local forcedColor = nil
               if pc == 'b' then
                  if not blackBishopColor then
                     blackBishopColor = math.random(0, 1)
                     forcedColor = blackBishopColor
                  else
                     forcedColor = 1 - blackBishopColor
                  end
               end

               local idx = randomFreeSquare(occupied, pc == "p", forcedColor)
               if not idx then ok = false; break end
               occupied[idx] = true
               board = aiPut(board, idx + __1, pc)
               blackCounts[pc:upper()] = (blackCounts[pc:upper()] or 0) + 1
            end
         end

         if ok then
            local pos = Position.new(board, 0, {false,false}, {false,false}, 0, 0)
            local blackPos = pos:rotate()
            if not next(findCheckers(blackPos)) then
               if findMateIn1Move(pos) then
                  return board
               end
            end
         end
      end
   end
   return nil
end

pieceFullNames = {
   K = "King", Q = "Queen", R = "Rook",
   B = "Bishop", N = "Knight", P = "Pawn",
}

-- Returns (solved, quit, newBoard); newBoard lets callers pick up a board loaded via 'l' (reassignment inside was previously lost with only 2 return values)
function attemptAiPuzzle(board)
   local curPos = Position.new(board, 0, {false,false}, {false,false}, 0, 0)
   printboard(arrayToBoard(curPos.board))
   print("Find mate in 1 move: ")
   local crdn = input()
   if not crdn then
      echoE("\nNo input (EOF). Ending puzzle mode.")
      return false, true, board
   end
   if crdn == 'q' then
       print("----")
      echoW("Leaving puzzle mode.")
      return false, true, board
   end
   if crdn == 'n' then
       print("----")
      echoW("Generating new puzzle...")
   local board = genAiMateIn1()
   return false, false, board
   end
   if crdn == 'd' then
   USE_UNICODE_PIECES = not USE_UNICODE_PIECES
   updateDisplayMode()
   print("----")
   echoW("Mode: " .. (USE_UNICODE_PIECES and "Unicode" or "Letters"))
   return false, false, board
end

if crdn == 'a' then
   SHOW_ANNOTATIONS = not SHOW_ANNOTATIONS
   print("----")
   echoW("Annotations: " .. (SHOW_ANNOTATIONS and "ON" or "OFF"))
   return false, false, board
end

if crdn == 'u' then
   print("----")
   checkForUpdate()
   return false, false, board
end

if crdn == 'h' then
   print("----")
   showHelp()
   return false, false, board
end

if crdn == '?' then
   print("----")
   showAbout()
   return false, false, board
end

if crdn == 's' then
   local curBoardStr = arrayToBoard(curPos.board)
   local boardLines = {}
   for rank = 8, 1, -1 do
      local line = {}
      for file = 0, 7 do
         local idx = A1 + file - 10*(rank-1)
         local c = curBoardStr:sub(idx + __1, idx + __1)
         table.insert(line, isspace(c) and '.' or c)
      end
      boardLines[#boardLines + 1] = table.concat(line)
   end
   local boardStr = table.concat(boardLines, '\n')
   local compactBoardStr = compressSaveRows(boardStr)
   local code = "board:" .. compactBoardStr
   print("----")
   echoW("=== PUZZLE CODE ===")
   print(code)
   echoW("==================")
   return false, false, board
end

if crdn == 'l' then
   print("----")
   print("Paste puzzle code:")
   local code = input()
   if code and code ~= '' then
      -- try loadGame first (supports both board: and 8x8 text)
      local result = {loadGame(code)}
      if result[1] then
         board = arrayToBoard(result[1].board)
         echoW("=== PUZZLE CODE ===")
         print(code)
         echoW("==================")
         echoS("Puzzle loaded!")
         return false, false, board
      end
      -- if loadGame failed, try as plain 8x8 text (old format)
      local boardLines = {}
      for line in code:gmatch("[^\n]+") do
         table.insert(boardLines, line)
      end
      if #boardLines == 8 then
         local fullBoard = '         \n         \n '
         local valid = true
         for rank = 1, 8 do
            local line = boardLines[rank]
            if #line ~= 8 then valid = false; break end
            fullBoard = fullBoard .. line
            if rank < 8 then fullBoard = fullBoard .. '\n ' end
         end
         if valid then
            fullBoard = fullBoard .. '\n         \n          '
            board = fullBoard
            echoS("Puzzle loaded (old format)!")
            return false, false, board
         end
      end
      echoE("Invalid code! Could not parse puzzle.")
   else
      echoE("No code entered.")
   end
   return false, false, board
end

   if crdn == 'h4' then
      local mv = findMateIn1Move(curPos)
      if mv then
          print("----")
         echoW("Solution: " .. render(mv[0 + __1]) .. render(mv[1 + __1]) .. " (mate)")
      else
         echoE("Couldn't find a solution \n(shouldn't happen).")

      echoW("Generating puzzle...")
   local board = genAiMateIn1()
   return false, false, board
      end
      return false, false, board
   end

   if crdn == 'h1' then
      local mv = findMateIn1Move(curPos)
      if mv then
         local piece = string.char(curPos.board[mv[1] + __1])
         local pieceName = pieceFullNames[piece] or piece
         print("----")
         echoW("Hint: the mating move is played by a " .. pieceName)
      else
         echoE("Couldn't find a solution \n(shouldn't happen).")
      print("Generating puzzle...")
   local board = genAiMateIn1()
   return false, false, board
      end
      return false, false, board
   end

   if crdn == 'h2' then
      local mv = findMateIn1Move(curPos)
      if mv then
         print("----")
         echoW("Hint: move the piece on " .. render(mv[0 + __1]))
      else
         echoE("Couldn't find a solution \n(shouldn't happen).")
      print("Generating puzzle...")
   local board = genAiMateIn1()
   return false, false, board
      end
      return false, false, board
   end

   if crdn == 'h3' then
      local mv = findMateIn1Move(curPos)
      if mv then
         print("----")
         echoW("Hint: deliver mate on " .. render(mv[1 + __1]))
      else
         echoE("Couldn't find a solution \n(shouldn't happen).")
         print("Generating puzzle...")
   local board = genAiMateIn1()
   return false, false, board
      end
      return false, false, board
   end

   local move = {parse(crdn:sub(1,2)), parse(crdn:sub(3,4))}
   local from = move[1]
   if not (from and move[2]) then
      echoE(crdn .. " - Invalid format. Enter a move like 'd2d4'")
   elseif not (curPos.board[from + __1] and curPos.board[from + __1] >= 65 and curPos.board[from + __1] <= 90) then -- isupper
      echoE(crdn .. " - There's no piece of yours on that square.")
   elseif not ttfind(curPos:genMoves(), move) then
      echoE(crdn .. " - That move is not allowed.")
   elseif not isLegalMove(curPos, move) then
      echoE(crdn .. " - That move leaves your king in check.")
   else
      local newPos = curPos:move(move)
      local checkers = findCheckers(newPos)
      if next(checkers) and not hasLegalMove(newPos) then
         echoS(crdn .. " - Checkmate!")
         print("")
         return true, false, board
      else
         local escapes = findKingEscapeSquares(newPos)
         echoE(crdn .. " - Not mate. Try again.")
         if #escapes > 0 then
            echoE("Free squares for king movement are: " .. table.concat(escapes, " "))
         else
            local defenders = findCapturingDefenders(newPos, checkers)
            if #defenders > 0 then
               echoE("King has no free squares, but watch out: " .. table.concat(defenders, ", "))
            else
               echoE("King has no free squares (mate must be blocked, not shown here).")
            end
         end
      end
   end
   return false, false, board
end

function aipuzMate1()
   print("")
   echoW("=== PUZZLE MODE: MATE IN 1 ===")
   print("• 'h1/h2/h3/h4' for hint")
   print("• 'h' for help")
   print("• 'q' to quit.")
   print("")
   echoW("Generating puzzle...")
   local board = genAiMateIn1()
   if not board then
      echoE("Couldn't generate a puzzle, try again.")
      return
   end
   while true do
      local solved, quit, newBoard = attemptAiPuzzle(board)
      board = newBoard
      if quit then return end
      if solved then
         echoW("Generating new puzzle...")
         board = genAiMateIn1()
         if not board then
            echoE("Couldn't generate a new puzzle, try again.")
            return
         end
      end
   end
end

-- mate1.lua ======= end

-- challenge.lua ======= 

function withQuietExec(fn)
   local realExec = binding.exec
   binding.exec = function(_) end
   local ok, a, b, c, d, e = pcall(fn)
   binding.exec = realExec
   if not ok then error(a) end
   return a, b, c, d, e
end

-- Best move for the side to move in `pos` (player/White in challenge mode), shown as an on-board hint; same node budget as Sunfish's own move. search() only treats a position as a repetition draw at deeper plies, never for the root move, so it can keep suggesting a back-and-forth into a seen position - if the top suggestion would revisit `history`, fall back to the best legal alternative that doesn't. avoidMove (player's own move from two of their own plies ago, e.g. an undone d4d3) is also excluded when a non-repeating alternative exists, to stop the hint nudging a stalling shuffle.
HINT_NODES_BEST = nil       -- nil = reuse NODES_SEARCHED

function movesEqual(a, b)
   return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

function findHintMove(pos, history, avoidMove)
   local legal = legalMovesOf(pos)
   if #legal == 0 then return nil end

   local best = withQuietExec(function()
      local mv = search(pos, HINT_NODES_BEST or NODES_SEARCHED, history)
      return mv
   end)
   if best and not isLegalMove(pos, best) then best = nil end
   if not best then
      table.sort(legal, function(a, b) return pos:value(a) > pos:value(b) end)
      best = legal[1]
   end

   local function leadsToSeenPosition(mv)
      local afterMove = pos:move(mv)
      return history[tpKey(afterMove)] == true
   end

   local function shouldAvoid(mv)
      return leadsToSeenPosition(mv) or (avoidMove and movesEqual(mv, avoidMove))
   end

   if best and shouldAvoid(best) then
      local alternatives = {}
      for _, mv in ipairs(legal) do
         if not movesEqual(mv, best) and not shouldAvoid(mv) then
            table.insert(alternatives, mv)
         end
      end
      if #alternatives > 0 then
         table.sort(alternatives, function(a, b) return pos:value(a) > pos:value(b) end)
         best = alternatives[1]
      end
-- If every legal move leads to an already-seen position or is the move to avoid, there's nothing better to suggest - keep the original result.
   end

   return best
end

-- Converts the candidate move into a hints table for printboard(), keyed by absolute index; from and to squares get wrapped in single quotes.
function buildHintDisplay(move)
   local hints = {}
   if move then
      hints[move[1]] = {quote = "'"}
      hints[move[2]] = {quote = "'"}
   end
   return hints
end

-- How many EXTRA pieces White gets over Black when generating a Challenge position (on top of the ~55-70% split). 0 = no extra bonus.
CHALLENGE_WHITE_EXTRA_PIECES = 2

-- Random "legal-looking" position: both kings + a spread of extra pieces (White gets a material edge for a realistic mate within the move budget). Unlike genAiMateIn1(), no immediate forced mate is required.
function genChallengePosition()
   for _ = 1, CHALLENGE_GEN_ATTEMPTS do
      local bkFile, bkRank = math.random(0,7), math.random(0,7)
      local bkIdx = A1 + bkFile - 10*bkRank

      local wkIdx = nil
      for _ = 1, 30 do
         local f, r = math.random(0,7), math.random(0,7)
         local idx = A1 + f - 10*r
         if idx ~= bkIdx and math.max(math.abs(f-bkFile), math.abs(r-bkRank)) > 1 then
            wkIdx = idx
            break
         end
      end
      if not wkIdx then goto continue end

      local occupied = {[bkIdx]=true, [wkIdx]=true}
      local board, ok = emptyBoard, true
      board = aiPut(board, bkIdx + __1, 'k')
      board = aiPut(board, wkIdx + __1, 'K')

      local totalPieces = math.random(CHALLENGE_MIN_PIECES, CHALLENGE_MAX_PIECES)
      local totalExtra = totalPieces - 2  -- minus both kings
      if totalExtra < 1 then totalExtra = 1 end

-- White gets ~55-70% of the extra pieces (winnable, but not overloaded); CHALLENGE_WHITE_EXTRA_PIECES adds more, shrinking Black's where possible.
      local numWhiteExtra = math.max(1, math.floor(totalExtra * (0.55 + math.random() * 0.15)))
      local numBlackExtra = math.max(0, totalExtra - numWhiteExtra)

      if CHALLENGE_WHITE_EXTRA_PIECES > 0 then
         local shift = math.min(CHALLENGE_WHITE_EXTRA_PIECES, numBlackExtra)
         numWhiteExtra = numWhiteExtra + CHALLENGE_WHITE_EXTRA_PIECES
         numBlackExtra = math.max(0, numBlackExtra - shift)
      end

      local whiteCounts = {}
      local blackCounts = {}
      local whiteBishopColor = nil
      local blackBishopColor = nil

      for _ = 1, numWhiteExtra do
         local pc = pickCappedPieceType(aiWhitePool, whiteCounts)
         if not pc then break end
         local forcedColor = nil
         if pc == 'B' then
            if not whiteBishopColor then
               whiteBishopColor = math.random(0, 1)
               forcedColor = whiteBishopColor
            else
               forcedColor = 1 - whiteBishopColor
            end
         end
         local idx = randomFreeSquare(occupied, pc == "P", forcedColor)
         if not idx then ok = false; break end
         occupied[idx] = true
         board = aiPut(board, idx + __1, pc)
         whiteCounts[pc] = (whiteCounts[pc] or 0) + 1
      end

      if ok then
         for _ = 1, numBlackExtra do
            local pc = pickCappedPieceType(aiBlackPool, blackCounts)
            if not pc then break end
            local forcedColor = nil
            if pc == 'b' then
               if not blackBishopColor then
                  blackBishopColor = math.random(0, 1)
                  forcedColor = blackBishopColor
               else
                  forcedColor = 1 - blackBishopColor
               end
            end
            local idx = randomFreeSquare(occupied, pc == "p", forcedColor)
            if not idx then ok = false; break end
            occupied[idx] = true
            board = aiPut(board, idx + __1, pc)
            blackCounts[pc:upper()] = (blackCounts[pc:upper()] or 0) + 1
         end
      end

      if ok then
         local pos = Position.new(board, 0, {false,false}, {false,false}, 0, 0)
-- Reject if either king already stands in check in the starting diagram, or if White (mover) has no legal move at all.
         if not next(findCheckers(pos)) and not next(findCheckers(pos:rotate())) and hasLegalMove(pos) then
            return board
         end
      end
      ::continue::
   end
   return nil
end

-- Runs one full challenge game on the given board: player is White. Returns "won", "quit", or "newgame" (player asked to regenerate a fresh position without finishing this one). Ends only via checkmate, draw, or the player leaving/resigning - no move limit.
function playChallengeGame(board, startPos, startLastMove, startCapturedByUser,
                                  startCapturedByEngine, startWhiteMoves, startHalfmoveClock,
                                  startGameHistory, startPositionCounts, startMoveHistory, startBlackMoves)
   local pos = startPos or Position.new(board, 0, {false,false}, {false,false}, 0, 0)
   local capturedByUser = startCapturedByUser or {}
   local capturedByEngine = startCapturedByEngine or {}
   local lastMove = startLastMove
   local whiteMoves = startWhiteMoves or 0
   local blackMoves = startBlackMoves or 0
   local halfmoveClock = startHalfmoveClock or 0
   local gameHistory = startGameHistory or { [tpKey(pos)] = true }
   local positionCounts = startPositionCounts or { [tpKey(pos)] = 1 }
   local moveHistory = startMoveHistory or {}
-- Index 0 is the starting position (before any moves), so 's0' can save it too. next="w" since it's the player's turn there.
   local moveSnapshots = {
      [0] = {
         pos = pos,
         lastMove = lastMove,
         capturedByUser = {table.unpack(capturedByUser)},
         capturedByEngine = {table.unpack(capturedByEngine)},
         whiteMoves = whiteMoves,
         blackMoves = blackMoves,
         halfmoveClock = halfmoveClock,
         moveHistory = {table.unpack(moveHistory)},
         nextToMove = "w",
      }
   }
   local hintsOn = CHALLENGE_HINTS_ENABLED
   local cachedHints = nil   -- hints table for the CURRENT position, computed once per move

-- Player's own move from two of their plies ago (skips the most recent, returns the one before). Used so findHintMove doesn't suggest undoing the move just played (e.g. after d4d3 then d3d4, don't suggest d4d3 again). Returns {from, to} or nil.
   local function findMoveTwoPliesAgo()
      local seen = 0
      for i = #moveHistory, 1, -1 do
         if moveHistory[i].by == "you" then
            seen = seen + 1
            if seen == 2 then
               local notation = moveHistory[i].notation
               local from, to = parse(notation:sub(1,2)), parse(notation:sub(3,4))
               if from and to then
                  return {from, to}
               end
               return nil
            end
         end
      end
      return nil
   end

-- Prints the board using cachedHints (computes it if missing/stale). forceRecompute=true only when the position just changed; the 'd' toggle reuses cachedHints since the position hasn't moved.
   local function showBoard(checkers, guards, isMateNow, forceRecompute)
      if hintsOn and not isMateNow and (forceRecompute or cachedHints == nil) then
         local avoidMove = findMoveTwoPliesAgo()
         local mv = findHintMove(pos, gameHistory, avoidMove)
         cachedHints = buildHintDisplay(mv)
      end
      local hints = (hintsOn and not isMateNow) and cachedHints or nil
      printboard(arrayToBoard(pos.board), lastMove, checkers, guards, isMateNow, hints)
   end

-- Prints the game code for the final position when a game ends (mate, resignation-equivalent draw, etc.) so the player can save/share/replay it. posForSave must be in the standard White-to-move orientation expected by saveGame() - callers pass pos:rotate() when `pos` is in Black's rotated view at that point.
-- Disabled: no game code output when a Challenge Game game ends.
   local function printFinalCode(posForSave)
   end

   while true do
      local checkers = findCheckers(pos)
      local guards = findKingGuards(pos, checkers)
      if next(checkers) then
         echoS("Check!")
      end
      showBoard(checkers, guards, false, true)
      print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))

      local usermove = nil
      while true do
         print("Your ".. (whiteMoves + 1) ..". move: ")
         local crdn = input()
         if not crdn then
            echoE("\nNo input (EOF). Ending challenge.")
            return "quit"
         end
         if crdn == '' then
            print("----")
            goto continue
         end
         if crdn == 'q' then
            print("----")
            echoW("Leaving Challenge Game.")
            return "quit"
         end
         if crdn == 'r' then
            print("----")
            echoW("Resigned this attempt.")
            return "newgame"
         end
         if crdn == 'n' then
            print("----")
            echoW("Starting new position...")
            return "newgame"
         end
         if crdn == 'th' then
            hintsOn = not hintsOn
            print("----")
            echoW("Hints: " .. (hintsOn and "ON" or "OFF"))
            showBoard(checkers, guards, false, true)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end
         if crdn == 'h' then
            print("----")
            showHelp()
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end
         if crdn == '?' then
            print("----")
            showAbout()
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end
         if crdn == 'u' then
            print("----")
            checkForUpdate()
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end
         if crdn == 'a' then
            SHOW_ANNOTATIONS = not SHOW_ANNOTATIONS
            print("----")
            echoW("Annotations: " .. (SHOW_ANNOTATIONS and "ON" or "OFF"))
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end
         if crdn == 'd' then
            USE_UNICODE_PIECES = not USE_UNICODE_PIECES
            updateDisplayMode()
            print("----")
            echoW("Display mode: " .. (USE_UNICODE_PIECES and "Unicode" or "Letters"))
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end
         if crdn:match('^n%d+$') then
            local n = tonumber(crdn:match('^n(%d+)$'))
            print("----")
            if n and n >= 1000 and n <= 50000 then
               NODES_SEARCHED = n
               TABLE_SIZE = NODES_SEARCHED * 25
               echoW("Node budget set to " .. NODES_SEARCHED)
               echoW("(table size " .. TABLE_SIZE .. ")")
            else
               echoE("Enter a number between 1000 and 50000, e.g. 'n2000'")
            end
            print("")
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end
         if crdn == 'm' then
            print("----")
            if #moveHistory == 0 then
               echoE("No moves played yet.")
            else
               local out = {"=== MOVE LIST ==="}
               local i = 1
               while i <= #moveHistory do
                  local w = moveHistory[i]
                  local bEntry = moveHistory[i + 1]
                  local moveNum = math.floor((i + 1) / 2)
                  local line = moveNum .. ". " .. w.notation
                  if bEntry then
                     line = line .. "  " .. bEntry.notation
                  end
                  table.insert(out, line)
                  i = i + 2
               end
               table.insert(out, "================")
               table.insert(out, "")
               print(table.concat(out, "\n"))
            end
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end
         if crdn == 's' then
            local code = saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, "w", moveHistory, board,
                                   {mode = "abc", hints = (hintsOn and "1" or "0")})
            print("----")
            echoW("=== GAME CODE ===")
            print(code)
            echoW("================")
            print("")
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end
         if crdn:match('^s%d+$') then
            local n = tonumber(crdn:match('^s(%d+)$'))
            local snap = moveSnapshots[n]
            print("----")
            if not snap then
               echoE("No snapshot for move " .. n .. ". You've played " .. whiteMoves .. " move(s) so far.")
               print("")
            else
               local code = saveGame(snap.pos, snap.lastMove, snap.capturedByUser, snap.capturedByEngine,
                                      snap.whiteMoves, snap.blackMoves, snap.halfmoveClock, snap.nextToMove or "b", snap.moveHistory, board,
                                      {mode = "abc", hints = (hintsOn and "1" or "0")})
               echoW("=== GAME CODE (as of move " .. n .. ") ===")
               print(code)
               echoW("================")
               print("")
            end
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end
         if crdn == 'l' then
            print("----")
            print("Paste game code:")
            local code = input()
            if code and code ~= '' then
               local result = {loadGame(code)}
               if result[1] then
                  pos = result[1]
                  lastMove = result[2]
                  capturedByUser = result[3] or {}
                  capturedByEngine = result[4] or {}
                  whiteMoves = result[5] or 0
                  blackMoves = result[6] or 0
                  halfmoveClock = result[7] or 0
                  local nextToMove = result[8] or "b"
                  local histStr = result[9]
                  moveSnapshots = {}
                  gameHistory, positionCounts = rebuildHistoryFromMoves(histStr, pos, board)
                  moveHistory = {}
                  if histStr and histStr ~= '-' and histStr ~= '' then
                     local i = 0
                     for notation in histStr:gmatch('[^,]+') do
                        i = i + 1
                        moveHistory[i] = { notation = notation, by = (i % 2 == 1) and "you" or "sunfish" }
                     end
                  end
                  cachedHints = nil
                  local loadedHints = result[12]
                  if loadedHints == "1" then
                     hintsOn = true
                  elseif loadedHints == "0" then
                     hintsOn = false
                  end

-- s0 after a load = the position exactly as loaded, before any further moves (and before Sunfish's automatic reply below).
                  moveSnapshots[0] = {
                     pos = pos,
                     lastMove = lastMove,
                     capturedByUser = {table.unpack(capturedByUser)},
                     capturedByEngine = {table.unpack(capturedByEngine)},
                     whiteMoves = whiteMoves,
                     blackMoves = blackMoves,
                     halfmoveClock = halfmoveClock,
                     moveHistory = {table.unpack(moveHistory)},
                     nextToMove = nextToMove,
                  }

                  local reloadCode = saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, nextToMove, moveHistory, board,
                                               {mode = "abc", hints = (hintsOn and "1" or "0")})
                  echoW("=== GAME CODE ===")
                  print(reloadCode)
                  echoW("================")
                  echoW("Game loaded.")

-- Sunfish's turn: show the loaded position (your move), then play its reply automatically, as in a live game.
                  if nextToMove == "b" then
                     if lastMove then
                        echoW("Loaded position (after your move):")
                        print("Your move: \n" .. render(lastMove[1]) .. render(lastMove[2]))
                        local checkersAfterYourMove = findCheckers(pos)
                        local guardsAfterYourMove = findKingGuards(pos, checkersAfterYourMove)
                        if next(checkersAfterYourMove) then
                           echoS("Check!")
                        end
                        printboard(arrayToBoard(pos.board), lastMove, checkersAfterYourMove, guardsAfterYourMove)
                        print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
                     end

                     local rotated = pos:rotate()
                     local engineHasMove = hasLegalMove(rotated)
                     if not engineHasMove then
                        echoW("Sunfish has no legal move (checkmate or stalemate).")
                     else
                        echoW("🐠 Sunfish is thinking...")
                        local enginemove, score, reachedDepth, usedNodes, elapsed = search(rotated, CHALLENGE_ENGINE_NODES, gameHistory)
                        assert(score)

                        if enginemove and not isLegalMove(rotated, enginemove) then
                           enginemove = nil
                        end
                        if not enginemove then
                           local legal = legalMovesOf(rotated)
                           if #legal > 0 then
                              table.sort(legal, function(a, b) return rotated:value(a) > rotated:value(b) end)
                              enginemove = legal[1]
                           end
                        end

                        if enginemove then
                           local engineCap = capturedAt(rotated, enginemove)
                           local enginePawnMove = isPawnMove(rotated, enginemove)
                           if engineCap or enginePawnMove then
                              halfmoveClock = 0
                           else
                              halfmoveClock = halfmoveClock + 1
                           end
                           if engineCap then table.insert(capturedByEngine, engineCap) end

                           local engineMoveNotation = render(119-enginemove[0 + __1]) .. render(119-enginemove[1 + __1])
                           if enginemove[3] and enginemove[3] ~= '' and enginemove[3] ~= 'Q' then
                              engineMoveNotation = engineMoveNotation .. enginemove[3]:lower()
                           end
                           table.insert(moveHistory, {notation = engineMoveNotation, by = "sunfish"})
                           pos = rotated:move(enginemove)
                           pos.score = 0
                           blackMoves = blackMoves + 1
                           gameHistory[tpKey(pos)] = true
                           positionCounts[tpKey(pos)] = (positionCounts[tpKey(pos)] or 0) + 1
                           lastMove = {119 - enginemove[1], 119 - enginemove[2]}
                           print("Sunfish " .. blackMoves .. ". move: \n" .. engineMoveNotation .. " (" .. math.floor(elapsed + 0.5) .. "s) - score: " .. score)
                        end
                     end
                  end
               else
                  echoE("Could not load that code.")
               end
            end
            checkers = findCheckers(pos)
            guards = findKingGuards(pos, checkers)
            showBoard(checkers, guards, false, true)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end

         usermove = {parse(crdn:sub(1,2)), parse(crdn:sub(3,4))}
         local from = usermove[1]
         if not (from and usermove[2]) then
            echoE(crdn .. " - Invalid format. Enter a move like 'a2a3'")
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         elseif not (pos.board[from + __1] and pos.board[from + __1] >= 65 and pos.board[from + __1] <= 90) then
            echoE(crdn .. " - There's no piece of yours on that square.")
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         elseif not ttfind(pos:genMoves(), usermove) then
            echoE(crdn .. " - That move is not allowed.")
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         elseif not isLegalMove(pos, usermove) then
            echoE(crdn .. " - That move leaves your king in check.")
            showBoard(checkers, guards, false, false)
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         else
            if isPromotionMove(pos, usermove) then
               print("Promote to (Q/R/B/N)? [default: Q]")
               local promoInput = input()
               local promoChar = promoInput and promoInput:upper():sub(1,1) or "Q"
               if promoChar ~= "Q" and promoChar ~= "R" and promoChar ~= "B" and promoChar ~= "N" then
                  echoW("Invalid choice, defaulting to Queen.")
                  promoChar = "Q"
               end
               usermove[3] = promoChar
            end
            whiteMoves = whiteMoves + 1
            print(crdn)
            break
         end
         ::continue::
      end

      local userCap = capturedAt(pos, usermove)
      local userPawnMove = isPawnMove(pos, usermove)
      if userCap or userPawnMove then
         halfmoveClock = 0
      else
         halfmoveClock = halfmoveClock + 1
      end
      if userCap then table.insert(capturedByUser, userCap) end
      local userNotation = render(usermove[1]) .. render(usermove[2])
      if usermove[3] and usermove[3] ~= '' and usermove[3] ~= 'Q' then
         userNotation = userNotation .. usermove[3]:lower()
      end
      table.insert(moveHistory, {notation = userNotation, by = "you"})
      pos = pos:move(usermove)
      pos.score = 0
      gameHistory[tpKey(pos)] = true
      positionCounts[tpKey(pos)] = (positionCounts[tpKey(pos)] or 0) + 1

-- Snapshot for 's<N>'; pos is in Black's rotated view here, so store the White-view rotation to match saveGame()/loadGame().
      moveSnapshots[whiteMoves] = {
         pos = pos:rotate(),
         lastMove = {usermove[1], usermove[2]},
         capturedByUser = {table.unpack(capturedByUser)},
         capturedByEngine = {table.unpack(capturedByEngine)},
         whiteMoves = whiteMoves,
         blackMoves = blackMoves,
         halfmoveClock = halfmoveClock,
         moveHistory = {table.unpack(moveHistory)},
         nextToMove = "b",
      }

      local checkersAfterUser = findCheckers(pos)
      local guardsAfterUser = findKingGuards(pos, checkersAfterUser)
      local engineHasMove = hasLegalMove(pos)
      local isMateNow = next(checkersAfterUser) ~= nil and not engineHasMove
      local displayCheckers = {}
      local displayGuards = {}
      for idx in pairs(checkersAfterUser) do
         displayCheckers[119 - idx] = true
      end
      for idx in pairs(guardsAfterUser) do
         displayGuards[119 - idx] = true
      end

      if next(displayCheckers) and not isMateNow then
         echoS("Check!")
      end
      printboard(arrayToBoard(pos:rotate().board), {usermove[1], usermove[2]}, displayCheckers, displayGuards, isMateNow)

      if isMateNow then
         echoS("Checkmate in " .. whiteMoves .. " moves!")
         echoS("You won the challenge!")
         printFinalCode(pos:rotate())
         return "won"
      end
      if not engineHasMove then
         echoW("Stalemate - draw! (counts as not solved)")
         printFinalCode(pos:rotate())
         return "lost"
      end
      if hasInsufficientMaterial(pos.board) then
         echoW("Draw by insufficient material! (counts as not solved)")
         printFinalCode(pos:rotate())
         return "lost"
      end
      if halfmoveClock >= 100 then
         echoW("Draw by 50-move rule! (counts as not solved)")
         printFinalCode(pos:rotate())
         return "lost"
      end
      if positionCounts[tpKey(pos)] >= 3 then
         echoW("Draw by threefold repetition! (counts as not solved)")
         printFinalCode(pos:rotate())
         return "lost"
      end

      echoW("🐠 Sunfish is thinking...")
      local enginemove, score, reachedDepth, usedNodes, elapsed = search(pos, CHALLENGE_ENGINE_NODES, gameHistory)
      assert(score)

      if enginemove and not isLegalMove(pos, enginemove) then
         enginemove = nil
      end
      if not enginemove then
         local legal = legalMovesOf(pos)
         if #legal == 0 then
            if next(findCheckers(pos)) then
               echoS("Checkmate!")
               echoS("You won the challenge!")
               printFinalCode(pos:rotate())
               return "won"
            else
               echoW("Stalemate - draw! (counts as not solved)")
               printFinalCode(pos:rotate())
               return "lost"
            end
         else
            table.sort(legal, function(a, b) return pos:value(a) > pos:value(b) end)
            enginemove = legal[1]
         end
      end

      local engineCap = capturedAt(pos, enginemove)
      local enginePawnMove = isPawnMove(pos, enginemove)
      if engineCap or enginePawnMove then
         halfmoveClock = 0
      else
         halfmoveClock = halfmoveClock + 1
      end
      if engineCap then table.insert(capturedByEngine, engineCap) end

      local engineMoveNotation = render(119-enginemove[0 + __1]) .. render(119-enginemove[1 + __1])
      if enginemove[3] and enginemove[3] ~= '' and enginemove[3] ~= 'Q' then
         engineMoveNotation = engineMoveNotation .. enginemove[3]:lower()
      end
      table.insert(moveHistory, {notation = engineMoveNotation, by = "sunfish"})
      print("Sunfish " .. (blackMoves + 1) .. ". move: \n" .. engineMoveNotation .. " (" .. math.floor(elapsed + 0.5) .. "s) - score: " .. score)
      -- IMPORTANT: Sunfish's move must be applied before computing the next position, history, or board display.
      pos = pos:move(enginemove)
      pos.score = 0

      blackMoves = blackMoves + 1
      gameHistory[tpKey(pos)] = true
      positionCounts[tpKey(pos)] = (positionCounts[tpKey(pos)] or 0) + 1
      lastMove = {119 - enginemove[1], 119 - enginemove[2]}

      if hasInsufficientMaterial(pos.board) then
         printboard(arrayToBoard(pos.board), lastMove, {}, {})
         echoW("Draw by insufficient material! (counts as not solved)")
         printFinalCode(pos)
         return "lost"
      end
      if halfmoveClock >= 100 then
         printboard(arrayToBoard(pos.board), lastMove, {}, {})
         echoW("Draw by 50-move rule! (counts as not solved)")
         printFinalCode(pos)
         return "lost"
      end
      if positionCounts[tpKey(pos)] >= 3 then
         printboard(arrayToBoard(pos.board), lastMove, {}, {})
         echoW("Draw by threefold repetition! (counts as not solved)")
         printFinalCode(pos)
         return "lost"
      end

      local matingCheckers = findCheckers(pos)
      local matingGuards = findKingGuards(pos, matingCheckers)
      if next(matingCheckers) and not hasLegalMove(pos) then
         printboard(arrayToBoard(pos.board), lastMove, matingCheckers, matingGuards, true)
         echoE("Checkmate!")
         echoE("You lost the challenge.")
         printFinalCode(pos)
         return "lost"
      end
   end
end

function challengeMode()
   print("")
   echoW("=== CHALLENGE GAME ===")
   print("• 'th' - toggle hints")
   print("• 'h' for help")
   print("• 'q' to quit.")
   print("")
   echoW("Generating position...")
   local board = genChallengePosition()
   if not board then
      echoE("Couldn't generate a position, try again.")
      return
   end
   while true do
      local result = playChallengeGame(board)
      if result == "quit" then
         return
      elseif result == "won" or result == "lost" or result == "newgame" then
         echoW("Generating new position...")
         board = genChallengePosition()
         if not board then
            echoE("Couldn't generate a position, try again.")
            return
         end
      end
   end
end

-- challenge.lua ======= end

-- main.lua ======= 

function main()
   local pos = Position.new(initial, 0, {true,true}, {true,true}, 0, 0)
-- Board this game started from (standard, unless a custom/puzzle position is loaded via 'l' before any moves). Saved with the game code so rebuildHistoryFromMoves() replays from the real start instead of always assuming `initial`.
   local startingBoard = initial
   local capturedByUser = {}
   local capturedByEngine = {}
   local lastMove = nil
   local whiteMoves = 0
   local blackMoves = 0
   local halfmoveClock = 0  -- resets on capture or pawn move; draw at 100 (50 full moves)
-- Position hashes seen this game; lets search() score repeats as a draw. Seeded with the starting position.
   local gameHistory = { [tpKey(pos)] = true }
-- Same keys as gameHistory but counts occurrences, to detect actual threefold repetition and end the game.
   local positionCounts = { [tpKey(pos)] = 1 }
-- Full move history, one entry per ply: {notation, by}. Used by 'm' (move list) and 's<N>' (save as of move N).
   local moveHistory = {}
-- Snapshot of full state after each of your moves, keyed by move number; lets 's<N>' save as of move N even after playing further.
-- Index 0 is the starting position (before any moves), so 's0' can save it too. next="w" since it's the player's turn there.
   local moveSnapshots = {
      [0] = {
         pos = pos,
         lastMove = nil,
         capturedByUser = {},
         capturedByEngine = {},
         whiteMoves = 0,
         blackMoves = 0,
         halfmoveClock = 0,
         moveHistory = {},
         startingBoard = startingBoard,
         nextToMove = "w",
      }
   }

   print("")
   echoW("=== sunfish.lua ===")
   print("• 'h' for help")
   print("• 'q' to quit.")

   while true do
      local checkers = findCheckers(pos)
      local guards = findKingGuards(pos, checkers)
      if next(checkers) then
         echoS("Check!")
      end
      printboard(arrayToBoard(pos.board), lastMove, checkers, guards)
print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))

            local usermove = nil
while true do
    print("Your ".. (whiteMoves + 1) ..". move: ")
   local startInputTime = os.clock()  -- start timing
   local crdn = input()
   local inputElapsed = os.clock() - startInputTime  -- elapsed time
   if not crdn then
      echoE("\nNo input from terminal (EOF). Ending game.")
      return
   end
   if crdn == '' then
      print("----")
      goto continue
   end
   if crdn == 'q' then
       print("----")
      echoW("Quitting game.")
      return
   elseif crdn == 'u' then
      print("----")
   checkForUpdate()
   displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
      elseif crdn == 'a' then
   SHOW_ANNOTATIONS = not SHOW_ANNOTATIONS
   print("----")
   echoW("Annotations: " .. (SHOW_ANNOTATIONS and "ON" or "OFF"))
   displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == 'd' then
      USE_UNICODE_PIECES = not USE_UNICODE_PIECES
      updateDisplayMode()
      print("----")
      echoW("Display mode: " .. (USE_UNICODE_PIECES and "Unicode" or "Letters"))
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
      elseif crdn:match('^n%d+$') then
   local n = tonumber(crdn:match('^n(%d+)$'))
   if n and n >= 1000 and n <= 50000 then
      NODES_SEARCHED = n
      TABLE_SIZE = NODES_SEARCHED * 25
      print("----")
      echoW("Node budget set to " .. NODES_SEARCHED)
      echoW("(table size " .. TABLE_SIZE .. ")")
   else
      print("----")
      echoE("Enter a number between 1000 and 50000, e.g. 'n2000'")
   end
   print("")
   displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == 's' then
      local code = saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, "w", moveHistory, startingBoard)
      print("----")
      echoW("=== GAME CODE ===")
      print(code)
      echoW("================")
      print("")
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn:match('^s%d+$') then
      local n = tonumber(crdn:match('^s(%d+)$'))
      local snap = moveSnapshots[n]
      if not snap then
          print("----")
         echoE("No snapshot for move " .. n .. ". You've played " .. whiteMoves .. " move(s) so far.")
         print("")
      else
         local code = saveGame(snap.pos, snap.lastMove, snap.capturedByUser, snap.capturedByEngine,
                                snap.whiteMoves, snap.blackMoves, snap.halfmoveClock, snap.nextToMove or "b", snap.moveHistory, snap.startingBoard)
        print("----")
         echoW("=== GAME CODE (as of move " .. n .. ") ===")
         print(code)
         echoW("================")
         print("")
      end
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == 'm' then
      if #moveHistory == 0 then
          print("----")
         echoE("No moves played yet.")
      else
          print("----")
         local out = {"=== MOVE LIST ==="}
         local i = 1
         while i <= #moveHistory do
            local w = moveHistory[i]
            local bEntry = moveHistory[i + 1]
            local moveNum = math.floor((i + 1) / 2)
            local line = moveNum .. ". " .. w.notation
            if bEntry then
               line = line .. "  " .. bEntry.notation
            end
            table.insert(out, line)
            i = i + 2
         end
         table.insert(out, "================")
         table.insert(out, "")
-- Single print() call so the whole move list can be copied in one go, instead of one print() per line.
         print(table.concat(out, "\n"))
      end
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == 'l' then
       print("----")
   print("Paste game code:")
   local code = input()
   if code and code ~= '' then
      local result = {loadGame(code)}
      if result[1] then
         if result[11] == "abc" then
            echoW("Note: this code was saved from Challenge Game (type 'cg' then 'l' there to resume with hints).")
         end
         pos = result[1]
         lastMove = result[2]
         capturedByUser = result[3]
         capturedByEngine = result[4]
         whiteMoves = result[5]
         blackMoves = result[6]
         halfmoveClock = result[7] or 0
         local nextToMove = result[8] or "b"
         local histStr = result[9]
         moveSnapshots = {}

-- Tracks where this (loaded) game actually started, so replay below - and future saves - use the real starting point rather than always the standard setup. If the code has no explicit start but also no history, the loaded board itself is the start; otherwise fall back to standard (best-effort for old codes missing both fields).
         if result[10] then
            startingBoard = result[10]
         elseif not histStr or histStr == '-' or histStr == '' then
            startingBoard = arrayToBoard(pos.board)
         end

-- Rebuilds gameHistory/positionCounts by replaying the saved move list from the real starting position (not always `initial`), for correct threefold repetition across save/load (falls back to seeding just the loaded position if histStr is missing/unparseable).
         gameHistory, positionCounts = rebuildHistoryFromMoves(histStr, pos, startingBoard)

-- Reconstructs the notation-only moveHistory (for 'm') from the same string, lining up with the replayed gameHistory/positionCounts.
         moveHistory = {}
         if histStr and histStr ~= '-' and histStr ~= '' then
            local i = 0
            for notation in histStr:gmatch('[^,]+') do
               i = i + 1
               moveHistory[i] = { notation = notation, by = (i % 2 == 1) and "you" or "sunfish" }
            end
         end

-- s0 after a load = the position exactly as loaded, before any further moves.
         moveSnapshots[0] = {
            pos = pos,
            lastMove = lastMove,
            capturedByUser = {table.unpack(capturedByUser)},
            capturedByEngine = {table.unpack(capturedByEngine)},
            whiteMoves = whiteMoves,
            blackMoves = blackMoves,
            halfmoveClock = halfmoveClock,
            moveHistory = {table.unpack(moveHistory)},
            startingBoard = startingBoard,
            nextToMove = nextToMove,
         }

         local code = saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, nextToMove, moveHistory, startingBoard)
      echoW("=== GAME CODE ===")
      print(code)
      echoW("================")
         echoS("Game loaded!")
         print("")

         if nextToMove == "b" then
-- Sunfish's turn: show the saved lastMove (this is the position as saved - YOUR move, before Sunfish replies), then play its reply as it would in a live game.
            if lastMove then
   echoW("Loaded position (after your move):")
   print("Your move: \n" .. render(lastMove[1]) .. render(lastMove[2]))
   print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
               local checkersAfterYourMove = findCheckers(pos)
               local guardsAfterYourMove = findKingGuards(pos, checkersAfterYourMove)
               if next(checkersAfterYourMove) then
                  echoS("Check!")
               end
               printboard(arrayToBoard(pos.board), lastMove, checkersAfterYourMove, guardsAfterYourMove)
            end
            local rotated = pos:rotate()
            print("")
            echoW("🐠 Sunfish is thinking...")
enginemove, score, reachedDepth, usedNodes, elapsed = search(pos, NODES_SEARCHED, gameHistory)
assert(score)
            if enginemove and not isLegalMove(rotated, enginemove) then
               enginemove = nil
            end
            if not enginemove then
               local legal = legalMovesOf(rotated)
               if #legal > 0 then
                  table.sort(legal, function(a, b) return rotated:value(a) > rotated:value(b) end)
                  enginemove = legal[1]
               end
            end
            if enginemove then
               local engineCap = capturedAt(rotated, enginemove)
               local enginePawnMove = isPawnMove(rotated, enginemove)
               if engineCap or enginePawnMove then
                  halfmoveClock = 0
               else
                  halfmoveClock = halfmoveClock + 1
               end
               if engineCap then table.insert(capturedByEngine, engineCap) end
               local engineMoveNotation = render(119-enginemove[0 + __1]) .. render(119-enginemove[1 + __1])
               if enginemove[3] and enginemove[3] ~= '' and enginemove[3] ~= 'Q' then
                  engineMoveNotation = engineMoveNotation .. enginemove[3]:lower()
               end
               print("Sunfish " .. (blackMoves + 1) .. ". move: \n" .. engineMoveNotation .. " (" .. math.floor(elapsed + 0.5) .. "s) - score: " .. score)
               print("Captured: " .. renderCaptured(capturedByEngine, whiteSymbols))
               table.insert(moveHistory, {notation = engineMoveNotation, by = "sunfish"})
               pos = rotated:move(enginemove)
               blackMoves = blackMoves + 1
               pos.score = 0
               gameHistory[tpKey(pos)] = true
               positionCounts[tpKey(pos)] = (positionCounts[tpKey(pos)] or 0) + 1
               lastMove = {119 - enginemove[1], 119 - enginemove[2]}
            else
               echoW("Sunfish has no legal move (checkmate or stalemate).")
            end
         end

         if lastMove and nextToMove ~= "b" then
            print("Sunfish " .. blackMoves .. ". move: \n" .. render(lastMove[1]) .. render(lastMove[2]))
            print("Captured: " .. renderCaptured(capturedByEngine, whiteSymbols))
         end

         local checkers = findCheckers(pos)
         local guards = findKingGuards(pos, checkers)
         local loadedMate = next(checkers) ~= nil and not hasLegalMove(pos)
         if next(checkers) then
            echoS("Check!")
         end
         printboard(arrayToBoard(pos.board), lastMove, checkers, guards, loadedMate)
print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
-- A loaded code can itself be a finished position (mate/stalemate) if saved/edited that way; check before handing control back to the player, or the game would sit waiting for an impossible move.
         if loadedMate then
            echoE("Checkmate!")
            echoE("You lost")
            return
         elseif not hasLegalMove(pos) then
            echoW("Stalemate - draw!")
            return
         end
      else
         echoE("Invalid code. Game continues.")
         print("")
         displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
      end
   end
   elseif crdn == 'r' then
       print("----")
      echoE("You resigned. Black wins!")
      return
   elseif crdn == 'n' then
       print("----")
      echoW("Starting new game...")
      return main()
   elseif crdn == 'h' then
       print("----")
      showHelp()
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == '?' then
       print("----")
      showAbout()
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == 'm1' then
      aipuzMate1()
      echoW("Resuming the game.")
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == 'cg' then
      challengeMode()
      echoW("Resuming the game.")
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   else
      usermove = {parse(crdn:sub(1,2)), parse(crdn:sub(3,4))}
      local from = usermove[1]
      if not (from and usermove[2]) then
         echoE(crdn.. " - Invalid format. Enter a move like 'a2a3'")
         displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
      elseif not (pos.board[from + __1] and pos.board[from + __1] >= 65 and pos.board[from + __1] <= 90) then -- isupper
         echoE(crdn .. " - There's no piece of yours on that square.")
         displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
      elseif not ttfind(pos:genMoves(), usermove) then
         echoE(crdn .. " - That move is not allowed.")
         displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
      elseif not isLegalMove(pos, usermove) then
         echoE(crdn .. " - That move leaves your king in check.")
         displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
      else
         if isPromotionMove(pos, usermove) then
            print("Promote to (Q/R/B/N)? [default: Q]")
            local promoInput = input()
            local promoChar = promoInput and promoInput:upper():sub(1,1) or "Q"
            if promoChar ~= "Q" and promoChar ~= "R" and promoChar ~= "B" and promoChar ~= "N" then
               echoW("Invalid choice, defaulting to Queen.")
               promoChar = "Q"
            end
            usermove[3] = promoChar -- ttfind() already auto-filled usermove[3] with 'Q'; overwrite with player's actual choice
         end
 whiteMoves = whiteMoves + 1
print(crdn .. " (" .. math.floor(inputElapsed + 0.5) .. "s)")
break
      end
   end
   ::continue::
end


      local userCap = capturedAt(pos, usermove)
      local userPawnMove = isPawnMove(pos, usermove)
      if userCap or userPawnMove then
         halfmoveClock = 0
      else
         halfmoveClock = halfmoveClock + 1
      end
      if userCap then table.insert(capturedByUser, userCap) end
-- Promotion suffix (e.g. "a7a8n") appended when promoted to non-Queen, so 'm' displays it correctly and rebuildHistoryFromMoves() can replay the exact position.
      local userNotation = render(usermove[1]) .. render(usermove[2])
      if usermove[3] and usermove[3] ~= '' and usermove[3] ~= 'Q' then
         userNotation = userNotation .. usermove[3]:lower()
      end
      table.insert(moveHistory, {
         notation = userNotation,
         by = "you"
      })
      pos = pos:move(usermove)
pos.score = 0
gameHistory[tpKey(pos)] = true
positionCounts[tpKey(pos)] = (positionCounts[tpKey(pos)] or 0) + 1

-- Snapshot for 's<N>'; pos is in Black's rotated view here, so store the White-view rotation to match saveGame()/loadGame().
      moveSnapshots[whiteMoves] = {
         pos = pos:rotate(),
         lastMove = {usermove[1], usermove[2]},
         capturedByUser = {table.unpack(capturedByUser)},
         capturedByEngine = {table.unpack(capturedByEngine)},
         whiteMoves = whiteMoves,
         blackMoves = blackMoves,
         halfmoveClock = halfmoveClock,
         moveHistory = {table.unpack(moveHistory)},
         startingBoard = startingBoard,
         nextToMove = "b",
      }

      local checkersAfterUser = findCheckers(pos)
guardsAfterUser = findKingGuards(pos, checkersAfterUser)
engineHasMove = hasLegalMove(pos)
isMateNow = next(checkersAfterUser) ~= nil and not engineHasMove
displayCheckers = {}
displayGuards = {}
for idx in pairs(checkersAfterUser) do
   displayCheckers[119 - idx] = true
end
for idx in pairs(guardsAfterUser) do
   displayGuards[119 - idx] = true
end

-- Print "Check!" only if not mate
if next(displayCheckers) and not isMateNow then
   echoS("Check!")
end
printboard(arrayToBoard(pos:rotate().board), {usermove[1], usermove[2]}, displayCheckers, displayGuards, isMateNow)

if isMateNow then
   echoS("Checkmate in " .. whiteMoves .. " moves for White!")
   echoS("You won!")
   break
end
      if not engineHasMove then
         echoW("Stalemate - draw!")
         break
      end
      if hasInsufficientMaterial(pos.board) then
         echoW("Draw by insufficient material!")
         break
      end
      if halfmoveClock >= 100 then
         echoW("Draw by 50-move rule!")
         break
      end
      if positionCounts[tpKey(pos)] >= 3 then
         echoW("Draw by threefold repetition!")
         break
      end
      echoW("🐠 Sunfish is thinking...")
enginemove, score, reachedDepth, usedNodes, elapsed = search(pos, NODES_SEARCHED, gameHistory)
assert(score)
      if score <= -MATE_UPPER then
         echoS("Checkmate in " .. whiteMoves .. " moves for White!")
         echoS("You won!")
         break
      end

      if enginemove and not isLegalMove(pos, enginemove) then
         enginemove = nil
      end

      if not enginemove then
         local legal = legalMovesOf(pos)
         if #legal == 0 then
            if next(findCheckers(pos)) then
               echoS("Checkmate in " .. whiteMoves .. " moves for White!")
               echoS("You won")
            else
               echoW("Stalemate - draw!")
            end
            break
         else
            table.sort(legal, function(a, b) return pos:value(a) > pos:value(b) end)
            enginemove = legal[1]
         end
      end

      local engineCap = capturedAt(pos, enginemove)
      local enginePawnMove = isPawnMove(pos, enginemove)
      if engineCap or enginePawnMove then
         halfmoveClock = 0
      else
         halfmoveClock = halfmoveClock + 1
      end
      if engineCap then table.insert(capturedByEngine, engineCap) end

      local engineMoveNotation = render(119-enginemove[0 + __1]) .. render(119-enginemove[1 + __1])
      if enginemove[3] and enginemove[3] ~= '' and enginemove[3] ~= 'Q' then
         engineMoveNotation = engineMoveNotation .. enginemove[3]:lower()
      end
print("Sunfish ".. (blackMoves + 1) ..". move: \n" .. engineMoveNotation .. " (" .. math.floor(elapsed + 0.5) .. "s) - score: " .. score)
print("Captured: " .. renderCaptured(capturedByEngine, whiteSymbols))
table.insert(moveHistory, {notation = engineMoveNotation, by = "sunfish"})
pos = pos:move(enginemove)
blackMoves = blackMoves + 1
pos.score = 0  -- CRITICAL!
gameHistory[tpKey(pos)] = true
positionCounts[tpKey(pos)] = (positionCounts[tpKey(pos)] or 0) + 1
      lastMove = {119 - enginemove[1], 119 - enginemove[2]}

      if hasInsufficientMaterial(pos.board) then
         printboard(arrayToBoard(pos.board), lastMove, {}, {})
         echoW("Draw by insufficient material!")
         break
      end
      if halfmoveClock >= 100 then
         printboard(arrayToBoard(pos.board), lastMove, {}, {})
         echoW("Draw by 50-move rule!")
         break
      end
      if positionCounts[tpKey(pos)] >= 3 then
         printboard(arrayToBoard(pos.board), lastMove, {}, {})
         echoW("Draw by threefold repetition!")
         break
      end
   -- Always confirm mate against the real position, not just when the search score crosses MATE_UPPER - a shallow/imperfect score can miss an actual mate.
   local matingCheckers = findCheckers(pos)
   local matingGuards = findKingGuards(pos, matingCheckers)

   if next(matingCheckers) and not hasLegalMove(pos) then -- check + no legal moves = mate
      printboard(arrayToBoard(pos.board), lastMove, matingCheckers, matingGuards, true)
      echoE("Checkmate!")
      echoE("You lost")
      break
   elseif score >= MATE_UPPER then -- score claimed mate but position isn't actually mate; play on
      echoE("Evaluation error detected. Continuing game...")
   end
   end
end

-- main.lua ======= end

math.randomseed(os.time())
main()