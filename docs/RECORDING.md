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

1. Start a Play test. Walk to the three training dummies.
2. Click four times in a row on one dummy. Show the four damage numbers. The gold number is the finisher with knockback.
3. Swing at a dummy behind you. No damage appears: the server rejected the hit.
4. Optional: in a second take, run an "exploit" from the client command bar to show it is blocked:

```lua
local r = game.ReplicatedStorage.Remotes.CombatRequest
for i = 1, 200 do r:FireServer({ action = "Swing", aim = Vector3.new(0, 0, -1) }) end
```

Only a few swings land. The rate limiter and cooldown drop the rest.

## GIF 3 — Idle economy (`economy.gif`)

1. Start a Play test. Buy Lemonade Stands until the rate climbs.
2. Switch the buy mode to `MAX` and buy again. Show the price change.
3. To show offline earnings, switch Studio to the **Server** view and run this in the command bar.
   It replays the join logic as if you had been away for 3 hours (Studio only):

```lua
game.Players:GetPlayers()[1]:SetAttribute("DebugOfflineSeconds", 3 * 3600)
```

   Switch back to the **Client** view. The "Welcome back! You earned …" toast appears at the top.
4. Run it again with `10 * 3600`. The toast now says "(8h cap)".

## After recording

1. Commit the GIFs: `git add docs/media && git commit -m "Add demo GIFs"`
2. Push. The README and the portfolio site pick them up from the same paths.
