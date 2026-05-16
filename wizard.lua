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
    AutoFarm=false, InstantKill=false, AutoSkill=false,
    AutoRespawn=false, FarmRange=150, FarmDelay=0.3,
    OrbitRadius=4, OrbitSpeed=120, AttackRate=0.1,
    FarmOrigin=nil, LastPos=nil,
}

-- Save position setiap 1 detik
task.spawn(function()
    while true do
        task.wait(1)
        if Root and Root.Parent and Hum and Hum.Health > 0 then
            S.LastPos = Root.Position
        end
    end
end)

local function notify(t,m)
    game:GetService("StarterGui"):SetCore("SendNotification",{Title=t,Text=m,Duration=3})
end

-- Respawn + teleport balik
LP.CharacterAdded:Connect(function(c)
    Char=c; Hum=c:WaitForChild("Humanoid"); Root=c:WaitForChild("HumanoidRootPart")
    if S.AutoRespawn and S.LastPos then
        task.wait(1)
        pcall(function() Root.CFrame = CFrame.new(S.LastPos + Vector3.new(0,3,0)) end)
        notify("Respawn","Kembali ke posisi terakhir!")
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
    local folders = {"Enemies","Mobs","Monsters","Enemy","Mob","Boss","Creature"}
    for _,fn in ipairs(folders) do
        local f = WS:FindFirstChild(fn)
        if f then for _,m in ipairs(f:GetChildren()) do
            if m:IsA("Model") and not seen[m] and isEnemy(m) then
                local r = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso") or m.PrimaryPart
                if r then table.insert(mobs,{model=m,root=r,dist=(Root.Position-r.Position).Magnitude}); seen[m]=true end
            end
        end end
    end
    if #mobs==0 then
        for _,obj in ipairs(WS:GetDescendants()) do
            if obj:IsA("Humanoid") and obj.Health>0 and not seen[obj.Parent] then
                local m=obj.Parent
                if m:IsA("Model") and isEnemy(m) then
                    local r=m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso") or m.PrimaryPart
                    if r then table.insert(mobs,{model=m,root=r,dist=(Root.Position-r.Position).Magnitude}); seen[m]=true end
                end
            end
        end
    end
    table.sort(mobs,function(a,b) return a.dist<b.dist end)
    if S.FarmRange>0 and S.FarmOrigin then
        local f={}
        for _,m in ipairs(mobs) do if (S.FarmOrigin-m.root.Position).Magnitude<=S.FarmRange then table.insert(f,m) end end
        return f
    end
    return mobs
end

-- ========================
-- ATTACK SYSTEM (Remote Spy — ZERO mouse)
-- ========================
-- Serang 1x manual → script tangkap remote → replay otomatis
local spiedRemote = nil
local spiedArgs = nil
local spyReady = false

-- Scan semua RemoteEvent SAAT ini (non-hook, safe)
-- Lalu listen manual click via .OnClientEvent / connections
task.spawn(function()
    -- Method 1: hookfunction (aman, tidak block panggilan asli)
    local ok = pcall(function()
        local mt = getrawmetatable(game)
        local oldNC = mt.__namecall
        local hook
        hook = hookfunction(oldNC, newcclosure(function(self, ...)
            local method = getnamecallmethod()
            if method == "FireServer" and typeof(self) == "Instance" and self:IsA("RemoteEvent") and not spyReady then
                local n = self.Name:lower()
                if n:find("attack") or n:find("swing") or n:find("cast")
                    or n:find("spell") or n:find("hit") or n:find("damage")
                    or n:find("use") or n:find("skill") or n:find("combat")
                    or n:find("weapon") then
                    spiedRemote = self
                    spiedArgs = {...}
                    spyReady = true
                    print("[WA Spy] Captured: " .. self.Name)
                end
            end
            return hook(self, ...)
        end))
    end)
    -- Method 2: fallback tanpa hook — scan remote dari RS
    if not ok then
        print("[WA] hookfunction gagal, pakai scan mode")
        for _,remote in ipairs(RS:GetDescendants()) do
            if remote:IsA("RemoteEvent") then
                local n = remote.Name:lower()
                if n:find("attack") or n:find("swing") or n:find("cast") or n:find("hit") or n:find("damage") then
                    spiedRemote = remote
                    spyReady = true
                    spiedArgs = {}
                    print("[WA Scan] Found: " .. remote.Name)
                    break
                end
            end
        end
    end
    print("[WA] Attack system ready — " .. (spyReady and "Remote: "..spiedRemote.Name or "serang 1x manual untuk capture"))
end)

local function pressKey(key)
    pcall(function() VIM:SendKeyEvent(true,key,false,game); task.wait(0.05); VIM:SendKeyEvent(false,key,false,game) end)
end

local function fireAttack()
    -- Prioritas: replay remote yang sudah di-spy (100% server-side, 0 mouse)
    if spyReady and spiedRemote then
        pcall(function() spiedRemote:FireServer(table.unpack(spiedArgs or {})) end)
        return
    end
    -- Fallback: tool activate + getconnections (tanpa mouse)
    local tool = Char:FindFirstChildOfClass("Tool")
    if tool then pcall(function() tool:Activate() end) end
    if tool then pcall(function() for _,c in ipairs(getconnections(tool.Activated)) do c:Fire() end end) end
end

-- ========================
-- ORBIT + KILL
-- ========================
local orbitConn, orbitActive = nil, false
local function stopOrbit() orbitActive=false; if orbitConn then orbitConn:Disconnect(); orbitConn=nil end end

local function orbitKill(enemy)
    if not enemy or not enemy.Parent then return end
    local h=enemy:FindFirstChild("Humanoid")
    if not h or h.Health<=0 then return end
    print("[WA] Target: " .. enemy.Name .. " | HP: " .. h.Health .. "/" .. h.MaxHealth .. " | Speed: " .. h.WalkSpeed)
    stopOrbit(); orbitActive=true
    local angle,lastAtk=0,0
    orbitConn = RunService.Heartbeat:Connect(function(dt)
        if not orbitActive or not S.InstantKill and not S.AutoFarm then orbitActive=false; return end
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
            pcall(fireAttack)
            if S.AutoSkill then pressKey(Enum.KeyCode.R); pressKey(Enum.KeyCode.E) end
            pcall(function() if hm.Health>1 then hm.Health=1 end end)
        end
    end)
    while orbitActive do task.wait(0.1) end
    stopOrbit()
end

-- ========================
-- FARM LOOPS
-- ========================
local function startInstantKill()
    task.spawn(function()
        while S.InstantKill do
            local mobs=scanMobs()
            if #mobs==0 then stopOrbit(); task.wait(1) else
                for _,m in ipairs(mobs) do
                    if not S.InstantKill then stopOrbit(); break end
                    if m.model and m.model.Parent then
                        local h=m.model:FindFirstChild("Humanoid")
                        if h and h.Health>0 then pcall(function() orbitKill(m.model) end) end
                    end; task.wait(0.1)
                end
            end; task.wait(0.2)
        end; stopOrbit()
    end)
end

local function startAutoFarm()
    task.spawn(function()
        while S.AutoFarm do
            local mobs=scanMobs()
            if #mobs==0 then stopOrbit(); task.wait(1) else
                for _,m in ipairs(mobs) do
                    if not S.AutoFarm then stopOrbit(); break end
                    if m.model and m.model.Parent then
                        local h=m.model:FindFirstChild("Humanoid")
                        if h and h.Health>0 then pcall(function() orbitKill(m.model) end) end
                    end; task.wait(S.FarmDelay)
                end
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
-- BUILD TOGGLES
-- ========================
mkSec("  COMBAT")

mkToggle("Instant Kill","Orbit + rapid attack semua mob",function(on)
    S.InstantKill=on
    if on then S.FarmOrigin=Root.Position; startInstantKill(); notify("Instant Kill","ON")
    else S.FarmOrigin=nil; stopOrbit(); notify("Instant Kill","OFF") end
end)

mkToggle("Auto Farm","Teleport ke mob dalam range",function(on)
    S.AutoFarm=on
    if on then S.FarmOrigin=Root.Position; startAutoFarm(); notify("Auto Farm","ON")
    else S.FarmOrigin=nil; stopOrbit(); notify("Auto Farm","OFF") end
end)

mkToggle("Auto Skill R+E","Otomatis tekan R dan E saat serang",function(on)
    S.AutoSkill=on; notify("Auto Skill",on and "ON" or "OFF")
end)

mkToggle("Auto Respawn","Balik ke posisi terakhir saat mati",function(on)
    S.AutoRespawn=on; notify("Auto Respawn",on and "ON" or "OFF")
end)

mkSec("  SETTINGS")
mkSlider("Farm Range",0,500,150,function(v) return v==0 and "ALL" or v.."st" end,function(v)
    S.FarmRange=v; if S.InstantKill or S.AutoFarm then S.FarmOrigin=Root.Position end
end)
mkSlider("Orbit Radius",2,12,4,function(v) return v.."st" end,function(v) S.OrbitRadius=v end)
mkSlider("Orbit Speed",30,360,120,function(v) return v.."/s" end,function(v) S.OrbitSpeed=v end)
mkSlider("Attack Rate",0.05,0.5,0.1,function(v) return v.."s" end,function(v) S.AttackRate=v end)
mkSlider("Farm Delay",0.1,2,0.3,function(v) return v.."s" end,function(v) S.FarmDelay=v end)

-- TELEPORT PLAYER
mkSec("  TELEPORT")
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
