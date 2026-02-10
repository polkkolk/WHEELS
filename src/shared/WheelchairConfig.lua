local WheelchairConfig = {
	-- Speed & Acceleration
	MaxSpeed = 70,           -- Target Speed (Studs/s)
	ReverseMaxSpeed = 15,    -- Capped at 15 for realism (Sim 18.0)
	Acceleration = 1.5,      -- Industrial Grade (Sim 5.0)
	Deceleration = 25.0,    -- Faster slow-down
	BrakeDrag = 150,        -- Heavy drag when letting go
	
	-- Suspension (Raycast)
	SusStiffness = 3800,     -- Stiffer for high horizontal velocity
	SusDamping = 800,        -- Standard damping (reverted Sim 34.0)
	SusRestLength = 2.5,     
	SusRayLength = 4.0,      
	
	-- Handling
	TurnSpeed = 10,          -- Reduced from 15 to prevent beyblading
	TurnTorque = 1500,       -- Increased for high-speed authority (Sim 3.0)
	TireGrip = 15.0,         -- Extreme grip to prevent tripping
	DriftGrip = 0.005,       -- Super-Slick "Speed Demon" (Sim 8.0)
	DriftThreshold = 55,     -- Drift requires more speed (Sim 3.0)
	DriftEntrySpeed = 50,    -- Speed floor to enter drift (Sim 19.0)
	DriftExitSpeed = 25,     -- Speed floor to exit drift (Sim 19.0)
	
	-- Jump
	JumpImpulse = 48,        -- Reduced power
	AirControl = 0.2,        -- Reduced to prevent flings (Sim 3.0)
	
	-- Tipping
    -- Advanced ChatGPT Physics 2.0
    MaxSlipAngle = 20,       -- Increased for better recoverability
    HybridSpeedThreshold = 65, -- Aggressive mode strictly at high speed (Sim 3.0)
    RollingDragCoeff = 0.12, -- Visible natural decay (Sim 5.0)
    YawDampingCoeff = 35,    -- Extra stability for heavy drift (Sim 4.0)
    DismountThreshold = 65,  -- Angle in degrees to eject player (Sim 17.0)
    WallCrashThreshold = 40, -- Speed studs/s for emergency ejection (Sim 23.0)
    BumperLength = 2.5,      -- Forward raycast length (Sim 23.0)
}

return WheelchairConfig
