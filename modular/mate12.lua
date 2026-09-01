-- mate1.lua ======= 1300

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

if crdn == 'i' then
   INVERT_PIECE_COLORS = not INVERT_PIECE_COLORS
   updateDisplayMode()
   print("----")
   echoW("Piece colors: " .. (INVERT_PIECE_COLORS and "Inverted" or "Normal"))
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
   showHelpPuzzle()
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
         echoW("💡 Solution: " .. render(mv[0 + __1]) .. render(mv[1 + __1]) .. " (mate)")
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
         echoW("💡 Hint: the mating move is played by a " .. pieceName)
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
         echoW("💡 Hint: move the piece on " .. render(mv[0 + __1]))
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
         echoW("💡 Hint: deliver mate on " .. render(mv[1 + __1]))
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