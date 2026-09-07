-- movetime.lua =======

-------------------------------------------------------------------------------
-- Debug: full move-timing breakdown.
--
-- Part 1 - printProfile(): search.lua accumulates PROFILE_genMoves_time/calls,
-- PROFILE_move_time/calls, PROFILE_tp_time/calls into globals during every
-- search() call (reset to 0 at the start of each search). This prints that
-- breakdown for a given elapsed/depth/nodes.
--
-- Part 2 - "your move -> Sunfish thinking" profile: wraps the global
-- search() so that right before each REAL search() call (skipping the quiet
-- SCORE_PEEK_NODES probe main.lua/challenge.lua run after your move to
-- refresh the displayed score - it's wrapped in withQuietExec(), which only
-- silences echoW/echoE/echoS via binding.exec, NOT plain print(), so
-- printing there would leak out mid-move before printboard() even runs), it
-- prints a printProfile() breakdown for everything since the LAST search()
-- call - i.e. your whole turn: reading input, pos:move, findCheckers,
-- hasLegalMove, printboard, etc.
--
-- Part 3 - per-step breakdown: wraps Position:move, findCheckers,
-- hasLegalMove, and printboard individually so the "other" bucket in Part 2
-- (time not spent in genMoves/move/tp) can be broken down further. Prints
-- right before Part 2's profile, covering the same window.
--
-- Standalone add-on: does NOT modify main.lua/search.lua/core.lua/ui.lua.
-- Controlled entirely by PROFILE_PRINT_ENABLED below; no in-game command.
-- Just add this ONE file to the loader's PARTS list, anywhere after
-- 04_ui.lua (needs Position/findCheckers/hasLegalMove/printboard to already
-- be defined) and before 08_main.lua.
-------------------------------------------------------------------------------

if PROFILE_PRINT_ENABLED == nil then
   PROFILE_PRINT_ENABLED = true -- fallback if not set elsewhere
end

local function round2(n)
   return math.floor(n * 100 + 0.5) / 100
end

-------------------------------------------------------------------------------
-- Part 1: printProfile() - used both by main.lua/challenge.lua directly
-- after their own search() calls, and by Part 2 below.
-------------------------------------------------------------------------------

function printProfile(elapsedArg, depthArg, nodesArg, inputTimeArg)
   if not elapsedArg then
      return
   end

   local genMovesTime = PROFILE_genMoves_time or 0
   local genMovesCalls = PROFILE_genMoves_calls or 0
   local moveTime = PROFILE_move_time or 0
   local moveCalls = PROFILE_move_calls or 0
   local tpTime = PROFILE_tp_time or 0
   local tpCalls = PROFILE_tp_calls or 0
   local inputTime = inputTimeArg or 0

   local other = elapsedArg - genMovesTime - moveTime - tpTime - inputTime
   if other < 0 then
      other = 0
   end

   genMovesTime = round2(genMovesTime)
   moveTime = round2(moveTime)
   tpTime = round2(tpTime)
   other = round2(other)
   elapsedArg = round2(elapsedArg)
   inputTime = round2(inputTime)

   print(string.format(
      "[profile] \ngenMoves: %.2fs/%d \nmove: %.2fs/%d \ntp: %.2fs/%d \ninput (waiting on you): %.2fs \nother (pure processing): %.2fs \ntotal: %.2fs \ndepth: %s \nnodes: %s",
      genMovesTime, genMovesCalls,
      moveTime, moveCalls,
      tpTime, tpCalls,
      inputTime,
      other,
      elapsedArg,
      tostring(depthArg or "?"),
      tostring(nodesArg or "?")
   ))
end

-------------------------------------------------------------------------------
-- Part 3: per-step breakdown (defined before Part 2 so Part 2's search()
-- wrapper can call printStepProfile() right before it prints its own).
-------------------------------------------------------------------------------

STEP_move_time = 0
STEP_move_calls = 0
STEP_findCheckers_time = 0
STEP_findCheckers_calls = 0
STEP_hasLegalMove_time = 0
STEP_hasLegalMove_calls = 0
STEP_printboard_time = 0
STEP_printboard_calls = 0

local realPositionMove = Position.move
function Position:move(move)
   local t0 = os.clock()
   local result = realPositionMove(self, move)
   STEP_move_time = STEP_move_time + (os.clock() - t0)
   STEP_move_calls = STEP_move_calls + 1
   return result
end

local realFindCheckers = findCheckers
function findCheckers(p)
   local t0 = os.clock()
   local result = realFindCheckers(p)
   STEP_findCheckers_time = STEP_findCheckers_time + (os.clock() - t0)
   STEP_findCheckers_calls = STEP_findCheckers_calls + 1
   return result
end

local realHasLegalMove = hasLegalMove
function hasLegalMove(pos)
   local t0 = os.clock()
   local result = realHasLegalMove(pos)
   STEP_hasLegalMove_time = STEP_hasLegalMove_time + (os.clock() - t0)
   STEP_hasLegalMove_calls = STEP_hasLegalMove_calls + 1
   return result
end

local realPrintboard = printboard
function printboard(...)
   local t0 = os.clock()
   local result = {realPrintboard(...)}
   STEP_printboard_time = STEP_printboard_time + (os.clock() - t0)
   STEP_printboard_calls = STEP_printboard_calls + 1
   return table.unpack(result)
end

-- Tracks time spent inside input() (waiting on you to type) so Part 2 can
-- subtract it from "other" and isolate pure processing time. input() is
-- provided by the host (Yantra/Java binding), not defined in this codebase,
-- so wrapping it is the only way to measure it without touching main.lua.
STEP_input_time = 0
STEP_input_calls = 0

local realInput = input
if realInput then
   function input(...)
      local t0 = os.clock()
      local result = {realInput(...)}
      STEP_input_time = STEP_input_time + (os.clock() - t0)
      STEP_input_calls = STEP_input_calls + 1
      return table.unpack(result)
   end
end

local function printStepProfile()
   print(string.format(
      "[steps] \nPosition:move: %.2fs/%d \nfindCheckers: %.2fs/%d \nhasLegalMove: %.2fs/%d \nprintboard: %.2fs/%d \npeek search (score refresh): %.2fs/%d \ninput (waiting on you): %.2fs/%d",
      round2(STEP_move_time), STEP_move_calls,
      round2(STEP_findCheckers_time), STEP_findCheckers_calls,
      round2(STEP_hasLegalMove_time), STEP_hasLegalMove_calls,
      round2(STEP_printboard_time), STEP_printboard_calls,
      round2(STEP_peek_time), STEP_peek_calls,
      round2(STEP_input_time), STEP_input_calls
   ))
   STEP_move_time = 0
   STEP_move_calls = 0
   STEP_findCheckers_time = 0
   STEP_findCheckers_calls = 0
   STEP_hasLegalMove_time = 0
   STEP_hasLegalMove_calls = 0
   STEP_printboard_time = 0
   STEP_printboard_calls = 0
   STEP_peek_time = 0
   STEP_peek_calls = 0
   local inputTime = STEP_input_time
   STEP_input_time = 0
   STEP_input_calls = 0
   return inputTime
end

-------------------------------------------------------------------------------
-- Part 2: wrap the real search() once. On every REAL call (not the quiet
-- score-peek probe), print the per-step breakdown (Part 3) followed by the
-- "your move -> Sunfish thinking" profile (Part 1) for everything
-- accumulated since the previous real search() call.
-------------------------------------------------------------------------------

local realSearch = search
local betweenSearchesStart = os.clock() -- first call also measures from script load

-- Tracks time spent in the SCORE_PEEK_NODES probe itself (the quiet
-- withQuietExec()-wrapped search that refreshes the displayed score right
-- after your move), separate from genMoves/move/tp so we can see whether
-- its cost is proportional to its node budget or mostly fixed overhead.
STEP_peek_time = 0
STEP_peek_calls = 0

function search(pos, maxn, history)
   if maxn == SCORE_PEEK_NODES then
      local t0 = os.clock()
      local result = {realSearch(pos, maxn, history)}
      STEP_peek_time = STEP_peek_time + (os.clock() - t0)
      STEP_peek_calls = STEP_peek_calls + 1
      return table.unpack(result)
   end

   local elapsed = os.clock() - betweenSearchesStart
   if PROFILE_PRINT_ENABLED then
      local inputTime = printStepProfile()
      echoW("[profile] your move -> Sunfish thinking:")
      printProfile(elapsed, "-", "-", inputTime)
   end

   local result = {realSearch(pos, maxn, history)}

   betweenSearchesStart = os.clock()

   return table.unpack(result)
end

-- movetime.lua ======= end
