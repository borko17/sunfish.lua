-- config.lua =======
-- ------------------
SHOW_ANNOTATIONS = true
SHOW_EVAL_BAR = true -- vertical eval bar to the right of the board, from Sunfish's last search
DISPLAY_MODE_STEP = 0 -- 0-7; 
-- DISPLAY_MODE_STEPS (0-7):
-- [0] = Letters
-- [1] = Letters 2
-- [2] = Unicode
-- [3] = Unicode (inverted)
-- [4] = Unicode 2
-- [5] = Unicode 2 (inverted)
-- [6] = Unicode 3
-- [7] = Unicode 3 (inverted)

NODES_SEARCHED = 4000 -- node budget/search; soft limit, checked only between depths
TABLE_SIZE = NODES_SEARCHED * 25 -- scaled off NODES_SEARCHED so it doesn't thrash; upstream's 1e6 too heavy for Luaj-jse on phone

CHALLENGE_ENGINE_NODES = 1000 -- separate, weaker budget for Sunfish's replies in Challenge mode
CHALLENGE_MIN_PIECES = 10
CHALLENGE_MAX_PIECES = 20
CHALLENGE_GEN_ATTEMPTS = 400
CHALLENGE_HINTS_ENABLED = false -- shows suggested move; toggle with 'th'

MATE_VALUE = 30000 -- exceeds 8*queen+2*(rook+knight+bishop); king value is double this
MATE_UPPER = 60000 + (10 * 2529) -- search() scores mate near this, not MATE_VALUE - callers must match
-- ------------------
-- config.lua ======= end