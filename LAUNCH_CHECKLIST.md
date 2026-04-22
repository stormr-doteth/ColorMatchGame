# Pre-Launch Audit & Checklist — Color Match Game

> Generated 2026-04-20. Address **BLOCKER** items before publish; **HIGH** items should ship fixed if possible.

---

## TL;DR — Top priorities before clicking "GO!"

1. **ProcessReceipt idempotency** (double-grant risk on Roblox retry) — `src/server/init.server.luau:70-128`
2. **ProfileService: no retry on DataStore failure** — `src/server/data/ProfileService.luau:65-76`
3. **No rate-limiting on purchase / claim remotes** — ChairShop, LuckyBlockShop, init.server
4. **Verify every gamepass ID & dev product ID matches the Creator Dashboard** (see IDs list below)
5. **Studio setup verification** — 32 chair models, 8 lucky block models, ScreenGui structure
6. **Test disconnect mid-purchase, mid-reveal, mid-match** (pending grants + ProfileService release)

---

## 1. SECURITY / EXPLOIT VECTORS

### BLOCKER

**[1.1] ProcessReceipt always returns `PurchaseGranted`, even on failure**
- File: `src/server/init.server.luau:70-128`
- Roblox retries receipts until acked. If a grant silently fails (nil profile, etc.) and we return PurchaseGranted anyway, the user is charged for nothing. Worse: if we ever return NotProcessedYet but already granted, we double-grant on retry.
- **Fix**: Track processed receipt IDs per player profile. Skip already-seen receipts. Return `NotProcessedYet` on ANY exception path. Only return `PurchaseGranted` after ProfileService write has confirmed.

### HIGH

**[1.2] No ownership / match validation on GuessPreview & SubmitGuess**
- File: `src/server/game/MatchController.luau:179-191, 439-441`
- A client in match A could in theory send GuessPreview updates to match B's papers. There's a `player == self.player1 or self.player2` check on paper updates, but SubmitGuess flow needs tighter verification that the player is in THIS match and it's currently in guessing phase.
- **Fix**: Gate by `self.phase == "guessing"` and player identity in every handler.

**[1.3] No rate-limiting on any remote**
- Files: `ChairShop.luau:202`, `LuckyBlockShop.luau:572`, `init.server.luau:152-158` (UseHint/UseMatch/claim remotes)
- Spammed remotes can race ProfileService writes (double-spend on cash purchase).
- **Fix**: Per-player cooldown table (0.25–0.5s). Drop if within window.

**[1.4] Concurrent-purchase race for cash items**
- Files: `ChairShop.luau:174-196`, `LuckyBlockShop.luau:331-377`
- Two parallel purchase requests both pass the cash check before either deducts. Double purchase for half price.
- **Fix**: `playerPurchaseLocks[player]` flag, acquire before check, release after deduction.

### MED

**[1.5] OpenLuckyBlock accepts client dropPosition without bounds check** — `LuckyBlockShop.luau:423` — validate distance from player character.
**[1.6] ProximityPrompt callbacks don't re-verify distance** — `ChairShop.luau:167`, `LuckyBlockShop.luau:317`.
**[1.7] Invalid blockId strings not logged / rate-flagged** — `LuckyBlockShop.luau:423, 572-577`.

### ✓ Verified safe
- No `loadstring`, `getfenv`, or external HttpService URLs.
- No client-authoritative currency grants found.

---

## 2. PLACEHOLDERS / MISSING ASSETS

### Verify before publish — every ID below must be live

**Gamepass IDs** (`src/server/game/GamePassUtil.luau:7-12`, duplicated in `init.server.luau:136, 143`)
- VIP: `1796710377`
- STARTER_PACK: `1796993729`
- DOUBLE_CASH: `1797672278`
- DOUBLE_WINS: `1796963414`
- DOUBLE_STREAK: `1797239408`
- **Action**: centralize into one constant; verify each on Creator Dashboard.

**Dev product IDs** (Constants.luau, ShopCatalog.luau, LuckyBlockCatalog.luau)
- Hint: `3571537505`
- MatchColor: `3574913860`
- Cash packs: `3575477629, 3575477715, 3575477758, 3575478040`
- Wins packs: `3575511557, 3575511597, 3575511650, 3575511685`
- Lucky blocks single-buy: Common `3575825989`, Uncommon `3575826043`, Rare `3575826076`, Epic `3575826120`, Legendary `3575826157`
- Lucky blocks main-shop Robux: Secret `3576692556`, Mythic `3576692643`, Brainrot `3576692698`
- Glacial: `3578611641, 3578989408, 3578989491`
- Stormbringer: `3578611508, 3578989669, 3578989769`

**SFX asset IDs** (`src/shared/Constants.luau:28-32`) — all populated, verify live:
`112101758985827, 104925453536304, 105053947878159, 131653558869295, 134684168566764`

**UI image asset IDs** (GameController.luau, RewardsUI.luau, etc.):
`121564337913131, 106881959484548, 128383063987894, 118846091715989, 137240287993410, 7059346373, 7072725342`

### Likely outstanding images / art
- [ ] **Loading screen / splash / game logo** — no splash screen module was found in code
- [ ] **Thumbnails for Roblox game page** (icon + 3 thumbnail images) — configured in Studio, not code
- [ ] **Gamepass icons on Creator Dashboard** — confirm each gamepass has a marketable icon
- [ ] **Dev product icons on Creator Dashboard** — confirm all ~25 products have icons
- [ ] **Verify the 3 main-shop lucky block SubmitButton labels** show correct Robux prices in Studio (previous session noted client no longer overwrites these)
- [ ] **Group reward badge** — optional

---

## 3. STUDIO-SIDE SETUP — MUST-HAVES

| Task | Source of truth | Notes |
|---|---|---|
| 32 chair models in Workspace/ReplicatedStorage | `src/shared/ChairCatalog.luau` | ChairShop.Init() warns in Output if any `modelName` is missing. Run once and read Output. |
| 8 lucky block models | `src/shared/LuckyBlockCatalog.luau` | LuckyBlockShop.buildToolTemplates() warns on missing. |
| 12 tables in `Workspace.Tables` (Table1–Table12) | TableManager.luau | ✅ done this session |
| SoloTables folder | TableManager.luau | ⚠️ you mentioned adding this — needs TableManager to iterate it too, currently only reads `Workspace.Tables` |
| StarterGui.ScreenGui required children | init.client, HUDs | HUD_Inventory_Numbers (CashFrame, WinsFrame), GamepassSpam, IngameAds, StarterPack, NotificationHudGui, Shop frames, Inventory frame w/ IndexLabel |
| Group ID `626343155` live | `init.server.luau:161` | Verify group exists & reward remote wired |
| DataStore name "PlayerData" | `ProfileService.luau:24` | Stable — don't change after first publish or you orphan save data |

### 🛑 SoloTables folder won't do anything yet
You created `Workspace.SoloTables` this session, but `TableManager.Init()` only scans `Workspace.Tables`. If you want solo tables separated, update the Init loop to also iterate `SoloTables`.

---

## 4. ERROR HANDLING / RESILIENCE

### BLOCKER
- **[4.1] No retry on ProfileService session load failure** (`ProfileService.luau:65-76`) — a 5-second DataStore hiccup kicks every connecting player. Add 3 retries w/ exponential backoff (1s, 3s, 9s) before kicking.

### HIGH
- **[4.2] Remote lookups use `FindFirstChild` (can be nil)** — ProfileService:35-43, LuckyBlockShop:65-68, ChairShop:25-28. Use `WaitForChild(name, 10)` or defer resolution until after RemoteSetup.Init().
- **[4.3] No pcall around GamePassUtil.InvalidateCache in MarketplaceService callback** — `init.server.luau:131`. One error kills the listener for everyone.

### MED
- **[4.4] Pending-grant queue cleanup relies on PlayerRemoving firing** — `LuckyBlockShop.luau:44-63, 600-604`. Good mitigation, but add logging if any grant inside flushPending throws.

---

## 5. MONETIZATION / ECONOMY

- **[5.1]** Gamepass IDs duplicated in init.server and GamePassUtil → centralize.
- **[5.2]** Verify every product/gamepass ID on Creator Dashboard (see §2).
- **[5.3]** Gamepass grant failures silently drop rewards. Add `if not profile then warn(); fireRemote("PurchaseFailed") end`.
- **[5.4]** All dev products are consumable — intentional, confirmed OK.
- **[5.5]** Guard against zero-price lucky blocks: assert `#buyOptions > 0 or robuxProductId`.

### Exploit-farm surfaces to probe
- [ ] MatchController — can a player force a win by desync/disconnect?
- [ ] PlaytimeRewards — can a player manipulate client time and claim early?
- [ ] DailyRewards — same
- [ ] Group reward — can it be claimed twice by rejoining?
- [ ] Win streak — can repeated disconnect/reconnect reset/abuse streaks?

---

## 6. GAMEPLAY LOOP

- ✅ Solo mode end-to-end OK (`SoloMatchController.luau`)
- ✅ 1v1 mode end-to-end OK (`MatchController.luau`)
- ✅ Rewards + streak + gamepass multipliers applied in EndMatch
- ✅ Leaderboard stats persist (Wins, WinStreak, TotalLogins, LoginStreak)
- ❓ **Spectator mode** — not found in code. Decide: planned or dropped?

---

## 7. UI POLISH

- ✅ All WaitForChild calls have timeouts
- ⚠️ Verify every ScreenGui child the client expects actually exists (see §3 table)
- ⚠️ **Mobile**: no explicit touch/scale handling found. Test in Studio's mobile emulator; many of the 1v1 UI panels use fixed pixel sizes.
- ⚠️ **1v1 seated jump lock** (this session): server-side JumpPower=0 should replicate; verify in live session that Space really is blocked.

---

## 8. PERFORMANCE / MEMORY

- ✅ All while-true loops have task.wait() yields
- ✅ Event connections cleaned up on PlayerRemoving / match end
- ⚠️ `LuckyBlockShop.pendingGrants` grows unbounded in theory — fine if PlayerRemoving always fires; add periodic sanity cleanup as insurance.

---

## 9. PUBLISH-TIME CONFIG

- [ ] Confirm publishing to **production PlaceId**, not a test place
- [ ] Confirm DataStore name `"PlayerData"` never changes post-launch (would orphan saves)
- [ ] Run once with Studio Output open — capture any warn() lines from ChairShop, LuckyBlockShop, ProfileService
- [ ] Commit & tag current state before flipping game to Public

---

## 10. FINAL BEFORE-PUBLISH CHECKLIST

### Code fixes (ordered by priority)
- [ ] ProcessReceipt idempotency + correct return codes (§1.1)
- [ ] ProfileService retry w/ backoff (§4.1)
- [ ] Rate-limit all purchase/claim remotes (§1.3)
- [ ] Per-player purchase lock to kill concurrent-buy race (§1.4)
- [ ] Validate player is in match + phase == guessing in GuessPreview/SubmitGuess (§1.2)
- [ ] Centralize gamepass/product IDs into Constants (§5.1)
- [ ] Replace FindFirstChild remote lookups with WaitForChild (§4.2)
- [ ] pcall around MarketplaceService callback (§4.3)
- [ ] Bounds-check `dropPosition` on OpenLuckyBlock (§1.5)
- [ ] Iterate `Workspace.SoloTables` in TableManager.Init if solo tables matter (§3)
- [ ] Decide on spectator mode (§6)

### Manual Studio verification
- [ ] All 32 chair models present (check Output for ChairShop warnings)
- [ ] All 8 lucky block models present (check Output for LuckyBlockShop warnings)
- [ ] StarterGui.ScreenGui has every expected child frame
- [ ] 3 main-shop lucky block SubmitButton labels show correct Robux prices
- [ ] Group reward feature: GROUP_ID `626343155` is real

### Creator Dashboard verification
- [ ] 5 gamepasses exist with matching IDs
- [ ] ~25 dev products exist with matching IDs
- [ ] All gamepasses/products have icons set
- [ ] Game thumbnails + icon uploaded
- [ ] Splash / logo — decide whether you want one

### Testing
- [ ] Play full solo round end-to-end
- [ ] Play full 1v1 round end-to-end (alt account)
- [ ] Buy each gamepass in Studio (test mode) — verify benefit granted
- [ ] Buy one dev product of each category — verify grant
- [ ] Open each of the 8 lucky block types — verify reveal + chair grant + duplicate refund
- [ ] Rapid-click purchase buttons — verify no double-spend
- [ ] Disconnect mid-reveal — reconnect, verify chair was granted
- [ ] Disconnect mid-match — verify no money leak, opponent gets win
- [ ] Sit at 1v1 table — verify jump is blocked
- [ ] Walk into chair seats — verify you can't auto-sit
- [ ] Test on mobile emulator (iPhone + iPad presets)

### Documentation / ops
- [ ] Commit + tag `v1.0.0` before flipping public
- [ ] Write a one-page rollback plan (how to take game offline if something breaks)
- [ ] Set up basic incident logging (server prints already help; consider AnalyticsService)

---

## Known non-issues (already verified clean)
- No TODO/FIXME/HACK comments in src/
- No loadstring / getfenv / external HTTP
- No client-authoritative currency grants
- All SFX IDs non-zero
- VIP chat tag wired (both server + client init)
- VIP throne grant logic added
- Pending grants survive disconnect (flushPending on PlayerRemoving)
- Chair rarity coloring in inventory works
- Reveal animation defers chair grant so it doesn't spoil
- Seat disable + JumpPower=0 at table (this session)

---

_End of checklist. When you return, start with the BLOCKERS in §1.1 and §4.1 — those are the ones that could ruin launch day._
