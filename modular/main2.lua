-- main.lua ======= 0615

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
-- Single-level undo snapshot: full state captured right BEFORE your most recent move (pre-move, pre-Sunfish-reply). 'z' restores this and clears it (no re-undo / no redo).
   local undoSnapshot = nil

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
   elseif crdn == 'c' then
      USE_FANCY_BOARD = not USE_FANCY_BOARD
      print("----")
      echoW("Board style: " .. (USE_FANCY_BOARD and "Fancy (shaded)" or "Classic (bordered)"))
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == 'z' then
      print("----")
      if not undoSnapshot then
         echoE("Nothing to undo yet.")
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
         undoSnapshot = nil -- one level only: no re-undo
         echoW("Move undone.")
      end
      print("")
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == 'e' then
      print("----")
      echoW("💡 Analyzing position...")
      local analyzeMove, analyzeScore, analyzeDepth, analyzeNodes, analyzeElapsed = search(pos, NODES_SEARCHED, gameHistory)
      if analyzeMove and isLegalMove(pos, analyzeMove) then
         echoW("Suggested move: " .. render(analyzeMove[1]) .. render(analyzeMove[2]) .. " (score: " .. analyzeScore .. ")")
      else
         echoE("No suggestion available (checkmate or stalemate).")
      end
      if PROFILE_PRINT_ENABLED then
         printProfile(analyzeElapsed, analyzeDepth, analyzeNodes)
      end
      print("")
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
         if result[11] == "cg" then
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
         undoSnapshot = nil -- loading a code invalidates any pending undo

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
enginemove, score, reachedDepth, usedNodes, elapsed = search(rotated, NODES_SEARCHED, gameHistory)
assert(score)
            if PROFILE_PRINT_ENABLED then
               printProfile(elapsed, reachedDepth, usedNodes)
            end
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
               print("Sunfish " .. (blackMoves + 1) .. ". move: \n" .. engineMoveNotation .. " (" .. formatSeconds(elapsed) .. "s) - score: " .. score)
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
      showHelpGame()
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == '?' then
       print("----")
      showAbout()
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == 'm1' then
      aipuzMate1()
      echoW("Resuming the game.")
      displayPosition(pos, lastMove, capturedByUser, capturedByEngine, blackMoves)
   elseif crdn == 'deb1' then
       print("----")
      runAutoDebugGames(AUTO_DEBUG_GAMES)
      binding.exec("echo -w " .. "Resuming the game.")
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
print(crdn .. " (" .. formatSeconds(inputElapsed) .. "s)")
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
      if PROFILE_PRINT_ENABLED then
         printProfile(elapsed, reachedDepth, usedNodes)
      end
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
print("Sunfish ".. (blackMoves + 1) ..". move: \n" .. engineMoveNotation .. " (" .. formatSeconds(elapsed) .. "s) - score: " .. score)
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