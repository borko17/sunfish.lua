-- search.lua =======

-- bound() is defined ONCE at load time (not as a closure re-created inside
-- search() on every call) so Luaj doesn't pay the cost of re-instantiating
-- a ~230-line nested function on every search() call, including cheap
-- SCORE_PEEK_NODES probes. MATE_LOWER/MATE_UPPER/EVAL_ROUGHNESS, which used
-- to be search()'s upvalues, are passed in via `ctx` instead; `nodes` stays
-- a plain global exactly as before.
local function ceilingFor(p, depth, val, ctx)
   if depth > 4 or val >= ctx.MATE_LOWER then
      return ctx.MATE_UPPER
   end
   return p.score + val + math.max(depth - 1, 0) * QS_A
end

local function bound(p, gamma, depth, root, ctx)
   nodes = nodes + 1

   if depth < 0 then
      depth = 0
   end

   if p.score <= -ctx.MATE_LOWER then
      return -ctx.MATE_UPPER
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
   if not root and depth > 0 and ctx.history[tpKey(p)] then
      return 0
   end

   local best = -ctx.MATE_UPPER
   local bestMove = nil
   local live = false

   -- "calm" position: no side is deep in a mating attack and at least one
   -- major/minor piece remains on the board (avoids zugzwang in K+P endings)
   local calm = math.abs(p.score) < 750 and hasMajorOrMinorPiece(p.board)
   local guard = (not root) and calm

   -- Deep null-move "fuel probe" (depth >= 6): passing must beat
   -- pos.score + NULL_MARGIN by a two-ply-reduced search to count.
   local nmr = false
   if calm and depth >= 6 then
      local t = p.score + NULL_MARGIN
      local probe = -bound(p:rotate(true), 1 - t, depth - 7, false, ctx)
      nmr = probe >= t
   end

   if killer == nil and depth > 2 then
      bound(p, gamma, depth - 3, true, ctx)

      local _, _, iidMove = tp_get(
         p,
         depth,
         true
      )

      killer = iidMove
   end

   local valLower = QS - depth * QS_A

   -- Collect candidate moves in evaluation order (short null included).
   local ordered = {}

   -- Short null-move: only offered as a candidate inside the move loop
   -- (not a separate early-return block), guard-gated, depth in (2,6)
   if guard and depth > 2 and depth < 6 then
      table.insert(ordered, { isNull = true })
   end

   if depth == 0 then
      table.insert(ordered, { isNull = true, qsStandPat = true })
   end

   if killer and (p:value(killer) >= valLower or depth > 0) and ceilingFor(p, depth, p:value(killer), ctx) >= gamma then
      table.insert(ordered, { value = p:value(killer), move = killer })
   end

   local genned = {}
   for _, move in ipairs(p:genMoves()) do
      local val = p:value(move)
      if val >= valLower or depth > 0 then
         table.insert(genned, { value = val, move = move })
      end
   end
   table.sort(genned, function(a, b) return a.value > b.value end)
   for _, item in ipairs(genned) do
      table.insert(ordered, item)
   end

   for _, item in ipairs(ordered) do
      local score

      if item.isNull then
         if item.qsStandPat then
            score = p.score
         else
            -- Cap the pass at static eval + one EVAL_ROUGHNESS bucket so
            -- it stays monotone and below the positive mate band.
            local cap = p.score + ctx.EVAL_ROUGHNESS
            if cap >= gamma then
               score = math.min(cap, -bound(p:rotate(true), 1 - gamma, depth - 4, false, ctx))
               if score >= gamma then
                  local proof = p:kingCapture()
                  if proof then
                     item.move = proof
                     score = ctx.MATE_UPPER
                     live = true
                  end
               end
            else
               score = cap
            end
         end
      elseif item.value >= ctx.MATE_LOWER then
         -- Intrinsic mate-band move: exact MATE_UPPER, never searched.
         score = ctx.MATE_UPPER
         live = true
      else
         local cap = ceilingFor(p, depth, item.value, ctx)
         if cap < gamma then
            -- Futility cutoff: sorted stream means nothing after this can improve it.
            if cap > best then best = cap end
            break
         end

         local reduced = 0
         if guard and depth >= 7 and item.value < LMR then
            reduced = reduced + 1
         end
         if nmr then
            reduced = reduced + 1
         end
         local moveDepth = depth - 1 - reduced

         score = math.min(cap, -bound(p:move(item.move), 1 - gamma, moveDepth, false, ctx))

         if score > -ctx.MATE_UPPER then
            live = true
         end
      end

      if score > best then
         best = score
         bestMove = item.move
      end

      if best >= gamma then
         if item.move ~= nil and depth > 0 then
            tp_set(p, depth, true, nil, nil, item.move)
         end
         break
      end
   end

   -- Terminal classification: no legal (non-king-capturing) reply seen.
   -- The mate score carries the remaining depth so the winner prefers the
   -- fastest mate and the loser drags it out (upstream issue #11).
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
         local mate = math.max(1 - ctx.MATE_UPPER, -ctx.MATE_LOWER - depth * ctx.EVAL_ROUGHNESS)

         if p:rotate(true):kingCapture() then
            best = mate
         else
            best = 0
         end

         bestMove = nil
      end
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
         storedBound.lower or -ctx.MATE_UPPER

      local oldUpper = storedBound and
         storedBound.upper or ctx.MATE_UPPER

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

   local ctx = {
      MATE_LOWER = 60000 - (13 * 2529),
      MATE_UPPER = 60000 + (10 * 2529),
      EVAL_ROUGHNESS = 15,
      history = history,
   }

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

   -- Iterative deepening MTD-bi.
   local prevDepthTime = startTime
   for depth = 1, 98 do
      local lower = 1 - ctx.MATE_UPPER
      local upper = ctx.MATE_UPPER
      local gamma = 0
      local score = 0

      while lower < upper - ctx.EVAL_ROUGHNESS do
         score = bound(pos, gamma, depth, true, ctx)

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
      local nowTime = os.clock()
      local depthTime = nowTime - prevDepthTime
      prevDepthTime = nowTime
      local centis = math.floor(depthTime * 100 + 0.5)
      local whole = math.floor(centis / 100)
      local frac = centis % 100
      local depthTimeStr = string.format("%d,%02d", whole, frac)

      echoW(string.format(
         "(depth %d, %d/%s nodes) - %ss",
         depth, nodes, nodeDisplay, depthTimeStr
      ))

      if nodes >= maxn or
         math.abs(score) >= ctx.MATE_UPPER then
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
emptySquareSymbols_unicode2 = {
   dark = '\xe2\x96\xa0',
   light = '\xe2\x96\xa1'
}
emptySquareSymbols_unicode3 = {
   dark = ' ',
   light = ' '
}
emptySquareSymbols_letters = {
   dark = ':',
   light = '.'
}
emptySquareSymbols_letters2 = {
   dark = ' ',
   light = ' '
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

-- Default to Letters mode (DISPLAY_MODE_STEP 0); updateDisplayMode() overrides these once called.
whiteSymbols = whiteSymbols_letters
blackSymbols = blackSymbols_letters
emptySquareSymbols = emptySquareSymbols_letters

-- search.lua ======= end