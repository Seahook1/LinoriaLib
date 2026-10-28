-- Ethereal.free v6 | Rivals HvH | Obsidian UI (visnoukkk/ObsidianLib → deividcomsono/Obsidian mirror)
-- Games: 95206881 | 17625359962

local SUPPORTED = { [95206881] = true, [17625359962] = true }
if not SUPPORTED[game.PlaceId] then
    warn("[Ethereal.free] Unsupported game: " .. game.PlaceId)
    return
end

local repo = "https://raw.githubusercontent.com/visnoukkk/ObsidianLib/refs/heads/main/"
local Library      = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager  = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

getgenv().config = getgenv().config or {
    desync_enabled = false, desync_intensity = 50, desync_speed = 10,
    desync_angle = 90, desync_jitter = 20, desync_flip = false,
    desync_unhittable_enabled = false, desync_unhittable_intensity = 50,
    desync_unhittable_radius = 9000, desync_unhittable_iters = 100,
    desync_unhittable_y_range = 10,
    godmode_enabled = false, melee_bypass_enabled = false,
    melee_bypass_y_range = 10,
    vst_enabled = false, vst_type = "Unhittability",
    vst_spin_speed = 1e85, vst_unhittability_y_range = 10,
    evs_burst = 100, evs_kill_velocity = true, evs_snap_back = false,
    vs_void_direction = "Random",
    vs_min_dist = -10000000000, vs_max_dist = 10000000000,
    void_hide_enabled = false, void_hide_x = 1000000, void_hide_y = 9e25, void_hide_z = 1000000,
    void_hide_sync_to_ragebot = false,
    orbit_enabled = false, orbit_radius = 50000, orbit_speed = 5, orbit_height = 0,
    orbit_target = "Closest", orbit_direction = "Clockwise", orbit_axis = "Y",
    -- Prediction
    prediction_enabled = false, prediction_speed = 16, prediction_hz = 20,
}

local Toggles = Library.Toggles
local Options  = Library.Options

local Window = Library:CreateWindow({
    Title         = "Ethereal.free",
    Footer        = "Made by Insomnia and AJ",
    Center        = true,
    AutoShow      = true,
    ToggleKeybind = Enum.KeyCode.RightShift,
})

local Tabs = {
    Void       = Window:AddTab("VoidSpam",           "zap"),
    Orbit      = Window:AddTab("Orbit",              "rotate-cw"),
    AntiAim    = Window:AddTab("Anti-Aim",           "crosshair"),
    Prediction = Window:AddTab("Prediction",         "crosshair"),
    Movement   = Window:AddTab("Movement",           "move"),
    Config     = Window:AddTab("UI Settings",        "settings"),
}

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local VOID_RANGE  = 10000000000
local BILLION_    = 1e9
local INT32_MAX_  = 2147483647

local char, root, hum
local conns = {}

local function getChar() return LocalPlayer.Character end
local function getHRP()
    local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid")
end
local function killConn(key)
    if conns[key] then conns[key]:Disconnect(); conns[key] = nil end
end

local function Notify(msg, dur)
    Library:Notify({ Title = "Ethereal.free", Description = msg, Time = dur or 2 })
end

-- ─────────────────────────────────────────────
-- Target helpers
-- ─────────────────────────────────────────────
local function getClosest()
    if not root then return nil end
    local best, bestD = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LocalPlayer or not p.Character then continue end
        local hrp = p.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local d = (root.Position - hrp.Position).Magnitude
        if d < bestD then bestD = d; best = p end
    end
    return best
end

local function getTarget(mode)
    if mode == "Closest" then return getClosest() end
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            table.insert(list, p)
        end
    end
    if #list == 0 then return nil end
    if mode == "Random" then return list[math.random(1, #list)]
    elseif mode == "Weakest" then
        table.sort(list, function(a, b)
            local ha = a.Character:FindFirstChildOfClass("Humanoid")
            local hb = b.Character:FindFirstChildOfClass("Humanoid")
            return (ha and ha.Health or 0) < (hb and hb.Health or 0)
        end)
        return list[1]
    elseif mode == "Strongest" then
        table.sort(list, function(a, b)
            local ha = a.Character:FindFirstChildOfClass("Humanoid")
            local hb = b.Character:FindFirstChildOfClass("Humanoid")
            return (ha and ha.Health or 0) > (hb and hb.Health or 0)
        end)
        return list[1]
    end
    return list[1]
end

-- ─────────────────────────────────────────────
-- ORBIT CONFIG + LOGIC
-- ─────────────────────────────────────────────
local cfg = {
    orbitEnabled = false, orbitSpeed = 90, orbitDist = 8, orbitHeight = 0,
    orbitLerp = 0.3, orbitMode = "Circle", orbitPredict = false, orbitPredStr = 0.2,
    orbitFace = true, orbitLockDist = 999999999, orbitTarget = "Closest", orbitAxis = "XZ",
    orbitReverse = false, orbitRandRad = false, orbitRandMin = 5, orbitRandMax = 20,
    orbitYawOff = 0, orbitPitchOff = 0, orbitOffX = 0, orbitOffZ = 0,
    orbitHeightOscillate = false, orbitHeightOscAmp = 5, orbitHeightOscSpeed = 2,
    orbitSpeedRandom = false, orbitSpeedRandMin = 20, orbitSpeedRandMax = 200,
    orbitDistPulse = false, orbitDistPulseAmp = 5, orbitDistPulseSpeed = 1,
    orbitSnapBack = false, orbitSnapInterval = 0.5,
    orbitZigzag = false, orbitZigzagAmp = 3, orbitZigzagFreq = 4,
}

local orbitAngle, orbitLocalElapsed, orbitCurrentRadius = 0, 0, 0
local orbitSnapTimer = 0

local function startOrbit()
    killConn("orbit")
    orbitAngle = 0; orbitLocalElapsed = 0; orbitCurrentRadius = cfg.orbitDist
    orbitSnapTimer = 0
    if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end) end
    conns.orbit = RunService.Heartbeat:Connect(function(dt)
        if not cfg.orbitEnabled then killConn("orbit"); return end
        if not root then return end
        if hum then pcall(function()
            if hum:GetState() ~= Enum.HumanoidStateType.Physics then
                hum:ChangeState(Enum.HumanoidStateType.Physics)
            end
        end) end

        local target    = getTarget(cfg.orbitTarget)
        local targetPos = root.Position
        if target and target.Character then
            local hrp = target.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (root.Position - hrp.Position).Magnitude <= cfg.orbitLockDist then
                targetPos = hrp.Position
                if cfg.orbitPredict then
                    targetPos = targetPos + hrp.AssemblyLinearVelocity * cfg.orbitPredStr
                end
            end
        end

        local speed = cfg.orbitReverse and -cfg.orbitSpeed or cfg.orbitSpeed
        if cfg.orbitSpeedRandom then
            speed = cfg.orbitSpeedRandMin + math.random() * (cfg.orbitSpeedRandMax - cfg.orbitSpeedRandMin)
            if cfg.orbitReverse then speed = -speed end
        end

        orbitAngle        = (orbitAngle + math.rad(speed) * dt) % (2 * math.pi)
        orbitLocalElapsed = orbitLocalElapsed + dt

        local r = cfg.orbitRandRad and math.random(cfg.orbitRandMin, cfg.orbitRandMax) or cfg.orbitDist
        if cfg.orbitDistPulse then
            r = r + math.sin(orbitLocalElapsed * cfg.orbitDistPulseSpeed * 2 * math.pi) * cfg.orbitDistPulseAmp
        end

        local h = cfg.orbitHeight
        if cfg.orbitHeightOscillate then
            h = h + math.sin(orbitLocalElapsed * cfg.orbitHeightOscSpeed * 2 * math.pi) * cfg.orbitHeightOscAmp
        end

        local x, y, z = 0, 0, 0
        local ax = cfg.orbitAxis
        local om = cfg.orbitMode

        if om == "Circle" then
            if ax == "XZ" then x=math.cos(orbitAngle)*r; z=math.sin(orbitAngle)*r; y=h
            elseif ax == "XY" then x=math.cos(orbitAngle)*r; y=math.sin(orbitAngle)*r; z=h
            elseif ax == "YZ" then y=math.cos(orbitAngle)*r; z=math.sin(orbitAngle)*r; x=h end
        elseif om == "Figure 8" then
            x=math.sin(orbitAngle)*r; z=math.sin(orbitAngle)*math.cos(orbitAngle)*r*0.7; y=h
        elseif om == "Ellipse" then
            x=math.cos(orbitAngle)*r; z=math.sin(orbitAngle)*r*0.6; y=h
        elseif om == "Spiral In" then
            orbitCurrentRadius = math.max(1, orbitCurrentRadius - dt * cfg.orbitDist * 0.2)
            x=math.cos(orbitAngle)*orbitCurrentRadius; z=math.sin(orbitAngle)*orbitCurrentRadius; y=h
        elseif om == "Spiral Out" then
            orbitCurrentRadius = math.min(cfg.orbitDist*2, orbitCurrentRadius + dt * cfg.orbitDist * 0.2)
            x=math.cos(orbitAngle)*orbitCurrentRadius; z=math.sin(orbitAngle)*orbitCurrentRadius; y=h
        elseif om == "Bounce" then
            x=math.cos(orbitAngle)*r; z=math.sin(orbitAngle)*r; y=h+math.sin(orbitLocalElapsed*3)*5
        elseif om == "Lemniscate" then
            local denom = 1 + math.sin(orbitAngle)^2
            x=r*math.cos(orbitAngle)/denom; z=r*math.sin(orbitAngle)*math.cos(orbitAngle)/denom; y=h
        elseif om == "Infinity" then
            x=r*math.cos(orbitAngle); z=r*math.sin(2*orbitAngle)/2; y=h
        elseif om == "RandomOrbit" then
            local a=math.random()*2*math.pi; x=math.cos(a)*r; z=math.sin(a)*r; y=h
        end

        if cfg.orbitZigzag then
            x = x + math.sin(orbitLocalElapsed * cfg.orbitZigzagFreq * 2 * math.pi) * cfg.orbitZigzagAmp
        end

        x = x + cfg.orbitOffX; z = z + cfg.orbitOffZ
        local dst = targetPos + Vector3.new(x, y, z)

        if cfg.orbitSnapBack then
            orbitSnapTimer = orbitSnapTimer + dt
            if orbitSnapTimer >= cfg.orbitSnapInterval then
                orbitSnapTimer = 0
                dst = targetPos + Vector3.new(cfg.orbitOffX, h, cfg.orbitOffZ)
            end
        end

        local alpha  = math.min(1, 1 - (1 - cfg.orbitLerp)^(dt * 60))
        local smooth = root.Position:Lerp(dst, alpha)

        pcall(function()
            if cfg.orbitFace then
                local cf = CFrame.new(smooth, Vector3.new(targetPos.X, smooth.Y, targetPos.Z))
                cf = cf * CFrame.Angles(math.rad(cfg.orbitPitchOff), math.rad(cfg.orbitYawOff), 0)
                root.CFrame = cf
            else
                root.CFrame = CFrame.new(smooth)
            end
            root.AssemblyLinearVelocity  = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end)
end

local function stopOrbit()
    killConn("orbit"); cfg.orbitEnabled = false
    if hum then pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end) end
end

local orbitConfigSyncConn = nil
local function syncOrbitConfig()
    local c = getgenv().config
    if not c then return end
    if c.orbit_radius    ~= nil then cfg.orbitDist     = c.orbit_radius    end
    if c.orbit_speed     ~= nil then cfg.orbitSpeed    = c.orbit_speed     end
    if c.orbit_height    ~= nil then cfg.orbitHeight   = c.orbit_height    end
    if c.orbit_target    ~= nil then
        local t = c.orbit_target
        cfg.orbitTarget = (t == "Self") and "Closest" or (t or "Closest")
    end
    if c.orbit_direction ~= nil then cfg.orbitReverse  = (c.orbit_direction == "Counter-clockwise") end
    if c.orbit_axis      ~= nil then
        local a = c.orbit_axis
        if     a == "Y" then cfg.orbitAxis = "XZ"
        elseif a == "X" then cfg.orbitAxis = "YZ"
        elseif a == "Z" then cfg.orbitAxis = "XY" end
    end
end

getgenv().start_orbit = function()
    cfg.orbitEnabled = true
    syncOrbitConfig()
    startOrbit()
    if orbitConfigSyncConn then orbitConfigSyncConn:Disconnect() end
    orbitConfigSyncConn = RunService.Heartbeat:Connect(syncOrbitConfig)
end

getgenv().stop_orbit = function()
    if orbitConfigSyncConn then orbitConfigSyncConn:Disconnect(); orbitConfigSyncConn = nil end
    stopOrbit()
end

-- ─────────────────────────────────────────────
-- ANTI-AIM CONFIG + LOGIC
-- ─────────────────────────────────────────────
local aaSettings = {
    enabled = false, mode = "RandomSpin", speed = 5000,
    angle = 90, randomSpeed = true, jitterPitch = true,
    pitchAngle = 45, yawAngle = 45, staticYaw = 90, staticPitch = 0,
    customYaw = 180, customPitch = 0, jitterYaw = true,
    microJitter = false, microJitterAmp = 5, microJitterSpeed = 30,
    desyncMode = false, desyncOffset = 180,
    rollEnabled = false, rollSpeed = 360,
    breatheEffect = false, breatheAmp = 3, breatheSpeed = 1,
    randomFlip = false, flipChance = 0.05,
}

local aaAngAcc = 0; local aaRollAcc = 0; local aaJitter = 0
local aaMicroT = 0; local aaBreatheT = 0; local aaFlipTimer = 0

local function startAntiAim()
    killConn("antiAim")
    aaAngAcc=0; aaRollAcc=0; aaJitter=0; aaMicroT=0; aaBreatheT=0; aaFlipTimer=0
    conns.antiAim = RunService.Heartbeat:Connect(function(dt)
        if not aaSettings.enabled then killConn("antiAim"); return end
        if not root then return end

        local spd = aaSettings.speed
        if aaSettings.randomSpeed then spd = spd * (0.5 + math.random()) end

        aaRollAcc = aaRollAcc + dt; aaMicroT = aaMicroT + dt
        aaBreatheT = aaBreatheT + dt; aaFlipTimer = aaFlipTimer + dt

        local extraPitch, extraYaw = 0, 0
        if aaSettings.breatheEffect then
            extraPitch = math.sin(aaBreatheT * aaSettings.breatheSpeed * 2 * math.pi) * aaSettings.breatheAmp
        end
        if aaSettings.microJitter then
            extraYaw   = math.sin(aaMicroT * aaSettings.microJitterSpeed * 2 * math.pi) * aaSettings.microJitterAmp
            extraPitch = extraPitch + math.cos(aaMicroT * aaSettings.microJitterSpeed * 2 * math.pi) * aaSettings.microJitterAmp
        end
        if aaSettings.desyncMode  then extraYaw = extraYaw + aaSettings.desyncOffset end
        if aaSettings.randomFlip and math.random() < aaSettings.flipChance then extraYaw = extraYaw + 180 end

        local rollAngle = 0
        if aaSettings.rollEnabled then
            rollAngle = (aaRollAcc * aaSettings.rollSpeed * math.pi / 180) % (2 * math.pi)
        end

        local m = aaSettings.mode
        pcall(function()
            if m == "Spin" then
                aaAngAcc = aaAngAcc + spd * dt
                root.CFrame = CFrame.new(root.Position) * CFrame.Angles(math.rad(extraPitch), math.rad(aaAngAcc+extraYaw), rollAngle)
            elseif m == "Jitter" then
                local p = aaSettings.jitterPitch and aaSettings.pitchAngle or 0
                local y = aaSettings.jitterYaw   and aaSettings.yawAngle   or 0
                root.CFrame = root.CFrame * CFrame.Angles(
                    math.rad((aaJitter==0 and p or -p)+extraPitch),
                    math.rad((aaJitter==0 and y or -y)+extraYaw), rollAngle)
                aaJitter = (aaJitter+1) % 2
            elseif m == "Static" then
                root.CFrame = CFrame.new(root.Position) * CFrame.Angles(
                    math.rad(aaSettings.staticPitch+extraPitch), math.rad(aaSettings.staticYaw+extraYaw), rollAngle)
            elseif m == "Up" then
                root.CFrame = CFrame.new(root.Position) * CFrame.Angles(math.rad(90+extraPitch), math.rad(extraYaw), rollAngle)
            elseif m == "Down" then
                root.CFrame = CFrame.new(root.Position) * CFrame.Angles(math.rad(-90+extraPitch), math.rad(extraYaw), rollAngle)
            elseif m == "Side" then
                root.CFrame = CFrame.new(root.Position) * CFrame.Angles(math.rad(extraPitch), math.rad(extraYaw), math.rad(90)+rollAngle)
            elseif m == "RandomSpin" then
                aaAngAcc = aaAngAcc + spd * dt * (math.random()*2-1)
                root.CFrame = CFrame.new(root.Position) * CFrame.Angles(
                    math.rad(aaSettings.customPitch+extraPitch), math.rad(aaAngAcc+extraYaw), rollAngle)
            elseif m == "Custom" then
                root.CFrame = CFrame.new(root.Position) * CFrame.Angles(
                    math.rad(aaSettings.customPitch+extraPitch), math.rad(aaSettings.customYaw+extraYaw), rollAngle)
            end
        end)
    end)
end

local function stopAntiAim() killConn("antiAim"); aaSettings.enabled = false end

-- ─────────────────────────────────────────────
-- CHAR BIND
-- ─────────────────────────────────────────────
local function bindChar(c)
    char = c
    root = c:WaitForChild("HumanoidRootPart", 5)
    hum  = c:WaitForChild("Humanoid", 5)
    if cfg.orbitEnabled   then startOrbit()   end
    if aaSettings.enabled then startAntiAim() end
end

if LocalPlayer.Character then bindChar(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(function(c) task.wait(0.3); bindChar(c) end)
LocalPlayer.CharacterRemoving:Connect(function()
    killConn("orbit"); killConn("antiAim")
    root = nil; hum = nil; char = nil
end)

-- ─────────────────────────────────────────────
-- VOID SPAM LOGIC
-- ─────────────────────────────────────────────
local spiralT = 0

local function readBound(key, fallback)
    local v = Options[key] and Options[key].Value
    return v ~= nil and v or fallback
end

local function largeRandom(lo, hi)
    if hi <= lo then return lo end
    if hi - lo <= INT32_MAX_ then return math.random(lo, hi) end
    return math.floor(lo + math.random() * (hi - lo + 1))
end

local function randVec(lo, hi)
    return Vector3.new(largeRandom(lo,hi), largeRandom(lo,hi), largeRandom(lo,hi))
end

local function getVoidCF()
    local lo   = readBound("SpamMin", -VOID_RANGE)
    local hi   = readBound("SpamMax",  VOID_RANGE)
    local mode = Options.SpamMode  and Options.SpamMode.Value  or "Random"
    local yBias= (Options.SpamYBias and Options.SpamYBias.Value or 0)
    if mode == "Random" then return CFrame.new(randVec(lo, hi))
    elseif mode == "Directional" then return CFrame.new(Vector3.new(hi, yBias, hi))
    elseif mode == "Spiral" then
        local rate = Options.SpamSpiralRate and Options.SpamSpiralRate.Value or 5
        spiralT = spiralT + rate * 0.05
        return CFrame.new(math.cos(spiralT)*math.abs(hi), yBias, math.sin(spiralT)*math.abs(hi))
    elseif mode == "Cubic" then
        local pts = { Vector3.new(hi,hi,hi), Vector3.new(lo,hi,hi), Vector3.new(hi,lo,hi), Vector3.new(hi,hi,lo), Vector3.new(lo,lo,lo) }
        return CFrame.new(pts[math.random(1,#pts)])
    elseif mode == "Ping-Pong" then
        local amp  = (Options.SpamPingAmp and Options.SpamPingAmp.Value or 5) * BILLION_
        local sign = math.random(0,1)==0 and 1 or -1
        return CFrame.new(sign*amp, yBias, sign*amp)
    end
    return CFrame.new(randVec(lo, hi))
end

function _G.EtherealCSync()
    local hrp = getHRP(); if not hrp then return end
    local hum2  = getHum()
    local vmult = Options.SpamVelMult and Options.SpamVelMult.Value or 1
    pcall(function()
        if hum2 and Toggles.SpamAntiCorrect.Value then
            hum2:ChangeState(Enum.HumanoidStateType.Physics); hum2.PlatformStand = true
        end
        local cf  = getVoidCF()
        local vel = Toggles.SpamRandVel.Value
            and randVec(readBound("SpamMin", -VOID_RANGE), readBound("SpamMax", VOID_RANGE)) * vmult
            or  cf.Position * vmult
        hrp.CFrame = cf; hrp.AssemblyLinearVelocity = vel
        if not Toggles.SpamAsmOnly.Value then hrp.Velocity = vel end
        if Toggles.SpamDoubleFlush.Value then
            local cf2 = getVoidCF()
            hrp.CFrame = cf2; hrp.AssemblyLinearVelocity = cf2.Position * vmult
            if not Toggles.SpamAsmOnly.Value then hrp.Velocity = cf2.Position * vmult end
        end
    end)
end

local function resetChar()
    pcall(function()
        local hrp  = getHRP(); local hum2 = getHum()
        if hum2 and Toggles.SpamAntiCorrect.Value then
            hum2.PlatformStand = false; hum2:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        if hrp and Toggles.SpamFreezeOnHide.Value then
            hrp.AssemblyLinearVelocity  = Vector3.zero
            hrp.Velocity                = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end)
end

local spamThread = nil; local lastPos = Vector3.zero

local function stopSpam()
    if spamThread then task.cancel(spamThread); spamThread = nil end; resetChar()
end
local function startSpam()
    stopSpam()
    spamThread = task.spawn(function()
        while Toggles.SpamToggle.Value do
            local delay = Options.SpamDelay.Value  or 0.05
            local atk   = Options.SpamAttack.Value or 0.5
            local hide  = Options.SpamHide.Value   or 0.5
            local burst = Options.SpamBurst.Value  or 3
            local t = os.clock() + atk
            while os.clock() < t and Toggles.SpamToggle.Value do
                local hrp = getHRP(); if hrp then lastPos = hrp.Position end
                for _ = 1, burst do _G.EtherealCSync() end; task.wait(delay)
            end
            if Toggles.SpamToggle.Value then resetChar() end
            t = os.clock() + hide
            while os.clock() < t and Toggles.SpamToggle.Value do
                if Toggles.SpamAutoRetry.Value then
                    local hrp = getHRP(); local thresh = Options.SpamRetryThresh.Value or 50
                    if hrp and (hrp.Position - lastPos).Magnitude > thresh then break end
                end
                task.wait(0.05)
            end
        end
        spamThread = nil
    end)
end

-- [ANTI-TRANSLOCATION REMOVED]

-- ─────────────────────────────────────────────
-- PREDICTION (from kill_him roaxi)
-- ─────────────────────────────────────────────
local cfgDodge = {
    predEnabled = false, predRadius = 50, predDodgeDist = 50,
    predCooldown = 0.05, predThreshold = 500, predMult = 1,
    predLeadTime = 0.15, predShootDetect = true, predShootDot = 0.88,
    predShootDist = 60, predBulletSpd = 200, predReactTime = 0.08,
}

local antiBaitCFG = {
    enabled = false, velSpikeEnabled = true, velThreshold = 300,
    velDodgeDist = 80, flickerEnabled = true, flickerWindow = 0.3,
    flickerMinTps = 2, flickerTpDist = 10, dodgeCooldown = 0.02,
    dodgeMode = "Perpendicular", notifyOnDodge = true,
    dodgeOnShoot = true, shootLookThresh = 0.9,
    gunPredEnabled = true, gunPredDot = 0.85, gunPredVelMin = 50,
    gunPredDodgeDist = 70, gunPredCooldown = 0.05, gunPredLead = 0.12,
}

local lastDodgeTick = 0
local predShootCD   = {}
local antiBaitData  = {}
local lastAntiBaitDodge = 0
local gunDodgeCDs   = {}

local function predictPos_kh(hrp, lead)
    if not hrp then return Vector3.zero end
    local vel  = hrp.AssemblyLinearVelocity
    local grav = Vector3.new(0, -workspace.Gravity * 0.5, 0)
    return hrp.Position + vel * lead + grav * (lead * lead * 0.5)
end

local function enemyAimingAtMe(enemyHrp, myPos, dot)
    if not enemyHrp or not myPos then return false end
    local look = enemyHrp.CFrame.LookVector
    local toMe = (myPos - enemyHrp.Position)
    if toMe.Magnitude < 0.01 then return false end
    return look:Dot(toMe.Unit) > dot
end

local function perpDodgeDir(fromPos, myPos)
    local flat = Vector3.new(fromPos.X - myPos.X, 0, fromPos.Z - myPos.Z)
    if flat.Magnitude < 0.01 then flat = Vector3.new(1, 0, 0) end
    flat = flat.Unit
    local p1 = Vector3.new(-flat.Z, 0, flat.X)
    local p2 = Vector3.new(flat.Z,  0, -flat.X)
    local chosen = math.random(0,1) == 0 and p1 or p2
    return chosen + Vector3.new(0, (math.random()-0.5)*0.4, 0)
end

local function startPrediction()
    killConn("pred")
    conns.pred = RunService.Heartbeat:Connect(function(dt)
        if not cfgDodge.predEnabled then killConn("pred"); return end
        if not root then return end
        if hum and hum.Health <= 0 then return end
        local myPos = root.Position
        local now   = tick()
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LocalPlayer or not p.Character then continue end
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            if not hrp then continue end
            local vel       = hrp.AssemblyLinearVelocity
            local predicted = predictPos_kh(hrp, cfgDodge.predLeadTime * cfgDodge.predMult)
            if vel.Magnitude > cfgDodge.predThreshold
                and (predicted - myPos).Magnitude < cfgDodge.predRadius
                and now - lastDodgeTick > cfgDodge.predCooldown
            then
                lastDodgeTick = now
                local dir = perpDodgeDir(hrp.Position, myPos)
                root.CFrame = CFrame.new(myPos + dir * cfgDodge.predDodgeDist)
                Notify("dodged " .. p.Name, 1.5); break
            end
            if cfgDodge.predShootDetect then
                local tool = p.Character:FindFirstChildOfClass("Tool")
                if tool then
                    local aiming  = enemyAimingAtMe(hrp, myPos, cfgDodge.predShootDot)
                    local timeHit = (hrp.Position - myPos).Magnitude / math.max(cfgDodge.predBulletSpd, 1)
                    local key     = p.UserId
                    if aiming and timeHit < cfgDodge.predReactTime + 0.05 then
                        if not predShootCD[key] or now - predShootCD[key] > 0.3 then
                            predShootCD[key] = now
                            if now - lastDodgeTick > cfgDodge.predCooldown then
                                lastDodgeTick = now
                                local dir = perpDodgeDir(hrp.Position, myPos)
                                root.CFrame = CFrame.new(myPos + dir * cfgDodge.predShootDist)
                                Notify("shot dodge: " .. p.Name, 1.2); break
                            end
                        end
                    end
                end
            end
        end
    end)
end
local function stopPrediction() killConn("pred"); cfgDodge.predEnabled = false end

local function getDodgeDir(threatPos)
    if not root then return Vector3.new(1, 0, 0) end
    local flat = Vector3.new(threatPos.X - root.Position.X, 0, threatPos.Z - root.Position.Z)
    local away = flat.Magnitude > 0.01 and -flat.Unit or Vector3.new(1, 0, 0)
    local m = antiBaitCFG.dodgeMode
    if m == "Away" then return away
    elseif m == "Perpendicular" then
        local p = Vector3.new(-away.Z, 0, away.X)
        return math.random(0,1)==0 and p or -p
    else
        local a = math.random() * 2 * math.pi
        return Vector3.new(math.cos(a), 0, math.sin(a))
    end
end

local function doDodge(player, reason)
    if not root then return end
    local now = tick()
    if now - lastAntiBaitDodge < antiBaitCFG.dodgeCooldown then return end
    lastAntiBaitDodge = now
    local threatPos = Vector3.new(0, 0, 0)
    if player and player.Character then
        local h = player.Character:FindFirstChild("HumanoidRootPart")
        if h then threatPos = h.Position end
    end
    local dir    = getDodgeDir(threatPos)
    local newPos = root.Position + dir * antiBaitCFG.velDodgeDist
    pcall(function() root.CFrame = CFrame.new(newPos); root.AssemblyLinearVelocity = dir * 150 end)
    if antiBaitCFG.notifyOnDodge then
        Notify("anti-bait: " .. (player and player.Name or "?") .. " [" .. reason .. "]", 1.5)
    end
end

local function initBaitData(p)
    antiBaitData[p] = { lastPos = nil, tpTimes = {}, lastVel = Vector3.zero, lastTool = nil }
end

local function cleanBaitTimes(data)
    local now, clean = tick(), {}
    for _, t in ipairs(data.tpTimes) do
        if now - t < antiBaitCFG.flickerWindow then clean[#clean+1] = t end
    end
    data.tpTimes = clean
end

local function startAntiBait()
    killConn("antiBait")
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then initBaitData(p) end
    end
    conns.antiBait = RunService.Heartbeat:Connect(function(dt)
        if not antiBaitCFG.enabled then killConn("antiBait"); antiBaitCFG.enabled=false; antiBaitData={}; gunDodgeCDs={}; return end
        if not root then return end
        local myPos = root.Position
        local now   = tick()
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LocalPlayer or not p.Character then continue end
            local hrp = p.Character:FindFirstChild("HumanoidRootPart"); if not hrp then continue end
            local data = antiBaitData[p]
            if not data then initBaitData(p); data = antiBaitData[p] end
            local curPos = hrp.Position
            local curVel = hrp.AssemblyLinearVelocity
            if antiBaitCFG.gunPredEnabled then
                local tool = p.Character:FindFirstChildOfClass("Tool")
                if tool then
                    local aiming  = enemyAimingAtMe(hrp, myPos, antiBaitCFG.gunPredDot)
                    local key     = p.UserId
                    local predP   = predictPos_kh(hrp, antiBaitCFG.gunPredLead)
                    local predDist= (predP - myPos).Magnitude
                    if aiming and (curVel.Magnitude > antiBaitCFG.gunPredVelMin or predDist < 80) then
                        if not gunDodgeCDs[key] or now - gunDodgeCDs[key] > antiBaitCFG.gunPredCooldown then
                            gunDodgeCDs[key] = now
                            local dir    = perpDodgeDir(hrp.Position, myPos)
                            local newPos = myPos + dir * antiBaitCFG.gunPredDodgeDist
                            pcall(function() root.CFrame = CFrame.new(newPos); root.AssemblyLinearVelocity = dir * 200 end)
                            if antiBaitCFG.notifyOnDodge then Notify("gun dodge: " .. p.Name, 1.2) end
                        end
                    end
                end
            end
            if antiBaitCFG.dodgeOnShoot then
                local tool = p.Character:FindFirstChildOfClass("Tool")
                if tool then
                    local look = hrp.CFrame.LookVector
                    local toMe = (myPos - hrp.Position).Unit
                    if look:Dot(toMe) > antiBaitCFG.shootLookThresh and data.lastTool ~= tool then
                        doDodge(p, "shoot"); data.lastTool = tool
                    end
                end
            end
            if antiBaitCFG.velSpikeEnabled and curVel.Magnitude > antiBaitCFG.velThreshold then
                local toMe = (myPos - curPos)
                if toMe.Magnitude > 0.01 and curVel.Unit:Dot(toMe.Unit) > 0.6 then doDodge(p, "vel spike") end
            end
            if antiBaitCFG.flickerEnabled and data.lastPos then
                if (curPos - data.lastPos).Magnitude > antiBaitCFG.flickerTpDist then
                    data.tpTimes[#data.tpTimes+1] = tick()
                end
                cleanBaitTimes(data)
                if #data.tpTimes >= antiBaitCFG.flickerMinTps then
                    data.tpTimes = {}; doDodge(p, "flicker")
                end
            end
            data.lastPos = curPos; data.lastVel = curVel
        end
    end)
end

local function AddBindableToggle(group, flag, text, default, callback)
    local toggle = group:AddToggle(flag, { Text = text, Default = default or false, Callback = callback })
    toggle:AddKeyPicker(flag .. "Key", { Default = "None", Mode = "Toggle", Text = text, SyncToggleState = true, NoUI = false })
    return toggle
end

-- ─────────────────────────────────────────────
-- VOID HIDE
-- ─────────────────────────────────────────────
local void_hide_conn = nil

getgenv().start_void_hide = function()
    if void_hide_conn then void_hide_conn:Disconnect() end
    void_hide_conn = RunService.Heartbeat:Connect(function()
        local c = getgenv().config
        if not c or not c.void_hide_enabled then return end
        pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
        pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
        local hrp = getHRP()
        local hum2 = getHum()
        if not hrp or not hum2 or hum2.Health <= 0 then return end
        if hum2:GetState() ~= Enum.HumanoidStateType.Physics then
            hum2:ChangeState(Enum.HumanoidStateType.Physics)
        end
        local base = hrp.Position
        local hx = c.void_hide_x or 1e6
        local hy = c.void_hide_y or 9e25
        local hz = c.void_hide_z or 1e6
        local sx = (math.random() < 0.5) and 1 or -1
        local sz = (math.random() < 0.5) and 1 or -1
        pcall(function()
            hrp.CFrame = CFrame.new(base.X + sx * hx, base.Y - hy, base.Z + sz * hz)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end)
        pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
        pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
    end)
end

getgenv().stop_void_hide = function()
    if void_hide_conn then void_hide_conn:Disconnect(); void_hide_conn = nil end
    getgenv().config.void_hide_enabled = false
end

-- ─────────────────────────────────────────────
-- GODMODE / MELEE BYPASS
-- ─────────────────────────────────────────────
getgenv().get_hrp = getgenv().get_hrp or function(plr)
    local p = plr or LocalPlayer
    if not p.Character then return nil end
    return p.Character:FindFirstChild("HumanoidRootPart")
end

local melee_conn           = nil
local melee_active         = false
local melee_fake_cf_store  = {}
local MELEE_FAKE_OFFSET    = Vector3.new(9000, 9000, 9000)

local function melee_in_y_range(my_hrp, target_hrp)
    local cfg2   = getgenv().config
    local range  = cfg2.melee_bypass_y_range or 10
    local y_diff = my_hrp.Position.Y - target_hrp.Position.Y
    return y_diff >= 0 and y_diff <= range
end

getgenv().start_melee_bypass = function()
    if melee_active then return end
    melee_active = true
    getgenv().config.melee_bypass_enabled = true
    melee_conn = RunService.Heartbeat:Connect(function()
        local cfg2 = getgenv().config
        if not cfg2 or not cfg2.melee_bypass_enabled then return end
        local my_hrp = getgenv().get_hrp(LocalPlayer)
        if not my_hrp then return end
        pcall(function()
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    local h = p.Character:FindFirstChild("HumanoidRootPart")
                    if h then
                        if melee_in_y_range(my_hrp, h) then
                            melee_fake_cf_store[p] = h.CFrame
                            local mt     = getrawmetatable(h)
                            local old_ni = mt and rawget(mt, "__newindex")
                            local fake_cf = CFrame.new(MELEE_FAKE_OFFSET)
                            if old_ni then pcall(old_ni, h, "CFrame", fake_cf)
                            else rawset(h, "CFrame", fake_cf) end
                            h.AssemblyLinearVelocity = Vector3.zero
                        else melee_fake_cf_store[p] = nil end
                    end
                end
            end
        end)
    end)
end

getgenv().stop_melee_bypass = function()
    melee_active = false
    getgenv().config.melee_bypass_enabled = false
    if melee_conn then melee_conn:Disconnect(); melee_conn = nil end
    melee_fake_cf_store = {}
end

-- ─────────────────────────────────────────────
-- DESYNC
-- ─────────────────────────────────────────────
local desync_heartbeat             = nil
local desync_render                = nil
local desync_realVel               = nil
local desync_angle_accum           = 0
local desync_unhittable_conn       = nil
local desync_unhittable_render     = nil
local desync_unhittable_realCF     = nil
local desync_unhittable_fake_store = {}

getgenv().start_desync = function()
    if desync_heartbeat then desync_heartbeat:Disconnect() end
    if desync_render    then desync_render:Disconnect()    end
    desync_realVel = nil; desync_angle_accum = 0
    desync_heartbeat = RunService.Heartbeat:Connect(function(dt)
        local cfg2 = getgenv().config
        if not cfg2 or not cfg2.desync_enabled then return end
        local hrp = getgenv().get_hrp(LocalPlayer)
        if not hrp then return end
        desync_realVel  = hrp.AssemblyLinearVelocity
        local intensity = math.clamp(cfg2.desync_intensity or 50, 1, 100)
        local spd       = math.clamp(cfg2.desync_speed     or 10, 1, 100)
        local base_ang  = math.rad(cfg2.desync_angle or 90)
        local jitter    = math.clamp(cfg2.desync_jitter or 20, 0, 180)
        local dir_sign  = cfg2.desync_flip and -1 or 1
        desync_angle_accum = desync_angle_accum + math.rad(spd * dt * 360)
        local angle = base_ang + math.rad((math.random()-0.5)*jitter*2) + desync_angle_accum
        local mag   = (intensity/100) * 50000
        local spoof = Vector3.new(math.cos(angle)*mag*dir_sign, (math.random()-0.5)*mag*0.5, math.sin(angle)*mag*dir_sign)
        local mt = getrawmetatable(hrp)
        local ni = mt and rawget(mt, "__newindex")
        if ni then pcall(ni, hrp, "AssemblyLinearVelocity", spoof)
        else   pcall(function() hrp.AssemblyLinearVelocity = spoof end) end
        if sethiddenproperty then pcall(sethiddenproperty, hrp, "AssemblyLinearVelocity", spoof) end
    end)
    desync_render = RunService.RenderStepped:Connect(function()
        local cfg2 = getgenv().config
        local hrp = getgenv().get_hrp(LocalPlayer)
        if cfg2 and cfg2.desync_enabled and hrp and desync_realVel then
            hrp.AssemblyLinearVelocity = desync_realVel
        end
    end)
end

getgenv().stop_desync = function()
    if desync_heartbeat then desync_heartbeat:Disconnect(); desync_heartbeat = nil end
    if desync_render    then desync_render:Disconnect();    desync_render    = nil end
    desync_realVel = nil; desync_angle_accum = 0
    getgenv().config.desync_enabled = false
end

getgenv().start_unhittable_desync = function()
    if desync_unhittable_conn   then desync_unhittable_conn:Disconnect() end
    if desync_unhittable_render then desync_unhittable_render:Disconnect() end
    desync_unhittable_realCF = nil; desync_unhittable_fake_store = {}
    desync_unhittable_conn = RunService.Heartbeat:Connect(function()
        local cfg2 = getgenv().config
        if not cfg2 or not cfg2.desync_unhittable_enabled then return end
        local hrp = getgenv().get_hrp(LocalPlayer)
        if not hrp then return end
        desync_unhittable_realCF = hrp.CFrame
        local iters  = math.clamp(cfg2.desync_unhittable_iters or 100, 1, 500)
        local radius = math.max(cfg2.desync_unhittable_radius or 9000, 1)
        local yr     = math.max(cfg2.desync_unhittable_y_range or 10, 1)
        local offset = radius * (math.clamp(cfg2.desync_unhittable_intensity or 50, 1, 100)/100)
        local base   = hrp.Position
        local mt = getrawmetatable(hrp); local ni = mt and rawget(mt, "__newindex")
        for _ = 1, iters do
            local sx = (math.random()<0.5) and 1 or -1
            local sz = (math.random()<0.5) and 1 or -1
            local fake_cf = CFrame.new(base.X+sx*(offset*(0.5+math.random()*0.5)), base.Y+(math.random()-0.5)*offset*0.3, base.Z+sz*(offset*(0.5+math.random()*0.5)))
            if ni then pcall(ni, hrp, "CFrame", fake_cf); pcall(ni, hrp, "AssemblyLinearVelocity", Vector3.zero)
            else   pcall(function() hrp.CFrame=fake_cf; hrp.AssemblyLinearVelocity=Vector3.zero end) end
            if sethiddenproperty then pcall(sethiddenproperty, hrp, "CFrame", fake_cf); pcall(sethiddenproperty, hrp, "AssemblyLinearVelocity", Vector3.zero) end
        end
        pcall(function()
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    local eh = p.Character:FindFirstChild("HumanoidRootPart")
                    if eh then
                        local y_diff = hrp.Position.Y - eh.Position.Y
                        if y_diff >= 0 and y_diff <= yr then
                            desync_unhittable_fake_store[p] = eh.CFrame
                            local emt   = getrawmetatable(eh); local eni = emt and rawget(emt, "__newindex")
                            local fkcf  = CFrame.new(MELEE_FAKE_OFFSET)
                            if eni then pcall(eni, eh, "CFrame", fkcf)
                            else pcall(function() rawset(eh, "CFrame", fkcf) end) end
                            eh.AssemblyLinearVelocity = Vector3.zero
                        else desync_unhittable_fake_store[p] = nil end
                    end
                end
            end
        end)
    end)
    desync_unhittable_render = RunService.RenderStepped:Connect(function()
        local cfg2 = getgenv().config
        local hrp = getgenv().get_hrp(LocalPlayer)
        if cfg2 and cfg2.desync_unhittable_enabled and hrp and desync_unhittable_realCF then
            pcall(function() hrp.CFrame=desync_unhittable_realCF; hrp.AssemblyLinearVelocity=Vector3.zero end)
        end
    end)
end

getgenv().stop_unhittable_desync = function()
    if desync_unhittable_conn   then desync_unhittable_conn:Disconnect();   desync_unhittable_conn   = nil end
    if desync_unhittable_render then desync_unhittable_render:Disconnect(); desync_unhittable_render = nil end
    desync_unhittable_realCF = nil; desync_unhittable_fake_store = {}
    getgenv().config.desync_unhittable_enabled = false
end

-- ─────────────────────────────────────────────
-- CLIENT-SIDE PREDICTION
-- ─────────────────────────────────────────────
local pred_conn      = nil
local pred_seq       = 0
local pred_pending   = {}   -- [seq] = { pos, t }
local pred_serverPos = nil
local pred_lastSend  = 0

-- MoveRemote is optional — prediction still smooths client-side without it
-- FIXED: Using GetService to prevent DataModel "Ugc" error
local MoveRemote = game:GetService("ReplicatedStorage"):FindFirstChild("MoveRemote")

local function pred_sampleInput()
    local UIS = game:GetService("UserInputService")
    local dir = Vector3.zero
    if UIS:IsKeyDown(Enum.KeyCode.W) then dir += Vector3.new( 0, 0,-1) end
    if UIS:IsKeyDown(Enum.KeyCode.S) then dir += Vector3.new( 0, 0, 1) end
    if UIS:IsKeyDown(Enum.KeyCode.A) then dir += Vector3.new(-1, 0, 0) end
    if UIS:IsKeyDown(Enum.KeyCode.D) then dir += Vector3.new( 1, 0, 0) end
    return dir.Magnitude > 0 and dir.Unit or Vector3.zero
end

-- Server correction callback — call this when your RemoteEvent fires back
-- with the authoritative position. Wires up automatically if MoveRemote exists.
getgenv().pred_onServerCorrect = function(serverPos)
    pred_serverPos = serverPos
    -- Reconcile: discard all pending moves older than the correction
    -- then reapply the rest from the corrected base
    local hrp = getHRP(); if not hrp then return end
    local replayPos = serverPos
    local cfg2 = getgenv().config
    -- we don't have dt stored per-pending so we use a fixed step
    local fixedDt = 1 / (cfg2.prediction_hz or 20)
    local speed   = cfg2.prediction_speed or 16
    -- rebuild position from remaining unacked inputs
    local keys = {}
    for seq in pairs(pred_pending) do keys[#keys+1] = seq end
    table.sort(keys)
    for _, seq in ipairs(keys) do
        local p = pred_pending[seq]
        replayPos = replayPos + p.inputDir * speed * fixedDt
    end
    pcall(function()
        hrp.CFrame = CFrame.new(Vector3.new(replayPos.X, hrp.Position.Y, replayPos.Z))
    end)
end

-- Wire server correction if remote exists
if MoveRemote then
    MoveRemote.OnClientEvent:Connect(function(serverPos)
        if typeof(serverPos) == "Vector3" then
            getgenv().pred_onServerCorrect(serverPos)
        end
    end)
end

getgenv().start_prediction = function()
    if pred_conn then pred_conn:Disconnect() end
    pred_seq = 0; pred_pending = {}; pred_serverPos = nil; pred_lastSend = 0
    pred_conn = RunService.Heartbeat:Connect(function(dt)
        local cfg2 = getgenv().config
        if not cfg2 or not cfg2.prediction_enabled then return end
        local hrp = getHRP(); if not hrp then return end
        local hum2 = getHum(); if not hum2 or hum2.Health <= 0 then return end

        local speed    = cfg2.prediction_speed or 16
        local sendHz   = cfg2.prediction_hz    or 20
        local inputDir = pred_sampleInput()

        -- Predict: move locally this frame
        if inputDir.Magnitude > 0 then
            local delta = Vector3.new(inputDir.X, 0, inputDir.Z) * speed * dt
            pcall(function()
                hrp.CFrame = CFrame.new(hrp.Position + delta)
                    * CFrame.Angles(0, math.atan2(-inputDir.X, -inputDir.Z), 0)
            end)
        end

        -- Send input to server at fixed rate
        pred_lastSend = pred_lastSend + dt
        if pred_lastSend >= (1 / sendHz) then
            pred_lastSend = 0
            pred_seq = pred_seq + 1
            -- store for reconciliation
            pred_pending[pred_seq] = {
                inputDir = inputDir,
                pos      = hrp.Position,
                t        = tick(),
            }
            -- flush stale unacked inputs older than 2s (server probably dropped them)
            local now = tick()
            for seq, data in pairs(pred_pending) do
                if now - data.t > 2 then pred_pending[seq] = nil end
            end
            -- fire remote if it exists
            if MoveRemote then
                pcall(function()
                    MoveRemote:FireServer(pred_seq, inputDir, hrp.Position)
                end)
            end
        end
    end)
end

getgenv().stop_prediction = function()
    if pred_conn then pred_conn:Disconnect(); pred_conn = nil end
    pred_seq = 0; pred_pending = {}; pred_serverPos = nil
    getgenv().config.prediction_enabled = false
end

-- ─────────────────────────────────────────────
-- VOIDSPAM TYPE
-- ─────────────────────────────────────────────
local vst_conn         = nil
local void_spin_conn   = nil
local vst_phase        = "hide"
local vst_phase_start  = 0
local vst_last_pos     = nil
local MELEE_FAKE_OFFSET_VST = Vector3.new(9000, 9000, 9000)

local function vst_get_direction_offset(base_pos, dist)
    local c        = getgenv().config
    local dir_mode = c.vs_void_direction or "Random"
    local cam      = workspace.CurrentCamera
    if dir_mode == "Forward" then
        local look = cam and Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z) or Vector3.new(0,0,-1)
        if look.Magnitude > 0.001 then look = look.Unit else look = Vector3.new(0,0,-1) end
        return Vector3.new(look.X*dist, (math.random()<0.5 and 1 or -1)*dist, look.Z*dist)
    elseif dir_mode == "Backward" then
        local look = cam and Vector3.new(-cam.CFrame.LookVector.X, 0, -cam.CFrame.LookVector.Z) or Vector3.new(0,0,1)
        if look.Magnitude > 0.001 then look = look.Unit else look = Vector3.new(0,0,1) end
        return Vector3.new(look.X*dist, (math.random()<0.5 and 1 or -1)*dist, look.Z*dist)
    elseif dir_mode == "Left" then
        local right = cam and cam.CFrame.RightVector or Vector3.new(1,0,0)
        local left = Vector3.new(-right.X, 0, -right.Z)
        if left.Magnitude > 0.001 then left = left.Unit else left = Vector3.new(-1,0,0) end
        return Vector3.new(left.X*dist, (math.random()<0.5 and 1 or -1)*dist, left.Z*dist)
    elseif dir_mode == "Right" then
        local right = cam and Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z) or Vector3.new(1,0,0)
        if right.Magnitude > 0.001 then right = right.Unit else right = Vector3.new(1,0,0) end
        return Vector3.new(right.X*dist, (math.random()<0.5 and 1 or -1)*dist, right.Z*dist)
    elseif dir_mode == "Up" then
        return Vector3.new((math.random()-0.5)*dist*0.2, dist, (math.random()-0.5)*dist*0.2)
    elseif dir_mode == "Down" then
        return Vector3.new((math.random()-0.5)*dist*0.2, -dist, (math.random()-0.5)*dist*0.2)
    elseif dir_mode == "Camera" then
        local look = cam and cam.CFrame.LookVector or Vector3.new(0,0,-1)
        return look * dist
    else
        local lo = c.vs_min_dist or -VOID_RANGE
        local hi = c.vs_max_dist or  VOID_RANGE
        local ir = math.max(math.abs(hi), math.abs(lo), 1)
        local sx = (math.random()<0.5) and 1 or -1
        local sy = (math.random()<0.5) and 1 or -1
        local sz = (math.random()<0.5) and 1 or -1
        return Vector3.new(sx*(ir*(0.5+math.random()*0.5)), sy*(ir*(0.5+math.random()*0.5)), sz*(ir*(0.5+math.random()*0.5)))
    end
end

local function vst_do_defend_burst(hrp)
    local c    = getgenv().config
    local iters     = math.clamp(c.evs_burst or 100, 1, 500)
    local ir        = math.max(math.abs(c.vs_max_dist or VOID_RANGE), math.abs(c.vs_min_dist or -VOID_RANGE), 1)
    local base_dist = ir * (0.5 + math.random()*0.5)
    for _ = 1, iters do
        local base   = vst_last_pos or hrp.Position
        local offset = vst_get_direction_offset(base, base_dist)
        pcall(function() hrp.CFrame = CFrame.new(base + offset) end)
        vst_last_pos = hrp.Position
    end
    if c.evs_kill_velocity ~= false then
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end
    pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
    pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
end

local function vst_suppress_enemies(hrp)
    local c  = getgenv().config
    local yr = math.max(c.vst_unhittability_y_range or 10, 1)
    pcall(function()
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local eh = p.Character:FindFirstChild("HumanoidRootPart")
                if eh then
                    local y_diff = hrp.Position.Y - eh.Position.Y
                    if y_diff >= 0 and y_diff <= yr then
                        local emt  = getrawmetatable and getrawmetatable(eh)
                        local eni  = emt and rawget(emt, "__newindex")
                        local fkcf = CFrame.new(MELEE_FAKE_OFFSET_VST)
                        if eni then pcall(eni, eh, "CFrame", fkcf)
                        else pcall(function() rawset(eh, "CFrame", fkcf) end) end
                        eh.AssemblyLinearVelocity = Vector3.zero
                    end
                end
            end
        end
    end)
end

getgenv().start_voidspam_type = function()
    if vst_conn        then vst_conn:Disconnect() end
    if void_spin_conn  then void_spin_conn:Disconnect() end
    vst_phase       = "hide"
    vst_phase_start = tick()
    vst_last_pos    = nil

    void_spin_conn = RunService.Heartbeat:Connect(function()
        local c = getgenv().config
        if not c or not c.vst_enabled then return end
        local char2 = LocalPlayer.Character; if not char2 then return end
        local spd   = c.vst_spin_speed or 1e85
        local spinCF = CFrame.Angles(0, (tick()*spd)%(2*math.pi), 0)
        pcall(function()
            for _, v in pairs(char2:GetDescendants()) do
                if v:IsA("Motor6D") then v.Transform = spinCF end
            end
        end)
    end)

    vst_conn = RunService.Heartbeat:Connect(function()
        local c = getgenv().config
        if not c or not c.vst_enabled then return end
        pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
        pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
        local hrp  = getHRP(); if not hrp then return end
        local hum2 = getHum(); if not hum2 or hum2.Health <= 0 then return end
        local vtype = c.vst_type or "Unhittability"
        if vtype ~= "Bait" then
            if hum2:GetState() ~= Enum.HumanoidStateType.Physics then
                hum2:ChangeState(Enum.HumanoidStateType.Physics)
            end
        end
        pcall(function()
            if vtype == "Unhittability" then
                vst_do_defend_burst(hrp)
                vst_suppress_enemies(hrp)
            elseif vtype == "Defend" then
                vst_do_defend_burst(hrp)
            elseif vtype == "Bait" then
                local cur = hrp.Position
                local depth = math.clamp(c.vst_bait_depth or 20, 1, 40)
                hrp.CFrame = CFrame.new(cur.X, cur.Y - depth, cur.Z)
                hrp.AssemblyLinearVelocity  = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            elseif vtype == "Extreme" then
                local cur = hrp.Position
                pcall(function() hrp.CFrame = CFrame.new(cur.X, cur.Y - 9e25, cur.Z) end)
                hrp.AssemblyLinearVelocity  = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            elseif vtype == "Random" or vtype == "Attack" then
                vst_do_defend_burst(hrp)
            end
        end)
        pcall(function() workspace.FallenPartsDestroyHeight = -math.huge end)
        pcall(function() workspace.FallenPartsDestroyHeight = 0/0 end)
    end)
end

getgenv().stop_voidspam_type = function()
    if vst_conn       then vst_conn:Disconnect();       vst_conn       = nil end
    if void_spin_conn then void_spin_conn:Disconnect(); void_spin_conn = nil end
    vst_last_pos = nil
    local c = getgenv().config; if c then c.vst_enabled = false end
end

getgenv().disable_voidspam_type = getgenv().stop_voidspam_type

-- ─────────────────────────────────────────────
-- XYZ OVERLAY
-- ─────────────────────────────────────────────
local _xyzSg, _xyzConn, _xyzVals

local function buildXYZOverlay()
    if _xyzSg and _xyzSg.Parent then return end
    local sg = Instance.new("ScreenGui")
    sg.Name = "EtherealXYZOverlay"; sg.ResetOnSpawn = false; sg.DisplayOrder = 9999
    local coreOk = pcall(function() sg.Parent = game:GetService("CoreGui") end)
    if not coreOk then sg.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    _xyzSg = sg
    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0, 170, 0, 96); panel.Position = UDim2.new(0, 14, 0.5, -48)
    panel.BackgroundColor3 = Color3.fromRGB(18, 18, 20); panel.BackgroundTransparency = 0.08
    panel.BorderSizePixel = 0; panel.Parent = sg
    local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0,7); pc.Parent = panel
    _xyzVals = {}
    for i, axis in ipairs({"X","Y","Z"}) do
        local y = 30 + (i-1)*20
        local al = Instance.new("TextLabel")
        al.Size = UDim2.new(0,18,0,18); al.Position = UDim2.new(0,10,0,y)
        al.BackgroundTransparency = 1; al.Text = axis
        al.TextColor3 = Color3.fromRGB(120,120,130); al.Font = Enum.Font.GothamBold
        al.TextSize = 12; al.TextXAlignment = Enum.TextXAlignment.Left; al.Parent = panel
        local vl = Instance.new("TextLabel")
        vl.Size = UDim2.new(1,-30,0,18); vl.Position = UDim2.new(0,14,0,y)
        vl.BackgroundTransparency = 1; vl.Text = "0"
        vl.TextColor3 = Color3.fromRGB(230,230,235); vl.Font = Enum.Font.Gotham
        vl.TextSize = 12; vl.TextXAlignment = Enum.TextXAlignment.Right; vl.Parent = panel
        _xyzVals[axis] = vl
    end
    _xyzConn = RunService.Heartbeat:Connect(function()
        local c = LocalPlayer.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if hrp then
            local p = hrp.Position
            _xyzVals.X.Text = tostring(math.floor(p.X+0.5))
            _xyzVals.Y.Text = tostring(math.floor(p.Y+0.5))
            _xyzVals.Z.Text = tostring(math.floor(p.Z+0.5))
        else _xyzVals.X.Text="-"; _xyzVals.Y.Text="-"; _xyzVals.Z.Text="-" end
    end)
end

local function destroyXYZOverlay()
    if _xyzConn then pcall(function() _xyzConn:Disconnect() end); _xyzConn = nil end
    if _xyzSg   then pcall(function() _xyzSg:Destroy() end);     _xyzSg   = nil end
end

-- ─────────────────────────────────────────────
-- UI: Void Tab
-- ─────────────────────────────────────────────
local VLeft  = Tabs.Void:AddLeftGroupbox("Void")
local VRight = Tabs.Void:AddRightGroupbox("Void Hide")

VLeft:AddToggle("vs_en", { Text="Void", Default=false, Tooltip="Makes you unhittable utilizing void movement." }):OnChanged(function(v)
    local cfg2 = getgenv().config
    cfg2.vst_enabled = v
    if v then
        pcall(getgenv().start_voidspam_type)
        buildXYZOverlay()
        if (cfg2.vst_type or "Unhittability") == "Unhittability" then
            cfg2.melee_bypass_enabled = true
            cfg2.melee_bypass_y_range = cfg2.vst_unhittability_y_range or 10
            if not melee_active then getgenv().start_melee_bypass() end
        end
    else
        pcall(getgenv().disable_voidspam_type)
        destroyXYZOverlay()
        if not cfg2.godmode_enabled then getgenv().stop_melee_bypass() end
    end
end)

VLeft:AddDropdown("vs_type_sel", { Text="Void Mode", Default=1, Values={"Unhittability","Defend","Attack","Bait","Extreme","Random"} }):OnChanged(function(v)
    local cfg2 = getgenv().config
    cfg2.vst_type = v
    if cfg2.vst_enabled then
        pcall(getgenv().stop_voidspam_type); pcall(getgenv().start_voidspam_type)
        if v == "Unhittability" then
            cfg2.melee_bypass_enabled = true
            cfg2.melee_bypass_y_range = cfg2.vst_unhittability_y_range or 10
            if not melee_active then getgenv().start_melee_bypass() end
        else
            if not cfg2.godmode_enabled then getgenv().stop_melee_bypass() end
        end
    end
end)

VLeft:AddDropdown("vs_void_dir_sel", { Text="Void Direction", Default=1, Values={"Random","Forward","Backward","Left","Right","Up","Down","Camera","Directional"} }):OnChanged(function(v)
    local cfg2=getgenv().config; cfg2.vs_void_direction=v
end)

VLeft:AddSlider("vst_spin_spd",  { Text="Spin Speed",    Default=1e85, Min=1, Max=1e85,   Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.vst_spin_speed=v end)
VLeft:AddSlider("evs_burst_sl",  { Text="Iterations",    Default=100,  Min=1, Max=1000,   Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.evs_burst=v end)
VLeft:AddToggle("evs_kv_tog",    { Text="Kill Velocity", Default=true  }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.evs_kill_velocity=v end)
VLeft:AddToggle("evs_sb_tog",    { Text="Snap Back",     Default=false }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.evs_snap_back=v end)
VLeft:AddToggle("evs_srb_tog",   { Text="Sync To Ragebot", Default=false }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.evs_sync_to_ragebot=v end)
VLeft:AddToggle("vs_char_orig",  { Text="Character Origin", Default=false }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.vs_char_origin=v end)
VLeft:AddSlider("vst_unhit_yr",  { Text="Activation Range", Default=10, Min=1, Max=50, Rounding=0, Tooltip="Activates melee bypass when enemy is within this Y below you." }):OnChanged(function(v)
    local cfg2=getgenv().config; cfg2.vst_unhittability_y_range=v; cfg2.melee_bypass_y_range=v
end)

VLeft:AddSlider("vs_min_dist_sl", {
    Text    = "Min Distance",
    Default = -10000000000,
    Min     = -10000000000,
    Max     = 10000000000,
    Rounding = 0,
}):OnChanged(function(v) local cfg2=getgenv().config; cfg2.vs_min_dist=v end)

VLeft:AddSlider("vs_max_dist_sl", {
    Text    = "Max Distance",
    Default = 10000000000,
    Min     = -10000000000,
    Max     = 10000000000,
    Rounding = 0,
}):OnChanged(function(v) local cfg2=getgenv().config; cfg2.vs_max_dist=v end)

VRight:AddToggle("vh_en", { Text="Void Hide", Default=false, Tooltip="Teleports you into the void." }):OnChanged(function(v)
    local cfg2=getgenv().config; cfg2.void_hide_enabled=v
    if v then pcall(getgenv().start_void_hide) else pcall(getgenv().stop_void_hide) end
end)
VRight:AddSlider("vh_x", { Text="X Distance", Default=1000000, Min=1, Max=12e25, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.void_hide_x=v end)
VRight:AddSlider("vh_y", { Text="Y Distance", Default=9e25,    Min=1, Max=12e25, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.void_hide_y=v end)
VRight:AddSlider("vh_z", { Text="Z Distance", Default=1000000, Min=1, Max=12e25, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.void_hide_z=v end)
VRight:AddToggle("vh_srb", { Text="Sync To Ragebot", Default=false }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.void_hide_sync_to_ragebot=v end)

-- ─────────────────────────────────────────────
-- UI: Orbit Tab
-- ─────────────────────────────────────────────
local OLeft  = Tabs.Orbit:AddLeftGroupbox("Orbit")
local ORight = Tabs.Orbit:AddRightGroupbox("Orbit Advanced")

OLeft:AddToggle("orbit_en", { Text="Orbit", Default=false, Tooltip="Orbits your character in a void-driven orbital pattern." }):OnChanged(function(v)
    local cfg2=getgenv().config; cfg2.orbit_enabled=v
    if v then pcall(getgenv().start_orbit); buildXYZOverlay() else pcall(getgenv().stop_orbit); destroyXYZOverlay() end
end)
OLeft:AddSlider("orbit_rad",    { Text="Orbit Radius",  Default=50000, Min=1,       Max=500000, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_radius=v end)
OLeft:AddSlider("orbit_spd",    { Text="Orbit Speed",   Default=5,     Min=1,       Max=200,    Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_speed=v end)
OLeft:AddSlider("orbit_iters",  { Text="Iterations",    Default=100,   Min=1,       Max=500,    Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_iters=v end)
OLeft:AddSlider("orbit_hgt",    { Text="Height Offset", Default=0,     Min=-500000, Max=500000, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_height=v end)
OLeft:AddSlider("orbit_jit",    { Text="Jitter",        Default=0,     Min=0,       Max=100000, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_jitter=v end)
OLeft:AddSlider("orbit_yb",     { Text="Y Bias",        Default=0,     Min=-500000, Max=0,      Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_y_bias=v end)
OLeft:AddSlider("orbit_df",     { Text="Depth Floor",   Default=0,     Min=0,       Max=500000, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_depth_floor=v end)
OLeft:AddSlider("orbit_tight",  { Text="Tightness",     Default=10,    Min=1,       Max=100,    Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_tightness=v end)
OLeft:AddSlider("orbit_wfreq",  { Text="Wave Freq",     Default=1,     Min=1,       Max=20,     Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_wave_freq=v end)
OLeft:AddSlider("orbit_phase",  { Text="Phase Offset",  Default=0,     Min=0,       Max=360,    Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_phase_offset=math.rad(v) end)
OLeft:AddSlider("orbit_layers", { Text="Layer Count",   Default=1,     Min=1,       Max=8,      Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_layer_count=v end)
OLeft:AddSlider("orbit_loff",   { Text="Layer Offset",  Default=0,     Min=0,       Max=360,    Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_layer_offset=v end)
OLeft:AddSlider("orbit_wstr",   { Text="Warp Strength", Default=50,    Min=1,       Max=100,    Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_warp_strength=v end)
OLeft:AddSlider("orbit_chaos",  { Text="Chaos Blend",   Default=0,     Min=0,       Max=100,    Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_chaos_blend=v end)
OLeft:AddDropdown("orbit_pat_sel",    { Text="Pattern",    Default=1, Values={"Circle","Ellipse","Figure8","Helix","Wave","Spiral","Pulse"} }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_pattern=v end)
OLeft:AddDropdown("orbit_target_sel", { Text="Target",     Default=1, Values={"Self","Closest"} }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_target=v end)
OLeft:AddDropdown("orbit_axis_sel",   { Text="Orbit Axis", Default=1, Values={"Y","X","Z"} }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_axis=v end)
OLeft:AddDropdown("orbit_dir_sel",    { Text="Direction",  Default=1, Values={"Clockwise","Counter-clockwise"} }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_direction=v end)
OLeft:AddDropdown("orbit_warp_sel",   { Text="Warp Mode",  Default=1, Values={"Instant","Lerp","Spring","Bounce","Elastic"} }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_warp_mode=v end)
OLeft:AddDropdown("orbit_fall_sel",   { Text="Falloff",    Default=1, Values={"None","Linear","Exp","Sine","Cosine"} }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_falloff=v end)
OLeft:AddToggle("orbit_kv",  { Text="Kill Velocity",   Default=true  }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_kill_velocity=v end)
OLeft:AddToggle("orbit_srb", { Text="Sync To Ragebot", Default=false }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_sync_ragebot=v end)
OLeft:AddToggle("orbit_ix",  { Text="Invert X",        Default=false }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_invert_x=v end)
OLeft:AddToggle("orbit_iz",  { Text="Invert Z",        Default=false }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.orbit_invert_z=v end)

-- ─────────────────────────────────────────────
-- UI: Movement Tab
-- ─────────────────────────────────────────────
local BoxDesync     = Tabs.Movement:AddLeftGroupbox("Desync")
local BoxGodmode    = Tabs.Movement:AddRightGroupbox("Godmode")
local BoxPrediction = Tabs.Movement:AddLeftGroupbox("Prediction")

BoxDesync:AddToggle("ds_en", { Text="Desync", Default=false, Tooltip="Spoofs your server-side velocity." }):OnChanged(function(v)
    local cfg2=getgenv().config; cfg2.desync_enabled=v
    if v then getgenv().start_desync() else getgenv().stop_desync() end
end)
BoxDesync:AddSlider("ds_int",  { Text="Intensity", Default=50, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.desync_intensity=v end)
BoxDesync:AddSlider("ds_spd",  { Text="Speed",     Default=10, Min=1, Max=100, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.desync_speed=v end)
BoxDesync:AddSlider("ds_ang",  { Text="Angle",     Default=90, Min=0, Max=360, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.desync_angle=v end)
BoxDesync:AddSlider("ds_jit",  { Text="Jitter",    Default=20, Min=0, Max=180, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.desync_jitter=v end)
BoxDesync:AddToggle("ds_flip", { Text="Flip", Default=false }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.desync_flip=v end)
BoxDesync:AddToggle("ds_uhit_en", { Text="Unhittable Desync", Default=false }):OnChanged(function(v)
    local cfg2=getgenv().config; cfg2.desync_unhittable_enabled=v
    if v then getgenv().start_unhittable_desync() else getgenv().stop_unhittable_desync() end
end)
BoxDesync:AddSlider("ds_uhit_int",   { Text="Unhittable Intensity",  Default=50,   Min=1,   Max=100,    Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.desync_unhittable_intensity=v end)
BoxDesync:AddSlider("ds_uhit_rad",   { Text="Unhittable Radius",     Default=9000, Min=100, Max=100000, Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.desync_unhittable_radius=v end)
BoxDesync:AddSlider("ds_uhit_iters", { Text="Unhittable Iterations", Default=100,  Min=1,   Max=500,    Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.desync_unhittable_iters=v end)
BoxDesync:AddSlider("ds_uhit_yr",    { Text="Activation Range",      Default=10,   Min=1,   Max=50,     Rounding=0 }):OnChanged(function(v) local cfg2=getgenv().config; cfg2.desync_unhittable_y_range=v end)

BoxGodmode:AddToggle("gm_en", { Text="Godmode", Default=false }):OnChanged(function(v)
    local cfg2=getgenv().config
    cfg2.godmode_enabled=v; cfg2.melee_bypass_enabled=v
    if v then getgenv().start_melee_bypass() else getgenv().stop_melee_bypass() end
end)
BoxGodmode:AddSlider("gm_yr", { Text="Activation Range", Default=10, Min=1, Max=50, Rounding=0 }):OnChanged(function(v)
    local cfg2=getgenv().config; cfg2.godmode_y_range=v; cfg2.melee_bypass_y_range=v
end)

BoxPrediction:AddToggle("pred_en", { Text="Prediction", Default=false, Tooltip="Client-side movement prediction — moves you locally before server confirms." }):OnChanged(function(v)
    local cfg2=getgenv().config; cfg2.prediction_enabled=v
    if v then getgenv().start_prediction() else getgenv().stop_prediction() end
end)
BoxPrediction:AddSlider("pred_spd", { Text="Move Speed", Default=16, Min=1, Max=100, Rounding=1,
    Tooltip="Studs/s — match to server walk speed for clean reconciliation." }):OnChanged(function(v)
    local cfg2=getgenv().config; cfg2.prediction_speed=v
end)
BoxPrediction:AddSlider("pred_hz", { Text="Send Rate (hz)", Default=20, Min=5, Max=60, Rounding=0,
    Tooltip="How often inputs are sent to the server." }):OnChanged(function(v)
    local cfg2=getgenv().config; cfg2.prediction_hz=v
end)

-- ─────────────────────────────────────────────
-- UI: Anti-Aim Tab
-- ─────────────────────────────────────────────
local AALeft  = Tabs.AntiAim:AddLeftGroupbox("Anti-Aim")
local AARight = Tabs.AntiAim:AddRightGroupbox("Advanced")

AALeft:AddToggle("AaToggle", { Text="Enable Anti-Aim", Default=false, Tooltip="Manipulates HRP angles server-side to break hitscan",
    Callback=function(v) aaSettings.enabled=v; if v then startAntiAim() else stopAntiAim() end end })
AALeft:AddDropdown("AaMode", { Text="Mode", Default="RandomSpin",
    Values={"Spin","Jitter","Static","Up","Down","Side","RandomSpin","Custom"},
    Callback=function(v) aaSettings.mode=v end })
AALeft:AddSlider("AaSpeed",    { Text="Speed (deg/s)",  Default=5000, Min=100, Max=5000, Rounding=0, Callback=function(v) aaSettings.speed=v end })
AALeft:AddSlider("AaPitch",    { Text="Pitch Angle",    Default=45,   Min=0,   Max=90,   Rounding=0, Callback=function(v) aaSettings.pitchAngle=v end })
AALeft:AddSlider("AaYaw",      { Text="Yaw Angle",      Default=45,   Min=0,   Max=180,  Rounding=0, Callback=function(v) aaSettings.yawAngle=v end })
AALeft:AddSlider("AaStaticYaw",{ Text="Static Yaw",     Default=90,   Min=-360,Max=360,  Rounding=0, Callback=function(v) aaSettings.staticYaw=v end })
AALeft:AddSlider("AaStaticPit",{ Text="Static Pitch",   Default=0,    Min=-90, Max=90,   Rounding=0, Callback=function(v) aaSettings.staticPitch=v end })
AALeft:AddSlider("AaCustomYaw",{ Text="Custom Yaw",     Default=180,  Min=-360,Max=360,  Rounding=0, Callback=function(v) aaSettings.customYaw=v end })
AALeft:AddSlider("AaCustomPit",{ Text="Custom Pitch",   Default=0,    Min=-90, Max=90,   Rounding=0, Callback=function(v) aaSettings.customPitch=v end })
AALeft:AddToggle("AaRandSpd",  { Text="Random Speed",   Default=true,  Callback=function(v) aaSettings.randomSpeed=v end })
AALeft:AddToggle("AaJitPitch", { Text="Jitter Pitch",   Default=true,  Callback=function(v) aaSettings.jitterPitch=v end })
AALeft:AddToggle("AaJitYaw",   { Text="Jitter Yaw",     Default=true,  Callback=function(v) aaSettings.jitterYaw=v end })

AARight:AddToggle("AaRoll",      { Text="Roll Enabled",    Default=false, Callback=function(v) aaSettings.rollEnabled=v end })
AARight:AddSlider("AaRollSpd",   { Text="Roll Speed",      Default=360,   Min=10,  Max=1080, Rounding=0, Callback=function(v) aaSettings.rollSpeed=v end })
AARight:AddToggle("AaDesync",    { Text="Desync Offset",   Default=false, Callback=function(v) aaSettings.desyncMode=v end })
AARight:AddSlider("AaDesyncOff", { Text="Desync Angle",    Default=180,   Min=0,   Max=360,  Rounding=0, Callback=function(v) aaSettings.desyncOffset=v end })
AARight:AddToggle("AaMicro",     { Text="Micro Jitter",    Default=false, Callback=function(v) aaSettings.microJitter=v end })
AARight:AddSlider("AaMicroAmp",  { Text="Micro Jitter Amp",Default=5,     Min=0,   Max=45,   Rounding=1, Callback=function(v) aaSettings.microJitterAmp=v end })
AARight:AddSlider("AaMicroSpd",  { Text="Micro Jitter Speed",Default=30,  Min=1,   Max=120,  Rounding=1, Callback=function(v) aaSettings.microJitterSpeed=v end })
AARight:AddToggle("AaBreathe",   { Text="Breathe Effect",  Default=false, Callback=function(v) aaSettings.breatheEffect=v end })
AARight:AddSlider("AaBreatheAmp",{ Text="Breathe Amplitude",Default=3,    Min=0,   Max=20,   Rounding=1, Callback=function(v) aaSettings.breatheAmp=v end })
AARight:AddSlider("AaBreatheSpd",{ Text="Breathe Speed",   Default=1,     Min=0.1, Max=10,   Rounding=1, Callback=function(v) aaSettings.breatheSpeed=v end })
AARight:AddToggle("AaRandFlip",  { Text="Random Flip",     Default=false, Callback=function(v) aaSettings.randomFlip=v end })
AARight:AddSlider("AaFlipChance",{ Text="Flip Chance (%)", Default=5,     Min=1,   Max=50,   Rounding=0, Callback=function(v) aaSettings.flipChance=v/100 end })

-- [Sling UI removed]


-- ─────────────────────────────────────────────
-- UI: Prediction Tab
-- ─────────────────────────────────────────────
local PredLeft  = Tabs.Prediction:AddLeftGroupbox("Prediction Dodge")
local PredRight = Tabs.Prediction:AddRightGroupbox("Anti Bait")

AddBindableToggle(PredLeft, "PredToggle", "Enable Prediction", false, function(v) cfgDodge.predEnabled = v; if v then startPrediction() else stopPrediction() end end)
PredLeft:AddSlider("PredRadius",    { Text = "Danger Radius",           Default = 50,  Min = 5,   Max = 100,  Rounding = 0, Callback = function(v) cfgDodge.predRadius    = v end })
PredLeft:AddSlider("PredDodge",     { Text = "Dodge Distance",          Default = 50,  Min = 5,   Max = 150,  Rounding = 0, Callback = function(v) cfgDodge.predDodgeDist  = v end })
PredLeft:AddSlider("PredCooldown",  { Text = "Cooldown (ms)",           Default = 300, Min = 50,  Max = 2000, Rounding = 0, Callback = function(v) cfgDodge.predCooldown   = v / 1000 end })
PredLeft:AddSlider("PredThreshold", { Text = "Speed Threshold",         Default = 500, Min = 200, Max = 5000, Rounding = 0, Callback = function(v) cfgDodge.predThreshold  = v end })
PredLeft:AddSlider("PredMult",      { Text = "Prediction Mult",         Default = 1,   Min = 0,   Max = 10,   Rounding = 1, Callback = function(v) cfgDodge.predMult       = v end })
PredLeft:AddSlider("PredLeadTime",  { Text = "Lead Time (x0.01s)",      Default = 15,  Min = 1,   Max = 100,  Rounding = 0, Callback = function(v) cfgDodge.predLeadTime   = v * 0.01 end })
AddBindableToggle(PredLeft, "PredShootDetect", "Detect Enemy Shooting", true, function(v) cfgDodge.predShootDetect = v end)
PredLeft:AddSlider("PredShootDot",  { Text = "Aim Threshold (%)",       Default = 88,  Min = 50,  Max = 99,   Rounding = 0, Callback = function(v) cfgDodge.predShootDot   = v * 0.01 end })
PredLeft:AddSlider("PredShootDist", { Text = "Shot Dodge Distance",     Default = 60,  Min = 10,  Max = 200,  Rounding = 0, Callback = function(v) cfgDodge.predShootDist  = v end })
PredLeft:AddSlider("PredBulletSpd", { Text = "Enemy Bullet Speed",      Default = 200, Min = 50,  Max = 2000, Rounding = 0, Callback = function(v) cfgDodge.predBulletSpd  = v end })
PredLeft:AddSlider("PredReactTime", { Text = "Reaction Time (x0.01s)",  Default = 8,   Min = 1,   Max = 50,   Rounding = 0, Callback = function(v) cfgDodge.predReactTime  = v * 0.01 end })

AddBindableToggle(PredRight, "AntiBaitToggle", "Enable Anti Bait", false, function(v) antiBaitCFG.enabled = v; if v then startAntiBait() else killConn("antiBait"); antiBaitCFG.enabled=false end end)
PredRight:AddDropdown("AntiBaitDodgeMode", { Text = "Dodge Mode", Default = "Perpendicular", Values = {"Perpendicular","Away","Random"}, Callback = function(v) antiBaitCFG.dodgeMode = v end })
AddBindableToggle(PredRight, "AntiBaitVel",        "Vel Spike Detect",     true,  function(v) antiBaitCFG.velSpikeEnabled = v end)
AddBindableToggle(PredRight, "AntiBaitFlicker",    "Flicker Detect",       true,  function(v) antiBaitCFG.flickerEnabled  = v end)
AddBindableToggle(PredRight, "AntiBaitNotify",     "Notify on Dodge",      true,  function(v) antiBaitCFG.notifyOnDodge  = v end)
AddBindableToggle(PredRight, "AntiBaitShoot",      "Dodge On Shoot",       true,  function(v) antiBaitCFG.dodgeOnShoot   = v end)
AddBindableToggle(PredRight, "AntiBaitGunPredict", "Gun Prediction Dodge", true,  function(v) antiBaitCFG.gunPredEnabled = v end)
PredRight:AddSlider("AntiBaitGunDot",    { Text = "Gun Aim Threshold (%)", Default = 85,  Min = 50,  Max = 99,   Rounding = 0, Callback = function(v) antiBaitCFG.gunPredDot       = v * 0.01 end })
PredRight:AddSlider("AntiBaitGunDodge",  { Text = "Gun Dodge Distance",    Default = 70,  Min = 10,  Max = 200,  Rounding = 0, Callback = function(v) antiBaitCFG.gunPredDodgeDist = v end })
PredRight:AddSlider("AntiBaitGunCD",     { Text = "Gun Dodge CD (ms)",     Default = 50,  Min = 10,  Max = 500,  Rounding = 0, Callback = function(v) antiBaitCFG.gunPredCooldown  = v * 0.001 end })
PredRight:AddSlider("AntiBaitGunLead",   { Text = "Gun Lead (x0.01s)",     Default = 12,  Min = 1,   Max = 100,  Rounding = 0, Callback = function(v) antiBaitCFG.gunPredLead      = v * 0.01 end })
PredRight:AddSlider("AntiBaitVelThresh", { Text = "Vel Threshold",         Default = 300, Min = 100, Max = 2000, Rounding = 0, Callback = function(v) antiBaitCFG.velThreshold     = v end })
PredRight:AddSlider("AntiBaitDodgeDist", { Text = "Dodge Distance",        Default = 80,  Min = 5,   Max = 150,  Rounding = 0, Callback = function(v) antiBaitCFG.velDodgeDist     = v end })
PredRight:AddSlider("AntiBaitCooldown",  { Text = "Cooldown (x0.1s)",      Default = 2,   Min = 1,   Max = 20,   Rounding = 0, Callback = function(v) antiBaitCFG.dodgeCooldown    = v * 0.1 end })
PredRight:AddSlider("AntiBaitTpCount",   { Text = "Min TPs to Confirm",    Default = 2,   Min = 2,   Max = 10,   Rounding = 0, Callback = function(v) antiBaitCFG.flickerMinTps   = v end })
PredRight:AddSlider("AntiBaitWindow",    { Text = "Flicker Window (x0.1s)",Default = 3,   Min = 1,   Max = 20,   Rounding = 0, Callback = function(v) antiBaitCFG.flickerWindow   = v * 0.1 end })
PredRight:AddSlider("AntiBaitTpDist",    { Text = "TP Delta (studs)",       Default = 10,  Min = 5,   Max = 100,  Rounding = 0, Callback = function(v) antiBaitCFG.flickerTpDist   = v end })

-- ─────────────────────────────────────────────
-- UI: Settings Tab
-- ─────────────────────────────────────────────
local CLeft = Tabs.Config:AddLeftGroupbox("Menu")

CLeft:AddToggle("KeybindMenuOpen", { Text="Show Keybind Menu", Default=true,  Callback=function(v) Library.KeybindFrame.Visible=v end })
CLeft:AddToggle("ShowCursor",      { Text="Custom Cursor",     Default=true,  Callback=function(v) Library.ShowCustomCursor=v end })
CLeft:AddLabel("Menu Bind"):AddKeyPicker("MenuBind", { Default="RightShift", NoUI=true, Text="Toggle Menu" })

Library.ToggleKeybind = Options.MenuBind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuBind" })
ThemeManager:SetFolder("EtherealFree")
SaveManager:SetFolder("EtherealFree/Configs")
SaveManager:BuildConfigSection(Tabs.Config)
ThemeManager:ApplyToTab(Tabs.Config)

-- ─────────────────────────────────────────────
-- POSITION OVERLAY (Drawing)
-- ─────────────────────────────────────────────
local overlay = {}

local function makeRect(x, y, w, h, colour, trans)
    local r = Drawing.new("Square")
    r.Visible = true; r.Filled = true; r.Color = colour
    r.Transparency = trans or 1; r.Size = Vector2.new(w, h)
    r.Position = Vector2.new(x, y); r.ZIndex = 5
    return r
end

local function makeText(x, y, text, colour, size)
    local t = Drawing.new("Text")
    t.Visible = true; t.Text = text; t.Color = colour
    t.Size = size or 13; t.Position = Vector2.new(x, y)
    t.Font = Drawing.Fonts.Plex; t.Outline = true
    t.OutlineColor = Color3.new(0,0,0); t.ZIndex = 6
    return t
end

local OX, OY  = 20, 20
local PW, PH  = 175, 90
local ROW_H   = 20
local BAR_W   = PW - 4
local LABEL_X = OX + 6
local VALUE_X = OX + 28

overlay.bg     = makeRect(OX, OY, PW, PH, Color3.fromRGB(15, 15, 20), 0.35)
overlay.dot    = makeText(OX + 6,  OY + 5, "●", Color3.fromRGB(80, 220, 100), 12)
overlay.header = makeText(OX + 20, OY + 5, "POSITION", Color3.fromRGB(200, 200, 210), 12)

local rowY       = { OY + 22, OY + 44, OY + 66 }
local barColours = {
    Color3.fromRGB(120, 25,  25),
    Color3.fromRGB(25,  80,  25),
    Color3.fromRGB(20,  40, 100),
}
overlay.bars = {}
for i = 1, 3 do
    overlay.bars[i] = makeRect(OX + 2, rowY[i], BAR_W, ROW_H - 2, barColours[i], 0.55)
end

local axisColours = {
    Color3.fromRGB(220, 60,  60),
    Color3.fromRGB(80,  200, 80),
    Color3.fromRGB(80,  120, 220),
}
local axisNames = { "X", "Y", "Z" }
overlay.labels = {}
overlay.values = {}
overlay.seps   = {}

for i = 1, 3 do
    overlay.labels[i] = makeText(LABEL_X,     rowY[i] + 3, axisNames[i], axisColours[i], 13)
    overlay.values[i] = makeText(VALUE_X + 4, rowY[i] + 3, "0", Color3.fromRGB(210, 210, 220), 13)
    overlay.seps[i]   = makeRect(VALUE_X + 1, rowY[i], 1, ROW_H - 2, Color3.fromRGB(80, 80, 100), 1)
end

local function isAnyFeatureActive()
    return (Toggles.SpamToggle            and Toggles.SpamToggle.Value)
        or (Toggles.OrbitToggle           and Toggles.OrbitToggle.Value)
        or (Toggles.AaToggle              and Toggles.AaToggle.Value)
        or (Toggles.pred_en               and Toggles.pred_en.Value)
end

local overlayConn = RunService.Heartbeat:Connect(function()
    if isAnyFeatureActive() then
        local hrp = getHRP()
        if hrp then
            local p = hrp.Position
            overlay.values[1].Text = string.format("%.1f", math.clamp(p.X, -999998, 999998))
            overlay.values[2].Text = string.format("%.1f", math.clamp(p.Y, -999998, 999998))
            overlay.values[3].Text = string.format("%.1f", math.clamp(p.Z, -999998, 999998))
        else
            overlay.values[1].Text = "999998"
            overlay.values[2].Text = "999998"
            overlay.values[3].Text = "999998"
        end
    else
        overlay.values[1].Text = "0"
        overlay.values[2].Text = "0"
        overlay.values[3].Text = "0"
    end
end)

local function destroyOverlay()
    if overlayConn then overlayConn:Disconnect(); overlayConn = nil end
    overlay.bg:Remove(); overlay.dot:Remove(); overlay.header:Remove()
    for i = 1, 3 do
        overlay.bars[i]:Remove()
        overlay.labels[i]:Remove()
        overlay.values[i]:Remove()
        overlay.seps[i]:Remove()
    end
end

-- ─────────────────────────────────────────────
-- Unload
-- ─────────────────────────────────────────────
Library:OnUnload(function()
    stopSpam(); stopOrbit(); stopAntiAim()
    getgenv().stop_prediction()
    stopPrediction()
    killConn('antiBait')
    for k in pairs(conns) do killConn(k) end
    destroyOverlay()
end)

SaveManager:LoadAutoloadConfig()