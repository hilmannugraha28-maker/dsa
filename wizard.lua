-- ================================================
-- WIZARD ALCHEMY HUB v3.0 | CLEAN BUILD
-- Fitur: Auto Farm, Instant Kill (Server-Side), Auto R+E Skill
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

-- State
local S = {
    AutoFarm=false, InstantKill=false, AutoSkill=false,
    FarmRange=150, FarmDelay=0.3, OrbitRadius=4, OrbitSpeed=120,
    AttackRate=0.1, FarmOrigin=nil,
}

-- Refresh character
LP.CharacterAdded:Connect(function(c)
    Char=c; Hum=c:WaitForChild("Humanoid"); Root=c:WaitForChild("HumanoidRootPart")
end)

-- Notify
local function notify(t,m)
    game:GetService("StarterGui"):SetCore("SendNotification",{Title=t,Text=m,Duration=3})
end

-- Tween helper
local function tw(obj,props,t)
    TweenService:Create(obj,TweenInfo.new(t or 0.3,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),props):Play()
end

-- ========================
-- ENEMY SCANNER
-- ========================
local BLACKLIST = {"wizard robe","robe","apprentice","shop","merchant","vendor","trader",
    "quest","dialog","friendly","civilian","keeper","banker","guide","neutral","villager","dummy"}

local function isEnemy(model)
    if model == Char then return false end
    for _,p in ipairs(Players:GetPlayers()) do if p.Character==model then return false end end
    local n = model.Name:lower()
    for _,kw in ipairs(BLACKLIST) do if n:find(kw,1,true) then return false end end
    local h = model:FindFirstChild("Humanoid")
    if not h or h.Health<=0 or h.MaxHealth<=0 or h.MaxHealth==math.huge then return false end
    return true
end

local function scanMobs()
    local mobs = {}
    local folders = {"Enemies","Mobs","Monsters","Enemy","Mob","Boss","Creature"}
    local seen = {}
    for _,fn in ipairs(folders) do
        local f = WS:FindFirstChild(fn)
        if f then for _,m in ipairs(f:GetChildren()) do
            if m:IsA("Model") and not seen[m] and isEnemy(m) then
                local r = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso") or m.PrimaryPart
                if r then
                    local d = (Root.Position-r.Position).Magnitude
                    table.insert(mobs,{model=m,root=r,dist=d,name=m.Name})
                    seen[m]=true
                end
            end
        end end
    end
    if #mobs==0 then
        for _,obj in ipairs(WS:GetDescendants()) do
            if obj:IsA("Humanoid") and obj.Health>0 and not seen[obj.Parent] then
                local m=obj.Parent
                if m:IsA("Model") and isEnemy(m) then
                    local r=m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso") or m.PrimaryPart
                    if r then
                        table.insert(mobs,{model=m,root=r,dist=(Root.Position-r.Position).Magnitude,name=m.Name})
                        seen[m]=true
                    end
                end
            end
        end
    end
    table.sort(mobs,function(a,b) return a.dist<b.dist end)
    if S.FarmRange>0 and S.FarmOrigin then
        local filtered={}
        for _,m in ipairs(mobs) do
            if (S.FarmOrigin-m.root.Position).Magnitude<=S.FarmRange then table.insert(filtered,m) end
        end
        return filtered
    end
    return mobs
end

-- ========================
-- ATTACK SYSTEM (Server-Side)
-- ========================
local function pressKey(key)
    pcall(function()
        VIM:SendKeyEvent(true,key,false,game)
        task.wait(0.05)
        VIM:SendKeyEvent(false,key,false,game)
    end)
end

local function fireAttack(pos)
    -- Tool activate
    local tool = Char:FindFirstChildOfClass("Tool")
    if tool then pcall(function() tool:Activate() end) end
    -- getconnections fallback
    if tool then
        pcall(function() for _,c in ipairs(getconnections(tool.Activated)) do c:Fire() end end)
    end
    -- Fire combat remotes
    for _,remote in ipairs(RS:GetDescendants()) do
        if remote:IsA("RemoteEvent") then
            local n=remote.Name:lower()
            if n:find("attack") or n:find("swing") or n:find("cast") or n:find("hit") or n:find("damage") then
                pcall(function() remote:FireServer() end)
            end
        end
    end
end

-- ========================
-- ORBIT + KILL SYSTEM
-- ========================
local orbitConn, orbitActive = nil, false

local function stopOrbit()
    orbitActive=false
    if orbitConn then orbitConn:Disconnect(); orbitConn=nil end
end

local function orbitKill(enemy)
    if not enemy or not enemy.Parent then return end
    local h=enemy:FindFirstChild("Humanoid")
    if not h or h.Health<=0 then return end
    stopOrbit()
    orbitActive=true
    local angle=0
    local lastAtk=0

    orbitConn = RunService.Heartbeat:Connect(function(dt)
        if not orbitActive then return end
        if not S.InstantKill and not S.AutoFarm then orbitActive=false; return end
        if not enemy or not enemy.Parent then orbitActive=false; return end
        local hm=enemy:FindFirstChild("Humanoid")
        if not hm or hm.Health<=0 then orbitActive=false; return end
        local r=enemy:FindFirstChild("HumanoidRootPart") or enemy:FindFirstChild("Torso") or enemy.PrimaryPart
        if not r then return end

        angle=(angle+S.OrbitSpeed*dt)%360
        local rad=math.rad(angle)
        local oPos=Vector3.new(r.Position.X+math.cos(rad)*S.OrbitRadius, r.Position.Y+3, r.Position.Z+math.sin(rad)*S.OrbitRadius)
        pcall(function() Root.CFrame=CFrame.lookAt(oPos,r.Position) end)

        local now=tick()
        if now-lastAtk>=S.AttackRate then
            lastAtk=now
            pcall(function() fireAttack(r.Position) end)
            -- Skills R + E
            if S.AutoSkill then
                pressKey(Enum.KeyCode.R)
                pressKey(Enum.KeyCode.E)
            end
            -- Set HP rendah agar cepat mati
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
            if #mobs==0 then stopOrbit(); task.wait(1)
            else
                for _,m in ipairs(mobs) do
                    if not S.InstantKill then stopOrbit(); break end
                    if m.model and m.model.Parent then
                        local h=m.model:FindFirstChild("Humanoid")
                        if h and h.Health>0 then pcall(function() orbitKill(m.model) end) end
                    end
                    task.wait(0.1)
                end
            end
            task.wait(0.2)
        end
        stopOrbit()
    end)
end

local function startAutoFarm()
    task.spawn(function()
        while S.AutoFarm do
            local mobs=scanMobs()
            if #mobs==0 then stopOrbit(); task.wait(1)
            else
                for _,m in ipairs(mobs) do
                    if not S.AutoFarm then stopOrbit(); break end
                    if m.model and m.model.Parent then
                        local h=m.model:FindFirstChild("Humanoid")
                        if h and h.Health>0 then pcall(function() orbitKill(m.model) end) end
                    end
                    task.wait(S.FarmDelay)
                end
            end
            task.wait(0.2)
        end
        stopOrbit()
    end)
end

-- ========================
-- GUI
-- ========================
local SG = Instance.new("ScreenGui")
SG.Name="WizardAlchemyHub"; SG.ResetOnSpawn=false; SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
if syn and syn.protect_gui then syn.protect_gui(SG); SG.Parent=game:GetService("CoreGui")
elseif gethui then SG.Parent=gethui() else SG.Parent=LP.PlayerGui end

local MF = Instance.new("Frame")
MF.Name="Main"; MF.Size=UDim2.new(0,300,0,480); MF.Position=UDim2.new(0.5,-150,0.5,-240)
MF.BackgroundColor3=Color3.fromRGB(10,10,22); MF.BorderSizePixel=0; MF.ClipsDescendants=true; MF.Parent=SG
Instance.new("UICorner",MF).CornerRadius=UDim.new(0,12)
local g=Instance.new("UIGradient",MF)
g.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(18,8,45)),ColorSequenceKeypoint.new(1,Color3.fromRGB(5,20,40))})
g.Rotation=135
Instance.new("UIStroke",MF).Color=Color3.fromRGB(148,87,235); MF:FindFirstChildOfClass("UIStroke").Thickness=2

-- Title
local TB=Instance.new("Frame"); TB.Size=UDim2.new(1,0,0,44); TB.BackgroundColor3=Color3.fromRGB(0,0,0)
TB.BackgroundTransparency=0.4; TB.BorderSizePixel=0; TB.Parent=MF
Instance.new("UICorner",TB).CornerRadius=UDim.new(0,12)
local TL=Instance.new("TextLabel"); TL.Size=UDim2.new(1,-50,1,0); TL.Position=UDim2.new(0,12,0,0)
TL.BackgroundTransparency=1; TL.Text="âš—ï¸ WA Hub v3"; TL.TextColor3=Color3.fromRGB(220,180,255)
TL.TextSize=16; TL.Font=Enum.Font.GothamBold; TL.TextXAlignment=Enum.TextXAlignment.Left; TL.Parent=TB

local MinB=Instance.new("TextButton"); MinB.Size=UDim2.new(0,28,0,28); MinB.Position=UDim2.new(1,-36,0.5,-14)
MinB.BackgroundColor3=Color3.fromRGB(148,87,235); MinB.Text="âˆ’"; MinB.TextColor3=Color3.new(1,1,1)
MinB.TextSize=16; MinB.Font=Enum.Font.GothamBold; MinB.BorderSizePixel=0; MinB.Parent=TB
Instance.new("UICorner",MinB).CornerRadius=UDim.new(1,0)

-- Scroll
local SF=Instance.new("ScrollingFrame"); SF.Size=UDim2.new(1,0,1,-48); SF.Position=UDim2.new(0,0,0,48)
SF.BackgroundTransparency=1; SF.ScrollBarThickness=3; SF.ScrollBarImageColor3=Color3.fromRGB(148,87,235)
SF.AutomaticCanvasSize=Enum.AutomaticSize.Y; SF.ScrollingDirection=Enum.ScrollingDirection.Y
SF.CanvasSize=UDim2.new(0,0,0,0); SF.BorderSizePixel=0; SF.Parent=MF
local LL=Instance.new("UIListLayout",SF); LL.Padding=UDim.new(0,6); LL.HorizontalAlignment=Enum.HorizontalAlignment.Center
local pad=Instance.new("UIPadding",SF); pad.PaddingTop=UDim.new(0,8); pad.PaddingLeft=UDim.new(0,10); pad.PaddingRight=UDim.new(0,10)

-- Toggle builder
local function mkToggle(label,icon,desc,cb)
    local C=Instance.new("Frame"); C.Size=UDim2.new(1,0,0,64); C.BackgroundColor3=Color3.fromRGB(25,15,55)
    C.BorderSizePixel=0; C.Parent=SF; Instance.new("UICorner",C).CornerRadius=UDim.new(0,10)
    local cs=Instance.new("UIStroke",C); cs.Color=Color3.fromRGB(80,40,160); cs.Thickness=1
    local il=Instance.new("TextLabel"); il.Size=UDim2.new(0,32,0,32); il.Position=UDim2.new(0,8,0.5,-16)
    il.BackgroundColor3=Color3.fromRGB(148,87,235); il.BackgroundTransparency=0.7; il.Text=icon; il.TextSize=18
    il.Font=Enum.Font.GothamBold; il.TextColor3=Color3.new(1,1,1); il.BorderSizePixel=0; il.Parent=C
    Instance.new("UICorner",il).CornerRadius=UDim.new(0,8)
    local lb=Instance.new("TextLabel"); lb.Size=UDim2.new(1,-100,0,20); lb.Position=UDim2.new(0,48,0,10)
    lb.BackgroundTransparency=1; lb.Text=label; lb.TextColor3=Color3.fromRGB(220,200,255); lb.TextSize=13
    lb.Font=Enum.Font.GothamBold; lb.TextXAlignment=Enum.TextXAlignment.Left; lb.Parent=C
    local dc=Instance.new("TextLabel"); dc.Size=UDim2.new(1,-100,0,16); dc.Position=UDim2.new(0,48,0,32)
    dc.BackgroundTransparency=1; dc.Text=desc; dc.TextColor3=Color3.fromRGB(140,120,180); dc.TextSize=10
    dc.Font=Enum.Font.Gotham; dc.TextXAlignment=Enum.TextXAlignment.Left; dc.Parent=C
    local tr=Instance.new("Frame"); tr.Size=UDim2.new(0,42,0,22); tr.Position=UDim2.new(1,-50,0.5,-11)
    tr.BackgroundColor3=Color3.fromRGB(60,30,100); tr.BorderSizePixel=0; tr.Parent=C
    Instance.new("UICorner",tr).CornerRadius=UDim.new(1,0)
    local kn=Instance.new("Frame"); kn.Size=UDim2.new(0,16,0,16); kn.Position=UDim2.new(0,3,0.5,-8)
    kn.BackgroundColor3=Color3.fromRGB(180,140,220); kn.BorderSizePixel=0; kn.Parent=tr
    Instance.new("UICorner",kn).CornerRadius=UDim.new(1,0)
    local on=false
    local btn=Instance.new("TextButton"); btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1
    btn.Text=""; btn.Parent=C
    btn.MouseButton1Click:Connect(function()
        on=not on
        if on then tw(tr,{BackgroundColor3=Color3.fromRGB(130,60,220)}); tw(kn,{Position=UDim2.new(0,23,0.5,-8),BackgroundColor3=Color3.new(1,1,1)})
        else tw(tr,{BackgroundColor3=Color3.fromRGB(60,30,100)}); tw(kn,{Position=UDim2.new(0,3,0.5,-8),BackgroundColor3=Color3.fromRGB(180,140,220)}) end
        cb(on)
    end)
end

-- Slider builder
local function mkSlider(label,icon,mn,mx,def,fmt,cb)
    local C=Instance.new("Frame"); C.Size=UDim2.new(1,0,0,70); C.BackgroundColor3=Color3.fromRGB(25,15,55)
    C.BorderSizePixel=0; C.Parent=SF; Instance.new("UICorner",C).CornerRadius=UDim.new(0,10)
    Instance.new("UIStroke",C).Color=Color3.fromRGB(80,40,160)
    local lb=Instance.new("TextLabel"); lb.Size=UDim2.new(1,-80,0,18); lb.Position=UDim2.new(0,10,0,6)
    lb.BackgroundTransparency=1; lb.Text=icon.." "..label; lb.TextColor3=Color3.fromRGB(220,200,255)
    lb.TextSize=12; lb.Font=Enum.Font.GothamBold; lb.TextXAlignment=Enum.TextXAlignment.Left; lb.Parent=C
    local vl=Instance.new("TextLabel"); vl.Size=UDim2.new(0,60,0,18); vl.Position=UDim2.new(1,-68,0,6)
    vl.BackgroundTransparency=1; vl.Text=fmt(def); vl.TextColor3=Color3.fromRGB(200,160,255)
    vl.TextSize=12; vl.Font=Enum.Font.GothamBold; vl.TextXAlignment=Enum.TextXAlignment.Right; vl.Parent=C
    local tk=Instance.new("Frame"); tk.Size=UDim2.new(1,-20,0,6); tk.Position=UDim2.new(0,10,0,42)
    tk.BackgroundColor3=Color3.fromRGB(60,30,100); tk.BorderSizePixel=0; tk.Parent=C
    Instance.new("UICorner",tk).CornerRadius=UDim.new(1,0)
    local r=(def-mn)/(mx-mn)
    local fl=Instance.new("Frame"); fl.Size=UDim2.new(r,0,1,0); fl.BackgroundColor3=Color3.fromRGB(148,87,235)
    fl.BorderSizePixel=0; fl.Parent=tk; Instance.new("UICorner",fl).CornerRadius=UDim.new(1,0)
    local kb=Instance.new("Frame"); kb.Size=UDim2.new(0,14,0,14); kb.Position=UDim2.new(r,-7,0.5,-7)
    kb.BackgroundColor3=Color3.new(1,1,1); kb.BorderSizePixel=0; kb.Parent=tk
    Instance.new("UICorner",kb).CornerRadius=UDim.new(1,0)
    local dragging=false
    local sb=Instance.new("TextButton"); sb.Size=UDim2.new(1,0,1,0); sb.BackgroundTransparency=1; sb.Text=""; sb.Parent=tk
    local function upd(pos)
        local rx=math.clamp((pos.X-tk.AbsolutePosition.X)/tk.AbsoluteSize.X,0,1)
        local v=math.floor((mn+rx*(mx-mn))*10+0.5)/10
        fl.Size=UDim2.new(rx,0,1,0); kb.Position=UDim2.new(rx,-7,0.5,-7); vl.Text=fmt(v); cb(v)
    end
    sb.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; upd(i.Position) end end)
    sb.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end end)
    UIS.InputChanged:Connect(function(i) if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then upd(i.Position) end end)
end

-- Section label
local function mkSec(t)
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,22); l.BackgroundTransparency=1; l.Text=t
    l.TextColor3=Color3.fromRGB(148,87,235); l.TextSize=11; l.Font=Enum.Font.GothamBold
    l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=SF
end

-- BUILD GUI
mkSec("  âš”ï¸  COMBAT")

mkToggle("Instant Kill","âš¡","Orbit + rapid attack semua mob",function(on)
    S.InstantKill=on
    if on then S.FarmOrigin=Root.Position; startInstantKill(); notify("âš¡ Instant Kill","âœ… ON")
    else S.FarmOrigin=nil; stopOrbit(); notify("âš¡ Instant Kill","âŒ OFF") end
end)

mkToggle("Auto Farm","ðŸŒ¾","Teleport ke mob dalam range",function(on)
    S.AutoFarm=on
    if on then S.FarmOrigin=Root.Position; startAutoFarm(); notify("ðŸŒ¾ Auto Farm","âœ… ON")
    else S.FarmOrigin=nil; stopOrbit(); notify("ðŸŒ¾ Auto Farm","âŒ OFF") end
end)

mkToggle("Auto Skill R+E","ðŸ”®","Otomatis tekan R dan E saat serang",function(on)
    S.AutoSkill=on
    notify("ðŸ”® Auto Skill",on and "âœ… ON" or "âŒ OFF")
end)

mkSec("  âš™ï¸  SETTINGS")

mkSlider("Farm Range","ðŸ“",0,500,150,function(v) return v==0 and "âˆž" or v.." st" end,function(v)
    S.FarmRange=v; if S.InstantKill or S.AutoFarm then S.FarmOrigin=Root.Position end
end)

mkSlider("Orbit Radius","ðŸŒ€",2,12,4,function(v) return v.." st" end,function(v) S.OrbitRadius=v end)
mkSlider("Orbit Speed","ðŸ’¨",30,360,120,function(v) return v.."Â°/s" end,function(v) S.OrbitSpeed=v end)
mkSlider("Attack Rate","ðŸ—¡ï¸",0.05,0.5,0.1,function(v) return v.."s" end,function(v) S.AttackRate=v end)
mkSlider("Farm Delay","â³",0.1,2,0.3,function(v) return v.."s" end,function(v) S.FarmDelay=v end)

-- TELEPORT PLAYER
mkSec("  ðŸ“  TELEPORT")
local PLF=Instance.new("Frame"); PLF.Size=UDim2.new(1,0,0,0); PLF.BackgroundTransparency=1
PLF.AutomaticSize=Enum.AutomaticSize.Y; PLF.Parent=SF
Instance.new("UIListLayout",PLF).Padding=UDim.new(0,4)

local function refreshPlayers()
    for _,c in ipairs(PLF:GetChildren()) do if not c:IsA("UIListLayout") then c:Destroy() end end
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LP then
            local r=Instance.new("Frame"); r.Size=UDim2.new(1,0,0,34); r.BackgroundColor3=Color3.fromRGB(25,15,55)
            r.BorderSizePixel=0; r.Parent=PLF; Instance.new("UICorner",r).CornerRadius=UDim.new(0,8)
            local nl=Instance.new("TextLabel"); nl.Size=UDim2.new(1,-80,1,0); nl.Position=UDim2.new(0,8,0,0)
            nl.BackgroundTransparency=1; nl.Text="ðŸ‘¤ "..p.Name; nl.TextColor3=Color3.fromRGB(220,200,255)
            nl.TextSize=11; nl.Font=Enum.Font.Gotham; nl.TextXAlignment=Enum.TextXAlignment.Left; nl.Parent=r
            local tb=Instance.new("TextButton"); tb.Size=UDim2.new(0,60,0,24); tb.Position=UDim2.new(1,-68,0.5,-12)
            tb.BackgroundColor3=Color3.fromRGB(100,50,200); tb.Text="TP"; tb.TextColor3=Color3.new(1,1,1)
            tb.TextSize=10; tb.Font=Enum.Font.GothamBold; tb.BorderSizePixel=0; tb.Parent=r
            Instance.new("UICorner",tb).CornerRadius=UDim.new(0,6)
            tb.MouseButton1Click:Connect(function()
                if p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                    Root.CFrame=CFrame.new(p.Character.HumanoidRootPart.Position+Vector3.new(2,0,2))
                    notify("ðŸ“","TP ke "..p.Name)
                end
            end)
        end
    end
end
refreshPlayers()
Players.PlayerAdded:Connect(refreshPlayers)
Players.PlayerRemoving:Connect(function() task.wait(0.1); refreshPlayers() end)

local rb=Instance.new("TextButton"); rb.Size=UDim2.new(1,0,0,28); rb.BackgroundColor3=Color3.fromRGB(40,20,80)
rb.Text="ðŸ”„ Refresh"; rb.TextColor3=Color3.fromRGB(200,160,255); rb.TextSize=11
rb.Font=Enum.Font.GothamBold; rb.BorderSizePixel=0; rb.Parent=SF
Instance.new("UICorner",rb).CornerRadius=UDim.new(0,8)
rb.MouseButton1Click:Connect(refreshPlayers)

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
    if mini then tw(MF,{Size=UDim2.new(0,300,0,44)}); MinB.Text="+"
    else tw(MF,{Size=UDim2.new(0,300,0,480)}); MinB.Text="âˆ’" end
end)

-- OPEN ANIMATION
MF.Size=UDim2.new(0,0,0,0); MF.Position=UDim2.new(0.5,0,0.5,0)
tw(MF,{Size=UDim2.new(0,300,0,480),Position=UDim2.new(0.5,-150,0.5,-240)},0.5)

notify("âš—ï¸ WA Hub v3","Script loaded!")
print("[WA Hub v3] Loaded | Instant Kill + Auto Farm + R/E Skills")

