# Recording the demo GIFs

Each system needs one short GIF (6–12 seconds) for the README and the portfolio site.
Keep every GIF under 5 MB so GitHub renders it inline.

## Setup (once)

1. Install the toolchain: `rokit install`
2. Install packages: `wally install`
3. Build the place: `rojo build -o demo.rbxl`
4. Open `demo.rbxl` in Roblox Studio.
5. In Studio, set the window to 1280×720. Hide the Explorer and Properties panels.
6. Record with a screen recorder. Good free options: ScreenToGif (Windows), Kap (macOS), Peek (Linux).
7. Save the GIFs as `docs/media/data.gif`, `docs/media/combat.gif` and `docs/media/economy.gif`.

## GIF 1 — Data + migrations (`data.gif`)

1. Open `ServerScriptService > Server > Services > DataService`.
2. Set `USE_MOCK_IN_STUDIO = true` (default).
3. Start a Play test (F5) with the Output window visible.
4. Show these lines in Output:
   - `[DataService] Studio: using ProfileStore.Mock (nothing is saved)`
   - `[Server] all services started`
5. Stop. Open the command bar and paste the migration demo below. Show the before and after tables.

```lua
local M = require(game.ReplicatedStorage.Shared.Data.Migrations)
local r = M.run({ Coins = 250, Items = { "Sword", "Sword", "Shield" }, Kills = 4 })
print(r.fromVersion, "->", r.toVersion, r.data)
```

## GIF 2 — Combat (`combat.gif`)

1. Start a Play test. Walk up close to the middle dummy.
2. Start recording.
3. Click **fast, about 3 clicks per second**, 4 times. The combo resets if you wait longer than 0.9 s.
   You see a white slash and a white number on hits 1–3, then a gold slash, a big gold number and knockback on hit 4.
4. Turn your back to the dummies and click once. The slash plays, but no damage appears: the server rejected the hit.
5. Stop recording. Keep it under 10 seconds.

## GIF 3 — Idle economy (`economy.gif`)

1. Start a Play test.
2. Start recording.
3. Buy 3–4 Lemonade Stands. Watch the rate go up.
4. Click **MAX**, then buy again.
5. Press **O** (Studio only). A "Welcome back! You earned …" message shows for 7 seconds and the cash jumps.
   Press **P** to replay 10 hours instead; the message ends with "(8h cap)".
6. Stop recording. Keep it under 15 seconds.

## After recording

1. Commit the GIFs: `git add docs/media && git commit -m "Add demo GIFs"`
2. Push. The README and the portfolio site pick them up from the same paths.
