-- debug2.lua =======

-------------------------------------------------------------------------------
-- Debug: search() profiling breakdown ("pp")
-- search.lua already accumulates PROFILE_genMoves_time/calls,
-- PROFILE_move_time/calls, and PROFILE_tp_time/calls into globals during
-- every search() call (reset to 0 at the start of each search). This file
-- just prints them, on demand, instead of after every single move.
--
-- 'elapsed', 'enginemove', 'score', 'reachedDepth', 'usedNodes' are the
-- globals main.lua already assigns (no 'local') right after each Sunfish
-- move's search() call, so this reads the profile of the LAST search that
-- populated them - normally Sunfish's most recent move. If 'e' (Analyze)
-- was used most recently, those globals still reflect the last real move's
-- search, not the analysis (Analyze uses a local search() call) - printProfile()
-- notes this so the numbers aren't misread as the analysis's own profile.
-------------------------------------------------------------------------------

function printProfile()
   if not elapsed then
      echoE("No search has run yet this game.")
      return
   end

   local genMovesTime = PROFILE_genMoves_time or 0
   local genMovesCalls = PROFILE_genMoves_calls or 0
   local moveTime = PROFILE_move_time or 0
   local moveCalls = PROFILE_move_calls or 0
   local tpTime = PROFILE_tp_time or 0
   local tpCalls = PROFILE_tp_calls or 0

   local other = elapsed - genMovesTime - moveTime - tpTime
   if other < 0 then other = 0 end -- os.clock() rounding can nudge this slightly negative

   echoW("=== SEARCH PROFILE (last move's search) ===")
   print(string.format(
      "[profile] genMoves: %.3fs/%d | move: %.3fs/%d | tp: %.3fs/%d | other: %.3fs | total: %.3fs",
      genMovesTime, genMovesCalls,
      moveTime, moveCalls,
      tpTime, tpCalls,
      other,
      elapsed
   ))
   if reachedDepth then
      print("depth reached: " .. reachedDepth .. "  nodes: " .. (usedNodes or nodes or 0))
   end
   print("Note: reflects the last actual move's search, not 'e' (Analyze), which searches locally.")
end

-- debug2.lua ======= end
