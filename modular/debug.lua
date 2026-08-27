-- Debug ("abcd"): plays N Chess School games with no input - White follows hint, Black is Sunfish - to sanity-check hint quality

local AUTO_DEBUG_GAMES = 10
local AUTO_DEBUG_MAX_MOVES = 200 -- safety cap so a drifting game can't hang forever

-- Plays one full Chess School game automatically (White = hint move every turn, Black = Sunfish). Returns "won"/"lost", White moves played, and a short reason string.
local function playChallengeGameAuto(board)
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
