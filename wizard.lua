-- ================================================
-- WIZARD ALCHEMY HUB v3.0 | CLEAN BUILD
-- Fitur: Auto Farm, Instant Kill, Auto R+E, Auto Respawn
-- ================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")

local LP = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()
local Hum = Char:WaitForChild("Humanoid")
local Root = Char:WaitForChild("HumanoidRootPart")

local S = {
    AutoFarm=false, AutoSkill=false,
    AutoRespawn=false, FarmRange=150, FarmDelay=0.3,
    OrbitRadius=4, OrbitSpeed=120, AttackRate=0.1,
    FarmOrigin=nil, LastPos=nil,
    TargetHPMin=120, TargetHPMax=300, -- hanya serang mob MaxHP 120-300
}

-- Save position history (rolling 1 menit)
local posHistory = {}
local POS_INTERVAL = 5 -- simpan setiap 5 detik
local POS_MAX = 12 -- 12 x 5 detik = 60 detik (1 menit)
task.spawn(function()
    while true do
        task.wait(POS_INTERVAL)
        if Root and Root.Parent and Hum and Hum.Health > 0 then
            table.insert(posHistory, Root.Position)
            if #posHistory > POS_MAX then table.remove(posHistory, 1) end
            S.LastPos = posHistory[1] -- posisi paling lama (1 menit lalu)
        end
    end
end)

local function notify(t,m)
    game:GetService("StarterGui"):SetCore("SendNotification",{Title=t,Text=m,Duration=3})
end

-- Respawn + auto equip + teleport balik
LP.CharacterAdded:Connect(function(c)
    Char=c; Hum=c:WaitForChild("Humanoid"); Root=c:WaitForChild("HumanoidRootPart")
    if S.AutoRespawn then
        local savedPos = S.LastPos
        task.wait(5) -- tunggu game selesai respawn
        -- 1. Teleport balik (retry 5x supaya pasti nyampe)
        if savedPos then
            task.spawn(function()
                for i=1,5 do
                    task.wait(1)
                    pcall(function()
                        if Root and Root.Parent then
                            Root.CFrame = CFrame.new(savedPos + Vector3.new(0,3,0))
                        end
                    end)
                end
                -- 2. Equip senjata (tekan 1, sekali saja)
                task.wait(0.5)
                pcall(function()
                    VIM:SendKeyEvent(true, Enum.KeyCode.One, false, game)
                    task.wait(0.1)
                    VIM:SendKeyEvent(false, Enum.KeyCode.One, false, game)
                end)
                notify("Respawn","Kembali + equip senjata!")
            end)
        end
    end
end)

local function tw(obj,props,t)
    TweenService:Create(obj,TweenInfo.new(t or 0.3,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),props):Play()
end

-- ========================
-- ENEMY SCANNER
-- ========================
local BLACKLIST = {
    -- English NPC names
    "wizard robe","robe","apprentice","shop","merchant","vendor","trader",
    "buy wizard","buy","wizard",
    "quest","dialog","dialogue","friendly","civilian","keeper","banker",
    "guide","neutral","villager","dummy","tutorial","innkeeper","blacksmith",
    "tailor","instructor","mayor","noble","citizen","townsfolk","npc",
    "seller","dealer","master","elder","sage","healer","priest",
    "alchemist","potion","cauldron","table","station","forge","anvil",
    -- Chinese NPC names (Wizard Alchemy specific)
    "隆巴特","商人","店主","炼金","对话","任务","向导","村民",
    "哈利因特","莱敏","罗杰","矿工","猎魔人","逃出","兽人",
    -- Game-specific NPC & display models
    "harryint","rank_","rig","npc1","npc2","npc3","npc4",
    "blueberrybush","blueberry","bird nest","bird","nest","bush","mushroom",
}

-- Folder yang berisi NPC damai (SKIP)
local FRIENDLY_FOLDERS = {
    "npcs","friendlynpcs","townnpcs","shopnpcs","vendors",
    "merchants","questnpcs","dialognpcs","civilians",
}

local function isEnemy(model)
    if model == Char then return false end
    -- Skip player characters
    for _,p in ipairs(Players:GetPlayers()) do if p.Character==model then return false end end
    -- Blacklist nama
    local n = model.Name:lower()
    for _,kw in ipairs(BLACKLIST) do if n:find(kw,1,true) then return false end end
    -- Skip model tanpa nama atau nama terlalu pendek
    if n=="" or #model.Name<=1 then return false end
    -- Blacklist folder parent
    if model.Parent and model.Parent:IsA("Folder") then
        local pn = model.Parent.Name:lower()
        for _,fn in ipairs(FRIENDLY_FOLDERS) do if pn==fn or pn:find(fn,1,true) then return false end end
    end
    -- Health check
    local h = model:FindFirstChild("Humanoid")
    if not h or h.Health<=0 or h.MaxHealth<=0 or h.MaxHealth==math.huge then return false end
    -- Skip NPC statis (WalkSpeed=0 = tidak jalan = bukan musuh)
    if h.WalkSpeed==0 then return false end
    return true
end

local function scanMobs()
    local mobs,seen = {},{}
    -- Scan SEMUA Humanoid di workspace (tidak terbatas folder tertentu)
    for _,obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Health > 0 and obj.MaxHealth > 0 and obj.MaxHealth ~= math.huge then
            local m = obj.Parent
            if m and m:IsA("Model") and not seen[m] and m ~= Char then
                -- Skip player characters
                local isPlayer = false
                for _,p in ipairs(Players:GetPlayers()) do if p.Character==m then isPlayer=true; break end end
                -- Skip NPC statis (WalkSpeed=0)
                if not isPlayer and obj.WalkSpeed > 0 then
                    -- Blacklist check
                    local n = m.Name:lower()
                    local blocked = false
                    for _,kw in ipairs(BLACKLIST) do if n:find(kw,1,true) then blocked=true; break end end
                    if not blocked and #m.Name > 1 then
                        -- Filter HP: hanya target mob dalam range
                        local hpMatch = (obj.MaxHealth >= S.TargetHPMin and obj.MaxHealth <= S.TargetHPMax)
                        if hpMatch then
                        local r = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso") or m.PrimaryPart
                        if r then
                            table.insert(mobs,{model=m,root=r,hp=obj.MaxHealth,dist=(Root.Position-r.Position).Magnitude})
                            seen[m]=true
                        end
                        end
                    end
                end
            end
        end
    end
    -- Sort: HP tertinggi duluan (boss/elite prioritas)
    table.sort(mobs,function(a,b) return a.hp > b.hp end)
    if S.FarmRange>0 and S.FarmOrigin then
        local f={}
        for _,m in ipairs(mobs) do if (S.FarmOrigin-m.root.Position).Magnitude<=S.FarmRange then table.insert(f,m) end end
        return f
    end
    return mobs
end

-- ========================
-- ========================
-- ATTACK SYSTEM (Wizard Alchemy specific)
-- ========================
local attackRemotes = {}
local allRemotes = {}
local mainRemote = nil -- RemoteEvent.RemoteEvent (generic remote)
local deriveSkill = nil
local releaseGroupSkill = nil

-- Scan semua remote
task.spawn(function()
    for _,remote in ipairs(RS:GetDescendants()) do
        if remote:IsA("RemoteEvent") then
            table.insert(allRemotes, remote)
            local n = remote.Name
            -- Cari remote spesifik Wizard Alchemy
            if n == "RemoteEvent" and remote.Parent and remote.Parent.Name == "RemoteEvent" then
                mainRemote = remote
                print("[WA] Main remote: " .. remote:GetFullName())
            elseif n == "DeriveSkill" then
                deriveSkill = remote
                print("[WA] DeriveSkill: " .. remote:GetFullName())
            elseif n == "ReleaseGroupSkill" then
                releaseGroupSkill = remote
                print("[WA] ReleaseGroupSkill: " .. remote:GetFullName())
            end
            -- Tetap collect semua skill/damage remote
            local nl = n:lower()
            if nl:find("skill") or nl:find("damage") or nl:find("attack") or nl:find("hit") then
                table.insert(attackRemotes, remote)
            end
        end
    end
    print("[WA] Attack remotes: " .. #attackRemotes .. " | Total: " .. #allRemotes)
end)

local function scanAllRemotes()
    print("=== ALL REMOTE EVENTS ===")
    for _,remote in ipairs(allRemotes) do
        print("  " .. remote:GetFullName())
    end
    print("=== END (" .. #allRemotes .. " total) ===")
end

local function pressKey(key)
    pcall(function() VIM:SendKeyEvent(true,key,false,game); task.wait(0.05); VIM:SendKeyEvent(false,key,false,game) end)
end

local function fireAttack(target)
    local tool = Char:FindFirstChildOfClass("Tool")

    local targetRoot = nil
    if target then
        targetRoot = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso") or target.PrimaryPart
    end

    -- 1. Tool activate
    if tool then pcall(function() tool:Activate() end) end
    -- 2. getconnections (trigger tool LocalScript tanpa mouse)
    if tool then pcall(function() for _,c in ipairs(getconnections(tool.Activated)) do c:Fire() end end) end

    -- 3. Fire main remote dengan berbagai argumen (game mungkin butuh target info)
    if mainRemote and targetRoot then
        pcall(function() mainRemote:FireServer(targetRoot.CFrame) end)
        pcall(function() mainRemote:FireServer(targetRoot.Position) end)
        pcall(function() mainRemote:FireServer(target) end)
        pcall(function() mainRemote:FireServer() end)
    end

    -- 4. Fire DeriveSkill
    if deriveSkill then pcall(function() deriveSkill:FireServer() end) end

    -- 5. firetouchinterest (simulasi sentuh fisik — ZERO mouse)
    if targetRoot and Root then
        pcall(function()
            firetouchinterest(Root, targetRoot, 0)
            task.wait(0.05)
            firetouchinterest(Root, targetRoot, 1)
        end)
    end
end

-- ========================
-- ORBIT + KILL
-- ========================
local orbitConn, orbitActive = nil, false
local mouseHeld = false

local function releaseMouseHold()
    if mouseHeld then
        pcall(function()
            local vp = workspace.CurrentCamera.ViewportSize
            VIM:SendMouseButtonEvent(vp.X/2, vp.Y/2, 0, false, game, 1) -- release
        end)
        mouseHeld = false
    end
end

local function startMouseHold()
    if not mouseHeld then
        pcall(function()
            local vp = workspace.CurrentCamera.ViewportSize
            VIM:SendMouseButtonEvent(vp.X/2, vp.Y/2, 0, true, game, 1) -- hold down
        end)
        mouseHeld = true
    end
end

local function stopOrbit()
    orbitActive=false
    releaseMouseHold() -- lepas mouse saat orbit berhenti
    if orbitConn then orbitConn:Disconnect(); orbitConn=nil end
end

local function orbitKill(enemy)
    if not enemy or not enemy.Parent then return end
    local h=enemy:FindFirstChild("Humanoid")
    if not h or h.Health<=0 then return end
    print("[WA] Target: " .. enemy.Name .. " | HP: " .. h.Health .. "/" .. h.MaxHealth .. " | Speed: " .. h.WalkSpeed)
    stopOrbit(); orbitActive=true
    startMouseHold() -- tekan mouse 1x (hold)
    local angle,lastAtk=0,0
    orbitConn = RunService.Heartbeat:Connect(function(dt)
        if not orbitActive or not S.AutoFarm then orbitActive=false; return end
        if not enemy or not enemy.Parent then orbitActive=false; return end
        local hm=enemy:FindFirstChild("Humanoid")
        if not hm or hm.Health<=0 then orbitActive=false; return end
        local r=enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso") or enemy.PrimaryPart
        if not r then return end
        angle=(angle+S.OrbitSpeed*dt)%360
        local rad=math.rad(angle)
        pcall(function() Root.CFrame=CFrame.lookAt(Vector3.new(r.Position.X+math.cos(rad)*S.OrbitRadius,r.Position.Y+3,r.Position.Z+math.sin(rad)*S.OrbitRadius),r.Position) end)
        local now=tick()
        if now-lastAtk>=S.AttackRate then
            lastAtk=now
            pcall(function() fireAttack(enemy) end)
            if S.AutoSkill then pressKey(Enum.KeyCode.R); pressKey(Enum.KeyCode.E) end
        end
    end)
    while orbitActive do task.wait(0.1) end
    stopOrbit() -- lepas mouse otomatis
end

-- ========================
-- FARM LOOPS
-- ========================

local function startAutoFarm()
    task.spawn(function()
        while S.AutoFarm do
            local mobs=scanMobs()
            if #mobs==0 then stopOrbit(); task.wait(1) else
                -- Ambil mob HP tertinggi (index 1 karena sudah sorted desc)
                local m = mobs[1]
                if m.model and m.model.Parent then
                    local h=m.model:FindFirstChild("Humanoid")
                    if h and h.Health>0 then
                        print(string.format("[Farm] Target: %s | MaxHP: %s | HP: %s/%s",
                            m.model.Name, tostring(m.hp), tostring(math.floor(h.Health)), tostring(math.floor(h.MaxHealth))))
                        pcall(function() orbitKill(m.model) end)
                    end
                end; task.wait(S.FarmDelay)
            end; task.wait(0.2)
        end; stopOrbit()
    end)
end

-- ========================
-- GUI
-- ========================
local SG = Instance.new("ScreenGui")
SG.Name="WAHub"; SG.ResetOnSpawn=false; SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
if syn and syn.protect_gui then syn.protect_gui(SG); SG.Parent=game:GetService("CoreGui")
elseif gethui then SG.Parent=gethui() else SG.Parent=LP.PlayerGui end

local MF = Instance.new("Frame")
MF.Name="Main"; MF.Size=UDim2.new(0,300,0,500); MF.Position=UDim2.new(0.5,-150,0.5,-250)
MF.BackgroundColor3=Color3.fromRGB(10,10,22); MF.BorderSizePixel=0; MF.ClipsDescendants=true; MF.Parent=SG
Instance.new("UICorner",MF).CornerRadius=UDim.new(0,12)
local gg=Instance.new("UIGradient",MF)
gg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(18,8,45)),ColorSequenceKeypoint.new(1,Color3.fromRGB(5,20,40))})
gg.Rotation=135
local st=Instance.new("UIStroke",MF); st.Color=Color3.fromRGB(148,87,235); st.Thickness=2

local TB=Instance.new("Frame"); TB.Size=UDim2.new(1,0,0,42); TB.BackgroundColor3=Color3.fromRGB(0,0,0)
TB.BackgroundTransparency=0.4; TB.BorderSizePixel=0; TB.Parent=MF
Instance.new("UICorner",TB).CornerRadius=UDim.new(0,12)
local TL=Instance.new("TextLabel"); TL.Size=UDim2.new(1,-50,1,0); TL.Position=UDim2.new(0,12,0,0)
TL.BackgroundTransparency=1; TL.Text="WA Hub v3"; TL.TextColor3=Color3.fromRGB(220,180,255)
TL.TextSize=15; TL.Font=Enum.Font.GothamBold; TL.TextXAlignment=Enum.TextXAlignment.Left; TL.Parent=TB
local MinB=Instance.new("TextButton"); MinB.Size=UDim2.new(0,26,0,26); MinB.Position=UDim2.new(1,-34,0.5,-13)
MinB.BackgroundColor3=Color3.fromRGB(148,87,235); MinB.Text="-"; MinB.TextColor3=Color3.new(1,1,1)
MinB.TextSize=16; MinB.Font=Enum.Font.GothamBold; MinB.BorderSizePixel=0; MinB.Parent=TB
Instance.new("UICorner",MinB).CornerRadius=UDim.new(1,0)

local SF=Instance.new("ScrollingFrame"); SF.Size=UDim2.new(1,0,1,-46); SF.Position=UDim2.new(0,0,0,46)
SF.BackgroundTransparency=1; SF.ScrollBarThickness=3; SF.ScrollBarImageColor3=Color3.fromRGB(148,87,235)
SF.AutomaticCanvasSize=Enum.AutomaticSize.Y; SF.ScrollingDirection=Enum.ScrollingDirection.Y
SF.CanvasSize=UDim2.new(0,0,0,0); SF.BorderSizePixel=0; SF.Parent=MF
Instance.new("UIListLayout",SF).Padding=UDim.new(0,6)
local pd=Instance.new("UIPadding",SF); pd.PaddingTop=UDim.new(0,8); pd.PaddingLeft=UDim.new(0,10); pd.PaddingRight=UDim.new(0,10)

-- Toggle Builder
local function mkToggle(label,desc,cb)
    local C=Instance.new("Frame"); C.Size=UDim2.new(1,0,0,56); C.BackgroundColor3=Color3.fromRGB(25,15,55)
    C.BorderSizePixel=0; C.Parent=SF; Instance.new("UICorner",C).CornerRadius=UDim.new(0,10)
    Instance.new("UIStroke",C).Color=Color3.fromRGB(80,40,160)
    local lb=Instance.new("TextLabel"); lb.Size=UDim2.new(1,-60,0,20); lb.Position=UDim2.new(0,10,0,8)
    lb.BackgroundTransparency=1; lb.Text=label; lb.TextColor3=Color3.fromRGB(220,200,255); lb.TextSize=13
    lb.Font=Enum.Font.GothamBold; lb.TextXAlignment=Enum.TextXAlignment.Left; lb.Parent=C
    local dc=Instance.new("TextLabel"); dc.Size=UDim2.new(1,-60,0,14); dc.Position=UDim2.new(0,10,0,30)
    dc.BackgroundTransparency=1; dc.Text=desc; dc.TextColor3=Color3.fromRGB(140,120,180); dc.TextSize=10
    dc.Font=Enum.Font.Gotham; dc.TextXAlignment=Enum.TextXAlignment.Left; dc.Parent=C
    local tr=Instance.new("Frame"); tr.Size=UDim2.new(0,40,0,20); tr.Position=UDim2.new(1,-48,0.5,-10)
    tr.BackgroundColor3=Color3.fromRGB(60,30,100); tr.BorderSizePixel=0; tr.Parent=C
    Instance.new("UICorner",tr).CornerRadius=UDim.new(1,0)
    local kn=Instance.new("Frame"); kn.Size=UDim2.new(0,16,0,16); kn.Position=UDim2.new(0,2,0.5,-8)
    kn.BackgroundColor3=Color3.fromRGB(180,140,220); kn.BorderSizePixel=0; kn.Parent=tr
    Instance.new("UICorner",kn).CornerRadius=UDim.new(1,0)
    local on=false
    local btn=Instance.new("TextButton"); btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""; btn.Parent=C
    btn.MouseButton1Click:Connect(function()
        on=not on
        if on then tw(tr,{BackgroundColor3=Color3.fromRGB(130,60,220)}); tw(kn,{Position=UDim2.new(0,22,0.5,-8),BackgroundColor3=Color3.new(1,1,1)})
        else tw(tr,{BackgroundColor3=Color3.fromRGB(60,30,100)}); tw(kn,{Position=UDim2.new(0,2,0.5,-8),BackgroundColor3=Color3.fromRGB(180,140,220)}) end
        cb(on)
    end)
end

-- Slider Builder
local function mkSlider(label,mn,mx,def,fmt,cb)
    local C=Instance.new("Frame"); C.Size=UDim2.new(1,0,0,60); C.BackgroundColor3=Color3.fromRGB(25,15,55)
    C.BorderSizePixel=0; C.Parent=SF; Instance.new("UICorner",C).CornerRadius=UDim.new(0,10)
    Instance.new("UIStroke",C).Color=Color3.fromRGB(80,40,160)
    local lb=Instance.new("TextLabel"); lb.Size=UDim2.new(1,-70,0,16); lb.Position=UDim2.new(0,10,0,6)
    lb.BackgroundTransparency=1; lb.Text=label; lb.TextColor3=Color3.fromRGB(220,200,255)
    lb.TextSize=11; lb.Font=Enum.Font.GothamBold; lb.TextXAlignment=Enum.TextXAlignment.Left; lb.Parent=C
    local vl=Instance.new("TextLabel"); vl.Size=UDim2.new(0,55,0,16); vl.Position=UDim2.new(1,-63,0,6)
    vl.BackgroundTransparency=1; vl.Text=fmt(def); vl.TextColor3=Color3.fromRGB(200,160,255)
    vl.TextSize=11; vl.Font=Enum.Font.GothamBold; vl.TextXAlignment=Enum.TextXAlignment.Right; vl.Parent=C
    local tk=Instance.new("Frame"); tk.Size=UDim2.new(1,-20,0,6); tk.Position=UDim2.new(0,10,0,36)
    tk.BackgroundColor3=Color3.fromRGB(60,30,100); tk.BorderSizePixel=0; tk.Parent=C
    Instance.new("UICorner",tk).CornerRadius=UDim.new(1,0)
    local r=(def-mn)/(mx-mn)
    local fl=Instance.new("Frame"); fl.Size=UDim2.new(r,0,1,0); fl.BackgroundColor3=Color3.fromRGB(148,87,235)
    fl.BorderSizePixel=0; fl.Parent=tk; Instance.new("UICorner",fl).CornerRadius=UDim.new(1,0)
    local kb=Instance.new("Frame"); kb.Size=UDim2.new(0,12,0,12); kb.Position=UDim2.new(r,-6,0.5,-6)
    kb.BackgroundColor3=Color3.new(1,1,1); kb.BorderSizePixel=0; kb.Parent=tk
    Instance.new("UICorner",kb).CornerRadius=UDim.new(1,0)
    local dragging=false
    local sb=Instance.new("TextButton"); sb.Size=UDim2.new(1,0,1,0); sb.BackgroundTransparency=1; sb.Text=""; sb.Parent=tk
    local function upd(pos)
        local rx=math.clamp((pos.X-tk.AbsolutePosition.X)/tk.AbsoluteSize.X,0,1)
        local v=math.floor((mn+rx*(mx-mn))*10+0.5)/10
        fl.Size=UDim2.new(rx,0,1,0); kb.Position=UDim2.new(rx,-6,0.5,-6); vl.Text=fmt(v); cb(v)
    end
    sb.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; upd(i.Position) end end)
    sb.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
    UIS.InputChanged:Connect(function(i) if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then upd(i.Position) end end)
end

local function mkSec(t)
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,20); l.BackgroundTransparency=1; l.Text=t
    l.TextColor3=Color3.fromRGB(148,87,235); l.TextSize=11; l.Font=Enum.Font.GothamBold
    l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=SF
end

-- ========================
-- BUILD GUI
-- ========================
-- DEBUG di atas supaya mudah ditemukan
mkSec("  DEBUG")
local scb=Instance.new("TextButton"); scb.Size=UDim2.new(1,0,0,28); scb.BackgroundColor3=Color3.fromRGB(80,30,30)
scb.Text="Scan All Remotes"; scb.TextColor3=Color3.fromRGB(255,200,200); scb.TextSize=11
scb.Font=Enum.Font.GothamBold; scb.BorderSizePixel=0; scb.Parent=SF
Instance.new("UICorner",scb).CornerRadius=UDim.new(0,8)
scb.MouseButton1Click:Connect(scanAllRemotes)

local npb=Instance.new("TextButton"); npb.Size=UDim2.new(1,0,0,28); npb.BackgroundColor3=Color3.fromRGB(80,50,20)
npb.Text="Scan All NPC"; npb.TextColor3=Color3.fromRGB(255,230,180); npb.TextSize=11
npb.Font=Enum.Font.GothamBold; npb.BorderSizePixel=0; npb.Parent=SF
Instance.new("UICorner",npb).CornerRadius=UDim.new(0,8)
npb.MouseButton1Click:Connect(function()
    print("=== ALL HUMANOID MODELS ===")
    for _,obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Parent and obj.Parent:IsA("Model") then
            local m = obj.Parent
            if m ~= Char then
                local blocked = not isEnemy(m)
                local hasPrompt = m:FindFirstChildWhichIsA("ProximityPrompt", true)
                local hasClick = m:FindFirstChildWhichIsA("ClickDetector", true)
                print(string.format("  %s [%s] HP:%s/%s SPD:%s Prompt:%s Click:%s PATH:%s",
                    blocked and "BLOCKED" or "TARGET",
                    m.Name, tostring(obj.Health), tostring(obj.MaxHealth),
                    tostring(obj.WalkSpeed),
                    hasPrompt and "YES" or "no",
                    hasClick and "YES" or "no",
                    m:GetFullName()))
            end
        end
    end
    print("=== ALL PROXIMITY PROMPTS ===")
    for _,v in ipairs(WS:GetDescendants()) do
        if v:IsA("ProximityPrompt") then
            print("  Prompt: " .. v:GetFullName() .. " | Action: " .. tostring(v.ActionText) .. " | Object: " .. tostring(v.ObjectText))
        end
    end
    print("=== ALL CLICK DETECTORS ===")
    for _,v in ipairs(WS:GetDescendants()) do
        if v:IsA("ClickDetector") then
            print("  Click: " .. v:GetFullName())
        end
    end
    print("=== END ===")
end)

-- Scan Inventory (debug)
local invb=Instance.new("TextButton"); invb.Size=UDim2.new(1,0,0,28); invb.BackgroundColor3=Color3.fromRGB(20,50,80)
invb.Text="Scan Inventory + Sell Remote"; invb.TextColor3=Color3.fromRGB(180,220,255); invb.TextSize=11
invb.Font=Enum.Font.GothamBold; invb.BorderSizePixel=0; invb.Parent=SF
Instance.new("UICorner",invb).CornerRadius=UDim.new(0,8)
invb.MouseButton1Click:Connect(function()
    -- 1. Scan semua children di LocalPlayer
    print("=== PLAYER DATA (LocalPlayer children) ===")
    for _,v in ipairs(LP:GetChildren()) do
        print(string.format("  [%s] %s | Children: %d", v.ClassName, v.Name, #v:GetChildren()))
        -- Print sub-children (max 2 level)
        for _,c in ipairs(v:GetChildren()) do
            if c:IsA("Folder") or c:IsA("Configuration") then
                print(string.format("    [%s] %s | Children: %d", c.ClassName, c.Name, #c:GetChildren()))
                for _,cc in ipairs(c:GetChildren()) do
                    print(string.format("      [%s] %s = %s", cc.ClassName, cc.Name, 
                        cc:IsA("ValueBase") and tostring(cc.Value) or tostring(#cc:GetChildren()).." children"))
                end
            elseif c:IsA("ValueBase") then
                print(string.format("    [%s] %s = %s", c.ClassName, c.Name, tostring(c.Value)))
            else
                print(string.format("    [%s] %s", c.ClassName, c.Name))
            end
        end
    end
    -- 2. Scan attributes di player
    print("=== PLAYER ATTRIBUTES ===")
    for k,v in pairs(LP:GetAttributes()) do
        print(string.format("  %s = %s (%s)", k, tostring(v), typeof(v)))
    end
    -- 3. Scan ReplicatedStorage untuk data/inventory folder
    print("=== REPLICATED STORAGE (inventory/data related) ===")
    for _,v in ipairs(RS:GetChildren()) do
        local n = v.Name:lower()
        if n:find("data") or n:find("inventory") or n:find("item") or n:find("bag") or n:find("storage") or n:find("player") then
            print(string.format("  [%s] %s | Children: %d", v.ClassName, v.Name, #v:GetChildren()))
            for _,c in ipairs(v:GetChildren()) do
                print(string.format("    [%s] %s", c.ClassName, c.Name))
            end
        end
    end
    -- 4. Scan sell-related remotes
    print("=== SELL/SHOP REMOTES ===")
    for _,v in ipairs(RS:GetDescendants()) do
        if (v:IsA("RemoteEvent") or v:IsA("RemoteFunction")) then
            local n = v.Name:lower()
            if n:find("sell") or n:find("shop") or n:find("trade") or n:find("buy") or n:find("item") or n:find("inventory") or n:find("bag") or n:find("drop") or n:find("discard") or n:find("destroy") then
                print(string.format("  [%s] %s | Path: %s", v.ClassName, v.Name, v:GetFullName()))
            end
        end
    end
    print("=== END INVENTORY SCAN ===")
    notify("Scan","Inventory scan selesai! Cek console (F9)")
end)

mkSec("  COMBAT")

mkToggle("Auto Farm","Orbit + serang mob terdekat dalam range",function(on)
    S.AutoFarm=on
    if on then S.FarmOrigin=Root.Position; startAutoFarm(); notify("Auto Farm","ON")
    else S.FarmOrigin=nil; stopOrbit(); notify("Auto Farm","OFF") end
end)

mkToggle("Auto Skill R+E","Otomatis tekan R dan E saat serang",function(on)
    S.AutoSkill=on; notify("Auto Skill",on and "ON" or "OFF")
end)

mkToggle("Auto Respawn","Balik ke posisi saat mati",function(on)
    S.AutoRespawn=on; notify("Auto Respawn",on and "ON" or "OFF")
end)

mkSec("  SELL")

-- ========================
-- SELL: Teleport ke Lombart saja
-- ========================
local function findLombart()
    local MERCHANT_NAMES = {
        "lombart","merchant","general merchant","seller","shop","vendor","trader",
        "隆巴特","商人","店主","杂货","杂货商","出售","卖","交易","贸易商",
    }
    for _,v in ipairs(WS:GetDescendants()) do
        if v:IsA("Model") then
            local n = v.Name:lower()
            for _,keyword in ipairs(MERCHANT_NAMES) do
                if n:find(keyword,1,true) then
                    local r = v:FindFirstChild("HumanoidRootPart") or v:FindFirstChild("Torso") or v:FindFirstChild("Head") or v.PrimaryPart
                    if r then return v, r end
                end
            end
        end
    end
    return nil, nil
end

-- Tombol TP ke Lombart
local tpSell=Instance.new("TextButton"); tpSell.Size=UDim2.new(1,0,0,32); tpSell.BackgroundColor3=Color3.fromRGB(60,40,20)
tpSell.Text="💰 TP ke Lombart (Sell)"; tpSell.TextColor3=Color3.fromRGB(255,220,140); tpSell.TextSize=12
tpSell.Font=Enum.Font.GothamBold; tpSell.BorderSizePixel=0; tpSell.Parent=SF
Instance.new("UICorner",tpSell).CornerRadius=UDim.new(0,8)
Instance.new("UIStroke",tpSell).Color=Color3.fromRGB(120,80,30)
tpSell.MouseButton1Click:Connect(function()
    local npc, npcRoot = findLombart()
    if npc and npcRoot then
        S.LastPos = Root.Position -- simpan posisi sebelum TP
        pcall(function() Root.CFrame = CFrame.new(npcRoot.Position + Vector3.new(0,0,3)) end)
        notify("TP","Teleport ke Lombart!")
    else
        notify("TP","Lombart tidak ditemukan!")
    end
end)

-- Tombol Balik dari Lombart
local tpBack=Instance.new("TextButton"); tpBack.Size=UDim2.new(1,0,0,32); tpBack.BackgroundColor3=Color3.fromRGB(20,40,60)
tpBack.Text="↩ Balik ke Posisi Farm"; tpBack.TextColor3=Color3.fromRGB(140,200,255); tpBack.TextSize=12
tpBack.Font=Enum.Font.GothamBold; tpBack.BorderSizePixel=0; tpBack.Parent=SF
Instance.new("UICorner",tpBack).CornerRadius=UDim.new(0,8)
Instance.new("UIStroke",tpBack).Color=Color3.fromRGB(30,70,120)
tpBack.MouseButton1Click:Connect(function()
    if S.LastPos then
        pcall(function() Root.CFrame = CFrame.new(S.LastPos + Vector3.new(0,3,0)) end)
        notify("TP","Balik ke posisi farm!")
    else
        notify("TP","Posisi farm belum tersimpan!")
    end
end)

mkSec("  SETTINGS")
mkSlider("Farm Range",0,500,150,function(v) return v==0 and "ALL" or v.."st" end,function(v)
    S.FarmRange=v; if S.AutoFarm then S.FarmOrigin=Root.Position end
end)
mkSlider("Orbit Radius",2,12,4,function(v) return v.."st" end,function(v) S.OrbitRadius=v end)
mkSlider("Orbit Speed",30,360,120,function(v) return v.."/s" end,function(v) S.OrbitSpeed=v end)
mkSlider("Attack Rate",0.05,0.5,0.1,function(v) return v.."s" end,function(v) S.AttackRate=v end)
mkSlider("Farm Delay",0.1,2,0.3,function(v) return v.."s" end,function(v) S.FarmDelay=v end)

-- TELEPORT PLAYER
mkSec("  TELEPORT")

-- TP to Base button
local tpBase=Instance.new("TextButton"); tpBase.Size=UDim2.new(1,0,0,32); tpBase.BackgroundColor3=Color3.fromRGB(20,60,40)
tpBase.Text="⛺ Teleport to Base"; tpBase.TextColor3=Color3.fromRGB(140,255,180); tpBase.TextSize=12
tpBase.Font=Enum.Font.GothamBold; tpBase.BorderSizePixel=0; tpBase.Parent=SF
Instance.new("UICorner",tpBase).CornerRadius=UDim.new(0,8)
Instance.new("UIStroke",tpBase).Color=Color3.fromRGB(40,120,70)
tpBase.MouseButton1Click:Connect(function()
    local spawn = nil
    -- Cari SpawnLocation di workspace
    for _,v in ipairs(WS:GetDescendants()) do
        if v:IsA("SpawnLocation") then spawn=v; break end
    end
    if spawn then
        pcall(function() Root.CFrame=CFrame.new(spawn.Position+Vector3.new(0,5,0)) end)
        notify("TP","Teleport ke Base!")
    else
        notify("TP","SpawnLocation tidak ditemukan!")
    end
end)

-- TP ke Boss HP 600-1000 (prioritas HP tertinggi)
local function findBoss()
    local bestModel, bestRoot, bestHP = nil, nil, 0
    for _,obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("Humanoid") and obj.Health > 0 and obj.MaxHealth >= 600 and obj.MaxHealth <= 1000 then
            if obj.MaxHealth > bestHP then
                local m = obj.Parent
                if m and m:IsA("Model") and m ~= Char then
                    local isPlayer = false
                    for _,p in ipairs(Players:GetPlayers()) do if p.Character==m then isPlayer=true; break end end
                    if not isPlayer and obj.WalkSpeed > 0 then
                        local r = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso") or m.PrimaryPart
                        if r then bestModel=m; bestRoot=r; bestHP=obj.MaxHealth end
                    end
                end
            end
        end
    end
    return bestModel, bestRoot
end

local tpBoss=Instance.new("TextButton"); tpBoss.Size=UDim2.new(1,0,0,32); tpBoss.BackgroundColor3=Color3.fromRGB(60,15,15)
tpBoss.Text="💀 TP ke Boss (HP 600-1000)"; tpBoss.TextColor3=Color3.fromRGB(255,140,140); tpBoss.TextSize=12
tpBoss.Font=Enum.Font.GothamBold; tpBoss.BorderSizePixel=0; tpBoss.Parent=SF
Instance.new("UICorner",tpBoss).CornerRadius=UDim.new(0,8)
Instance.new("UIStroke",tpBoss).Color=Color3.fromRGB(120,30,30)
tpBoss.MouseButton1Click:Connect(function()
    local boss, bossRoot = findBoss()
    if boss and bossRoot then
        pcall(function() Root.CFrame = CFrame.new(bossRoot.Position + Vector3.new(0,3,0)) end)
        local h = boss:FindFirstChild("Humanoid")
        notify("TP","Boss: " .. boss.Name .. " | HP: " .. (h and tostring(math.floor(h.Health)).."/"..tostring(math.floor(h.MaxHealth)) or "?"))
    else
        notify("TP","Boss HP 600-1000 tidak ditemukan!")
    end
end)

local PLF=Instance.new("Frame"); PLF.Size=UDim2.new(1,0,0,0); PLF.BackgroundTransparency=1
PLF.AutomaticSize=Enum.AutomaticSize.Y; PLF.Parent=SF
Instance.new("UIListLayout",PLF).Padding=UDim.new(0,4)

local function refreshPlayers()
    for _,c in ipairs(PLF:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LP then
            local r=Instance.new("Frame"); r.Size=UDim2.new(1,0,0,32); r.BackgroundColor3=Color3.fromRGB(25,15,55)
            r.BorderSizePixel=0; r.Parent=PLF; Instance.new("UICorner",r).CornerRadius=UDim.new(0,8)
            local nl=Instance.new("TextLabel"); nl.Size=UDim2.new(1,-70,1,0); nl.Position=UDim2.new(0,8,0,0)
            nl.BackgroundTransparency=1; nl.Text=p.Name; nl.TextColor3=Color3.fromRGB(220,200,255)
            nl.TextSize=11; nl.Font=Enum.Font.Gotham; nl.TextXAlignment=Enum.TextXAlignment.Left; nl.Parent=r
            local tb=Instance.new("TextButton"); tb.Size=UDim2.new(0,55,0,22); tb.Position=UDim2.new(1,-62,0.5,-11)
            tb.BackgroundColor3=Color3.fromRGB(100,50,200); tb.Text="TP"; tb.TextColor3=Color3.new(1,1,1)
            tb.TextSize=10; tb.Font=Enum.Font.GothamBold; tb.BorderSizePixel=0; tb.Parent=r
            Instance.new("UICorner",tb).CornerRadius=UDim.new(0,6)
            tb.MouseButton1Click:Connect(function()
                if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                    Root.CFrame=CFrame.new(p.Character.HumanoidRootPart.Position+Vector3.new(2,0,2))
                    notify("TP","ke "..p.Name)
                end
            end)
        end
    end
end
refreshPlayers()
Players.PlayerAdded:Connect(refreshPlayers)
Players.PlayerRemoving:Connect(function() task.wait(0.1); refreshPlayers() end)

local rfb=Instance.new("TextButton"); rfb.Size=UDim2.new(1,0,0,26); rfb.BackgroundColor3=Color3.fromRGB(40,20,80)
rfb.Text="Refresh Players"; rfb.TextColor3=Color3.fromRGB(200,160,255); rfb.TextSize=11
rfb.Font=Enum.Font.GothamBold; rfb.BorderSizePixel=0; rfb.Parent=SF
Instance.new("UICorner",rfb).CornerRadius=UDim.new(0,8)
rfb.MouseButton1Click:Connect(refreshPlayers)

-- DRAG
local dragging,dStart,sPos=false,nil,nil
TB.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true;dStart=i.Position;sPos=MF.Position end end)
TB.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
UIS.InputChanged:Connect(function(i)
    if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
        local d=i.Position-dStart; MF.Position=UDim2.new(sPos.X.Scale,sPos.X.Offset+d.X,sPos.Y.Scale,sPos.Y.Offset+d.Y)
    end
end)

-- MINIMIZE
local mini=false
MinB.MouseButton1Click:Connect(function()
    mini=not mini
    if mini then tw(MF,{Size=UDim2.new(0,300,0,42)}); MinB.Text="+"
    else tw(MF,{Size=UDim2.new(0,300,0,500)}); MinB.Text="-" end
end)

-- OPEN ANIMATION
MF.Size=UDim2.new(0,0,0,0); MF.Position=UDim2.new(0.5,0,0.5,0)
tw(MF,{Size=UDim2.new(0,300,0,500),Position=UDim2.new(0.5,-150,0.5,-250)},0.5)

notify("WA Hub v3","Script loaded!")
print("[WA Hub v3] Loaded | Instant Kill + Auto Farm + R/E Skills + Auto Respawn")
