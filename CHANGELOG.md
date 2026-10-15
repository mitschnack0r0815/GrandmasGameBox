# Changelog

The version lives in `SchiffeVersenken.toc` (`## Version`). Bump it there, add a section
here, then run `./release.sh` to build the zip.

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
