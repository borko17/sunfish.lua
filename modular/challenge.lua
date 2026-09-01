-- challenge.lua ======= 1550

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

function findHintMove(pos, history, avoidMove, showDepth)
   local legal = legalMovesOf(pos)
   if #legal == 0 then return nil end

   local runSearch = function()
      local mv = search(pos, HINT_NODES_BEST or NODES_SEARCHED, history)
      return mv
   end
   local best = showDepth and runSearch() or withQuietExec(runSearch)
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
CHALLENGE_WHITE_EXTRA_PIECES = 1

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

-- White gets ~52-62% of the extra pieces (winnable, but not overloaded); CHALLENGE_WHITE_EXTRA_PIECES adds more, shrinking Black's where possible.
      local numWhiteExtra = math.max(1, math.floor(totalExtra * (0.52 + math.random() * 0.10)))
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
   local currentStartBoard = board -- starting position used for saves/replay; updated on 'l' load to the loaded code's own start
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
-- Single-level undo snapshot: full state captured right BEFORE the player's most recent move (pre-move, pre-Sunfish-reply). 'z' restores this and clears it (no re-undo / no redo).
   local undoSnapshot = nil

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
         echoW("💡 Calculating hint...")
         local avoidMove = findMoveTwoPliesAgo()
         local mv = findHintMove(pos, gameHistory, avoidMove, true)
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
         if crdn == 'z' then
            print("----")
            if not undoSnapshot then
               echoE("Nothing to undo yet.")
               showBoard(checkers, guards, false, false)
            else
               pos = undoSnapshot.pos
               lastMove = undoSnapshot.lastMove
               capturedByUser = undoSnapshot.capturedByUser
               capturedByEngine = undoSnapshot.capturedByEngine
               whiteMoves = undoSnapshot.whiteMoves
               blackMoves = undoSnapshot.blackMoves
               halfmoveClock = undoSnapshot.halfmoveClock
               gameHistory = undoSnapshot.gameHistory
               positionCounts = undoSnapshot.positionCounts
               moveHistory = undoSnapshot.moveHistory
               moveSnapshots[whiteMoves + 1] = nil -- drop the snapshot that pointed at the now-undone move
               cachedHints = nil
               undoSnapshot = nil -- one level only: no re-undo
               echoW("Move undone.")
               checkers = findCheckers(pos)
               guards = findKingGuards(pos, checkers)
               showBoard(checkers, guards, false, true)
            end
            print("Captured: " .. renderCaptured(capturedByUser, blackSymbols))
            goto continue
         end
         if crdn == 'h' then
            print("----")
            showHelpChallenge()
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
            local modeName = cycleDisplayMode()
            print("----")
            echoW("Display mode: " .. modeName)
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
            local code = saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, "w", moveHistory, currentStartBoard,
                                   {mode = "cg", hints = (hintsOn and "1" or "0")})
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
                                      snap.whiteMoves, snap.blackMoves, snap.halfmoveClock, snap.nextToMove or "b", snap.moveHistory, currentStartBoard,
                                      {mode = "cg", hints = (hintsOn and "1" or "0")})
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
                  currentStartBoard = result[10] or board
                  moveSnapshots = {}
                  undoSnapshot = nil -- loading a code invalidates any pending undo
                  gameHistory, positionCounts = rebuildHistoryFromMoves(histStr, pos, currentStartBoard)
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

                  local reloadCode = saveGame(pos, lastMove, capturedByUser, capturedByEngine, whiteMoves, blackMoves, halfmoveClock, nextToMove, moveHistory, currentStartBoard,
                                               {mode = "cg", hints = (hintsOn and "1" or "0")})
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
                           print("Sunfish ".. (blackMoves + 1) ..". move:")
print(engineMoveNotation .. " (" .. formatSeconds(elapsed) .. "s) - score: " .. score)
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
-- Capture full pre-move state for 'z' (undo), right before this move is applied. One level only: overwrites any previous undoSnapshot.
            undoSnapshot = {
               pos = pos,
               lastMove = lastMove,
               capturedByUser = {table.unpack(capturedByUser)},
               capturedByEngine = {table.unpack(capturedByEngine)},
               whiteMoves = whiteMoves,
               blackMoves = blackMoves,
               halfmoveClock = halfmoveClock,
               gameHistory = (function() local t = {}; for k,v in pairs(gameHistory) do t[k]=v end; return t end)(),
               positionCounts = (function() local t = {}; for k,v in pairs(positionCounts) do t[k]=v end; return t end)(),
               moveHistory = {table.unpack(moveHistory)},
            }
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
      print("Sunfish ".. (blackMoves + 1) ..". move:")
print(engineMoveNotation .. " (" .. formatSeconds(elapsed) .. "s) - score: " .. score)
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