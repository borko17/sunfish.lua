![Sunfish logo](https://raw.github.com/borko17/sunfish-lua/master/docs/logo/sunfish03.jpeg)

# sunfish.lua

A Lua port of [Sunfish](https://github.com/thomasahle/sunfish), a compact chess engine originally written in Python by [Thomas Ahle](https://github.com/thomasahle), adapted to run on Android inside [Yantra Launcher Pro](https://github.com/coderGtm/yantra-app-launcher) (Luaj-jse 3.0.1).

Originally based on the Lua port by [Soumith Chintala](https://github.com/soumith), this version has been substantially extended and adapted for the Android/Luaj-jse environment. Sunfish itself draws heavily on [Micro-Max by Geert Muller](http://home.hccnet.nl/h.g.muller/max-src2.html) and [PyChess](http://pychess.org).

## Origin & attribution

- **Original algorithm & Python implementation:** [Thomas Ahle](https://github.com/thomasahle) — [thomasahle/sunfish](https://github.com/thomasahle/sunfish) (also documented at [chessprogramming.org/Sunfish](https://www.chessprogramming.org/Sunfish))
- **Initial Lua transpilation/port:** [Soumith Chintala](https://github.com/soumith) — [soumith/sunfish.lua](https://github.com/soumith/sunfish.lua)
- **Android / Yantra Launcher Pro adaptation and extensions:** [Borko Danilović](https://github.com/borko17) — [borko17/sunfish-lua](https://github.com/borko17/sunfish-lua), with help from Claude AI

This version includes substantial modifications to the original Lua port: the Android/Luaj-jse adaptation, node-budget search configuration, legal chess-game handling, save/load system, display system, puzzle system, Challenge mode, draw detection, annotations, promotion handling, and other application features.

The project also contains historical code lineage from the Lua port by Soumith Chintala. The original [soumith/sunfish.lua](https://github.com/soumith/sunfish.lua) repository contains its own attribution and licensing information.

### AI assistance

Parts of the adaptation, debugging, refactoring, documentation, and development process were performed with assistance from Claude AI. AI assistance does not replace or alter attribution to the original Sunfish authors and upstream projects.

## What this version changes

The engine's search and evaluation logic was adapted to run well in a constrained mobile Lua environment (Luaj-jse 3.0.1):

- **Node-budget search** instead of a wall-clock timer
- Configurable search strength through `nN`
- **Smaller, budget-scaled transposition table**, sized according to the selected node budget
- Reduced memory requirements for mobile execution
- **Zugzwang guard** on null-move pruning
- **Endgame king-centralization table**, used in bare-king endgames to improve convergence
- **Depth-scaled quiescence threshold** for improved tactical search at the same node budget
- Search statistics and node-count reporting
- Mate-score handling and mate detection
- Adjustments for the limitations of Luaj-jse on Android

## Chess features

- Full legal-move validation
- Check / checkmate / stalemate detection
- Threefold-repetition, fifty-move-rule and insufficient-material draw detection
- Move history and last-move tracking
- Captured-piece tracking for both sides
- Pawn promotion with choice of **Queen, Rook, Bishop, or Knight**
- Unicode and plain-letter piece display, with an inverted Unicode variant for dark backgrounds
- Board annotations
- Position snapshots
- Compact text-based save/load, compatible with multiple save/position formats
- Mate-in-1 puzzle mode with random generation and progressive hints
- Challenge mode: play generated mid-game positions against a weaker engine
- In-app Help (`h`), About (`?`) and online update checker (`u`)

## Usage

Load `sunfish.lua` as a script in Yantra Launcher Pro.

### Normal game commands

| Key | Action |
|---|---|
| `e2e4` (etc.) | Enter a move in coordinate notation |
| `h` | Show help |
| `?` | Show About / project information |
| `d` | Cycle display mode (Letters → Unicode → Unicode inverted) |
| `a` | Toggle board annotations |
| `s` | Save the current game |
| `sN` | Save position as of history entry N (e.g. `s15`) |
| `l` | Load a saved game or position |
| `nN` | Change engine node budget in the range 1000–50000 |
| `r` | Resign |
| `n` | Start a new game |
| `u` | Check for a sunfish.lua update |
| `m1` | Enter Mate-in-1 puzzle mode |
| `cg` | Enter Challenge mode |
| `q` | Quit |

### Engine strength

The `nN` command controls the engine's node budget. For example:

```text
n4000
```

uses a 4000-node search budget. Lower N is faster but weaker, higher N is slower but stronger. The available range is `n1000` to `n50000`. Actual playing strength depends on the position and device performance.

### Mate-in-1 puzzle mode commands

| Key | Action |
|---|---|
| `h` | Show puzzle help and hints |
| `d` | Cycle display mode |
| `s` | Save current puzzle |
| `l` | Load puzzle |
| `n` | Generate a new puzzle |
| `q` | Exit puzzle mode and return to normal game |

### Challenge mode commands

Challenge mode (`cg`) generates a random mid-game position (`CHALLENGE_MIN_PIECES`–`CHALLENGE_MAX_PIECES` pieces on the board) and plays it against a weaker engine (`CHALLENGE_ENGINE_NODES` node budget), for practicing specific kinds of positions rather than full games.

| Key | Action |
|---|---|
| `th` | Toggle on-board move hints |
| `z` | Undo your last move (also undoes the reply, one level only) |
| `r` | Resign this attempt |
| `n` | New position |
| `s` / `sN` | Save current game / position after move N |
| `l` | Load saved game |
| `m` | Show move history |
| `h` | Show this help screen |
| `a` | Toggle annotations |
| `d` | Cycle display mode |
| `u` | Check for a sunfish.lua update |
| `?` | Show About screen |
| `q` | Leave Challenge mode |

## Save / Load formats

The `l` command can load saved positions in several formats.

### Normal game mode

Three formats are supported.

#### 1. Full game save

The complete format contains game state, history, counters, captures, starting position and current board:

```text
c:11|bc:11|ep:0|last:e7e6|ucap:-|ecap:-|wm:1|bm:1|hc:0|next:w|hist:a2a4,e7e6|start:rnbqkbnr;pppppppp;8;8;8;8;PPPPPPPP;RNBQKBNR|board:rnbqkbnr;pppp1ppp;4p3;8;P7;8;1PPPPPPP;RNBQKBNR
```

This is the preferred format when the complete game state needs to be restored: current board, starting position, move history, side to move, last move, half-move counter, captured pieces, en-passant state, and move counters.

#### 2. Board-only format

A position can be saved as only the encoded board:

```text
board:rnbqkbnr;pppp1ppp;4p3;8;P7;8;1PPPPPPP;RNBQKBNR
```

This restores the board position without the complete game history and associated state.

#### 3. Plain 8×8 board

A position can also be entered as eight lines containing eight characters each:

```text
....k...
........
........
........
........
........
........
R...K..R
```

This is useful for entering arbitrary positions manually. The plain board format is interpreted as a position rather than a complete game save.

### Puzzle mode save / load

Mate-in-1 puzzle mode accepts the board-only and plain 8×8 formats above (formats 2 and 3). The full game-state save format is intended for normal games; puzzle mode only needs the board position.

### Position snapshots

The `sN` command saves a previous position from the current move history. For example, `s15` saves the position corresponding to history entry 15, and `s0` saves the starting position — useful for extracting a position from an ongoing game without manually reconstructing it.

### What the save formats mean

The compact board representation consists of eight ranks separated by semicolons:

```text
rank8;rank7;rank6;rank5;rank4;rank3;rank2;rank1
```

Numbers represent consecutive empty squares. For example:

```text
rnbqkbnr;pppppppp;8;8;8;8;PPPPPPPP;RNBQKBNR
```

represents the normal starting position. The full save format wraps this board representation together with additional game-state fields.

## Mate-in-1 puzzle mode

Enter `m1` to start the Mate-in-1 puzzle generator. The program generates a position where the side to move has a legal mate in one and verifies the generated position before presenting it.

Hints (progressive):

- Which piece type delivers mate
- Which square the mating piece moves from
- Which square it moves to
- The complete solution

## Display configuration

Display mode and board annotations can be configured at the top of the script:

```lua
USE_UNICODE_PIECES = false
USE_UNICODE_INVERTED_PIECES = false
SHOW_ANNOTATIONS = true
```

`USE_UNICODE_INVERTED_PIECES = true` also implies Unicode mode, even if `USE_UNICODE_PIECES` is left `false`. These settings are only the startup defaults — `d` cycles through the same three modes at runtime: Letters → Unicode → Unicode inverted → Letters.

### Unicode mode

```text
♔ ♕ ♖ ♗ ♘ ♙   (white)
♚ ♛ ♜ ♝ ♞ ♟   (black)
```

### Unicode inverted mode

Swaps which symbol set represents which side, for setups using a dark board background where the solid/outline pieces read better reversed. Empty-square light/dark shading is swapped along with the pieces.

### Letter mode

```text
K Q R B N P   (white)
k q r b n p   (black)
```

Letter mode is useful when the terminal font does not provide reliable chess-symbol support. If Unicode rendering is unreliable, use letter mode with `d`, or set `USE_UNICODE_PIECES = false`.

### Board annotations

When enabled, annotations can display additional board information such as last move, check/guard information, and other move-related markers. Toggle during a game with `a`.

## Promotion

When a pawn reaches the last rank, the player can select `Q`, `R`, `B`, or `N`. Underpromotion is therefore supported instead of automatically promoting every pawn to a queen.

## Screenshots

Letters mode:

![letters](https://github.com/borko17/sunfish.lua/blob/main/docs%2Fscreenshots%2Fscreenshot001.png)

Unicode mode:

![unicode](https://github.com/borko17/sunfish.lua/blob/main/docs%2Fscreenshots%2Fscreenshot002.png)

## Requirements

- Yantra Launcher Pro (Luaj-jse 3.0.1)
- Android device capable of running Yantra Launcher Pro
- A monospaced font is recommended for board alignment
- For Unicode piece mode, a font with good chess-symbol coverage is recommended

Recommended fonts include DejaVu Sans Mono, Julia Mono, Everson Mono, and Unifont.

## License

This project is distributed under GNU GPL v3, following the licensing of the current original Sunfish project. See `LICENSE.md` for the full license text.

For upstream attribution and licensing information, see:

- [Thomas Ahle / Sunfish](https://github.com/thomasahle/sunfish)
- [Soumith Chintala / sunfish.lua](https://github.com/soumith/sunfish.lua)

## Status

This is a lightweight, self-contained chess engine and terminal chess application for Android (Yantra Launcher Pro / Luaj-jse 3.0.1), built for terminal-based chess, chess-engine experimentation, compact text-based position storage, and Mate-in-1 puzzle generation.

It is not intended to compete with modern high-performance chess engines such as Stockfish. The goal is a compact, modifiable and self-contained chess engine that can run directly on Android through Lua, while retaining the small and elegant spirit of the original Sunfish.
