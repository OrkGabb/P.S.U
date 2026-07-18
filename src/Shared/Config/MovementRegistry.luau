--!strict
--@author OrkGabb
--@module MovementRegistry.luau
--@version 1.0
-- Static movement-tuning registry: the single source of truth for every
-- tunable number behind locomotion abilities. FeatureToggles stays purely
-- executive (high-level on/off switches); designers retune movement feel
-- here without ever touching executive flags or controller logic.
--
-- Consumed by:
--   * Client/Controllers/DashController — input, charges, physics timing
--   * Client/UI/DashFX                  — procedural lean + camera juice
--   * Server/Services/DashService       — server-side validation numbers

export type DashPhysicsConfig = {
	-- Peak speed along the dash direction (studs/second).
	Speed: number,
	-- Total seconds from impulse start until the constraint is removed.
	Duration: number,
	-- Final slice of Duration during which speed eases down to zero.
	-- Must be less than Duration; the remainder is the full-speed sustain phase.
	EaseOutSeconds: number,
	-- Easing applied to the speed ramp-down tween.
	EasingStyle: Enum.EasingStyle,
	EasingDirection: Enum.EasingDirection,
	-- Force budget for the LinearVelocity actuator.
	MaxForce: number,
}

export type DashLeanConfig = {
	-- Peak torso inclination when dashing straight forward/backward (degrees).
	ForwardAngleDegrees: number,
	-- Peak sideways roll when dashing straight left/right (degrees).
	SideAngleDegrees: number,
	-- Fraction of the root lean also applied to the R15 Waist joint for a
	-- softer two-segment bend (0 disables it; R6 rigs only have the RootJoint).
	WaistScale: number,
	EaseInSeconds: number,
	EaseOutSeconds: number,
	EasingStyle: Enum.EasingStyle,
	EasingDirection: Enum.EasingDirection,
}

export type DashCameraConfig = {
	-- Degrees added to the camera FieldOfView at the peak of the impulse.
	FovBoost: number,
	EaseInSeconds: number,
	EaseOutSeconds: number,
	EasingStyle: Enum.EasingStyle,
	EasingDirection: Enum.EasingDirection,
}

export type DashMovementConfig = {
	-- Seconds a spent charge takes to refill (server-authoritative).
	Cooldown: number,
	MaxCharges: number,
	-- Minimum seconds between accepted dash inputs (client-side debounce).
	InputDebounceSeconds: number,
	DesktopKeybinds: { Enum.KeyCode },
	Physics: DashPhysicsConfig,
	Lean: DashLeanConfig,
	Camera: DashCameraConfig,
}

export type MovementRegistryType = {
	Dash: DashMovementConfig,
}

local MovementRegistry: MovementRegistryType = {
	-- Q and LeftShift are owned by WeaponController (weapon-cycle and sprint);
	-- dash stays on LeftControl.
	Dash = {
		Cooldown             = 2.0,
		MaxCharges           = 3,
		InputDebounceSeconds = 0.1,
		DesktopKeybinds      = { Enum.KeyCode.LeftControl },

		Physics = {
			Speed           = 50.0,
			Duration        = 0.35,
			EaseOutSeconds  = 0.15,
			EasingStyle     = Enum.EasingStyle.Quad,
			EasingDirection = Enum.EasingDirection.Out,
			MaxForce        = math.huge,
		},

		Lean = {
			ForwardAngleDegrees = 14,
			SideAngleDegrees    = 10,
			WaistScale          = 0.5,
			EaseInSeconds       = 0.08,
			EaseOutSeconds      = 0.18,
			EasingStyle         = Enum.EasingStyle.Quad,
			EasingDirection     = Enum.EasingDirection.Out,
		},

		Camera = {
			FovBoost        = 8,
			EaseInSeconds   = 0.1,
			EaseOutSeconds  = 0.25,
			EasingStyle     = Enum.EasingStyle.Quad,
			EasingDirection = Enum.EasingDirection.Out,
		},
	},
}

return MovementRegistry
