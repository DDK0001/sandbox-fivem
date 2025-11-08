-- Development Mode Configuration
-- Dev mode is automatically enabled when sv_environment is set to "DEV"
-- You can also manually enable it by setting _devMode = true
_devMode = true -- Set to true to force dev mode (overrides environment check)
_devCookTime = 30 -- Cook time in seconds when dev mode is enabled (default: 30 seconds)
_devAgingTime = 30 -- Barrel aging time in seconds when dev mode is enabled (default: 30 seconds)

-- Still Tiers Configuration
_stillTiers = {
    [1] = {
        label = "Basic Still",
        checks = 10,
        cookTime = 30,
        efficiency = 0.75, -- Quality multiplier
        maxHeat = 50, -- Heat generation per brew
        upgradeCost = 0, -- Cost to upgrade to next tier
    },
    [2] = {
        label = "Improved Still",
        checks = 15,
        cookTime = 20,
        efficiency = 0.90,
        maxHeat = 40,
        upgradeCost = 50000,
    },
    [3] = {
        label = "Professional Still",
        checks = 20,
        cookTime = 15,
        efficiency = 1.0,
        maxHeat = 30,
        upgradeCost = 150000,
    },
    [4] = {
        label = "Master Still",
        checks = 25,
        cookTime = 10,
        efficiency = 1.15,
        maxHeat = 20,
        upgradeCost = 0, -- Max tier
    }
}

-- Moonshine Recipes
_moonshineRecipes = {
    {
        id = "classic",
        label = "Classic Moonshine",
        description = "Traditional corn-based moonshine",
        ingredients = {
            { item = "corn", amount = 5 },
            { item = "sugar", amount = 3 },
            { item = "water", amount = 2 },
        },
        baseQuality = 50,
        difficulty = 1,
        agingBonus = 1.2, -- Quality multiplier from aging
        minAgingTime = 60 * 60 * 24, -- 1 day minimum
        optimalAgingTime = 60 * 60 * 24 * 3, -- 3 days optimal
        effects = {
            drunkAmount = 10, -- Base drunk level
            healAmount = 5, -- Health per second
            healDuration = 30, -- Seconds of healing
            stressRelief = 5, -- Stress reduction
        },
    },
    {
        id = "apple",
        label = "Apple Pie Moonshine",
        description = "Sweet apple-flavored moonshine",
        ingredients = {
            { item = "corn", amount = 4 },
            { item = "apple", amount = 6 },
            { item = "sugar", amount = 4 },
            { item = "water", amount = 2 },
        },
        baseQuality = 60,
        difficulty = 2,
        agingBonus = 1.3,
        minAgingTime = 60 * 60 * 24 * 2,
        optimalAgingTime = 60 * 60 * 24 * 4,
        effects = {
            drunkAmount = 12, -- Slightly more drunk
            healAmount = 6, -- Better healing
            healDuration = 35, -- Longer healing
            stressRelief = 8, -- More stress relief
        },
    },
    {
        id = "peach",
        label = "Peach Moonshine",
        description = "Premium peach-infused moonshine",
        ingredients = {
            { item = "corn", amount = 5 },
            { item = "peach", amount = 8 },
            { item = "sugar", amount = 5 },
            { item = "water", amount = 2 },
        },
        baseQuality = 70,
        difficulty = 3,
        agingBonus = 1.4,
        minAgingTime = 60 * 60 * 24 * 3,
        optimalAgingTime = 60 * 60 * 24 * 5,
        effects = {
            drunkAmount = 15, -- More drunk
            healAmount = 7, -- Better healing
            healDuration = 40, -- Longer healing
            stressRelief = 10, -- Good stress relief
        },
    },
    {
        id = "cherry",
        label = "Cherry Bomb Moonshine",
        description = "High-quality cherry moonshine",
        ingredients = {
            { item = "corn", amount = 6 },
            { item = "cherry", amount = 10 },
            { item = "sugar", amount = 6 },
            { item = "water", amount = 3 },
        },
        baseQuality = 80,
        difficulty = 4,
        agingBonus = 1.5,
        minAgingTime = 60 * 60 * 24 * 4,
        optimalAgingTime = 60 * 60 * 24 * 7,
        effects = {
            drunkAmount = 18, -- Strong drunk effect
            healAmount = 8, -- Great healing
            healDuration = 45, -- Long healing
            stressRelief = 15, -- Excellent stress relief
        },
    },
    {
        id = "premium",
        label = "Premium Reserve",
        description = "Ultra-premium moonshine for connoisseurs",
        ingredients = {
            { item = "corn", amount = 8 },
            { item = "honey", amount = 4 },
            { item = "sugar", amount = 8 },
            { item = "water", amount = 4 },
            { item = "yeast", amount = 2 },
        },
        baseQuality = 90,
        difficulty = 5,
        agingBonus = 1.6,
        minAgingTime = 60 * 60 * 24 * 7,
        optimalAgingTime = 60 * 60 * 24 * 14,
        effects = {
            drunkAmount = 20, -- Maximum drunk effect
            healAmount = 10, -- Maximum healing
            healDuration = 50, -- Longest healing
            stressRelief = 20, -- Maximum stress relief
        },
    }
}

-- Quality Calculation Factors
_qualityFactors = {
    skillMultiplier = 0.3, -- 30% from skill level
    ingredientQuality = 0.2, -- 20% from ingredient quality
    temperature = 0.15, -- 15% from temperature
    skillChecks = 0.25, -- 25% from skill check success rate
    stillTier = 0.10, -- 10% from still tier
}

-- Police Detection System
_policeDetection = {
    heatPerBrew = 5, -- Heat generated per brew
    heatDecayRate = 1, -- Heat lost per minute
    maxHeat = 100,
    alertThreshold = 50, -- Heat level to trigger police alert
    raidThreshold = 80, -- Heat level to trigger raid chance
    raidChance = 0.15, -- 15% chance per check when above threshold
    detectionRadius = 100.0, -- Meters
    alertCooldown = 60 * 5, -- 5 minutes between alerts
}

-- Temperature Effects (affects quality)
_temperatureEffects = {
    optimal = { min = 15, max = 25 }, -- Celsius, optimal range
    good = { min = 10, max = 30 }, -- Good range
    poor = { min = 5, max = 35 }, -- Poor range
    -- Outside poor range = very bad quality
}

-- Weather Effects
_weatherEffects = {
    clear = 1.0, -- No modifier
    clouds = 0.95,
    foggy = 0.90,
    rain = 0.85,
    thunder = 0.80,
    snow = 0.75,
}

-- Reputation System
_reputationSystem = {
    repPerBrew = 2, -- Reputation gained per successful brew
    repPerDelivery = 10, -- Reputation gained per delivery
    repLossOnRaid = 20, -- Reputation lost if raided
    unlockRecipes = {
        classic = 0,
        apple = 500,
        peach = 1500,
        cherry = 3000,
        premium = 5000,
    }
}

-- Delivery System
_deliverySystem = {
    minRep = 100, -- Minimum reputation to unlock deliveries
    basePay = 500, -- Base payment per delivery
    payPerQuality = 10, -- Additional pay per quality point
    maxDistance = 5000.0, -- Max delivery distance in meters
    minDistance = 1000.0, -- Min delivery distance
    deliveryTimeLimit = 60 * 15, -- 15 minutes to complete
    policeChance = 0.10, -- 10% chance of police encounter
}

-- Aging System
_agingSystem = {
    baseAgingTime = 60 * 60 * 24 * 2, -- 2 days base
    qualityIncreasePerDay = 2, -- Quality points per day of aging
    maxAgingBonus = 30, -- Maximum quality bonus from aging
    optimalTemp = 12, -- Optimal aging temperature (Celsius)
}

-- Still Upgrade System
_upgradeSystem = {
    upgradeTime = 60 * 5, -- 5 minutes to upgrade
    upgradeCostMultiplier = 1.5, -- Cost multiplier per tier
    requireRep = {
        [2] = 0,
        [3] = 1000,
        [4] = 3000,
    }
}