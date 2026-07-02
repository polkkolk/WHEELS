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
        FullAuto = true, -- Hold to fire
        
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
    
    Pistol = {
        -- Base Stats
        Damage = 15,
        HeadshotDamage = 25,
        FireRate = 0.2, -- Semi-auto, ~300 RPM max
        MagSize = 12,
        ReloadTime = 1.4,
        MaxDistance = 200,
        FullAuto = false, -- Semi-auto: one shot per click
        
        -- Recoil (Camera Space)
        RecoilVertical = 2.5, -- Snappier kick per shot
        RecoilHorizontal = 0.8, -- More horizontal sway
        RecoilRecoverySpeed = 12, -- Slightly slower recovery
        RecoilCap = 20, -- Max vertical rise
        
        -- Spread / Bloom (Authoritative)
        BaseSpread = 0.3, -- Less first-shot accuracy
        SpreadPerShot = 0.5, -- Bigger bloom per shot
        MaxSpread = 5.0, -- Higher max bloom
        SpreadDecay = 12, -- Faster recovery between shots
        
        -- Camera (OTS)
        OTSOffset = Vector3.new(3.0, 2.5, 8.0), -- Match AR exactly to prevent screen jerk
        FOV_Magnification = 1.0,
        
        -- Accessibility
        MoveSpreadFactor = 1.1,
    }
}

return GunConfig
