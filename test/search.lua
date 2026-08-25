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

