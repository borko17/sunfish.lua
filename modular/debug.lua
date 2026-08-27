-------------------------------------------------------------------------------
-- Debug: automatic Challenge Game games ("abcd")
-- Plays N Challenge Game games with NO user input: White always plays the
-- on-board hint move (findHintMove), Black is Sunfish at
-- CHALLENGE_ENGINE_NODES. Prints a one-line result per game and a final
-- win/loss tally. Meant to sanity-check "how well does following the hint
-- actually do" without playing move-by-move by hand.
-------------------------------------------------------------------------------

AUTO_DEBUG_GAMES = 10
AUTO_DEBUG_MAX_MOVES = 200 -- safety cap so a drifting game can't hang forever

-- Plays one full Challenge Game automatically (White = hint move every
-- turn, Black = Sunfish). Returns "won" or "lost", the number of White
-- moves played, and a short reason string.
function playChallengeGameAuto(board)
   local pos = Position.new(board, 0, {false,false}, {false,false}, 0, 0)
   local capturedByUser, capturedByEngine = {}, {}
   local whiteMoves, blackMoves = 0, 0
   local halfmoveClock = 0
   local gameHistory = { [tpKey(pos)] = true }
   local positionCounts = { [tpKey(pos)] = 1 }

   while true do
      if whiteMoves >= AUTO_DEBUG_MAX_MOVES then
         return "lost", whiteMoves, "move limit"
      end

      -- White (player stand-in) always plays the current hint move.
      local hintMove = findHintMove(pos, gameHistory, nil)
      if not hintMove then
         local legal = legalMovesOf(pos)
         if #legal == 0 then
            if next(findCheckers(pos)) then
               return "lost", whiteMoves, "no legal move (mated)"
            else
               return "lost", whiteMoves, "stalemate"
            end
         end
         table.sort(legal, function(a, b) return pos:value(a) > pos:value(b) end)
         hintMove = legal[1]
      end

      whiteMoves = whiteMoves + 1
      local userCap = capturedAt(pos, hintMove)
      local userPawnMove = isPawnMove(pos, hintMove)
      if userCap or userPawnMove then halfmoveClock = 0 else halfmoveClock = halfmoveClock + 1 end
      if userCap then table.insert(capturedByUser, userCap) end

      pos = pos:move(hintMove)
      pos.score = 0
      gameHistory[tpKey(pos)] = true
      positionCounts[tpKey(pos)] = (positionCounts[tpKey(pos)] or 0) + 1

      local checkersAfterUser = findCheckers(pos)
      local engineHasMove = hasLegalMove(pos)
      local isMateNow = next(checkersAfterUser) ~= nil and not engineHasMove

      if isMateNow then
         return "won", whiteMoves, "checkmate"
      end
      if not engineHasMove then
         return "lost", whiteMoves, "stalemate"
      end
      if hasInsufficientMaterial(pos.board) then
         return "lost", whiteMoves, "insufficient material"
      end
      if halfmoveClock >= 100 then
         return "lost", whiteMoves, "50-move rule"
      end
      if positionCounts[tpKey(pos)] >= 3 then
         return "lost", whiteMoves, "repetition"
      end

      -- Black (Sunfish) replies, weakened via CHALLENGE_ENGINE_NODES.
      local enginemove, score = search(pos, CHALLENGE_ENGINE_NODES, gameHistory)

      if enginemove and not isLegalMove(pos, enginemove) then
         enginemove = nil
      end
      if not enginemove then
         local legal = legalMovesOf(pos)
         if #legal == 0 then
            if next(findCheckers(pos)) then
               return "won", whiteMoves, "checkmate"
            else
               return "lost", whiteMoves, "stalemate"
            end
         end
         table.sort(legal, function(a, b) return pos:value(a) > pos:value(b) end)
         enginemove = legal[1]
      end

      local engineCap = capturedAt(pos, enginemove)
      local enginePawnMove = isPawnMove(pos, enginemove)
      if engineCap or enginePawnMove then halfmoveClock = 0 else halfmoveClock = halfmoveClock + 1 end
      if engineCap then table.insert(capturedByEngine, engineCap) end

      pos = pos:move(enginemove)
      blackMoves = blackMoves + 1
      pos.score = 0
      gameHistory[tpKey(pos)] = true
      positionCounts[tpKey(pos)] = (positionCounts[tpKey(pos)] or 0) + 1

      if hasInsufficientMaterial(pos.board) then
         return "lost", whiteMoves, "insufficient material"
      end
      if halfmoveClock >= 100 then
         return "lost", whiteMoves, "50-move rule"
      end
      if positionCounts[tpKey(pos)] >= 3 then
         return "lost", whiteMoves, "repetition"
      end

      local matingCheckers = findCheckers(pos)
      if next(matingCheckers) and not hasLegalMove(pos) then
         return "lost", whiteMoves, "checkmate"
      end
   end
end

-- Plays n automatic Challenge Game games (default AUTO_DEBUG_GAMES) and
-- prints a short per-game result plus a final W/L tally. All search()
-- progress spam ("(depth X, Nk nodes)") is suppressed for the duration.
function runAutoDebugGames(n)
   n = n or AUTO_DEBUG_GAMES

   print("")
   binding.exec("echo -w " .. "=== ABCD DEBUG: " .. n .. " auto-played games (hint-only) ===")
   print("White plays the hint move every turn.")
   print("Black is Sunfish at " .. CHALLENGE_ENGINE_NODES .. " nodes.")
   print("")

   local wins, losses = 0, 0

   withQuietExec(function()
      for i = 1, n do
         local board = genChallengePosition()
         if not board then
            print("Game " .. i .. ": FAILED to generate a position")
         else
            local result, moves, reason = playChallengeGameAuto(board)
            if result == "won" then
               wins = wins + 1
            else
               losses = losses + 1
            end
            -- Printed inside withQuietExec, but print() itself isn't
            -- silenced (only binding.exec is) so per-game lines still show.
            print("Game " .. i .. ": " .. string.upper(result) .. " (" .. moves .. " White moves, " .. reason .. ")")
         end
      end
   end)

   print("")
   binding.exec("echo -w " .. "=== RESULT: " .. wins .. "W / " .. losses .. "L out of " .. n .. " games ===")
   print("")
end