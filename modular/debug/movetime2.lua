-- debug3.lua =======

-------------------------------------------------------------------------------
-- Debug: profiles the time BETWEEN two search() calls - i.e. everything that
-- happens on your turn (reading input, pos:move, findCheckers, hasLegalMove,
-- printboard, etc), using the same PROFILE_genMoves_time/calls,
-- PROFILE_move_time/calls, PROFILE_tp_time/calls accumulators search.lua
-- already fills in.
--
-- This is a standalone add-on: it does NOT modify main.lua or search.lua.
-- It wraps the global search() function so it can snapshot the accumulators
-- right before search() resets them for its own run, and print a profile for
-- the "between-searches" segment before handing off to the real search().
--
-- Requires movetime.lua (defines printProfile()/round2 and
-- PROFILE_PRINT_ENABLED) to be loaded first - reuses printProfile() as-is.
-- Controlled by the same PROFILE_PRINT_ENABLED constant; no in-game command.
-------------------------------------------------------------------------------

if PROFILE_PRINT_ENABLED == nil then
   PROFILE_PRINT_ENABLED = true -- fallback if movetime.lua wasn't loaded first
end

local realSearch = search
local betweenSearchesStart = os.clock() -- first call also measures from script load

echoW("[debug] movetime_between.lua loaded, wrapping search()")

function search(pos, maxn, history)
-- Skip profiling (and don't reset the timer) for the quiet SCORE_PEEK_NODES
-- probe main.lua/challenge.lua run right after your move to refresh the
-- displayed score - it's wrapped in withQuietExec() (which only silences
-- echoW/echoE/echoS via binding.exec, NOT plain print()), so if we printed
-- here it would leak out mid-move, before printboard() even runs.
   echoW("[debug] search() wrapper called, maxn=" .. tostring(maxn) .. " SCORE_PEEK_NODES=" .. tostring(SCORE_PEEK_NODES))
   if maxn == SCORE_PEEK_NODES then
      return realSearch(pos, maxn, history)
   end

-- Snapshot accumulator values as of RIGHT NOW, before realSearch() resets
-- them for its own run. Since search.lua's genMoves()/move()/tp_get()/
-- tp_set() add to these same globals whenever they're called - including
-- calls made outside of search(), on your turn - what's accumulated here
-- since the last search() call is exactly your turn's cost.
   local elapsed = os.clock() - betweenSearchesStart
   if PROFILE_PRINT_ENABLED then
      echoW("[profile] your move -> Sunfish thinking:")
      printProfile(elapsed, "-", "-")
   end

   local result = {realSearch(pos, maxn, history)}

-- Start timing the NEXT between-searches segment from here, right after
-- this search() call returns (so it excludes the search itself and this
-- function's own printProfile() calls, keeping the two profiles disjoint).
   betweenSearchesStart = os.clock()

   return table.unpack(result)
end

-- debug3.lua ======= end
