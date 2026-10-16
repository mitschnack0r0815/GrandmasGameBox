# Changelog

The version lives in `GrandmasGameBox.toc` (`## Version`). Bump it there, add a section
here, then run `./release.sh` to build the zip.

Up to 0.2-alpha this was the addon "SchiffeVersenken".

## 0.3-alpha (2026-10-16)

- New game: **Quiz Duel**, WoW trivia against another player (its own tab, `/quiz` or
  `/qd`, `/quiz <name>` to challenge).
  - 6 rounds of 3 questions, 4 answers each, 20 seconds per question. Whoever picks the
    round's category (from 3) answers first; the challenger picks rounds 1, 3 and 5.
  - Turns don't need both players online: a finished turn is sent and resent until the
    opponent has it, and both sides catch up when either logs in. Several duels at once,
    one per opponent; duels are saved per character.
  - 314 questions in 9 categories: Lore, Zones, Dungeons & Raids, Classes, Races &
    Factions, Professions, Bosses, Items & Mounts (all Classic), and WoW History
    (expansion releases, famous moments, popular addons). Some are hard: spell durations,
    DoT ticks, boss counts, battleground rules.
  - After answering you see the right answer and, if they played the round already, what
    your opponent picked. Their results stay hidden (grey "?") until you've played the round.
  - Closing the window or switching tabs during a question counts as running out of time.
  - Won/lost/draw stats, overall and per opponent. The last 10 finished duels stay listed.
  - Test duel against the Training Dummy (minimap menu or `/quiz test`):
    it plays its turns a couple of seconds after yours and gets about half its answers
    right. Doesn't count for stats.

- Schiffe versenken is now a game in **Grandma's Game Box**, a new addon (folder
  `GrandmasGameBox`) that replaces the SchiffeVersenken addon. Remove the old
  SchiffeVersenken folder when updating.
- The box is one window framed like the character pane, with icon tabs on its right edge
  like the spellbook's: "Grandma's Game Box" (home page with a card per game, its current
  status and your record; click a card to play) and "Schiffe versenken". The round portrait shows the open tab's
  icon (dice, or your faction's banner). More games get their own tab later.
- `/ggb` or `/gamebox` opens the box; `/sv` and `/schiffe` still open Schiffe versenken.
- The minimap button belongs to the box now (dice icon). It still pulses on your turn; the
  menu has the Schiffe versenken entries under its own heading. `/ggb minimap` shows/hides it
  (`/sv minimap` still works).
- Window settings (compact layout, minimap button position) start fresh; stats carry over
  if you copy `WTF/Account/<account>/SavedVariables/SchiffeVersenken.lua` to
  `GrandmasGameBox.lua`. Same game protocol, so you can still play against 0.2-alpha.
- All addon messages go through one shared queue (Box/Comm.lua): a small burst, then at
  most one message per second for all games together, moves in a running Schiffe versenken
  game first. The same message is never queued twice and at most 6 wait per player. If the
  game throttles us anyway the queue pauses. Offline players are detected once for all
  games (the "No player named" message stays hidden); nothing more is queued for them, and
  they're retried once a minute (Schiffe versenken) or every 5 minutes (Quiz Duel) instead
  of every few seconds.
- Big "VICTORY!" / "DEFEAT" banner across the grids when a game ends, with the winner's
  faction banners and cry; it fades after a few seconds. Losing plays a sound too. If the
  window was closed, the banner shows when you open it.
- Your record is bigger, with green wins and red losses, and moved out of the bottom corner:
  top right in the full layout, under the game status when compact. Your record against the
  current opponent shows next to their name (below your record when compact).

## 0.2-alpha (2026-10-15)

- Compact window for small screens (Compact button, `/sv compact` or minimap menu): narrow
  and vertical, about 340x650. Your fleet is a small map at the top with the game status
  beside it, the enemy waters full size below. While placing ships your fleet is the big
  grid and the placing buttons sit where the small map goes.
- Record moved to the bottom left of the window; placing buttons are a bit narrower.
- Test game against a built-in Training Dummy (minimap menu or `/sv test`): each side has
  one 2x2 ship. You place yours, the dummy's is always in the middle (E5-F6). Doesn't count
  for stats.
- Rule change: ships may touch each other. Sinking a ship no longer marks the squares around
  it as water. Protocol 3, so both players need this version.
- Grid squares look like empty action bar slots (the game's own slot textures and
  highlight); ships and hits fill the slot with color.
- Misses fill the slot blue instead of showing a white dot (a water icon may replace this).
- More room around the grids: a dark gap inside the faction border, coordinates and headers
  moved clear of the turn glow, wider window margins.

## 0.1-alpha (2026-10-15)

First test version.

- Battleship ("Schiffe versenken") against other players over addon whispers: `/sv <name>`
  or the Challenge button, accept/decline popup.
- Classic German rules: 10x10 board; fleet of 1x5, 2x4, 3x3, 4x2; ships may not touch;
  a hit lets you fire again.
- Ship placement by clicking, right-click to rotate, random placement.
- Horde vs Alliance look: faction colors, banners and Warcraft II ship names, victory cries.
- Turn highlight: pulsing frame and "YOUR TURN!" splash, sound, taskbar flash.
- Minimap button that pulses on your turn.
- Win/loss stats, overall and per opponent (`/sv stats`).
- Both fleets are revealed after a game; lying about a shot gets flagged as cheating.
- Running games survive /reload, logout (30 minutes) and loading screens; unanswered
  messages are resent and the opponent's offline state is shown.
