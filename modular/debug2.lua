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

-- elapsedArg/depthArg/nodesArg are the return values of the specific
-- search() call just made (works the same for a real move or 'e' Analyze).
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

   local other = elapsedArg - genMovesTime - moveTime - tpTime
   if other < 0 then other = 0 end -- os.clock() rounding can nudge this slightly negative

   print(string.format(
      "[profile] genMoves: %.3fs/%d | move: %.3fs/%d | tp: %.3fs/%d | other: %.3fs | total: %.3fs | depth: %s | nodes: %s",
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
