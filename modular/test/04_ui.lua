-- ui.lua ======= 0755

function updateDisplayMode()
   if USE_UNICODE_INVERTED_PIECES then
      USE_UNICODE_PIECES = true
   end

   whiteSymbols = USE_UNICODE_PIECES and whiteSymbols_unicode or whiteSymbols_letters
   blackSymbols = USE_UNICODE_PIECES and blackSymbols_unicode or blackSymbols_letters
   emptySquareSymbols = USE_UNICODE_PIECES and emptySquareSymbols_unicode or emptySquareSymbols_letters

   if USE_UNICODE_INVERTED_PIECES and USE_UNICODE_PIECES then
      whiteSymbols, blackSymbols = blackSymbols, whiteSymbols
      emptySquareSymbols = { light = emptySquareSymbols.dark, dark = emptySquareSymbols.light }
   end

-- "Captured" lists always store the captured piece's letter uppercased regardless of its
-- real color, so the caption glyph set has to be chosen by who captured, not board case.
-- ownSymbols renders what the player captured (opponent's set); opponentSymbols renders
-- what Sunfish captured (player's own set) - swapped from White's-perspective defaults
-- when PLAYER_IS_BLACK, so captured pieces always show their true color.
   if PLAYER_IS_BLACK then
      ownSymbols, opponentSymbols = whiteSymbols, blackSymbols
   else
      ownSymbols, opponentSymbols = blackSymbols, whiteSymbols
   end
end

-- Cycles: Letters -> Unicode -> Unicode Inverted -> Letters
function cycleDisplayMode()
   if not USE_UNICODE_PIECES then
      USE_UNICODE_PIECES = true
      USE_UNICODE_INVERTED_PIECES = false
   elseif not USE_UNICODE_INVERTED_PIECES then
      USE_UNICODE_INVERTED_PIECES = true
   else
      USE_UNICODE_PIECES = false
      USE_UNICODE_INVERTED_PIECES = false
   end
   updateDisplayMode()
   if USE_UNICODE_PIECES and USE_UNICODE_INVERTED_PIECES then
      return "Unicode (inverted)"
   elseif USE_UNICODE_PIECES then
      return "Unicode"
   else
      return "Letters"
   end
end

-- User interface

-- When true, the player is Black and the board is shown/entered from Black's side:
-- 'a1' as typed/shown means the square physically in the a1 corner of Black's view,
-- i.e. absolute h8. Set by 'nb' in main(), read by parse()/render()/printboard().
PLAYER_IS_BLACK = false

function parse(c)
   if not c then return nil end
   local p, v = c:sub(1,1), c:sub(2,2)
   if not (p and v and tonumber(v)) then return nil end

   local fil, rank = string.byte(p) - string.byte('a'), tonumber(v) - 1
   if PLAYER_IS_BLACK then
      fil, rank = 7 - fil, 7 - rank
   end
   return A1 + fil - 10*rank
end

function render(i)
   local rank, fil = math.floor((i - A1) / 10), (i - A1) % 10
   if PLAYER_IS_BLACK then
      rank, fil = -7 - rank, 7 - fil -- rank here is already negated (-7..0), so flip within that range
   end
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
-- Rank rows top-to-bottom, and files within each row left-to-right.
-- NOTE: the board string passed in here is already physically rotated 180°
-- when PLAYER_IS_BLACK (see Position:rotate() in main()), so the *reading*
-- order must stay the same as White's (k=3..10, i=2..9) - only the printed
-- rank/file labels flip, so the board is shown from Black's side (rank 1 at
-- top, h-file on the left) without re-reversing the already-rotated string.
   local kFrom, kTo, kStep = 3, 10, 1
   local iFrom, iTo, iStep = 2, 9, 1
   for k = kFrom, kTo, kStep do
      local rank = PLAYER_IS_BLACK and (k - 2) or (11 - k)
      local line = {}
      table.insert(line, tostring(rank) .. " " .. sideBorder .. "  ")
      for i = iFrom, iTo, iStep do
         local idx = (k - 1) * 10 + (i - 1)
-- Read directly from the flat board string at its absolute position (idx+1, 1-indexed),
-- rather than splitting into lines by '\n' first: after Position:rotate() the '\n' bytes
-- move around inside what used to be row boundaries, so a naive per-line split misreads
-- the board (dropped/shifted files). Absolute-index lookup stays correct either way.
         local c = board:sub(idx + 1, idx + 1)
         local file = i - 1
         local sym
         if c == '.' then
            if (file + rank) % 2 == 0 then
               sym = emptySquareSymbols.light
            else
               sym = emptySquareSymbols.dark
            end
         elseif USE_UNICODE_PIECES then
            local isWhitePiece = c:match('%u') ~= nil -- uppercase = white piece
            local upperC = c:upper()
            local set = isWhitePiece and whiteSymbols or blackSymbols
            sym = set[upperC] or c
         else
            sym = c
         end

         if hints[idx] then
   if #line > 0 then
      line[#line] = line[#line]:gsub(" $", "")
   end
   local q = hints[idx].quote
   table.insert(line, q .. sym .. q .. " ")
elseif checkers[idx] then
   if #line > 0 then
      line[#line] = line[#line]:gsub(" $", "")
   end
   if SHOW_ANNOTATIONS then
      local openChar = isMate and "!" or (highlight[idx] and "(" or " ")
      table.insert(line, openChar .. sym .. "! ")
   else
      table.insert(line, " " .. sym .. "  ")
   end
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
   if PLAYER_IS_BLACK then
      print("     h  g  f  e  d  c  b  a")
   else
      print("     a  b  c  d  e  f  g  h")
   end
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
      local msg = tostring(err)
      local firstLine = msg:match("^[^\n]*") or msg
      echoW("Warning: could not replay move history (" .. firstLine .. "). Repetition tracking resets from this position.")
      seedFallback()
   end

   return gameHistory, positionCounts
end


function displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   if lastMove then
      local moveLabel = blackMoves and (blackMoves .. ". ") or ""
      print("Sunfish " .. moveLabel .. "move: \n" .. render(lastMove[1]) .. render(lastMove[2]))
      print("Captured: " .. renderCaptured(capturedByEngine, opponentSymbols))
   end
   local checkers = findCheckers(pos)
   local guards = findKingGuards(pos, checkers)
   local isMate = next(checkers) and not hasLegalMove(pos)
   if next(checkers) and not isMate then
      echoS("Check!")
   end
   printboard(arrayToBoard(pos.board), lastMove, checkers, guards, isMate)
   print("Captured: " .. renderCaptured(capturedByUser, ownSymbols))
end

-- ui.lua ======= end