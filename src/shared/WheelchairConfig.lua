local WheelchairConfig = {
	-- Speed & Acceleration
	MaxSpeed = 50,           -- Target Speed (Studs/s)
	ReverseMaxSpeed = 11,    -- Proportional (was 15 at 70)
	Acceleration = 1.5,      -- Industrial Grade (Sim 5.0)
	Deceleration = 25.0,    -- Faster slow-down
	BrakeDrag = 150,        -- Heavy drag when letting go
	
	-- Suspension (Raycast)
	SusStiffness = 3800,     -- Stiffer for high horizontal velocity
	SusDamping = 800,        -- Standard damping
	SusRestLength = 2.5,     
	SusRayLength = 4.0,      
	
	-- Handling
	TurnSpeed = 10,          -- Reduced from 15 to prevent beyblading
	TurnTorque = 1500,       -- High-speed authority
	TireGrip = 15.0,         -- Extreme grip to prevent tripping
	DriftGrip = 0.005,       -- Super-Slick "Speed Demon"
	DriftThreshold = 39,     -- Proportional (was 55 at 70)
	DriftEntrySpeed = 36,    -- Proportional (was 50 at 70)
	DriftExitSpeed = 18,     -- Proportional (was 25 at 70)
	
	-- Jump
	JumpImpulse = 48,        -- Reduced power
	AirControl = 0.2,        -- Reduced to prevent flings
	
	-- Tipping
    MaxSlipAngle = 20,       -- Increased for better recoverability
    HybridSpeedThreshold = 30, -- Lowered so drift is accessible before max speed
    RollingDragCoeff = 0.12, -- Visible natural decay
    YawDampingCoeff = 35,    -- Extra stability for heavy drift
    DismountThreshold = 65,  -- Angle in degrees to eject player
    WallCrashThreshold = 29, -- Proportional (was 40 at 70)
    BumperLength = 2.5,      -- Forward raycast length
}

return WheelchairConfig
