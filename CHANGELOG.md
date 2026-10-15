# Changelog

The version lives in `SchiffeVersenken.toc` (`## Version`). Bump it there, add a section
here, then run `./release.sh` to build the zip.

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
