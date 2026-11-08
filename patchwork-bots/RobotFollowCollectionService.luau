local Config = require(game.ReplicatedStorage.Shared.Configs.RobotExplorationConfig)
local Follow = require(game.ReplicatedStorage.Shared.Configs.RobotFollowConfig).Collection
local Pose = require(game.ReplicatedStorage.Shared.RobotPose)
local Navigation = require(script.Parent.RobotNavigationService)
local Zones = require(script.Parent.RobotZoneService)
local WorldScrap = require(script.Parent.WorldScrapService)
local Discovery = require(script.Parent.CollectibleDiscoveryService)
local MovementRecovery = require(script.Parent.RobotMovementRecovery)

local Collection = {}
local states = {}

local function attribute(record, name, value)
	if record:GetAttribute(name) ~= value then record:SetAttribute(name, value) end
end

function Collection.Cancel(record)
	local state = states[record]
	if state and state.Target then WorldScrap.ReleaseRobotReservation(state.Target.Model, record) end
	if state then state.Plan, state.RescueToken = nil, nil end
	states[record] = nil
	attribute(record, "FollowCollecting", nil)
	attribute(record, "FollowCollectTarget", nil)
	attribute(record, "FollowScanning", false)
end

function Collection.AfterRejoin(record)
	local state = states[record]
	if not state then return end
	local now = os.clock()
	state.NextScan = math.max(state.NextScan, now + Follow.AfterPickupSeconds)
	for scrap in state.Ignored do state.Ignored[scrap] = now + Follow.RetrySeconds end
end

-- Keep the direct approach cheap. Obstacle detours run outside the heartbeat.
local function destination(context, current, target)
	if Navigation.CanCollectFrom(context, current, target) then return current end
	local flat = Vector3.new(current.X - target.X, 0, current.Z - target.Z)
	local startAngle = math.atan2(flat.Z, flat.X)
	local radius = (Config.CollectDistance - Config.ScrapCollectMargin) * 0.8
	for index = 0, 8 do
		local angle = startAngle + index * math.pi / 4
		local wanted = Vector3.new(target.X + math.cos(angle) * radius, current.Y, target.Z + math.sin(angle) * radius)
		local point = Navigation.GroundAtPivot(context, wanted)
		if point
			and Navigation.CanCollectFrom(context, point, target)
			and Navigation.CanTravel(context, current, point) then return point end
	end
	return nil
end

local function planRoute(record, model, state, current)
	local plan = {}
	state.Plan, state.Planning = plan, true
	state.PlanningStartedAt = os.clock()
	local target = state.Target
	local function active()
		return states[record] == state and state.Plan == plan and state.Target == target
			and model.Parent ~= nil and target.Model.Parent ~= nil
			and record:GetAttribute("Status") == "Following"
			and record:GetAttribute("FollowPaused") ~= true
			and record:GetAttribute("CommandGeneration") == state.Generation
	end
	task.spawn(function()
		local ok, points = pcall(function()
			return Navigation.FindScrapPath(Navigation.CreateContext(model), current, target.Position, active, nil, target.SurfacePosition)
		end)
		-- A cancelled planner must never overwrite a new target or release its reservation.
		if states[record] ~= state or state.Plan ~= plan or state.Target ~= target then return end
		state.Planning = false
		if ok and points and #points > 0 and active() then
			state.Path, state.PathIndex = points, 1
			state.LastProgressAt = os.clock()
		else
			state.RouteFailed = true
		end
	end)
end

function Collection.Update(player, record, model, context, frame): (boolean, boolean)
	local current = Pose.Get(model).Position
	local area = Zones.GetZoneAt(current)
	local canScan = not frame.Rejoining and area ~= nil
		and WorldScrap.CanFollowCollect(player, record, model, area)
	if not canScan then
		local previous = states[record]
		local hadTarget = previous and previous.Target ~= nil
		Collection.Cancel(record)
		-- Preserve pickup/retry cooldowns while returning to the line.
		if previous then
			previous.Target, previous.Path, previous.Plan = nil, nil, nil
			previous.Planning, previous.RouteFailed = false, false
			previous.Recovering, previous.RecoveryResult, previous.StuckRecovery = false, nil, nil
			if hadTarget then previous.NextScan = os.clock() + Follow.RetrySeconds end
			states[record] = previous
		end
		return false, hadTarget == true
	end
	attribute(record, "FollowScanning", true)
	local state = states[record]
	if not state then state = {NextScan = 0, Ignored = {}}; states[record] = state end
	local now = os.clock()
	local function finish(delay, ignore)
		if state.Target then
			WorldScrap.ReleaseRobotReservation(state.Target.Model, record)
			if ignore then state.Ignored[state.Target.Model] = now + Follow.RetrySeconds end
		end
		state.Target, state.Path, state.Plan = nil, nil, nil
		state.Planning, state.RouteFailed = false, false
		state.RescueToken, state.Recovering, state.RecoveryResult, state.StuckRecovery = nil, false, nil, nil
		state.NextScan = now + delay
		attribute(record, "FollowCollecting", nil)
		attribute(record, "FollowCollectTarget", nil)
		attribute(record, "FollowScanning", false)
		return true, true
	end
	if not state.Target and now >= state.NextScan then
		state.NextScan = now + Follow.ScanIntervalSeconds
		for scrap, untilTime in state.Ignored do
			if not scrap.Parent or now >= untilTime then state.Ignored[scrap] = nil end
		end
		local scanRadius = Config.GetScanRadius(record:GetAttribute("RangeRating"))
		attribute(record, "SearchRadius", scanRadius)
		-- The sensor radius is centred on the robot, independent of trail and owner velocity.
		for _ = 1, Follow.MaxCandidatesPerScan do
			local nearby = WorldScrap.GetNearestAvailable(area, current,
				scanRadius, record, state.Ignored, current.Y - context.GroundOffset)
			if not nearby then break end
			if WorldScrap.ReserveForRobot(nearby.Model, record) then
				state.Target, state.Area, state.Model = nearby, area, model
				state.Generation = record:GetAttribute("CommandGeneration")
				state.LastProgressAt = now
				attribute(record, "FollowCollecting", true)
				local goal = destination(context, current, nearby.Position)
				if goal then
					state.Path, state.PathIndex = {goal}, 1
				else
					planRoute(record, model, state, current)
				end
				break
			else
				state.Ignored[nearby.Model] = now + Follow.RetrySeconds
			end
		end
	end
	local target = state.Target
	if not target then return false, false end
	if not target.Model.Parent or state.Area ~= area or state.Model ~= model
		or state.Generation ~= record:GetAttribute("CommandGeneration")
		or not WorldScrap.ReserveForRobot(target.Model, record) then
		return finish(Follow.RetrySeconds, true)
	end
	local recoveryReady = MovementRecovery.Observe(state, current, target.Position, "Scrap")
	if state.Recovering then return true, false end
	if state.RecoveryResult then
		local result = state.RecoveryResult
		state.RecoveryResult = nil
		if result ~= "Reached" then return finish(Follow.RetrySeconds, true) end
		state.StuckRecovery, recoveryReady = nil, false
	end
	if Navigation.CanCollectFrom(context, current, target.Position) then
		local collected, _, itemId = WorldScrap.CollectForRobot(area, target.Model, player, record, model, Config.CollectDistance)
		if collected and itemId then Discovery.RecordFound(player, itemId, 1, area) end
		return finish(Follow.AfterPickupSeconds, not collected)
	end
	if recoveryReady then
		local rescue = {}
		state.RescueToken, state.Recovering, state.Plan, state.Planning = rescue, true, nil, false
		local function active()
			return states[record] == state and state.RescueToken == rescue and state.Target == target
				and state.Generation == record:GetAttribute("CommandGeneration") and target.Model.Parent ~= nil
				and WorldScrap.CanFollowCollect(player, record, model, area)
		end
		task.spawn(function()
			local ok, result = pcall(MovementRecovery.Move, record, model, context, target.Position, "Scrap", active, target.SurfacePosition)
			-- Even a transient eligibility loss must finish the owned worker. The next
			-- heartbeat may be eligible again; leaving Recovering=true would strand it.
			if states[record] ~= state or state.RescueToken ~= rescue or state.Target ~= target then return end
			state.Recovering, state.RecoveryResult = false, if ok then result else "Failed"
		end)
		return true, false
	end
	if state.RouteFailed then
		state.RouteFailed, state.Path, state.NextPlan = false, nil, now + 0.5
	end
	if not state.Planning and not state.Path then
		if now >= (state.NextPlan or 0) then planRoute(record, model, state, current) end
		return true, false
	end
	if state.Planning then
		if now - state.PlanningStartedAt >= Follow.PlanningTimeoutSeconds then return finish(Follow.RetrySeconds, true) end
		return true, false
	end
	local speed = record:GetAttribute("Speed")
	if type(speed) ~= "number" or speed ~= speed or math.abs(speed) == math.huge or speed <= 0 then
		return finish(Follow.RetrySeconds, true)
	end
	if now - state.LastProgressAt >= Follow.StalledTimeoutSeconds then
		state.Path, state.NextPlan = nil, now
		state.LastProgressAt = now
		return true, false
	end
	local goal = state.Path and state.Path[state.PathIndex]
	while goal and (goal - current).Magnitude < 0.05 do
		state.PathIndex += 1
		goal = state.Path[state.PathIndex]
	end
	if not goal then return finish(Follow.RetrySeconds, true) end
	attribute(record, "FollowCollectTarget", goal)
	local delta = goal - current
	local step = math.min(delta.Magnitude, speed * frame.DeltaTime)
	if step < 0.001 then return finish(Follow.RetrySeconds, true) end
	local nextPoint = Navigation.GroundAtPivot(context, current + delta.Unit * step)
	if not nextPoint or not Navigation.CanTravel(context, current, nextPoint) then
		state.Path, state.NextPlan = nil, now + 0.5
		return true, false
	end
	local direction = Vector3.new(delta.X, 0, delta.Z)
	local rotation = Pose.Get(model).Rotation
	if direction.Magnitude > 0.001 then
		rotation = rotation:Lerp(CFrame.lookAt(Vector3.zero, -direction.Unit), 1 - math.exp(-8 * frame.DeltaTime))
	end
	Pose.Set(model, CFrame.new(nextPoint) * rotation, record)
	state.LastProgressAt = now
	return true, false
end

return Collection
