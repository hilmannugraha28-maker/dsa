-- ================================================
-- WIZARD ALCHEMY | AUTO FARM + INSTANT KILL
-- Script by: Antigravity Assistant
-- NOTE: Gunakan di executor yang mendukung getconnections
--       (Synapse X, KRNL, Fluxus, dll.)
-- ================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")

-- ========================
-- STATE
-- ========================
local State = {
    AutoFarm = false,
    InstantKill = false,
    AutoAttack = false,
    AutoCollect = false,
    AutoRebirth = false,
    AutoSell = false,
    FarmLoop = nil,
    KillLoop = nil,
    AttackLoop = nil,
    CollectLoop = nil,
    SellLoop = nil,
    KillDelay = 0.8,
    FarmDelay = 0.5,
    FarmRange = 150,
    FarmOrigin = nil,
    SellRarities = {
        Common    = true,
        Uncommon  = true,
        Rare      = false,
        Epic      = false,
        Legendary = false,
    },
}

-- ========================
-- UTILITY
-- ========================
local function notify(title, msg)
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = title,
        Text = msg,
        Duration = 3,
    })
end

local function tween(obj, props, t)
    TweenService:Create(obj, TweenInfo.new(t or 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props):Play()
end

-- ========================
-- ENEMY FILTER
-- ========================
local NPC_BLACKLIST = {
    "wizard robe", "robe", "apprentice", "shop", "merchant", "vendor", "trader",
    "quest", "dialog", "dialogue", "friendly", "civilian", "townsfolk",
    "keeper", "banker", "innkeeper", "blacksmith", "tailor", "guide",
    "tutor", "instructor", "mayor", "king", "queen", "noble",
    "neutral", "villager", "citizen", "dummy", "tutorial",
}

local FRIENDLY_FOLDERS = {
    "npcs", "friendlynpcs", "townnpcs", "shopnpcs", "vendors",
    "merchants", "questnpcs", "dialognpcs", "civilians",
}

local function isFriendlyNPC(model)
    -- Filter 1: Blacklist nama (NPC toko/damai)
    local nameLower = model.Name:lower()
    for _, kw in ipairs(NPC_BLACKLIST) do
        if nameLower:find(kw, 1, true) then return true end
    end

    -- Filter 2: Berada di folder NPC damai
    if model.Parent and model.Parent:IsA("Folder") then
        local pn = model.Parent.Name:lower()
        for _, fn in ipairs(FRIENDLY_FOLDERS) do
            if pn == fn then return true end
        end
    end

    -- Filter 3: MaxHealth tidak valid (immortal / 0)
    local hum = model:FindFirstChild("Humanoid")
    if hum then
        if hum.MaxHealth <= 0 or hum.MaxHealth == math.huge then return true end
    end

    -- Lulus semua filter → anggap musuh
    return false
end

-- Scan SEMUA mob hidup di map, return list beserta posisi dan jarak
local function scanAllMobs()
    local mobs = {}
    local seen = {}

    -- Priority: folder ENEMY saja (NPCs dilewati)
    local enemyFolders = {"Enemies", "Mobs", "Monsters", "Enemy", "Mob", "Boss", "Bosses", "Creature"}
    for _, folderName in ipairs(enemyFolders) do
        local folder = Workspace:FindFirstChild(folderName)
        if folder then
            for _, model in ipairs(folder:GetChildren()) do
                if model:IsA("Model") and not seen[model] then
                    local hum = model:FindFirstChild("Humanoid")
                    if hum and hum.Health > 0 and hum.MaxHealth > 0 and hum.MaxHealth ~= math.huge then
                        if not isFriendlyNPC(model) then
                            local root = model:FindFirstChild("HumanoidRootPart")
                                or model:FindFirstChild("Torso")
                                or model.PrimaryPart
                            if root then
                                local dist = (RootPart.Position - root.Position).Magnitude
                                table.insert(mobs, {
                                    model = model, root = root,
                                    pos = root.Position, dist = dist,
                                    name = model.Name, hp = hum.Health,
                                })
                                seen[model] = true
                            end
                        end
                    end
                end
            end
        end
    end

    -- Fallback: scan rekursif (filter ketat)
    if #mobs == 0 then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Humanoid") and obj.Health > 0 and not seen[obj.Parent] then
                local model = obj.Parent
                if model ~= Character and model:IsA("Model") then
                    local isPlayer = false
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p.Character == model then isPlayer = true; break end
                    end
                    if not isPlayer and not isFriendlyNPC(model) then
                        if obj.MaxHealth > 0 and obj.MaxHealth ~= math.huge then
                            local root = model:FindFirstChild("HumanoidRootPart")
                                or model:FindFirstChild("Torso")
                                or model.PrimaryPart
                            if root then
                                local dist = (RootPart.Position - root.Position).Magnitude
                                table.insert(mobs, {
                                    model = model, root = root,
                                    pos = root.Position, dist = dist,
                                    name = model.Name, hp = obj.Health,
                                })
                                seen[model] = true
                            end
                        end
                    end
                end
            end
        end
    end

    -- Urutkan dari yang terdekat ke terjauh
    table.sort(mobs, function(a, b) return a.dist < b.dist end)

    -- Filter berdasarkan FarmRange (0 = tidak ada batas)
    if State.FarmRange > 0 then
        local origin = State.FarmOrigin or RootPart.Position
        local filtered = {}
        for _, mob in ipairs(mobs) do
            local d = (origin - mob.pos).Magnitude
            if d <= State.FarmRange then
                table.insert(filtered, mob)
            end
        end
        return filtered
    end

    return mobs
end

-- Alias sederhana untuk kompatibilitas
local function getEnemies()
    local list = {}
    for _, mob in ipairs(scanAllMobs()) do
        table.insert(list, mob.model)
    end
    return list
end

local function getNearestEnemy()
    local nearest, dist = nil, math.huge
    for _, enemy in ipairs(getEnemies()) do
        local root = enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso") or enemy.PrimaryPart
        if root then
            local d = (RootPart.Position - root.Position).Magnitude
            if d < dist then
                dist = d
                nearest = enemy
            end
        end
    end
    return nearest, dist
end

local function teleportTo(pos)
    if RootPart then
        RootPart.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
    end
end

-- ========================
-- REMOTE SPY + REAL ATTACK SYSTEM
-- ========================
-- Cara kerja:
-- 1. Pasang hook ke semua RemoteEvent saat game load
-- 2. Saat player menyerang normal 1x → remote + argumen asli tertangkap
-- 3. killEnemy replay call yang sama ke target → server-side REAL hit

local cachedAttackRemote = nil   -- Remote yang dipakai untuk menyerang
local cachedAttackArgs   = nil   -- Argumen asli yang dipakai

-- Hook semua RemoteEvent yang mungkin adalah attack remote
local hookedRemotes = {}
local function hookAllRemotes()
    local function tryHook(remote)
        if hookedRemotes[remote] then return end
        hookedRemotes[remote] = true
        local n = remote.Name:lower()

        -- Hanya hook remote yang namanya relevan dengan combat
        if n:find("attack") or n:find("swing") or n:find("cast") or n:find("spell")
            or n:find("shoot") or n:find("hit") or n:find("damage") or n:find("fire")
            or n:find("use") or n:find("activate") or n:find("ability") or n:find("skill") then

            -- Hook menggunakan hookfunction / newcclosure (executor API)
            pcall(function()
                local originalFF = remote.FireServer
                hookfunction(originalFF, function(self, ...)
                    local args = {...}
                    -- Simpan remote + argumen saat player menyerang
                    if self == remote then
                        cachedAttackRemote = remote
                        cachedAttackArgs = args
                        print("[WA Spy] Attack remote captured: " .. remote.Name)
                    end
                    return originalFF(self, ...)
                end)
            end)
        end
    end

    -- Hook semua remote yang sudah ada
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteEvent") then tryHook(obj) end
    end
    -- Hook remote yang mungkin ada di dalam tool
    for _, child in ipairs(Character:GetChildren()) do
        if child:IsA("Tool") then
            for _, obj in ipairs(child:GetDescendants()) do
                if obj:IsA("RemoteEvent") then tryHook(obj) end
            end
        end
    end

    -- Monitor tool baru yang di-equip
    Character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            task.wait(0.1)
            for _, obj in ipairs(child:GetDescendants()) do
                if obj:IsA("RemoteEvent") then tryHook(obj) end
            end
        end
    end)
end

-- Jalankan hook di background
task.spawn(hookAllRemotes)

-- Fallback: fire tool tanpa spy (jika hookfunction tidak tersedia)
local function fireToolFallback(targetPos)
    local tool = Character:FindFirstChildOfClass("Tool")
    if not tool then return end

    -- Native Roblox API
    pcall(function() tool:Activate() end)

    -- getconnections (executor premium)
    pcall(function()
        for _, c in ipairs(getconnections(tool.Activated)) do c:Fire() end
    end)
    pcall(function()
        local fakeInput = {
            UserInputType = Enum.UserInputType.MouseButton1,
            UserInputState = Enum.UserInputState.Begin,
            KeyCode = Enum.KeyCode.Unknown,
            Position = Vector3.zero,
        }
        for _, c in ipairs(getconnections(tool.InputBegan)) do
            c:Fire(fakeInput, false)
        end
    end)

    -- Brute-force remote dalam tool
    for _, remote in ipairs(tool:GetDescendants()) do
        if remote:IsA("RemoteEvent") then
            pcall(function() remote:FireServer() end)
        end
    end
end

-- ★ REAL SERVER-SIDE ATTACK — replay exact remote call ★
local function fireToolActivated(targetPos)
    -- Prioritas: gunakan cached remote (100% real, server-side)
    if cachedAttackRemote then
        pcall(function()
            -- Replay call dengan argumen asli (tetap kirim ke target)
            cachedAttackRemote:FireServer(table.unpack(cachedAttackArgs or {}))
        end)
        -- Juga coba argumen alternatif dengan target position
        if targetPos then
            pcall(function()
                cachedAttackRemote:FireServer(targetPos)
            end)
        end
        return -- pakai cached, tidak perlu fallback
    end

    -- Fallback jika belum ada cached remote
    fireToolFallback(targetPos)
end

-- ========================
-- ORBIT ATTACK SYSTEM
-- ========================
-- Karakter melayang mengelilingi target sambil menyerang.
-- Saat target mati, loop lanjut ke target berikutnya.

State.OrbitRadius = 4      -- jarak orbit dari target (studs)
State.OrbitHeight = 3      -- ketinggian melayang di atas target
State.OrbitSpeed  = 90     -- derajat per detik (kecepatan putar)
State.AttackInterval = 0.12 -- interval serangan (detik)

-- Variabel orbit aktif
local _orbitRunning = false
local _orbitAngle   = 0
local _orbitConn    = nil

-- Hentikan orbit jika sedang berjalan
local function stopOrbit()
    _orbitRunning = false
    if _orbitConn then
        _orbitConn:Disconnect()
        _orbitConn = nil
    end
end

-- Mulai orbit + serang target tertentu
-- Mengembalikan: true jika target mati, false jika loop dihentikan
local function orbitAndAttack(enemy)
    if not enemy or not enemy.Parent then return false end
    local hum = enemy:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return true end

    stopOrbit()
    _orbitRunning = true
    _orbitAngle = 0

    local lastAttack = 0

    -- Loop orbit via RunService.Heartbeat
    _orbitConn = RunService.Heartbeat:Connect(function(dt)
        if not _orbitRunning then return end

        -- Hentikan jika SEMUA fitur combat dimatikan
        if not State.InstantKill and not State.AutoAttack and not State.AutoFarm then
            _orbitRunning = false
            return
        end

        -- Cek target masih valid
        if not enemy or not enemy.Parent then
            _orbitRunning = false
            return
        end
        local h = enemy:FindFirstChild("Humanoid")
        if not h or h.Health <= 0 then
            _orbitRunning = false
            return
        end

        local root = enemy:FindFirstChild("HumanoidRootPart")
            or enemy:FindFirstChild("Torso")
            or enemy.PrimaryPart
        if not root then return end

        local center = root.Position

        -- Hitung posisi orbit
        _orbitAngle = (_orbitAngle + State.OrbitSpeed * dt) % 360
        local rad   = math.rad(_orbitAngle)
        local orbitPos = Vector3.new(
            center.X + math.cos(rad) * State.OrbitRadius,
            center.Y + State.OrbitHeight,
            center.Z + math.sin(rad) * State.OrbitRadius
        )

        -- Teleport CFrame ke posisi orbit, menghadap target
        pcall(function()
            RootPart.CFrame = CFrame.lookAt(orbitPos, center)
        end)

        -- Serang sesuai interval
        local now = tick()
        if now - lastAttack >= State.AttackInterval then
            lastAttack = now
            pcall(function() fireToolActivated(center) end)
            -- Fire combat remotes
            for _, remote in ipairs(ReplicatedStorage:GetDescendants()) do
                if remote:IsA("RemoteEvent") then
                    local n = remote.Name:lower()
                    if n:find("attack") or n:find("swing") or n:find("cast")
                        or n:find("spell") or n:find("hit") or n:find("damage") then
                        pcall(function() remote:FireServer(enemy, center) end)
                    end
                end
            end
            -- Set HP lokal ke 1 agar kill cepat (server tetap proses normal)
            pcall(function()
                if h and h.Health > 0 and h.Health < h.MaxHealth then
                    h.Health = 1
                end
            end)
        end
    end)

    -- Tunggu sampai target mati atau orbit dihentikan
    while _orbitRunning do
        task.wait(0.1)
    end

    stopOrbit()

    -- Return true jika target sudah mati (bukan karena dihentikan manual)
    if enemy and enemy.Parent then
        local h2 = enemy:FindFirstChild("Humanoid")
        return not h2 or h2.Health <= 0
    end
    return true
end

-- Wrapper kompatibilitas (dipakai GUI toggle lama)
local function autoAttackEnemy(enemy)
    if not enemy or not enemy:FindFirstChild("Humanoid") then return end
    if enemy.Humanoid.Health <= 0 then return end
    orbitAndAttack(enemy)
end

local function killEnemy(enemy)
    if not enemy or not enemy:FindFirstChild("Humanoid") then return end
    if enemy.Humanoid.Health <= 0 then return end
    orbitAndAttack(enemy)
end

local function collectItems()
    -- Cari item collectible di workspace
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") or obj:IsA("Model") then
            local name = obj.Name:lower()
            if name:find("coin") or name:find("gem") or name:find("potion") or name:find("drop") or name:find("orb") or name:find("reward") then
                local pos = obj:IsA("Model") and obj.PrimaryPart and obj.PrimaryPart.Position or (obj:IsA("BasePart") and obj.Position)
                if pos then
                    teleportTo(pos)
                    task.wait(0.1)
                end
            end
        end
    end
end

-- ========================
-- LOOP HANDLERS
-- ========================
-- ========================
-- ORBIT-BASED FARM LOOPS
-- ========================

-- startInstantKill: orbit tiap mob satu per satu, pindah saat mati
local function startInstantKill()
    State.KillLoop = task.spawn(function()
        while State.InstantKill do
            local mobs = scanAllMobs()

            if #mobs == 0 then
                stopOrbit()
                task.wait(2)
            else
                print(string.format("[WA Hub] Ditemukan %d mob, mulai orbit hunt...", #mobs))

                for _, mobData in ipairs(mobs) do
                    if not State.InstantKill then stopOrbit(); break end

                    local enemy = mobData.model
                    if not enemy or not enemy.Parent then continue end
                    local hum = enemy:FindFirstChild("Humanoid")
                    if not hum or hum.Health <= 0 then continue end

                    print("[WA Hub] Orbit → " .. enemy.Name)
                    -- Orbit & serang sampai mati, lalu lanjut ke mob berikutnya
                    pcall(function() orbitAndAttack(enemy) end)

                    task.wait(0.15) -- jeda kecil sebelum target berikutnya
                end

                print("[WA Hub] Semua mob selesai, scan ulang...")
                task.wait(0.3)
            end
        end
        stopOrbit()
    end)
end

-- startAutoAttack: orbit musuh terdekat terus-menerus
local function startAutoAttack()
    State.AttackLoop = task.spawn(function()
        while State.AutoAttack do
            local nearest = getNearestEnemy()
            if nearest then
                local hum = nearest:FindFirstChild("Humanoid")
                if hum and hum.Health > 0 then
                    pcall(function() orbitAndAttack(nearest) end)
                end
            else
                stopOrbit()
                task.wait(0.5)
            end
            task.wait(0.1)
        end
        stopOrbit()
    end)
end

-- startAutoFarm: orbit mob dalam range, teleport ke berikutnya setelah mati
local function startAutoFarm()
    State.FarmLoop = task.spawn(function()
        while State.AutoFarm do
            local mobs = scanAllMobs()
            if #mobs == 0 then
                stopOrbit()
                task.wait(1)
            else
                for _, mob in ipairs(mobs) do
                    if not State.AutoFarm then stopOrbit(); break end
                    local enemy = mob.model
                    if not enemy or not enemy.Parent then continue end
                    local hum = enemy:FindFirstChild("Humanoid")
                    if not hum or hum.Health <= 0 then continue end
                    pcall(function() orbitAndAttack(enemy) end)
                    task.wait(State.FarmDelay)
                end
            end
            task.wait(0.2)
        end
        stopOrbit()
    end)
end

local function startAutoCollect()
    State.CollectLoop = task.spawn(function()
        while State.AutoCollect do
            pcall(collectItems)
            task.wait(1)
        end
    end)
end

-- ========================
-- AUTO SELL SYSTEM (Remote Spy via __namecall)
-- ========================

local cachedSellRemote    = nil  -- remote update/select item
local cachedSellArgs      = nil
local cachedConfirmRemote = nil  -- remote confirm sell
local cachedConfirmArgs   = nil
local State_DebugRemotes  = false

-- Hook via __namecall (reliable di semua executor)
task.spawn(function()
    local ok, err = pcall(function()
        local mt = getrawmetatable(game)
        local oldNamecall = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()
            local args = {...}
            if method == "FireServer" and typeof(self) == "Instance" then
                pcall(function()
                    if self:IsA("RemoteEvent") then
                        local n = self.Name:lower()
                        if State_DebugRemotes then
                            print("[DEBUG Remote] " .. self.Name)
                        end
                        -- Capture update/select remote
                        if n:find("trade") or n:find("shop") or n:find("sell")
                            or n:find("item") or n:find("exchange") then
                            cachedSellRemote = self
                            cachedSellArgs   = args
                            print("[⚡ Spy] Update: " .. self.Name)
                        end
                        -- Capture confirm remote (lebih spesifik)
                        if n:find("confirm") or n:find("buy") or n:find("purchase")
                            or n:find("complete") or n:find("submit") then
                            cachedConfirmRemote = self
                            cachedConfirmArgs   = args
                            print("[⚡ Spy] ✅ CONFIRM: " .. self.Name)
                        end
                    end
                end)
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
    end)
    if ok then
        print("[WA Sell Spy] __namecall hook aktif. Jual 1x manual!")
    else
        print("[WA Sell Spy] __namecall gagal: " .. tostring(err))
        print("[WA Sell Spy] Coba cara lain...")
        -- Fallback: hookfunction biasa
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("RemoteEvent") then
                local n = obj.Name:lower()
                if n:find("sell") or n:find("shop") or n:find("trade") then
                    pcall(function()
                        local orig = obj.FireServer
                        hookfunction(orig, function(s, ...)
                            if s == obj then
                                cachedSellRemote = obj
                                cachedSellArgs = {...}
                                print("[⚡ Sell Spy] Captured (fallback): " .. obj.Name)
                            end
                            return orig(s, ...)
                        end)
                    end)
                end
            end
        end
    end
end)

-- Cari NPC Lombart
-- Nama NPC merchant (bisa diubah user lewat GUI)
State.MerchantName = "" -- kosong = pakai auto-detect

-- Scan dan print semua NPC/Model di workspace ke Output
local function scanAllNPCNames()
    local found = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= Character then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            -- Cek apakah player
            local isPlayer = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character == obj then isPlayer = true; break end
            end
            if not isPlayer and hum then
                table.insert(found, obj.Name)
            end
        end
    end
    -- Print ke output
    print("[WA] === LIST NPC DI MAP ===")
    for _, name in ipairs(found) do
        print("[WA NPC] " .. name)
    end
    print("[WA] Total: " .. #found .. " NPC ditemukan")
    notify("🔍 NPC Scan", #found .. " NPC ditemukan — cek Output executor!")
    return found
end

local function findLombart()
    -- Prioritas: gunakan nama kustom dari user
    if State.MerchantName and State.MerchantName ~= "" then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Model") and obj.Name:lower() == State.MerchantName:lower() then
                return obj
            end
        end
        -- Juga coba partial match
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Model") and obj.Name:lower():find(State.MerchantName:lower(), 1, true) then
                return obj
            end
        end
    end
    -- Auto-detect: keyword umum + nama China
    local keywords = {"lombart", "merchant", "penjual", "shop", "vendor",
                      "seller", "trader", "dealer", "keeper",
                      "隆巴特", "商人", "店主"}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= Character then
            local n = obj.Name:lower()
            local isPlayer = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character == obj then isPlayer = true; break end
            end
            if not isPlayer then
                for _, kw in ipairs(keywords) do
                    if n:find(kw, 1, true) then return obj end
                end
            end
        end
    end
    return nil
end


-- Klik TextButton via getconnections (tanpa mouse)
local function clickGuiButton(btn)
    pcall(function()
        for _, c in ipairs(getconnections(btn.MouseButton1Click)) do c:Fire() end
    end)
    pcall(function()
        for _, c in ipairs(getconnections(btn.Activated)) do c:Fire() end
    end)
    pcall(function() btn:activate() end)
end

-- Teleport ke Lombart dan open shop
local function goToLombart()
    local lombart = findLombart()
    if not lombart then
        notify("⚠️ Sell", "NPC tidak ditemukan! Set nama di input.")
        return false
    end
    local root = lombart:FindFirstChild("HumanoidRootPart")
        or lombart:FindFirstChild("Torso") or lombart.PrimaryPart
    if root then
        -- Teleport dekat NPC
        RootPart.CFrame = CFrame.new(root.Position + Vector3.new(3, 0, 0))
        RootPart.CFrame = CFrame.lookAt(RootPart.Position, root.Position)
        task.wait(0.6)
    end

    -- Metode 1: fireproximityprompt
    for _, obj in ipairs(lombart:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            pcall(function() fireproximityprompt(obj) end)
            pcall(function()
                for _, c in ipairs(getconnections(obj.Triggered)) do
                    c:Fire(LocalPlayer)
                end
            end)
            task.wait(0.2)
        end
        if obj:IsA("ClickDetector") then
            pcall(function() fireclickdetector(obj) end)
        end
    end

    -- Metode 2: simulasi keypress H (tombol default ProximityPrompt)
    task.wait(0.3)
    pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true,  Enum.KeyCode.H, false, game)
        task.wait(0.05)
        vim:SendKeyEvent(false, Enum.KeyCode.H, false, game)
    end)
    task.wait(0.5)
    return true
end

-- Tunggu dialog muncul lalu klik opsi "I have goods to sell"
local function clickSellDialogue()
    local deadline = tick() + 4
    while tick() < deadline do
        -- Cari frame dialog NPC (berdasarkan nama atau teks China)
        for _, gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
            -- Cari container dialog
            local isDialogContainer = false
            if gui:IsA("Frame") or gui:IsA("ScreenGui") then
                local n = gui.Name:lower()
                if n:find("npc") or n:find("dialog") or n:find("chat")
                    or n:find("conv") or n:find("talk") or n:find("quest") then
                    isDialogContainer = true
                end
                -- Cek jika ada TextLabel dengan teks China
                for _, child in ipairs(gui:GetDescendants()) do
                    if child:IsA("TextLabel") and child.Text:find("对话") then
                        isDialogContainer = true
                    end
                end
            end

            if isDialogContainer then
                -- Klik tombol pertama di dalam container ini
                local buttons = {}
                for _, btn in ipairs(gui:GetDescendants()) do
                    if btn:IsA("TextButton") and btn.Visible and btn.Text ~= "" then
                        table.insert(buttons, btn)
                        print("[WA Dialog] Found btn in NPC GUI: '" .. btn.Text .. "'")
                    end
                end
                -- Sort: cari yang mengandung "1", "goods", "sell", atau ambil yg pertama
                for _, btn in ipairs(buttons) do
                    local t = btn.Text:lower()
                    if t:find("goods") or t:find("sell") or t:find("1")
                        or t:find("have") or t:find("jual") then
                        clickGuiButton(btn)
                        print("[WA Sell] Klik dialog NPC: " .. btn.Text)
                        return true
                    end
                end
                -- Jika tidak ada match spesifik, klik tombol pertama
                if #buttons > 0 then
                    clickGuiButton(buttons[1])
                    print("[WA Sell] Klik tombol pertama: " .. buttons[1].Text)
                    return true
                end
            end
        end

        -- Scan SEMUA TextButton visible sebagai fallback
        local allBtns = {}
        for _, gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
            if gui:IsA("TextButton") and gui.Visible and gui.Text ~= "" then
                local t = gui.Text:lower()
                table.insert(allBtns, "'" .. gui.Text .. "'")
                if t:find("goods") or t:find("sell") or t == "1"
                    or t:find("^1[%.%)]") or t:find("jual") then
                    clickGuiButton(gui)
                    print("[WA Sell] Klik fallback: " .. gui.Text)
                    return true
                end
            end
        end
        if #allBtns > 0 then
            print("[WA Debug] Visible buttons: " .. table.concat(allBtns, ", "))
        end
        task.wait(0.25)
    end
    print("[WA Sell] Dialog timeout, skip ke sell")
    return false
end


-- Tunggu GUI Sell Shop muncul
local function waitForSellShop(timeout)
    local t = tick()
    while tick() - t < timeout do
        for _, gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
            if gui:IsA("Frame") or gui:IsA("ScrollingFrame") then
                local n = gui.Name:lower()
                if n:find("sell") or n:find("shop") or n:find("store") or n:find("merchant") then
                    return gui
                end
            end
            if gui:IsA("TextLabel") then
                local txt = gui.Text:lower()
                if txt:find("sell shop") or txt:find("confirm sell") then
                    return gui.Parent
                end
            end
        end
        task.wait(0.1)
    end
    return nil
end

-- Filter dan klik item berdasarkan rarity di Sell Shop GUI
local function selectItemsByRarity(shopFrame)
    if not shopFrame then return end
    -- Cari "Multi Select" button dulu
    for _, btn in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if btn:IsA("TextButton") then
            local txt = btn.Text:lower()
            if txt:find("multi") or txt:find("select all") then
                clickGuiButton(btn)
                print("[WA Sell] Klik Multi Select")
                task.wait(0.3)
                break
            end
        end
    end

    -- Filter berdasarkan rarity yang dipilih
    -- Klik tombol category/filter rarity jika ada
    local rarityMap = {
        Common = {"common", "biasa"},
        Uncommon = {"uncommon"},
        Rare = {"rare"},
        Epic = {"epic"},
        Legendary = {"legendary"},
    }
    for rarity, enabled in pairs(State.SellRarities) do
        if enabled and rarityMap[rarity] then
            for _, btn in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                if btn:IsA("TextButton") then
                    local txt = btn.Text:lower()
                    for _, kw in ipairs(rarityMap[rarity]) do
                        if txt:find(kw) then
                            clickGuiButton(btn)
                            task.wait(0.1)
                        end
                    end
                end
            end
        end
    end
end

-- Klik Confirm Sell
local function clickConfirmSell()
    task.wait(0.3)
    for _, btn in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
        if btn:IsA("TextButton") then
            local txt = btn.Text:lower()
            if txt:find("confirm") or txt:find("sell") and not txt:find("sell shop") then
                clickGuiButton(btn)
                print("[WA Sell] Klik Confirm Sell: " .. btn.Text)
                task.wait(0.3)
                -- Klik konfirmasi jika ada popup
                for _, confirmBtn in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                    if confirmBtn:IsA("TextButton") then
                        local ct = confirmBtn.Text:lower()
                        if ct == "yes" or ct == "ok" or ct == "confirm" or ct:find("iya") then
                            clickGuiButton(confirmBtn)
                            print("[WA Sell] Klik konfirmasi popup: " .. confirmBtn.Text)
                        end
                    end
                end
                return true
            end
        end
    end
    return false
end

-- Main sell function
local function sellInventory()
    -- 1. Teleport ke Lombart + trigger proximity
    local ok = goToLombart()
    if not ok then return 0 end

    -- 2. Tunggu dan klik dialog "I have goods to sell"
    clickSellDialogue()
    task.wait(0.5)

    -- 3. Tunggu Sell Shop GUI muncul (max 5 detik)
    local shopGui = waitForSellShop(5)
    if shopGui then
        print("[WA Sell] Sell Shop terbuka!")
    else
        print("[WA Sell] Sell Shop tidak muncul")
    end

    -- 4. Select item berdasarkan rarity
    selectItemsByRarity(shopGui)
    task.wait(0.4)

    -- 5. Klik Confirm Sell
    local sold = clickConfirmSell()

    -- 6. Fallback: prioritaskan confirm remote, lalu update remote
    if not sold then
        if cachedConfirmRemote then
            pcall(function() cachedConfirmRemote:FireServer(table.unpack(cachedConfirmArgs or {})) end)
            pcall(function() cachedConfirmRemote:FireServer() end)
            print("[WA Sell] Fallback pakai CONFIRM remote: " .. cachedConfirmRemote.Name)
        elseif cachedSellRemote then
            pcall(function() cachedSellRemote:FireServer(table.unpack(cachedSellArgs or {})) end)
            pcall(function() cachedSellRemote:FireServer() end)
            print("[WA Sell] Fallback pakai update remote: " .. cachedSellRemote.Name)
        end
    end

    return sold and 1 or 0
end


local function startAutoSell()
    State.SellLoop = task.spawn(function()
        while State.AutoSell do
            local ok, result = pcall(sellInventory)
            local sold = (ok and result) or 0
            task.wait(10)
        end
    end)
end


-- ========================
-- CHARACTER REFRESH
-- ========================
LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    Humanoid = char:WaitForChild("Humanoid")
    RootPart = char:WaitForChild("HumanoidRootPart")
end)

-- ========================
-- GUI BUILDER
-- ========================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WizardAlchemyHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Protect from character reset
if syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = game:GetService("CoreGui")
elseif gethui then
    ScreenGui.Parent = gethui()
else
    ScreenGui.Parent = LocalPlayer.PlayerGui
end

-- ── MAIN FRAME ──
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 320, 0, 600)
MainFrame.Position = UDim2.new(0.5, -160, 0.5, -210)
MainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 22)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 14)

-- Gradient latar
local BG = Instance.new("UIGradient", MainFrame)
BG.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 8, 45)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 20, 40)),
})
BG.Rotation = 135

-- Glow border
local Stroke = Instance.new("UIStroke", MainFrame)
Stroke.Color = Color3.fromRGB(148, 87, 235)
Stroke.Thickness = 2

-- ── TITLE BAR ──
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 50)
TitleBar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
TitleBar.BackgroundTransparency = 0.4
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 14)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -60, 1, 0)
TitleLabel.Position = UDim2.new(0, 14, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "⚗️ Wizard Alchemy Hub"
TitleLabel.TextColor3 = Color3.fromRGB(220, 180, 255)
TitleLabel.TextSize = 17
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TitleBar

-- Minimize button
local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 32, 0, 32)
MinBtn.Position = UDim2.new(1, -44, 0.5, -16)
MinBtn.BackgroundColor3 = Color3.fromRGB(148, 87, 235)
MinBtn.Text = "−"
MinBtn.TextColor3 = Color3.new(1,1,1)
MinBtn.TextSize = 18
MinBtn.Font = Enum.Font.GothamBold
MinBtn.BorderSizePixel = 0
MinBtn.Parent = TitleBar
Instance.new("UICorner", MinBtn).CornerRadius = UDim.new(1, 0)

-- ── SCROLL CONTENT ──
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(1, 0, 1, -54)
ScrollFrame.Position = UDim2.new(0, 0, 0, 54)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.ScrollBarThickness = 4
ScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(148, 87, 235)
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)          -- dikelola AutomaticCanvasSize
ScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y  -- otomatis expand sesuai isi
ScrollFrame.ScrollingDirection = Enum.ScrollingDirection.Y
ScrollFrame.BorderSizePixel = 0
ScrollFrame.Parent = MainFrame

local ListLayout = Instance.new("UIListLayout", ScrollFrame)
ListLayout.Padding = UDim.new(0, 8)
ListLayout.FillDirection = Enum.FillDirection.Vertical
ListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local Padding = Instance.new("UIPadding", ScrollFrame)
Padding.PaddingTop = UDim.new(0, 10)
Padding.PaddingLeft = UDim.new(0, 12)
Padding.PaddingRight = UDim.new(0, 12)

-- ── TOGGLE BUILDER ──
local function makeToggle(labelText, icon, description, callback)
    local Container = Instance.new("Frame")
    Container.Size = UDim2.new(1, 0, 0, 72)
    Container.BackgroundColor3 = Color3.fromRGB(25, 15, 55)
    Container.BorderSizePixel = 0
    Container.Parent = ScrollFrame
    Instance.new("UICorner", Container).CornerRadius = UDim.new(0, 10)

    local CStroke = Instance.new("UIStroke", Container)
    CStroke.Color = Color3.fromRGB(80, 40, 160)
    CStroke.Thickness = 1

    local IconL = Instance.new("TextLabel")
    IconL.Size = UDim2.new(0, 36, 0, 36)
    IconL.Position = UDim2.new(0, 10, 0.5, -18)
    IconL.BackgroundColor3 = Color3.fromRGB(148, 87, 235)
    IconL.BackgroundTransparency = 0.7
    IconL.Text = icon
    IconL.TextSize = 20
    IconL.Font = Enum.Font.GothamBold
    IconL.TextColor3 = Color3.new(1,1,1)
    IconL.BorderSizePixel = 0
    IconL.Parent = Container
    Instance.new("UICorner", IconL).CornerRadius = UDim.new(0, 8)

    local Lbl = Instance.new("TextLabel")
    Lbl.Size = UDim2.new(1, -110, 0, 22)
    Lbl.Position = UDim2.new(0, 54, 0, 12)
    Lbl.BackgroundTransparency = 1
    Lbl.Text = labelText
    Lbl.TextColor3 = Color3.fromRGB(220, 200, 255)
    Lbl.TextSize = 14
    Lbl.Font = Enum.Font.GothamBold
    Lbl.TextXAlignment = Enum.TextXAlignment.Left
    Lbl.Parent = Container

    local Desc = Instance.new("TextLabel")
    Desc.Size = UDim2.new(1, -110, 0, 18)
    Desc.Position = UDim2.new(0, 54, 0, 36)
    Desc.BackgroundTransparency = 1
    Desc.Text = description
    Desc.TextColor3 = Color3.fromRGB(140, 120, 180)
    Desc.TextSize = 11
    Desc.Font = Enum.Font.Gotham
    Desc.TextXAlignment = Enum.TextXAlignment.Left
    Desc.Parent = Container

    -- Toggle switch
    local Track = Instance.new("Frame")
    Track.Size = UDim2.new(0, 46, 0, 24)
    Track.Position = UDim2.new(1, -56, 0.5, -12)
    Track.BackgroundColor3 = Color3.fromRGB(60, 30, 100)
    Track.BorderSizePixel = 0
    Track.Parent = Container
    Instance.new("UICorner", Track).CornerRadius = UDim.new(1, 0)

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 18, 0, 18)
    Knob.Position = UDim2.new(0, 3, 0.5, -9)
    Knob.BackgroundColor3 = Color3.fromRGB(180, 140, 220)
    Knob.BorderSizePixel = 0
    Knob.Parent = Track
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)

    local enabled = false
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(1, 0, 1, 0)
    Button.BackgroundTransparency = 1
    Button.Text = ""
    Button.Parent = Container

    Button.MouseButton1Click:Connect(function()
        enabled = not enabled
        if enabled then
            tween(Track, {BackgroundColor3 = Color3.fromRGB(130, 60, 220)})
            tween(Knob, {Position = UDim2.new(0, 25, 0.5, -9), BackgroundColor3 = Color3.new(1,1,1)})
            CStroke.Color = Color3.fromRGB(148, 87, 235)
        else
            tween(Track, {BackgroundColor3 = Color3.fromRGB(60, 30, 100)})
            tween(Knob, {Position = UDim2.new(0, 3, 0.5, -9), BackgroundColor3 = Color3.fromRGB(180, 140, 220)})
            CStroke.Color = Color3.fromRGB(80, 40, 160)
        end
        callback(enabled)
    end)

    return Container
end

-- ── SECTION LABEL ──
local function makeSection(text)
    local Lbl = Instance.new("TextLabel")
    Lbl.Size = UDim2.new(1, 0, 0, 24)
    Lbl.BackgroundTransparency = 1
    Lbl.Text = text
    Lbl.TextColor3 = Color3.fromRGB(148, 87, 235)
    Lbl.TextSize = 12
    Lbl.Font = Enum.Font.GothamBold
    Lbl.TextXAlignment = Enum.TextXAlignment.Left
    Lbl.Parent = ScrollFrame
    return Lbl
end

-- ── SLIDER BUILDER ──
local function makeSlider(labelText, icon, minVal, maxVal, defaultVal, formatFn, onChange)
    local Container = Instance.new("Frame")
    Container.Size = UDim2.new(1, 0, 0, 80)
    Container.BackgroundColor3 = Color3.fromRGB(25, 15, 55)
    Container.BorderSizePixel = 0
    Container.Parent = ScrollFrame
    Instance.new("UICorner", Container).CornerRadius = UDim.new(0, 10)
    local CStroke = Instance.new("UIStroke", Container)
    CStroke.Color = Color3.fromRGB(80, 40, 160)
    CStroke.Thickness = 1

    local IconL = Instance.new("TextLabel")
    IconL.Size = UDim2.new(0, 36, 0, 36)
    IconL.Position = UDim2.new(0, 10, 0, 8)
    IconL.BackgroundColor3 = Color3.fromRGB(148, 87, 235)
    IconL.BackgroundTransparency = 0.7
    IconL.Text = icon
    IconL.TextSize = 18
    IconL.Font = Enum.Font.GothamBold
    IconL.TextColor3 = Color3.new(1,1,1)
    IconL.BorderSizePixel = 0
    IconL.Parent = Container
    Instance.new("UICorner", IconL).CornerRadius = UDim.new(0, 8)

    local Lbl = Instance.new("TextLabel")
    Lbl.Size = UDim2.new(1, -100, 0, 20)
    Lbl.Position = UDim2.new(0, 54, 0, 8)
    Lbl.BackgroundTransparency = 1
    Lbl.Text = labelText
    Lbl.TextColor3 = Color3.fromRGB(220, 200, 255)
    Lbl.TextSize = 13
    Lbl.Font = Enum.Font.GothamBold
    Lbl.TextXAlignment = Enum.TextXAlignment.Left
    Lbl.Parent = Container

    local ValLbl = Instance.new("TextLabel")
    ValLbl.Size = UDim2.new(0, 70, 0, 20)
    ValLbl.Position = UDim2.new(1, -78, 0, 8)
    ValLbl.BackgroundTransparency = 1
    ValLbl.Text = formatFn(defaultVal)
    ValLbl.TextColor3 = Color3.fromRGB(200, 160, 255)
    ValLbl.TextSize = 13
    ValLbl.Font = Enum.Font.GothamBold
    ValLbl.TextXAlignment = Enum.TextXAlignment.Right
    ValLbl.Parent = Container

    -- Track
    local Track = Instance.new("Frame")
    Track.Size = UDim2.new(1, -24, 0, 6)
    Track.Position = UDim2.new(0, 12, 0, 52)
    Track.BackgroundColor3 = Color3.fromRGB(60, 30, 100)
    Track.BorderSizePixel = 0
    Track.Parent = Container
    Instance.new("UICorner", Track).CornerRadius = UDim.new(1, 0)

    local ratio = (defaultVal - minVal) / (maxVal - minVal)
    local Fill = Instance.new("Frame")
    Fill.Size = UDim2.new(ratio, 0, 1, 0)
    Fill.BackgroundColor3 = Color3.fromRGB(148, 87, 235)
    Fill.BorderSizePixel = 0
    Fill.Parent = Track
    Instance.new("UICorner", Fill).CornerRadius = UDim.new(1, 0)

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 16, 0, 16)
    Knob.Position = UDim2.new(ratio, -8, 0.5, -8)
    Knob.BackgroundColor3 = Color3.new(1,1,1)
    Knob.BorderSizePixel = 0
    Knob.Parent = Track
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)

    local draggingSlider = false
    local SliderBtn = Instance.new("TextButton")
    SliderBtn.Size = UDim2.new(1, 0, 1, 0)
    SliderBtn.BackgroundTransparency = 1
    SliderBtn.Text = ""
    SliderBtn.Parent = Track

    local function updateSlider(inputPos)
        local trackPos = Track.AbsolutePosition
        local trackSize = Track.AbsoluteSize
        local r = math.clamp((inputPos.X - trackPos.X) / trackSize.X, 0, 1)
        local val = math.floor((minVal + r * (maxVal - minVal)) * 10 + 0.5) / 10
        Fill.Size = UDim2.new(r, 0, 1, 0)
        Knob.Position = UDim2.new(r, -8, 0.5, -8)
        ValLbl.Text = formatFn(val)
        onChange(val)
    end

    SliderBtn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSlider = true
            updateSlider(inp.Position)
        end
    end)
    SliderBtn.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSlider = false
        end
    end)
    UserInputService.InputChanged:Connect(function(inp)
        if draggingSlider and inp.UserInputType == Enum.UserInputType.MouseMovement then
            updateSlider(inp.Position)
        end
    end)

    return Container
end

-- ── TOGGLES ──
makeSection("  ⚔️  COMBAT")

makeToggle("Instant Kill", "⚡", "Scan map lalu kill satu per satu", function(on)
    State.InstantKill = on
    if on then
        -- Simpan posisi saat ini sebagai anchor farming
        State.FarmOrigin = RootPart.Position
        startInstantKill()
        notify("Instant Kill", "✅ Aktif! Range: " .. (State.FarmRange == 0 and "Unlimited" or State.FarmRange .. " studs"))
    else
        State.FarmOrigin = nil
        stopOrbit()  -- langsung hentikan orbit
        notify("Instant Kill", "❌ Nonaktif")
    end
end)

makeSlider("Kill Delay", "⏱️", 0.3, 2.0, 0.8,
    function(v) return v .. "s" end,
    function(v) State.KillDelay = v end
)

makeSlider("Orbit Radius", "🌀", 2, 12, 4,
    function(v) return v .. " st" end,
    function(v) State.OrbitRadius = v end
)

makeSlider("Orbit Speed", "⚡", 30, 360, 90,
    function(v) return v .. "°/s" end,
    function(v) State.OrbitSpeed = v end
)

makeSlider("Attack Rate", "🗡️", 0.05, 0.5, 0.12,
    function(v) return v .. "s" end,
    function(v) State.AttackInterval = v end
)

makeSlider("Farm Range", "📍", 0, 500, 150,
    function(v)
        if v == 0 then return "Unlimited" end
        return v .. " st"
    end,
    function(v)
        State.FarmRange = v
        -- Update anchor ke posisi sekarang saat range diubah
        if State.InstantKill or State.AutoFarm then
            State.FarmOrigin = RootPart.Position
        end
    end
)

makeToggle("Auto Attack", "🗡️", "Serang musuh terdekat terus-menerus", function(on)
    State.AutoAttack = on
    if on then
        startAutoAttack()
        notify("Auto Attack", "✅ Aktif! Menyerang musuh terdekat")
    else
        stopOrbit()  -- langsung hentikan orbit
        notify("Auto Attack", "❌ Nonaktif")
    end
end)

makeToggle("Auto Farm", "🌾", "Otomatis teleport ke musuh dalam range", function(on)
    State.AutoFarm = on
    if on then
        State.FarmOrigin = RootPart.Position -- anchor posisi saat ini
        startAutoFarm()
        notify("Auto Farm", "✅ Aktif! Range: " .. (State.FarmRange == 0 and "Unlimited" or State.FarmRange .. " studs"))
    else
        State.FarmOrigin = nil
        stopOrbit()  -- langsung hentikan orbit
        notify("Auto Farm", "❌ Nonaktif")
    end
end)

makeSlider("Farm Delay", "⏳", 0.1, 3.0, 0.5,
    function(v) return v .. "s" end,
    function(v) State.FarmDelay = v end
)

makeSlider("Farm Range", "📍", 0, 500, 150,
    function(v)
        if v == 0 then return "Unlimited" end
        return v .. " st"
    end,
    function(v)
        State.FarmRange = v
        if State.AutoFarm then
            State.FarmOrigin = RootPart.Position
        end
    end
)

makeSection("  💰  COLLECT")

makeToggle("Auto Collect", "💎", "Otomatis ambil drop & item di tanah", function(on)
    State.AutoCollect = on
    if on then
        startAutoCollect()
        notify("Auto Collect", "✅ Aktif!")
    else
        notify("Auto Collect", "❌ Nonaktif")
    end
end)

makeSection("  🏪  AUTO SELL (Lombart)")

-- ── INPUT NAMA NPC ──
local NpcLabel = Instance.new("TextLabel")
NpcLabel.Size = UDim2.new(1, 0, 0, 18)
NpcLabel.BackgroundTransparency = 1
NpcLabel.Text = "Nama NPC Merchant:"
NpcLabel.TextColor3 = Color3.fromRGB(180, 150, 255)
NpcLabel.TextSize = 11
NpcLabel.Font = Enum.Font.GothamBold
NpcLabel.TextXAlignment = Enum.TextXAlignment.Left
NpcLabel.Parent = ScrollFrame

local NpcInputRow = Instance.new("Frame")
NpcInputRow.Size = UDim2.new(1, 0, 0, 34)
NpcInputRow.BackgroundTransparency = 1
NpcInputRow.Parent = ScrollFrame
local NpcRowLayout = Instance.new("UIListLayout", NpcInputRow)
NpcRowLayout.FillDirection = Enum.FillDirection.Horizontal
NpcRowLayout.Padding = UDim.new(0.02, 0)

local NpcBox = Instance.new("TextBox")
NpcBox.Size = UDim2.new(0.68, 0, 1, 0)
NpcBox.BackgroundColor3 = Color3.fromRGB(20, 10, 45)
NpcBox.Text = ""
NpcBox.PlaceholderText = "Ketik nama NPC..."
NpcBox.PlaceholderColor3 = Color3.fromRGB(100, 80, 140)
NpcBox.TextColor3 = Color3.new(1,1,1)
NpcBox.TextSize = 11
NpcBox.Font = Enum.Font.Gotham
NpcBox.BorderSizePixel = 0
NpcBox.ClearTextOnFocus = false
NpcBox.Parent = NpcInputRow
Instance.new("UICorner", NpcBox).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", NpcBox).Color = Color3.fromRGB(100, 50, 200)

local NpcSetBtn = Instance.new("TextButton")
NpcSetBtn.Size = UDim2.new(0.28, 0, 1, 0)
NpcSetBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 200)
NpcSetBtn.Text = "✔ Set"
NpcSetBtn.TextColor3 = Color3.new(1,1,1)
NpcSetBtn.TextSize = 11
NpcSetBtn.Font = Enum.Font.GothamBold
NpcSetBtn.BorderSizePixel = 0
NpcSetBtn.Parent = NpcInputRow
Instance.new("UICorner", NpcSetBtn).CornerRadius = UDim.new(0, 8)
NpcSetBtn.MouseButton1Click:Connect(function()
    local name = NpcBox.Text
    if name and name ~= "" then
        State.MerchantName = name
        notify("🏪 NPC Set", "Merchant: " .. name)
    end
end)

-- Tombol scan semua NPC
local ScanNpcBtn = Instance.new("TextButton")
ScanNpcBtn.Size = UDim2.new(1, 0, 0, 30)
ScanNpcBtn.BackgroundColor3 = Color3.fromRGB(30, 60, 120)
ScanNpcBtn.Text = "🔍 Scan NPC (cek Output executor)"
ScanNpcBtn.TextColor3 = Color3.fromRGB(150, 200, 255)
ScanNpcBtn.TextSize = 11
ScanNpcBtn.Font = Enum.Font.GothamBold
ScanNpcBtn.BorderSizePixel = 0
ScanNpcBtn.Parent = ScrollFrame
Instance.new("UICorner", ScanNpcBtn).CornerRadius = UDim.new(0, 8)
ScanNpcBtn.MouseButton1Click:Connect(function()
    task.spawn(scanAllNPCNames)
end)

-- Rarity checkbox helper
local function makeRarityBtn(label, color, rarityKey)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0.48, 0, 0, 32)
    Btn.BackgroundColor3 = State.SellRarities[rarityKey] and color or Color3.fromRGB(40, 25, 60)
    Btn.Text = (State.SellRarities[rarityKey] and "✅ " or "⬜ ") .. label
    Btn.TextColor3 = Color3.new(1, 1, 1)
    Btn.TextSize = 11
    Btn.Font = Enum.Font.GothamBold
    Btn.BorderSizePixel = 0
    Btn.AutoButtonColor = false
    Btn.Parent = ScrollFrame
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 8)
    local Stroke = Instance.new("UIStroke", Btn)
    Stroke.Color = color
    Stroke.Thickness = 1

    Btn.MouseButton1Click:Connect(function()
        State.SellRarities[rarityKey] = not State.SellRarities[rarityKey]
        local on = State.SellRarities[rarityKey]
        Btn.BackgroundColor3 = on and color or Color3.fromRGB(40, 25, 60)
        Btn.Text = (on and "✅ " or "⬜ ") .. label
    end)
    return Btn
end

-- Row 1: Common + Uncommon
local RarRow1 = Instance.new("Frame")
RarRow1.Size = UDim2.new(1, 0, 0, 32)
RarRow1.BackgroundTransparency = 1
RarRow1.Parent = ScrollFrame
local RL1 = Instance.new("UIListLayout", RarRow1)
RL1.FillDirection = Enum.FillDirection.Horizontal
RL1.Padding = UDim.new(0.04, 0)

local function makeRarBtn2(label, color, key)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0.48, 0, 1, 0)
    Btn.BackgroundColor3 = State.SellRarities[key] and color or Color3.fromRGB(40, 25, 60)
    Btn.Text = (State.SellRarities[key] and "✅ " or "⬜ ") .. label
    Btn.TextColor3 = Color3.new(1,1,1)
    Btn.TextSize = 11
    Btn.Font = Enum.Font.GothamBold
    Btn.BorderSizePixel = 0
    Btn.AutoButtonColor = false
    Btn.Parent = RarRow1
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", Btn).Color = color
    Btn.MouseButton1Click:Connect(function()
        State.SellRarities[key] = not State.SellRarities[key]
        local on = State.SellRarities[key]
        Btn.BackgroundColor3 = on and color or Color3.fromRGB(40, 25, 60)
        Btn.Text = (on and "✅ " or "⬜ ") .. label
    end)
end
makeRarBtn2("Common", Color3.fromRGB(150, 150, 150), "Common")
makeRarBtn2("Uncommon", Color3.fromRGB(80, 200, 80), "Uncommon")

-- Row 2: Rare + Epic
local RarRow2 = Instance.new("Frame")
RarRow2.Size = UDim2.new(1, 0, 0, 32)
RarRow2.BackgroundTransparency = 1
RarRow2.Parent = ScrollFrame
local RL2 = Instance.new("UIListLayout", RarRow2)
RL2.FillDirection = Enum.FillDirection.Horizontal
RL2.Padding = UDim.new(0.04, 0)

local function makeRarBtn3(label, color, key)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0.48, 0, 1, 0)
    Btn.BackgroundColor3 = State.SellRarities[key] and color or Color3.fromRGB(40, 25, 60)
    Btn.Text = (State.SellRarities[key] and "✅ " or "⬜ ") .. label
    Btn.TextColor3 = Color3.new(1,1,1)
    Btn.TextSize = 11
    Btn.Font = Enum.Font.GothamBold
    Btn.BorderSizePixel = 0
    Btn.AutoButtonColor = false
    Btn.Parent = RarRow2
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", Btn).Color = color
    Btn.MouseButton1Click:Connect(function()
        State.SellRarities[key] = not State.SellRarities[key]
        local on = State.SellRarities[key]
        Btn.BackgroundColor3 = on and color or Color3.fromRGB(40, 25, 60)
        Btn.Text = (on and "✅ " or "⬜ ") .. label
    end)
end
makeRarBtn3("Rare", Color3.fromRGB(60, 120, 255), "Rare")
makeRarBtn3("Epic", Color3.fromRGB(160, 50, 220), "Epic")

-- Row 3: Legendary (full width)
local LegBtn = Instance.new("TextButton")
LegBtn.Size = UDim2.new(1, 0, 0, 32)
LegBtn.BackgroundColor3 = State.SellRarities.Legendary and Color3.fromRGB(255, 165, 0) or Color3.fromRGB(40, 25, 60)
LegBtn.Text = (State.SellRarities.Legendary and "✅ " or "⬜ ") .. "Legendary"
LegBtn.TextColor3 = Color3.new(1,1,1)
LegBtn.TextSize = 11
LegBtn.Font = Enum.Font.GothamBold
LegBtn.BorderSizePixel = 0
LegBtn.AutoButtonColor = false
LegBtn.Parent = ScrollFrame
Instance.new("UICorner", LegBtn).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", LegBtn).Color = Color3.fromRGB(255, 165, 0)
LegBtn.MouseButton1Click:Connect(function()
    State.SellRarities.Legendary = not State.SellRarities.Legendary
    local on = State.SellRarities.Legendary
    LegBtn.BackgroundColor3 = on and Color3.fromRGB(255, 165, 0) or Color3.fromRGB(40, 25, 60)
    LegBtn.Text = (on and "✅ " or "⬜ ") .. "Legendary"
end)

-- Tombol Sell Now
local SellNowBtn = Instance.new("TextButton")
SellNowBtn.Size = UDim2.new(1, 0, 0, 34)
SellNowBtn.BackgroundColor3 = Color3.fromRGB(200, 120, 20)
SellNowBtn.Text = "💰 Sell Now (Teleport ke NPC)"
SellNowBtn.TextColor3 = Color3.new(1,1,1)
SellNowBtn.TextSize = 11
SellNowBtn.Font = Enum.Font.GothamBold
SellNowBtn.BorderSizePixel = 0
SellNowBtn.Parent = ScrollFrame
Instance.new("UICorner", SellNowBtn).CornerRadius = UDim.new(0, 8)
SellNowBtn.MouseButton1Click:Connect(function()
    SellNowBtn.Text = "⏳ Menjual..."
    task.spawn(function()
        local sold = sellInventory()
        SellNowBtn.Text = "💰 Sell Now (Teleport ke NPC)"
        notify("🏪 Auto Sell", "Selesai! " .. sold .. " item dijual")
    end)
end)

-- ── STATUS REMOTE SPY ──
local SpyStatusLabel = Instance.new("TextLabel")
SpyStatusLabel.Size = UDim2.new(1, 0, 0, 20)
SpyStatusLabel.BackgroundTransparency = 1
SpyStatusLabel.Text = "🔴 Remote Spy: Belum capture (jual manual 1x dulu)"
SpyStatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
SpyStatusLabel.TextSize = 10
SpyStatusLabel.Font = Enum.Font.Gotham
SpyStatusLabel.TextWrapped = true
SpyStatusLabel.Parent = ScrollFrame

-- Update status label setiap 2 detik
task.spawn(function()
    while true do
        task.wait(2)
        if cachedSellRemote then
            SpyStatusLabel.Text = "🟢 Remote Spy: " .. cachedSellRemote.Name .. " (siap bypass!)"
            SpyStatusLabel.TextColor3 = Color3.fromRGB(80, 220, 80)
        else
            SpyStatusLabel.Text = "🔴 Remote Spy: Belum capture (jual manual 1x dulu)"
            SpyStatusLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        end
    end
end)

-- ── BYPASS SELL (Tanpa ke NPC) ──
local BypassBtn = Instance.new("TextButton")
BypassBtn.Size = UDim2.new(1, 0, 0, 34)
BypassBtn.BackgroundColor3 = Color3.fromRGB(20, 140, 80)
BypassBtn.Text = "⚡ Bypass Sell (Tanpa ke NPC)"
BypassBtn.TextColor3 = Color3.new(1,1,1)
BypassBtn.TextSize = 11
BypassBtn.Font = Enum.Font.GothamBold
BypassBtn.BorderSizePixel = 0
BypassBtn.Parent = ScrollFrame
Instance.new("UICorner", BypassBtn).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", BypassBtn).Color = Color3.fromRGB(0, 220, 100)
BypassBtn.MouseButton1Click:Connect(function()
    BypassBtn.Text = "⏳ Bypass..."
    task.spawn(function()
        local count = 0
        -- Pakai cached remote jika sudah ter-capture
        if cachedSellRemote then
            pcall(function() cachedSellRemote:FireServer(table.unpack(cachedSellArgs or {})) end)
            pcall(function() cachedSellRemote:FireServer() end)
            -- Fire dengan setiap rarity
            for rarity, on in pairs(State.SellRarities) do
                if on then
                    pcall(function() cachedSellRemote:FireServer(rarity) end)
                    pcall(function() cachedSellRemote:FireServer(rarity:lower()) end)
                    count = count + 1
                end
            end
            notify("⚡ Bypass Sell", "Remote fired! " .. count .. " rarity")
        else
            -- Scan semua sell remote dan fire
            for _, remote in ipairs(game:GetDescendants()) do
                if remote:IsA("RemoteEvent") then
                    local n = remote.Name:lower()
                    if n:find("sell") or n:find("shop") or n:find("trade") then
                        pcall(function() remote:FireServer() end)
                        for rarity, on in pairs(State.SellRarities) do
                            if on then
                                pcall(function() remote:FireServer(rarity) end)
                                pcall(function() remote:FireServer(rarity:lower()) end)
                                count = count + 1
                            end
                        end
                    end
                end
            end
            notify("⚡ Bypass Sell", "Brute-force " .. count .. " remote fired")
        end
        BypassBtn.Text = "⚡ Bypass Sell (Tanpa ke NPC)"
    end)
end)

makeToggle("Auto Sell", "💰", "Jual item setiap 10 detik ke Lombart", function(on)
    State.AutoSell = on
    if on then
        startAutoSell()
        notify("Auto Sell", "✅ Aktif! Jual setiap 10 detik")
    else
        notify("Auto Sell", "❌ Nonaktif")
    end
end)


makeSection("  🔁  MISC")

-- ── SCAN NPC MERCHANT ──
local ScanNpcBtn2 = Instance.new("TextButton")
ScanNpcBtn2.Size = UDim2.new(1, 0, 0, 32)
ScanNpcBtn2.BackgroundColor3 = Color3.fromRGB(30, 60, 120)
ScanNpcBtn2.Text = "🔍 Scan Nama NPC di Map"
ScanNpcBtn2.TextColor3 = Color3.fromRGB(150, 200, 255)
ScanNpcBtn2.TextSize = 12
ScanNpcBtn2.Font = Enum.Font.GothamBold
ScanNpcBtn2.BorderSizePixel = 0
ScanNpcBtn2.Parent = ScrollFrame
Instance.new("UICorner", ScanNpcBtn2).CornerRadius = UDim.new(0, 8)
ScanNpcBtn2.MouseButton1Click:Connect(function()
    -- Print semua NPC ke Output
    local found = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj ~= Character then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            local isPlayer = false
            for _, p in ipairs(Players:GetPlayers()) do
                if p.Character == obj then isPlayer = true; break end
            end
            if not isPlayer and hum then table.insert(found, obj.Name) end
        end
    end
    print("[WA] === LIST NPC ===")
    for _, n in ipairs(found) do print("[NPC] " .. n) end
    notify("🔍 NPC Scan", #found .. " NPC — cek Output executor!")
end)

makeToggle("Anti AFK", "🛡️", "Mencegah kick karena tidak aktif", function(on)
    if on then
        State._afkConn = RunService.Heartbeat:Connect(function()
            LocalPlayer:Move(Vector3.new(0, 0, 0))
        end)
        -- Fake input to bypass AFK detection
        local VIM = game:GetService("VirtualInputManager")
        task.spawn(function()
            while State._afkOn do
                pcall(function()
                    VIM:SendKeyEvent(true, Enum.KeyCode.W, false, nil)
                    task.wait(0.1)
                    VIM:SendKeyEvent(false, Enum.KeyCode.W, false, nil)
                end)
                task.wait(60)
            end
        end)
        State._afkOn = true
        notify("Anti AFK", "✅ Aktif!")
    else
        State._afkOn = false
        if State._afkConn then State._afkConn:Disconnect() end
        notify("Anti AFK", "❌ Nonaktif")
    end
end)

makeToggle("Auto Rebirth", "⬆️", "Rebirth otomatis saat tersedia", function(on)
    State.AutoRebirth = on
    if on then
        task.spawn(function()
            while State.AutoRebirth do
                -- Cari tombol rebirth di GUI player
                for _, gui in ipairs(LocalPlayer.PlayerGui:GetDescendants()) do
                    if gui:IsA("TextButton") or gui:IsA("ImageButton") then
                        local n = gui.Name:lower() .. (gui:IsA("TextButton") and gui.Text:lower() or "")
                        if n:find("rebirth") or n:find("prestige") or n:find("ascend") then
                            -- Cek apakah rebirth tersedia (tidak di-disable)
                            if gui.Active and gui.Visible then
                                local conn = gui.MouseButton1Click
                                pcall(function()
                                    for _, c in ipairs(getconnections(conn)) do
                                        c:Fire()
                                    end
                                end)
                                task.wait(1)
                            end
                        end
                    end
                end
                task.wait(3)
            end
        end)
        notify("Auto Rebirth", "✅ Aktif!")
    else
        notify("Auto Rebirth", "❌ Nonaktif")
    end
end)

makeSection("  📍  TELEPORT")

-- ── PLAYER LIST BUILDER ──
local PlayerListFrame = Instance.new("Frame")
PlayerListFrame.Size = UDim2.new(1, 0, 0, 0) -- auto height via layout
PlayerListFrame.BackgroundTransparency = 1
PlayerListFrame.AutomaticSize = Enum.AutomaticSize.Y
PlayerListFrame.Parent = ScrollFrame

local PlayerLayout = Instance.new("UIListLayout", PlayerListFrame)
PlayerLayout.Padding = UDim.new(0, 4)
PlayerLayout.FillDirection = Enum.FillDirection.Vertical

local function makePlayerButton(player)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, 0, 0, 38)
    Row.BackgroundColor3 = Color3.fromRGB(25, 15, 55)
    Row.BorderSizePixel = 0
    Row.Parent = PlayerListFrame
    Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", Row).Color = Color3.fromRGB(80, 40, 160)

    local NameL = Instance.new("TextLabel")
    NameL.Size = UDim2.new(1, -90, 1, 0)
    NameL.Position = UDim2.new(0, 10, 0, 0)
    NameL.BackgroundTransparency = 1
    NameL.Text = "👤 " .. player.Name
    NameL.TextColor3 = Color3.fromRGB(220, 200, 255)
    NameL.TextSize = 12
    NameL.Font = Enum.Font.Gotham
    NameL.TextXAlignment = Enum.TextXAlignment.Left
    NameL.Parent = Row

    local TpBtn = Instance.new("TextButton")
    TpBtn.Size = UDim2.new(0, 70, 0, 26)
    TpBtn.Position = UDim2.new(1, -78, 0.5, -13)
    TpBtn.BackgroundColor3 = Color3.fromRGB(100, 50, 200)
    TpBtn.Text = "Teleport"
    TpBtn.TextColor3 = Color3.new(1,1,1)
    TpBtn.TextSize = 11
    TpBtn.Font = Enum.Font.GothamBold
    TpBtn.BorderSizePixel = 0
    TpBtn.Parent = Row
    Instance.new("UICorner", TpBtn).CornerRadius = UDim.new(0, 6)

    TpBtn.MouseButton1Click:Connect(function()
        local char = player.Character
        if char then
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                RootPart.CFrame = CFrame.new(root.Position + Vector3.new(2, 0, 2))
                notify("📍 Teleport", "Teleport ke " .. player.Name)
            end
        else
            notify("⚠️", player.Name .. " tidak punya karakter")
        end
    end)

    return Row
end

local function refreshPlayerList()
    for _, child in ipairs(PlayerListFrame:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            makePlayerButton(p)
        end
    end
    if #Players:GetPlayers() <= 1 then
        local noP = Instance.new("TextLabel")
        noP.Size = UDim2.new(1, 0, 0, 30)
        noP.BackgroundTransparency = 1
        noP.Text = "Tidak ada player lain di server"
        noP.TextColor3 = Color3.fromRGB(140, 120, 180)
        noP.TextSize = 11
        noP.Font = Enum.Font.Gotham
        noP.Parent = PlayerListFrame
    end
end

refreshPlayerList()
Players.PlayerAdded:Connect(refreshPlayerList)
Players.PlayerRemoving:Connect(function() task.wait(0.1) refreshPlayerList() end)

-- Refresh button
local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Size = UDim2.new(1, 0, 0, 30)
RefreshBtn.BackgroundColor3 = Color3.fromRGB(40, 20, 80)
RefreshBtn.Text = "🔄 Refresh Player List"
RefreshBtn.TextColor3 = Color3.fromRGB(200, 160, 255)
RefreshBtn.TextSize = 12
RefreshBtn.Font = Enum.Font.GothamBold
RefreshBtn.BorderSizePixel = 0
RefreshBtn.Parent = ScrollFrame
Instance.new("UICorner", RefreshBtn).CornerRadius = UDim.new(0, 8)
RefreshBtn.MouseButton1Click:Connect(refreshPlayerList)

-- ── EGG / BOSS DETECTOR ──
makeSection("  🥚  EGG / BOSS DETECTOR")

local EggListFrame = Instance.new("Frame")
EggListFrame.Size = UDim2.new(1, 0, 0, 0)
EggListFrame.BackgroundTransparency = 1
EggListFrame.AutomaticSize = Enum.AutomaticSize.Y
EggListFrame.Parent = ScrollFrame
local EggLayout = Instance.new("UIListLayout", EggListFrame)
EggLayout.Padding = UDim.new(0, 4)

local function scanEggsAndBosses()
    local results = {}
    local EGG_KEYWORDS = {"egg", "boss", "giant", "mega", "super", "king", "queen", "elder", "ancient", "legendary", "rare"}
    local MIN_HP = 50000 -- threshold HP tinggi = egg/boss

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Humanoid") then
            local model = obj.Parent
            if model and model ~= Character then
                -- Cek apakah player
                local isPlayer = false
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.Character == model then isPlayer = true; break end
                end
                if not isPlayer then
                    local maxHp = obj.MaxHealth
                    local nameLower = model.Name:lower()
                    local isEgg = maxHp >= MIN_HP
                    -- Juga cek keyword nama
                    if not isEgg then
                        for _, kw in ipairs(EGG_KEYWORDS) do
                            if nameLower:find(kw, 1, true) then isEgg = true; break end
                        end
                    end
                    if isEgg and obj.Health > 0 then
                        local root = model:FindFirstChild("HumanoidRootPart")
                            or model:FindFirstChild("Torso") or model.PrimaryPart
                        if root then
                            table.insert(results, {
                                model = model,
                                root = root,
                                name = model.Name,
                                hp = obj.Health,
                                maxHp = maxHp,
                            })
                        end
                    end
                end
            end
        end
    end
    -- Sort by maxHp descending (paling besar dulu)
    table.sort(results, function(a, b) return a.maxHp > b.maxHp end)
    return results
end

local function makeEggButton(data)
    local Row = Instance.new("Frame")
    Row.Size = UDim2.new(1, 0, 0, 50)
    Row.BackgroundColor3 = Color3.fromRGB(30, 10, 50)
    Row.BorderSizePixel = 0
    Row.Parent = EggListFrame
    Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 8)
    local RS = Instance.new("UIStroke", Row)
    RS.Color = Color3.fromRGB(200, 100, 50)
    RS.Thickness = 1

    local NameL = Instance.new("TextLabel")
    NameL.Size = UDim2.new(1, -90, 0, 20)
    NameL.Position = UDim2.new(0, 10, 0, 6)
    NameL.BackgroundTransparency = 1
    NameL.Text = "🥚 " .. data.name
    NameL.TextColor3 = Color3.fromRGB(255, 200, 100)
    NameL.TextSize = 12
    NameL.Font = Enum.Font.GothamBold
    NameL.TextXAlignment = Enum.TextXAlignment.Left
    NameL.Parent = Row

    local HpL = Instance.new("TextLabel")
    HpL.Size = UDim2.new(1, -90, 0, 16)
    HpL.Position = UDim2.new(0, 10, 0, 28)
    HpL.BackgroundTransparency = 1
    HpL.Text = string.format("HP: %d / %d", math.floor(data.hp), math.floor(data.maxHp))
    HpL.TextColor3 = Color3.fromRGB(200, 150, 80)
    HpL.TextSize = 10
    HpL.Font = Enum.Font.Gotham
    HpL.TextXAlignment = Enum.TextXAlignment.Left
    HpL.Parent = Row

    local TpBtn = Instance.new("TextButton")
    TpBtn.Size = UDim2.new(0, 70, 0, 32)
    TpBtn.Position = UDim2.new(1, -78, 0.5, -16)
    TpBtn.BackgroundColor3 = Color3.fromRGB(180, 80, 20)
    TpBtn.Text = "Farm🔥"
    TpBtn.TextColor3 = Color3.new(1,1,1)
    TpBtn.TextSize = 11
    TpBtn.Font = Enum.Font.GothamBold
    TpBtn.BorderSizePixel = 0
    TpBtn.Parent = Row
    Instance.new("UICorner", TpBtn).CornerRadius = UDim.new(0, 6)

    TpBtn.MouseButton1Click:Connect(function()
        local model = data.model
        if not model or not model.Parent then
            notify("⚠️", data.name .. " sudah mati")
            return
        end
        local root = model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Torso") or model.PrimaryPart
        if root then
            -- Teleport dan mulai serang
            RootPart.CFrame = CFrame.new(root.Position + Vector3.new(0, 3, 3))
            notify("🥚 Farm Egg", "Farming " .. data.name .. " (" .. math.floor(data.maxHp) .. " HP)")
            -- Kill loop khusus egg
            task.spawn(function()
                local hum = model:FindFirstChild("Humanoid")
                local timeout = tick() + 60
                while hum and hum.Health > 0 and tick() < timeout do
                    local r = model:FindFirstChild("HumanoidRootPart")
                        or model:FindFirstChild("Torso") or model.PrimaryPart
                    if r then
                        RootPart.CFrame = CFrame.new(r.Position + Vector3.new(0, 3, 3))
                        RootPart.CFrame = CFrame.lookAt(RootPart.Position, r.Position)
                    end
                    pcall(function() fireToolActivated(r and r.Position) end)
                    task.wait(0.06)
                end
                notify("✅ Egg Selesai", data.name .. " telah dikalahkan!")
            end)
        end
    end)

    return Row
end

local function refreshEggList()
    for _, child in ipairs(EggListFrame:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end
    local eggs = scanEggsAndBosses()
    if #eggs == 0 then
        local noEgg = Instance.new("TextLabel")
        noEgg.Size = UDim2.new(1, 0, 0, 30)
        noEgg.BackgroundTransparency = 1
        noEgg.Text = "Tidak ada egg/boss ditemukan"
        noEgg.TextColor3 = Color3.fromRGB(140, 120, 180)
        noEgg.TextSize = 11
        noEgg.Font = Enum.Font.Gotham
        noEgg.Parent = EggListFrame
    else
        for _, data in ipairs(eggs) do
            makeEggButton(data)
        end
    end
    notify("🥚 Egg Detector", "Ditemukan " .. #eggs .. " egg/boss di map")
end

local RefreshEggBtn = Instance.new("TextButton")
RefreshEggBtn.Size = UDim2.new(1, 0, 0, 30)
RefreshEggBtn.BackgroundColor3 = Color3.fromRGB(60, 25, 10)
RefreshEggBtn.Text = "🔍 Scan Egg & Boss"
RefreshEggBtn.TextColor3 = Color3.fromRGB(255, 180, 80)
RefreshEggBtn.TextSize = 12
RefreshEggBtn.Font = Enum.Font.GothamBold
RefreshEggBtn.BorderSizePixel = 0
RefreshEggBtn.Parent = ScrollFrame
Instance.new("UICorner", RefreshEggBtn).CornerRadius = UDim.new(0, 8)
RefreshEggBtn.MouseButton1Click:Connect(refreshEggList)

-- ── DRAGGABLE LOGIC ──
local dragging, dragStart, startPos = false, nil, nil
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
    end
end)
TitleBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- ── MINIMIZE LOGIC ──
local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        tween(MainFrame, {Size = UDim2.new(0, 320, 0, 50)})
        MinBtn.Text = "+"
    else
        tween(MainFrame, {Size = UDim2.new(0, 320, 0, 600)})
        MinBtn.Text = "-"
    end
end)

-- ── OPENING ANIMATION ──
MainFrame.Size = UDim2.new(0, 0, 0, 0)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
tween(MainFrame, {
    Size = UDim2.new(0, 320, 0, 600),
    Position = UDim2.new(0.5, -160, 0.5, -300)
}, 0.5)

notify("⚗️ Wizard Alchemy Hub", "Script berhasil diload! v2.0")
print("[WA Hub] v2.0 loaded | Teleport Player + Egg Detector + Remote Spy")
