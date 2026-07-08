-- GunConfig.lua (Shared)
-- Defines the behavior for the AAA Gun System (Wheelchair Optimized)

local GunConfig = {
    AssaultRifle = {
        -- Base Stats
        Damage = 10,
        HeadshotDamage = 15,
        FireRate = 0.09, -- ~660 RPM
        MagSize = 30,
        ReloadTime = 2.2,
        MaxDistance = 800,
        
        -- Recoil (Camera Space)
        RecoilVertical = 1.0, -- Degrees/shot up
        RecoilHorizontal = 0.4, -- Max Degrees/shot side
        RecoilRecoverySpeed = 15, -- Speed of return to center
        RecoilCap = 20, -- Max vertical rise
        
        -- Spread / Bloom (Authoritative)
        BaseSpread = 0.1, -- Degrees (First shot accuracy)
        SpreadPerShot = 0.2, -- Degrees added per shot
        MaxSpread = 4.0, -- Max bloom
        SpreadDecay = 10, -- Degrees per second recovery
        
        -- Camera (OTS)
        -- NOTE: Logic uses Base * Rotation * Offset
        OTSOffset = Vector3.new(3.0, 2.5, 8.0), -- Right, Up, Back (Increased Z/Y)
        FOV_Magnification = 1.1, -- Slight zoom on aim?
        
        -- Accessibility
        -- Modifiers for when moving/drifting (kept low for access)
        MoveSpreadFactor = 1.1, -- 10% penalty only
    },
    
    ["CRUTCH SPEAR"] = {
        Damage = 0,
        HeadshotDamage = 0,
        FireRate = 0.5,
        MagSize = 1,
        ReloadTime = 0,
        MaxDistance = 0,
        FullAuto = true,
        RecoilVertical = 0,
        RecoilHorizontal = 0,
        RecoilRecoverySpeed = 10,
        RecoilCap = 0,
        BaseSpread = 0,
        SpreadPerShot = 0,
        MaxSpread = 0,
        SpreadDecay = 10,
        OTSOffset = Vector3.new(3.0, 2.5, 8.0),
        FOV_Magnification = 1.0,
        MoveSpreadFactor = 1.0,
    }
}

return GunConfig
