-- debug2.lua =======

-------------------------------------------------------------------------------
-- Debug: search() profiling breakdown
-- search.lua already accumulates PROFILE_genMoves_time/calls,
-- PROFILE_move_time/calls, and PROFILE_tp_time/calls into globals during
-- every search() call (reset to 0 at the start of each search).
--
-- Controlled entirely by the PROFILE_PRINT_ENABLED constant below (set in
-- loader.lua's CONFIG section, or here as a fallback default) - no in-game
-- command. When true, main.lua prints this automatically right after every
-- search() call: your normal moves' Sunfish replies, and 'e' (Analyze).
-------------------------------------------------------------------------------

if PROFILE_PRINT_ENABLED == nil then
   PROFILE_PRINT_ENABLED = true -- fallback if not set in loader.lua CONFIG
end

-------------------------------------------------------------------------------
-- Zaokruživanje na 2 decimale
-------------------------------------------------------------------------------

local function round2(n)
   return math.floor(n * 100 + 0.5) / 100
end

-------------------------------------------------------------------------------
-- Ispis profila
-------------------------------------------------------------------------------

function printProfile(elapsedArg, depthArg, nodesArg)
   if not elapsedArg then
      return
   end

   local genMovesTime = PROFILE_genMoves_time or 0
   local genMovesCalls = PROFILE_genMoves_calls or 0
   local moveTime = PROFILE_move_time or 0
   local moveCalls = PROFILE_move_calls or 0
   local tpTime = PROFILE_tp_time or 0
   local tpCalls = PROFILE_tp_calls or 0

   ---------------------------------------------------------------------------
   -- Vrijeme koje nije obuhvaćeno genMoves, move i transposition tabelom
   ---------------------------------------------------------------------------

   local other = elapsedArg - genMovesTime - moveTime - tpTime

   if other < 0 then
      other = 0
   end

   ---------------------------------------------------------------------------
   -- Zaokruži sva vremena na 2 decimale
   ---------------------------------------------------------------------------

   genMovesTime = round2(genMovesTime)
   moveTime = round2(moveTime)
   tpTime = round2(tpTime)
   other = round2(other)
   elapsedArg = round2(elapsedArg)

   ---------------------------------------------------------------------------
   -- Ispis
   ---------------------------------------------------------------------------

   print(string.format(
      "[profile] genMoves: %.2fs/%d | move: %.2fs/%d | tp: %.2fs/%d | other: %.2fs | total: %.2fs | depth: %s | nodes: %s",
      genMovesTime, genMovesCalls,
      moveTime, moveCalls,
      tpTime, tpCalls,
      other,
      elapsedArg,
      tostring(depthArg or "?"),
      tostring(nodesArg or "?")
   ))
end

-- debug2.lua ======= end