local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

do
	if getgenv().SlapBattlesCombined and getgenv().SlapBattlesCombined.destroy then
		pcall(getgenv().SlapBattlesCombined.destroy)
	end
	getgenv().SlapBattlesCombined = nil
	local function wipeNamed(root)
		if not root then
			return
		end
		for _, child in ipairs(root:GetChildren()) do
			if child.Name == "SlapBattlesCombined" then
				pcall(function()
					child:Destroy()
				end)
			end
		end
	end
	wipeNamed(CoreGui)
	wipeNamed(playerGui)
	pcall(function()
		if gethui then
			wipeNamed(gethui())
		end
	end)
end

local COLORS = {
	void = Color3.fromRGB(8, 9, 11),
	shell = Color3.fromRGB(16, 18, 22),
	panel = Color3.fromRGB(22, 25, 30),
	line = Color3.fromRGB(42, 46, 54),
	mute = Color3.fromRGB(110, 118, 128),
	text = Color3.fromRGB(236, 240, 244),
	soft = Color3.fromRGB(180, 188, 196),
	signal = Color3.fromRGB(200, 245, 66),
	signalDim = Color3.fromRGB(90, 110, 40),
	danger = Color3.fromRGB(255, 72, 72),
	trackOff = Color3.fromRGB(36, 40, 48),
	trackOn = Color3.fromRGB(48, 72, 18),
	knob = Color3.fromRGB(248, 250, 252),
	ok = Color3.fromRGB(200, 245, 66),
	err = Color3.fromRGB(255, 72, 72),
	accent = Color3.fromRGB(200, 245, 66),
	muted = Color3.fromRGB(110, 118, 128),
}

local MENU_TOGGLE_KEY = Enum.KeyCode.G
local GLOVE_NAME = "Glove"
local LOBBY_PATH = { "Lobby", "Teleport1" }
local STEP_PAUSE = 0.85
local ARENA_LOAD_WAIT = 2.5
local ARENA_READY_TIMEOUT = 15
local AFTER_DEATH_WAIT = 0.5
local RESET_WAIT = 1
local NEW_GLOVE_POLL = 0.4
local NEW_GLOVE_IDLE = 2.5
local DEATH_WAIT_MAX = 2.5
local MAX_COLLECT_ROUNDS = 40
local RESOLVE_WAIT = 15
local RESCAN_WAIT = 1
local RESPAWN_TIMEOUT = 20
local RESET_RESPAWN_TIMEOUT = 8
local SLAP_JITTER = 0.15
local SLAP_MIN_SAFE = 0.8
local STRIKE_WAIT = 0.1
local AURA_MAX = 1
local AURA_RANGE = 500
local STEALTH_REFRESH = 3.0
local ARENA_ENTER_WAIT = 2.2
local RESPAWN_WAIT = 1.0

local state = {
	alive = true,
	glovesOn = false,
	slapOn = false,
	targetFarmOn = false,
	autoTP = true,
	stealth = true,
	slapInterval = 2.0,
	cycleCount = 0,
	sessionStart = 0,
	connections = {},
	auraHits = 0,
	localClone = nil,
	followConn = nil,
	stealthOn = false,
	rejoining = false,
	lastStealthRefresh = 0,
	lastFireAt = 0,
	targetName = nil,
}

local playerListFrame
local playerListLayout
local selectedLabel
local stopTargetBtn
local targetFarmBtn
local playerRowButtons = {}

local bRemote = ReplicatedStorage:WaitForChild("b")
local generalHit = ReplicatedStorage:FindFirstChild("GeneralHit")
local dualHit = ReplicatedStorage:FindFirstChild("DualHit")

local screenGui
local mainFrame
local glovesBtn
local slapBtn
local tpBtn
local stealthBtn
local intervalBox
local statusLabel
local toggleUI = {}

local function track(conn)
	table.insert(state.connections, conn)
	return conn
end

local function disconnectAll()
	for _, conn in ipairs(state.connections) do
		pcall(function()
			conn:Disconnect()
		end)
	end
	table.clear(state.connections)
end

local function setStatus(text, color)
	if statusLabel then
		statusLabel.Text = text
		statusLabel.TextColor3 = color or COLORS.mute
	end
end

local function setToggleVisual(key, on)
	local ui = toggleUI[key]
	if not ui then
		return
	end
	local goalTrack = on and COLORS.trackOn or COLORS.trackOff
	local goalKnob = on and 15 or 2
	local goalDot = on and COLORS.signal or COLORS.mute
	TweenService:Create(ui.track, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = goalTrack,
	}):Play()
	TweenService:Create(ui.knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(goalKnob, 2),
	}):Play()
	if ui.dot then
		ui.dot.BackgroundColor3 = goalDot
	end
	if ui.value then
		ui.value.Text = on and "ON" or "OFF"
		ui.value.TextColor3 = on and COLORS.signal or COLORS.mute
	end
end

local function refreshButtons()
	setToggleVisual("gloves", state.glovesOn)
	setToggleVisual("slap", state.slapOn)
	setToggleVisual("targetFarm", state.targetFarmOn)
	setToggleVisual("autoTP", state.autoTP)
	setToggleVisual("stealth", state.stealth)
end

local function updateSelectedLabel()
	if not selectedLabel then
		return
	end
	if state.targetName then
		selectedLabel.Text = "TARGET · " .. state.targetName
		selectedLabel.TextColor3 = COLORS.signal
	else
		selectedLabel.Text = "TARGET · none"
		selectedLabel.TextColor3 = COLORS.mute
	end
end

local function isOtherInArena(other)
	local ch = other and other.Character
	if not ch then
		return false
	end
	local arena = ch:FindFirstChild("isInArena")
	return arena ~= nil and arena.Value == true
end

local function refreshPlayerRows()
	if not playerListFrame then
		return
	end
	for _, btn in pairs(playerRowButtons) do
		if btn and btn.Parent then
			btn:Destroy()
		end
	end
	table.clear(playerRowButtons)
	local names = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			table.insert(names, other.Name)
		end
	end
	table.sort(names)
	for i, name in ipairs(names) do
		local other = Players:FindFirstChild(name)
		local inArena = other and isOtherInArena(other)
		local selected = state.targetName == name
		local row = Instance.new("TextButton")
		row.Name = name
		row.AutoButtonColor = false
		row.BackgroundColor3 = selected and COLORS.trackOn or COLORS.void
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -2, 0, isMobileUi() and 24 or 18)
		row.Font = Enum.Font.GothamMedium
		row.TextSize = isMobileUi() and 11 or 10
		row.TextColor3 = selected and COLORS.signal or (inArena and COLORS.soft or COLORS.mute)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = " " .. name .. (inArena and " ·A" or " ·L")
		row.LayoutOrder = i
		row.Parent = playerListFrame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 3)
		corner.Parent = row
		track(row.MouseButton1Click:Connect(function()
			state.targetName = name
			updateSelectedLabel()
			refreshPlayerRows()
			if state.targetFarmOn then
				setStatus("> target · " .. name, COLORS.signal)
			else
				setStatus("> selected · " .. name, COLORS.mute)
			end
		end))
		playerRowButtons[name] = row
	end
	local rowH = isMobileUi() and 27 or 21
	playerListFrame.CanvasSize = UDim2.fromOffset(0, math.max(0, #names * rowH))
end

local function clearTarget()
	state.targetName = nil
	state.targetFarmOn = false
	updateSelectedLabel()
	refreshButtons()
	refreshPlayerRows()
	setStatus("> target cleared", COLORS.mute)
end

local function resolveLobby()
	local current = Workspace
	for _, segment in ipairs(LOBBY_PATH) do
		local child = current:FindFirstChild(segment)
		if not child then
			child = current:WaitForChild(segment, RESOLVE_WAIT)
		end
		if not child then
			return nil
		end
		current = child
	end
	if current:IsA("BasePart") then
		return current
	end
	return nil
end

local function isPlayerPart(part)
	local character = player.Character
	return character and part:IsDescendantOf(character)
end

local function countReplicatedGloves()
	local count = 0
	for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
		if desc.Name == GLOVE_NAME and desc:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

local function collectArenaGloves()
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then
		return {}
	end
	local gloves = {}
	local seen = {}
	for _, desc in ipairs(arena:GetDescendants()) do
		if desc.Name == GLOVE_NAME and desc:IsA("BasePart") and not isPlayerPart(desc) then
			if not seen[desc] then
				seen[desc] = true
				table.insert(gloves, desc)
			end
		end
	end
	table.sort(gloves, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return gloves
end

local function stabilizeCharacter(root, humanoid)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
	for _ = 1, 4 do
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		RunService.Heartbeat:Wait()
	end
end

local function teleportTo(part, humanoid)
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not part or not part:IsA("BasePart") then
		return false
	end
	if not part:IsDescendantOf(Workspace) then
		return false
	end
	local wasPlatformStand = humanoid and humanoid.PlatformStand
	if humanoid then
		humanoid.PlatformStand = true
	end
	root.CFrame = part:GetPivot()
	stabilizeCharacter(root, humanoid)
	if humanoid then
		humanoid.PlatformStand = wasPlatformStand
	end
	task.wait(STEP_PAUSE)
	return true
end

local function waitForArenaGloves()
	local deadline = tick() + ARENA_READY_TIMEOUT
	while state.alive and state.glovesOn and tick() < deadline do
		local gloves = collectArenaGloves()
		if #gloves > 0 then
			return gloves
		end
		task.wait(0.25)
	end
	return collectArenaGloves()
end

local function waitForLiveCharacterGloves()
	local deadline = tick() + RESPAWN_TIMEOUT
	while state.alive and state.glovesOn and tick() < deadline do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and humanoid.Health > 0 then
				return character, humanoid, root
			end
		end
		task.wait(0.1)
	end
	return nil
end

local function waitForDeathShort(humanoid)
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local died = false
	local conn = humanoid.Died:Connect(function()
		died = true
	end)
	local deadline = tick() + DEATH_WAIT_MAX
	while state.alive and state.glovesOn and not died and humanoid.Parent and humanoid.Health > 0 and tick() < deadline do
		task.wait(0.05)
	end
	conn:Disconnect()
	if died then
		task.wait(AFTER_DEATH_WAIT)
	end
end

local function getUnvisitedGloves(visited)
	local list = {}
	for _, glove in ipairs(collectArenaGloves()) do
		if glove.Parent and not visited[glove] then
			table.insert(list, glove)
		end
	end
	table.sort(list, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)
	return list
end

local function visitGlove(glove, visited, totalCount)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false, humanoid, totalCount
	end
	setStatus("Glove #" .. (totalCount + 1), COLORS.muted)
	if not teleportTo(glove, humanoid) then
		return false, humanoid, totalCount
	end
	visited[glove] = true
	return true, character:FindFirstChildOfClass("Humanoid"), totalCount + 1
end

local function collectAllGlovesWithRespawn()
	local visited = {}
	local totalVisited = 0
	local idleSince = tick()
	local rounds = 0
	while state.alive and state.glovesOn and rounds < MAX_COLLECT_ROUNDS do
		rounds += 1
		local batch = getUnvisitedGloves(visited)
		if #batch == 0 then
			if tick() - idleSince >= NEW_GLOVE_IDLE then
				break
			end
			setStatus("Wait spawn gloves…", COLORS.muted)
			task.wait(NEW_GLOVE_POLL)
			continue
		end
		idleSince = tick()
		for _, glove in ipairs(batch) do
			if not state.alive or not state.glovesOn then
				return totalVisited
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				return totalVisited
			end
			local ok, newHumanoid, newTotal = visitGlove(glove, visited, totalVisited)
			totalVisited = newTotal
			if not ok then
				return totalVisited
			end
		end
	end
	return totalVisited
end

local function forceKillCharacter()
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		pcall(function()
			character:BreakJoints()
		end)
	end
end

local function waitForRespawnAfterReset()
	local oldCharacter = player.Character
	forceKillCharacter()
	local newCharacter = nil
	local addedConn = player.CharacterAdded:Connect(function(char)
		newCharacter = char
	end)
	local deadline = tick() + RESET_RESPAWN_TIMEOUT
	while state.alive and state.glovesOn and tick() < deadline do
		local current = player.Character
		if current and current ~= oldCharacter then
			newCharacter = current
			break
		end
		if newCharacter and newCharacter.Parent then
			break
		end
		if oldCharacter and not oldCharacter.Parent and current then
			newCharacter = current
			break
		end
		task.wait(0.1)
	end
	addedConn:Disconnect()
	local character = newCharacter or player.Character
	if not character then
		return false
	end
	pcall(function()
		character:WaitForChild("HumanoidRootPart", 6)
		character:WaitForChild("Humanoid", 6)
	end)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		task.wait(RESET_WAIT)
		return true
	end
	return false
end

local function runGlovesCycle(lobbyPart)
	local character, humanoid = waitForLiveCharacterGloves()
	if not state.alive or not state.glovesOn or not character or not humanoid then
		return false
	end
	setStatus("Gloves · lobby TP", COLORS.muted)
	if not teleportTo(lobbyPart, humanoid) then
		setStatus("Gloves · lobby fail", COLORS.err)
		return false
	end
	if not state.glovesOn or humanoid.Health <= 0 then
		return false
	end
	setStatus("Gloves · arena loading…", COLORS.accent)
	task.wait(ARENA_LOAD_WAIT)
	if not state.alive or not state.glovesOn then
		return false
	end
	local gloves = waitForArenaGloves()
	if #gloves == 0 then
		setStatus("Gloves · no gloves yet", COLORS.err)
		return false
	end
	character = player.Character
	humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	setStatus("Gloves · collecting…", COLORS.muted)
	local collected = collectAllGlovesWithRespawn()
	if not state.alive or not state.glovesOn then
		return false
	end
	character = player.Character
	humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		waitForDeathShort(humanoid)
	end
	state.cycleCount += 1
	setStatus("Gloves cycle " .. state.cycleCount .. " · " .. collected, COLORS.ok)
	waitForRespawnAfterReset()
	return true
end

local function glovesFarmLoop()
	while state.alive do
		if not state.glovesOn then
			task.wait(0.2)
			continue
		end
		local lobbyPart = resolveLobby()
		if not lobbyPart then
			setStatus("Gloves · waiting lobby…", COLORS.err)
			task.wait(RESCAN_WAIT)
			continue
		end
		runGlovesCycle(lobbyPart)
		task.wait(0.05)
	end
end

local function myHRP()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart"), character
end

local function amInArena()
	local _, character = myHRP()
	local arena = character and character:FindFirstChild("isInArena")
	return arena and arena.Value == true
end

local function getLobbyTeleport()
	return resolveLobby()
end

local function currentGloveName()
	local ls = player:FindFirstChild("leaderstats")
	local g = ls and ls:FindFirstChild("Glove")
	if g then
		return tostring(g.Value)
	end
	return tostring(player:GetAttribute("Glove") or "Default")
end

local function getHitRemote()
	local name = currentGloveName()
	if name == "Default" or name == "default" then
		return bRemote
	end
	if name == "Dual" and dualHit then
		return dualHit
	end
	local named = ReplicatedStorage:FindFirstChild(name .. "Hit")
		or ReplicatedStorage:FindFirstChild(name .. "hit")
		or ReplicatedStorage:FindFirstChild(name:gsub("%s+", "") .. "Hit")
	if named then
		return named
	end
	if generalHit then
		return generalHit
	end
	return bRemote
end

local function getHitPart(character)
	return character:FindFirstChild("Right Arm")
		or character:FindFirstChild("RightHand")
		or character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChildWhichIsA("BasePart")
end

local function equipGloveTool()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local name = currentGloveName()
	local tool = character:FindFirstChildOfClass("Tool")
	if tool then
		return tool
	end
	local bp = player:FindFirstChild("Backpack")
	if not bp then
		return nil
	end
	tool = bp:FindFirstChild(name) or bp:FindFirstChildOfClass("Tool")
	if tool then
		pcall(function()
			humanoid:EquipTool(tool)
		end)
		task.wait(0.05)
	end
	return character:FindFirstChildOfClass("Tool")
end

local function clearLocalClone()
	if state.followConn then
		pcall(function()
			state.followConn:Disconnect()
		end)
		state.followConn = nil
	end
	if state.localClone then
		pcall(function()
			state.localClone:Destroy()
		end)
		state.localClone = nil
	end
end

local function hideModelForOthers(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.NameDisplayDistance = 0
		humanoid.HealthDisplayDistance = 0
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = 1
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = 1
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d.Enabled = false
		elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Fire") or d:IsA("Smoke") then
			d.Enabled = false
		end
	end
end

local function makeLocalClone(character)
	clearLocalClone()
	character.Archivable = true
	local ok, clone = pcall(function()
		return character:Clone()
	end)
	if not ok or not clone then
		return false
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
			d.LocalTransparencyModifier = 0
			if d.Name == "HumanoidRootPart" then
				d.Transparency = 1
			else
				d.Transparency = 0
			end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = 0
			d.LocalTransparencyModifier = 0
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Humanoid") or d:IsA("ForceField") then
			pcall(function()
				d:Destroy()
			end)
		end
	end
	clone.Name = "SB_StealthClone"
	local cloneRoot = clone:FindFirstChild("HumanoidRootPart")
	if not cloneRoot then
		clone:Destroy()
		return false
	end
	clone.PrimaryPart = cloneRoot
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") and part ~= cloneRoot then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = cloneRoot
			weld.Part1 = part
			weld.Parent = cloneRoot
		end
	end
	cloneRoot.Anchored = true
	clone.Parent = Workspace.CurrentCamera
	state.localClone = clone
	state.followConn = RunService.RenderStepped:Connect(function()
		if not state.alive or not state.stealthOn then
			return
		end
		local ch = player.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		if r and state.localClone and state.localClone.Parent then
			pcall(function()
				state.localClone:PivotTo(r.CFrame)
			end)
		end
	end)
	return true
end

local function enableStealth()
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false
	end
	if not state.localClone or not state.localClone.Parent then
		makeLocalClone(character)
	end
	hideModelForOthers(character)
	state.stealthOn = true
	return true
end

local function disableStealth()
	state.stealthOn = false
	clearLocalClone()
end

local function waitForLiveCharacter(timeout)
	local deadline = tick() + (timeout or 15)
	while state.alive and tick() < deadline do
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and humanoid.Health > 0 then
				return character, humanoid, root
			end
		end
		task.wait(0.1)
	end
	return nil
end

local function enterArena()
	if state.rejoining then
		return amInArena()
	end
	state.rejoining = true
	setStatus("respawn → arena…", COLORS.accent)
	local character, _, root = waitForLiveCharacter(20)
	if not character or not root then
		state.rejoining = false
		setStatus("respawn failed", COLORS.err)
		return false
	end
	task.wait(RESPAWN_WAIT)
	if amInArena() then
		if state.stealth and (state.slapOn or state.targetFarmOn) then
			enableStealth()
		end
		state.rejoining = false
		setStatus("back in arena", COLORS.ok)
		return true
	end
	local tele = getLobbyTeleport()
	if not tele then
		state.rejoining = false
		setStatus("no Teleport1", COLORS.err)
		return false
	end
	root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		state.rejoining = false
		return false
	end
	root.CFrame = tele.CFrame + Vector3.new(0, 4, 0)
	local deadline = tick() + 12
	while state.alive and (state.slapOn or state.targetFarmOn) and tick() < deadline do
		if amInArena() then
			task.wait(ARENA_ENTER_WAIT)
			if state.stealth and (state.slapOn or state.targetFarmOn) then
				enableStealth()
			end
			state.rejoining = false
			setStatus("back in arena", COLORS.ok)
			return true
		end
		task.wait(0.2)
	end
	state.rejoining = false
	setStatus("arena enter timeout", COLORS.err)
	return false
end

local function collectAuraTargets(onlyName)
	local hrp = myHRP()
	if not hrp then
		return {}
	end
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then
			if onlyName and other.Name ~= onlyName then
				continue
			end
			local ch = other.Character
			local arena = ch:FindFirstChild("isInArena")
			local vuln = ch:FindFirstChild("TSVulnerability")
			local hum = ch:FindFirstChildOfClass("Humanoid")
			local thrp = ch:FindFirstChild("HumanoidRootPart")
			local rag = ch:FindFirstChild("Ragdolled")
			local okVuln = (vuln == nil) or (vuln.Value == true)
			local okRag = (rag == nil) or (rag.Value == false)
			if arena and arena.Value == true and okVuln and okRag and hum and hum.Health > 0 and thrp then
				local flat = Vector3.new(hrp.Position.X - thrp.Position.X, 0, hrp.Position.Z - thrp.Position.Z).Magnitude
				if flat <= AURA_RANGE then
					table.insert(list, {
						player = other,
						hrp = thrp,
						part = getHitPart(ch),
						dist = flat,
					})
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	return list
end

local function fireSlap(part)
	local now = tick()
	if now - state.lastFireAt < math.max(0.75, state.slapInterval * 0.85) then
		return false
	end
	local remote = getHitRemote()
	local tool = equipGloveTool()
	if tool then
		pcall(function()
			tool:Activate()
		end)
		if state.stealthOn then
			for _, p in ipairs(tool:GetDescendants()) do
				if p:IsA("BasePart") or p:IsA("Decal") or p:IsA("Texture") then
					p.Transparency = 1
				end
			end
		end
	end
	local ok = pcall(function()
		remote:FireServer(part)
	end)
	if ok then
		state.lastFireAt = now
		return true
	end
	return false
end

local function strikeTarget(entry)
	local hrp = myHRP()
	local thrp = entry.hrp
	local part = entry.part
	if not hrp or not thrp or not part or not part.Parent then
		return false
	end
	if state.autoTP then
		hrp.CFrame = CFrame.new(thrp.Position + Vector3.new(0, 2.2, 0))
		task.wait(STRIKE_WAIT)
	end
	if fireSlap(part) then
		state.auraHits += 1
		return true
	end
	return false
end

local function slapActive()
	return state.slapOn or state.targetFarmOn
end

local function slapFarmLoop()
	while state.alive do
		if not slapActive() then
			task.wait(0.2)
			continue
		end
		if not amInArena() then
			if not state.rejoining then
				enterArena()
			else
				task.wait(0.3)
			end
			continue
		end
		if state.stealth then
			if not state.stealthOn or tick() - state.lastStealthRefresh >= STEALTH_REFRESH then
				enableStealth()
				state.lastStealthRefresh = tick()
			end
		end
		local filterName = nil
		if state.targetFarmOn then
			if not state.targetName then
				setStatus("pick target in list…", Color3.fromRGB(220, 180, 100))
				task.wait(0.4)
				continue
			end
			filterName = state.targetName
		end
		local targets = collectAuraTargets(filterName)
		if #targets == 0 then
			if filterName then
				local targetPlr = Players:FindFirstChild(filterName)
				if not targetPlr then
					setStatus("offline · " .. filterName, COLORS.err)
				elseif not isOtherInArena(targetPlr) then
					setStatus("not in arena · " .. filterName, Color3.fromRGB(220, 180, 100))
				else
					setStatus("waiting · " .. filterName, Color3.fromRGB(220, 180, 100))
				end
			else
				setStatus("waiting target…", Color3.fromRGB(220, 180, 100))
			end
			task.wait(0.5)
			if filterName and tick() % 2 < 0.6 then
				refreshPlayerRows()
			end
			continue
		end
		local entry = targets[1]
		local hitOk = false
		local lastName = entry.player.Name
		if entry.hrp and entry.hrp.Parent then
			hitOk = strikeTarget(entry)
		end
		local slaps = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Slaps")
		local got = slaps and (slaps.Value - state.sessionStart) or 0
		local tag = state.stealth and " · stealth" or ""
		local mode = filterName and " · LOCK" or ""
		if hitOk then
			setStatus("hit · +" .. tostring(got) .. " · " .. lastName .. mode .. tag, COLORS.ok)
		else
			setStatus("skip/cd · " .. lastName .. mode .. tag, COLORS.muted)
		end
		local waitTime = math.max(1.0, state.slapInterval)
		local jitter = (math.random() * 2 - 1) * SLAP_JITTER
		task.wait(math.max(1.0, waitTime + jitter))
	end
end

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function addStroke(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function isMobileUi()
	return UserInputService.TouchEnabled
end

local function getViewport()
	local cam = Workspace.CurrentCamera
	if cam then
		return cam.ViewportSize
	end
	return Vector2.new(800, 600)
end

local function clampMenuToScreen(frame)
	if not frame or not frame.Parent then
		return
	end
	local vs = getViewport()
	local size = frame.AbsoluteSize
	local pos = frame.AbsolutePosition
	local x = math.clamp(pos.X, 4, math.max(4, vs.X - size.X - 4))
	local y = math.clamp(pos.Y, 4, math.max(4, vs.Y - size.Y - 4))
	frame.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

local function makeDraggable(frame, handle)
	local dragging = false
	local dragStart
	local startPos
	local function beginDrag(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
		end
	end
	local function stopDrag(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if dragging then
				dragging = false
				clampMenuToScreen(frame)
			end
		end
	end
	local function moveDrag(input)
		if not dragging or not state.alive then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end
	track(handle.InputBegan:Connect(beginDrag))
	track(handle.InputChanged:Connect(moveDrag))
	track(handle.InputEnded:Connect(stopDrag))
	track(UserInputService.InputChanged:Connect(moveDrag))
	track(UserInputService.InputEnded:Connect(stopDrag))
end

local function makeToggleRow(parent, key, title, layoutOrder, defaultOn)
	local mobile = isMobileUi()
	local rowH = mobile and 24 or 20
	local row = Instance.new("TextButton")
	row.Name = key
	row.AutoButtonColor = false
	row.BackgroundColor3 = COLORS.panel
	row.BorderSizePixel = 0
	row.Size = UDim2.new(1, 0, 0, rowH)
	row.LayoutOrder = layoutOrder
	row.Text = ""
	row.Parent = parent
	addCorner(row, 3)
	addStroke(row, COLORS.line, 1)

	local dot = Instance.new("Frame")
	dot.BackgroundColor3 = defaultOn and COLORS.signal or COLORS.mute
	dot.BorderSizePixel = 0
	dot.Size = UDim2.fromOffset(3, 3)
	dot.Position = UDim2.fromOffset(6, math.floor(rowH / 2) - 1)
	dot.Parent = row
	addCorner(dot, 2)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = mobile and 11 or 10
	label.TextColor3 = COLORS.text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = title
	label.Size = UDim2.new(1, -70, 1, 0)
	label.Position = UDim2.fromOffset(14, 0)
	label.Parent = row

	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.Code
	value.TextSize = 8
	value.TextColor3 = defaultOn and COLORS.signal or COLORS.mute
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Text = defaultOn and "ON" or "OFF"
	value.Size = UDim2.fromOffset(20, rowH)
	value.Position = UDim2.new(1, -56, 0, 0)
	value.Parent = row

	local track = Instance.new("Frame")
	track.BackgroundColor3 = defaultOn and COLORS.trackOn or COLORS.trackOff
	track.BorderSizePixel = 0
	track.Size = UDim2.fromOffset(28, 14)
	track.Position = UDim2.new(1, -34, 0.5, -7)
	track.Parent = row
	addCorner(track, 3)

	local knob = Instance.new("Frame")
	knob.BackgroundColor3 = COLORS.knob
	knob.BorderSizePixel = 0
	knob.Size = UDim2.fromOffset(10, 10)
	knob.Position = UDim2.fromOffset(defaultOn and 15 or 2, 2)
	knob.Parent = track
	addCorner(knob, 2)

	toggleUI[key] = {
		row = row,
		track = track,
		knob = knob,
		dot = dot,
		value = value,
	}
	return row
end

local function destroy()
	if not state.alive then
		return
	end
	state.alive = false
	state.glovesOn = false
	state.slapOn = false
	state.targetFarmOn = false
	disableStealth()
	disconnectAll()
	if screenGui then
		pcall(function()
			screenGui:Destroy()
		end)
		screenGui = nil
	end
	local function wipeNamed(root)
		if not root then
			return
		end
		for _, child in ipairs(root:GetChildren()) do
			if child.Name == "SlapBattlesCombined" then
				pcall(function()
					child:Destroy()
				end)
			end
		end
	end
	wipeNamed(CoreGui)
	wipeNamed(playerGui)
	pcall(function()
		if gethui then
			wipeNamed(gethui())
		end
	end)
	getgenv().SlapBattlesCombined = nil
end

local function armSlapSession()
	local slaps = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Slaps")
	state.sessionStart = slaps and slaps.Value or 0
	if state.stealth then
		enableStealth()
	end
	if not amInArena() then
		task.spawn(enterArena)
	end
end

local function buildMenu()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SlapBattlesCombined"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 120
	screenGui.IgnoreGuiInset = true
	pcall(function()
		screenGui.Parent = (gethui and gethui()) or CoreGui
	end)
	if not screenGui.Parent then
		screenGui.Parent = playerGui
	end

	local mobile = isMobileUi()
	local vs = getViewport()
	local menuW = math.clamp(math.floor(vs.X * (mobile and 0.88 or 0.38)), mobile and 280 or 340, mobile and math.min(480, vs.X - 12) or 420)
	local menuH = math.clamp(math.floor(vs.Y * (mobile and 0.36 or 0.3)), mobile and 190 or 210, mobile and math.min(250, vs.Y - 20) or 260)
	if menuW <= menuH then
		menuW = menuH + 90
	end
	local pad = 5
	local headerH = mobile and 32 or 30

	mainFrame = Instance.new("Frame")
	mainFrame.Name = "Main"
	mainFrame.BackgroundColor3 = COLORS.shell
	mainFrame.BorderSizePixel = 0
	mainFrame.Size = UDim2.fromOffset(menuW, menuH)
	mainFrame.Position = UDim2.fromOffset(math.floor((vs.X - menuW) * 0.5), math.floor((vs.Y - menuH) * 0.5))
	mainFrame.Active = true
	mainFrame.ClipsDescendants = true
	mainFrame.Parent = screenGui
	addCorner(mainFrame, 8)
	addStroke(mainFrame, COLORS.line, 1)

	local signalBar = Instance.new("Frame")
	signalBar.BackgroundColor3 = COLORS.signal
	signalBar.BorderSizePixel = 0
	signalBar.Size = UDim2.new(0, 3, 1, 0)
	signalBar.Parent = mainFrame

	local header = Instance.new("TextButton")
	header.Name = "DragHandle"
	header.AutoButtonColor = false
	header.BackgroundColor3 = COLORS.void
	header.BackgroundTransparency = 0.2
	header.BorderSizePixel = 0
	header.Text = ""
	header.Size = UDim2.new(1, -3, 0, headerH)
	header.Position = UDim2.fromOffset(3, 0)
	header.Parent = mainFrame

	local grip = Instance.new("Frame")
	grip.BackgroundColor3 = COLORS.mute
	grip.BorderSizePixel = 0
	grip.Size = UDim2.fromOffset(28, 3)
	grip.Position = UDim2.new(0.5, -14, 0, 4)
	grip.Parent = header
	addCorner(grip, 2)

	local brand = Instance.new("TextLabel")
	brand.BackgroundTransparency = 1
	brand.Font = Enum.Font.GothamBold
	brand.TextSize = 15
	brand.TextColor3 = COLORS.text
	brand.TextXAlignment = Enum.TextXAlignment.Left
	brand.Text = "AETHER"
	brand.Size = UDim2.new(0.45, 0, 1, 0)
	brand.Position = UDim2.fromOffset(10, 0)
	brand.Parent = header

	local tag = Instance.new("TextLabel")
	tag.BackgroundTransparency = 1
	tag.Font = Enum.Font.Code
	tag.TextSize = 9
	tag.TextColor3 = COLORS.signal
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.Text = mobile and "drag · scroll" or "SLAP // CONTROL"
	tag.Size = UDim2.new(0.4, 0, 1, 0)
	tag.Position = UDim2.fromOffset(90, 0)
	tag.Parent = header

	local closeButton = Instance.new("TextButton")
	closeButton.AutoButtonColor = false
	closeButton.BackgroundColor3 = COLORS.panel
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 11
	closeButton.TextColor3 = COLORS.soft
	closeButton.Text = "X"
	closeButton.Size = UDim2.fromOffset(22, 22)
	closeButton.Position = UDim2.new(1, -28, 0.5, -11)
	closeButton.Parent = header
	addCorner(closeButton, 4)
	addStroke(closeButton, COLORS.line, 1)
	track(closeButton.MouseButton1Click:Connect(destroy))

	makeDraggable(mainFrame, header)

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Size = UDim2.new(1, -3, 1, -(headerH + 20))
	body.Position = UDim2.fromOffset(3, headerH)
	body.ScrollBarThickness = mobile and 4 or 3
	body.ScrollBarImageColor3 = COLORS.signal
	body.ScrollingDirection = Enum.ScrollingDirection.Y
	body.CanvasSize = UDim2.fromOffset(0, 0)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.Parent = mainFrame

	local bodyPad = Instance.new("UIPadding")
	bodyPad.PaddingTop = UDim.new(0, 4)
	bodyPad.PaddingBottom = UDim.new(0, 6)
	bodyPad.PaddingLeft = UDim.new(0, pad)
	bodyPad.PaddingRight = UDim.new(0, pad)
	bodyPad.Parent = body

	local bodyLayout = Instance.new("UIListLayout")
	bodyLayout.Padding = UDim.new(0, 3)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bodyLayout.Parent = body

	local section = Instance.new("TextLabel")
	section.BackgroundTransparency = 1
	section.Font = Enum.Font.Code
	section.TextSize = 8
	section.TextColor3 = COLORS.mute
	section.TextXAlignment = Enum.TextXAlignment.Left
	section.Text = "MODULES"
	section.Size = UDim2.new(1, 0, 0, 10)
	section.LayoutOrder = 1
	section.Parent = body

	glovesBtn = makeToggleRow(body, "gloves", "Gloves Farm", 2, false)
	slapBtn = makeToggleRow(body, "slap", "Slap Farm", 3, false)
	targetFarmBtn = makeToggleRow(body, "targetFarm", "Target Farm", 4, false)
	tpBtn = makeToggleRow(body, "autoTP", "Auto Teleport", 5, true)
	stealthBtn = makeToggleRow(body, "stealth", "Stealth", 6, true)

	local intRow = Instance.new("Frame")
	intRow.BackgroundColor3 = COLORS.panel
	intRow.BorderSizePixel = 0
	intRow.Size = UDim2.new(1, 0, 0, mobile and 28 or 24)
	intRow.LayoutOrder = 7
	intRow.Parent = body
	addCorner(intRow, 4)
	addStroke(intRow, COLORS.line, 1)

	local intLabel = Instance.new("TextLabel")
	intLabel.BackgroundTransparency = 1
	intLabel.Font = Enum.Font.GothamMedium
	intLabel.TextSize = mobile and 12 or 11
	intLabel.TextColor3 = COLORS.text
	intLabel.TextXAlignment = Enum.TextXAlignment.Left
	intLabel.Text = "Interval"
	intLabel.Size = UDim2.new(1, -90, 1, 0)
	intLabel.Position = UDim2.fromOffset(10, 0)
	intLabel.Parent = intRow

	local intUnit = Instance.new("TextLabel")
	intUnit.BackgroundTransparency = 1
	intUnit.Font = Enum.Font.Code
	intUnit.TextSize = 9
	intUnit.TextColor3 = COLORS.mute
	intUnit.Text = "SEC"
	intUnit.Size = UDim2.fromOffset(24, mobile and 28 or 24)
	intUnit.Position = UDim2.new(1, -28, 0, 0)
	intUnit.Parent = intRow

	intervalBox = Instance.new("TextBox")
	intervalBox.Size = UDim2.fromOffset(40, mobile and 20 or 18)
	intervalBox.Position = UDim2.new(1, -74, 0.5, mobile and -10 or -9)
	intervalBox.BackgroundColor3 = COLORS.void
	intervalBox.TextColor3 = COLORS.signal
	intervalBox.Text = "2.0"
	intervalBox.Font = Enum.Font.Code
	intervalBox.TextSize = 11
	intervalBox.ClearTextOnFocus = false
	intervalBox.BorderSizePixel = 0
	intervalBox.Parent = intRow
	addCorner(intervalBox, 3)
	addStroke(intervalBox, COLORS.line, 1)

	local playersHead = Instance.new("Frame")
	playersHead.BackgroundTransparency = 1
	playersHead.Size = UDim2.new(1, 0, 0, 18)
	playersHead.LayoutOrder = 8
	playersHead.Parent = body

	local playersSection = Instance.new("TextLabel")
	playersSection.BackgroundTransparency = 1
	playersSection.Font = Enum.Font.Code
	playersSection.TextSize = 8
	playersSection.TextColor3 = COLORS.mute
	playersSection.TextXAlignment = Enum.TextXAlignment.Left
	playersSection.Text = "PLAYERS"
	playersSection.Size = UDim2.new(0.3, 0, 1, 0)
	playersSection.Parent = playersHead

	selectedLabel = Instance.new("TextLabel")
	selectedLabel.BackgroundTransparency = 1
	selectedLabel.Font = Enum.Font.Code
	selectedLabel.TextSize = 9
	selectedLabel.TextColor3 = COLORS.mute
	selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
	selectedLabel.Text = "TARGET · none"
	selectedLabel.Size = UDim2.new(0.5, 0, 1, 0)
	selectedLabel.Position = UDim2.fromOffset(70, 0)
	selectedLabel.Parent = playersHead

	local refreshPlayersBtn = Instance.new("TextButton")
	refreshPlayersBtn.AutoButtonColor = false
	refreshPlayersBtn.BackgroundColor3 = COLORS.panel
	refreshPlayersBtn.Font = Enum.Font.Code
	refreshPlayersBtn.TextSize = 9
	refreshPlayersBtn.TextColor3 = COLORS.soft
	refreshPlayersBtn.Text = "SYNC"
	refreshPlayersBtn.Size = UDim2.fromOffset(40, 16)
	refreshPlayersBtn.Position = UDim2.new(1, -40, 0.5, -8)
	refreshPlayersBtn.Parent = playersHead
	addCorner(refreshPlayersBtn, 3)
	addStroke(refreshPlayersBtn, COLORS.line, 1)

	playerListFrame = Instance.new("ScrollingFrame")
	playerListFrame.BackgroundColor3 = COLORS.panel
	playerListFrame.BorderSizePixel = 0
	playerListFrame.Size = UDim2.new(1, 0, 0, mobile and 64 or 58)
	playerListFrame.LayoutOrder = 9
	playerListFrame.ScrollBarThickness = mobile and 4 or 3
	playerListFrame.ScrollBarImageColor3 = COLORS.signal
	playerListFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	playerListFrame.CanvasSize = UDim2.fromOffset(0, 0)
	playerListFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	playerListFrame.Parent = body
	addCorner(playerListFrame, 4)
	addStroke(playerListFrame, COLORS.line, 1)

	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 2)
	listPad.PaddingLeft = UDim.new(0, 2)
	listPad.PaddingRight = UDim.new(0, 2)
	listPad.PaddingBottom = UDim.new(0, 2)
	listPad.Parent = playerListFrame

	playerListLayout = Instance.new("UIListLayout")
	playerListLayout.Padding = UDim.new(0, 2)
	playerListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	playerListLayout.Parent = playerListFrame

	stopTargetBtn = Instance.new("TextButton")
	stopTargetBtn.AutoButtonColor = false
	stopTargetBtn.BackgroundColor3 = COLORS.panel
	stopTargetBtn.Font = Enum.Font.GothamBold
	stopTargetBtn.TextSize = 11
	stopTargetBtn.TextColor3 = COLORS.danger
	stopTargetBtn.Text = "STOP TARGET"
	stopTargetBtn.Size = UDim2.new(1, 0, 0, mobile and 26 or 22)
	stopTargetBtn.LayoutOrder = 10
	stopTargetBtn.Parent = body
	addCorner(stopTargetBtn, 4)
	addStroke(stopTargetBtn, COLORS.line, 1)

	statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Font = Enum.Font.Code
	statusLabel.TextSize = 9
	statusLabel.TextColor3 = COLORS.mute
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
	statusLabel.Text = mobile and "> ready · drag" or "> ready · G"
	statusLabel.Size = UDim2.new(1, -10, 0, 14)
	statusLabel.Position = UDim2.fromOffset(8, menuH - 16)
	statusLabel.Parent = mainFrame

	local credit = Instance.new("TextLabel")
	credit.Name = "Credit"
	credit.BackgroundTransparency = 1
	credit.Font = Enum.Font.Code
	credit.TextSize = 10
	credit.TextColor3 = COLORS.mute
	credit.TextTransparency = 0.25
	credit.TextXAlignment = Enum.TextXAlignment.Right
	credit.TextYAlignment = Enum.TextYAlignment.Bottom
	credit.Text = "By Fr0st1208"
	credit.Size = UDim2.fromOffset(100, 14)
	credit.Position = UDim2.new(1, -110, 1, -18)
	credit.ZIndex = 50
	credit.Parent = screenGui

	task.defer(function()
		clampMenuToScreen(mainFrame)
	end)

	track(glovesBtn.MouseButton1Click:Connect(function()
		state.glovesOn = not state.glovesOn
		refreshButtons()
		setStatus(state.glovesOn and "> gloves online" or "> gloves idle", state.glovesOn and COLORS.signal or COLORS.mute)
	end))

	track(slapBtn.MouseButton1Click:Connect(function()
		state.slapOn = not state.slapOn
		if state.slapOn then
			state.targetFarmOn = false
			armSlapSession()
			setStatus("> slap farm armed", COLORS.signal)
		else
			if not state.targetFarmOn then
				disableStealth()
			end
			setStatus("> slap farm idle", COLORS.mute)
		end
		refreshButtons()
	end))

	track(targetFarmBtn.MouseButton1Click:Connect(function()
		if not state.targetName then
			setStatus("> pick player first", COLORS.err)
			refreshPlayerRows()
			return
		end
		state.targetFarmOn = not state.targetFarmOn
		if state.targetFarmOn then
			state.slapOn = false
			armSlapSession()
			setStatus("> target farm · " .. state.targetName, COLORS.signal)
		else
			if not state.slapOn then
				disableStealth()
			end
			setStatus("> target farm idle", COLORS.mute)
		end
		refreshButtons()
	end))

	track(tpBtn.MouseButton1Click:Connect(function()
		state.autoTP = not state.autoTP
		refreshButtons()
		setStatus(state.autoTP and "> auto-tp on" or "> auto-tp off", COLORS.mute)
	end))

	track(stealthBtn.MouseButton1Click:Connect(function()
		state.stealth = not state.stealth
		if state.stealth and slapActive() then
			enableStealth()
		elseif not state.stealth then
			disableStealth()
		end
		refreshButtons()
		setStatus(state.stealth and "> stealth engaged" or "> stealth off", state.stealth and COLORS.signal or COLORS.mute)
	end))

	track(intervalBox.FocusLost:Connect(function()
		local n = tonumber((intervalBox.Text:gsub(",", ".")))
		if n then
			state.slapInterval = math.clamp(n, 1.0, 10)
			intervalBox.Text = string.format("%.1f", state.slapInterval)
		else
			intervalBox.Text = string.format("%.1f", state.slapInterval)
		end
		refreshButtons()
	end))

	track(refreshPlayersBtn.MouseButton1Click:Connect(function()
		refreshPlayerRows()
		setStatus("> players refreshed", COLORS.mute)
	end))

	track(stopTargetBtn.MouseButton1Click:Connect(function()
		clearTarget()
		if not state.slapOn then
			disableStealth()
		end
	end))

	track(UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not state.alive then
			return
		end
		if input.KeyCode == MENU_TOGGLE_KEY then
			mainFrame.Visible = not mainFrame.Visible
		end
	end))

	track(Players.PlayerAdded:Connect(function()
		task.defer(refreshPlayerRows)
	end))
	track(Players.PlayerRemoving:Connect(function(leaving)
		if state.targetName == leaving.Name then
			clearTarget()
			if not state.slapOn then
				disableStealth()
			end
		else
			task.defer(refreshPlayerRows)
		end
	end))

	refreshButtons()
	refreshPlayerRows()
	updateSelectedLabel()
end

buildMenu()
task.spawn(glovesFarmLoop)
task.spawn(slapFarmLoop)

track(player.CharacterAdded:Connect(function()
	clearLocalClone()
	state.stealthOn = false
	if not state.alive or not slapActive() then
		return
	end
	task.spawn(function()
		task.wait(0.8)
		if state.alive and slapActive() then
			enterArena()
		end
	end)
end))

getgenv().SlapBattlesCombined = {
	destroy = destroy,
	setGloves = function(v)
		state.glovesOn = v and true or false
		refreshButtons()
	end,
	setSlap = function(v)
		state.slapOn = v and true or false
		if state.slapOn then
			state.targetFarmOn = false
			armSlapSession()
		elseif not state.targetFarmOn then
			disableStealth()
		end
		refreshButtons()
	end,
	setTargetFarm = function(v, name)
		if name then
			state.targetName = name
			updateSelectedLabel()
			refreshPlayerRows()
		end
		state.targetFarmOn = v and true or false
		if state.targetFarmOn then
			state.slapOn = false
			armSlapSession()
		elseif not state.slapOn then
			disableStealth()
		end
		refreshButtons()
	end,
	clearTarget = clearTarget,
}

print("[SlapBattlesCombined] gloves + slap farm + target farm")
