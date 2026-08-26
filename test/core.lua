-- sunfish.lua Chess engine, Lua port chain: 1. Original algorithm: Sunfish (Python) by Thomas Ahle https://github.com/thomasahle/sunfish - BSD license 2. Initial Lua transpilation attributed to Soumith Chintala 3. Extended for Yantra Launcher / Android (Luaj-jse 3.0.1), with UI, save/load, puzzle mode, and search tuning, by borko17 (https://github.com/borko17/sunfish-lua) (with help from Claude AI).

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
-- Loader always fetches the latest version of every part on each /run, so the
-- user is always on the newest code already -- there's nothing to compare against
-- locally. 'u' here just reports the version and changelog currently published
-- in the manifest on GitHub.
UPDATE_BASE_URL = "https://raw.githubusercontent.com/borko17/sunfish.lua/main/test/"
MANIFEST_URL = UPDATE_BASE_URL .. "manifest.txt"

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
   print("Checking version on GitHub...")
   local result = fetchURL(MANIFEST_URL)

   if not result or result == '' then
      echoE("No response from GitHub. Check your connection.")
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
