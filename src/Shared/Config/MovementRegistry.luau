--!strict
--@author OrkGabb
--@module MovementRegistry.luau
--@version 1.6
-- Static movement-tuning registry: the single source of truth for every
-- tunable number behind locomotion abilities. FeatureToggles stays purely
-- executive (high-level on/off switches); designers retune movement feel
-- here without ever touching executive flags or controller logic.
--
-- Consumed by:
--   * Client/Controllers/DashController — input, charges, physics timing
--   * Client/UI/DashFX                  — procedural glide pose, wind trail + camera juice
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
	-- Force budget for the LinearVelocity actuator, applied to each axis
	-- (PerAxis limit mode) — the vertical altitude hold gets the same budget
	-- as the horizontal drive.
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
	-- Backward rotation applied to both shoulders about the character's right
	-- axis, pinning the arms behind the back for the aerodynamic "ninja
	-- glide" pose (degrees; 0 leaves the arms animation-driven).
	ArmPitchDegrees: number,
	-- Fade (seconds) used to stop the playing AnimationTracks at dash start —
	-- limbs blend to the rest pose and glide instead of locking mid-stride.
	-- (The default Animate script is disabled for the dash and re-enabled on
	-- release; its restart resumes locomotion on its own.)
	AnimationFadeSeconds: number,
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

export type DashTrailConfig = {
	-- Particle texture for the wind wisps streaming off the character.
	Texture: string,
	-- Particles emitted per second by EACH arm emitter (one per arm).
	EmitRate: number,
	-- Self-illumination of the wisps (0-1). High values render the trail as
	-- clean bright white instead of lighting-dependent gray smoke.
	LightEmission: number,
	-- How much scene lighting darkens the wisps (0 = not at all, 1 = fully).
	LightInfluence: number,
	-- Particle size over each particle's lifetime (studs): spawns at SizeStart,
	-- grows/shrinks linearly to SizeEnd right before it dies.
	SizeStart: number,
	SizeEnd: number,
	-- Particle transparency over lifetime: TransparencyStart at spawn, easing
	-- along a smoothstep curve (built by DashFX) to TransparencyEnd at death —
	-- wisps fade out naturally instead of popping out of existence.
	TransparencyStart: number,
	TransparencyEnd: number,
	-- Per-particle lifetime range (seconds). LifetimeMax also bounds cleanup:
	-- the emitter is destroyed LifetimeMax seconds after it stops emitting.
	LifetimeMin: number,
	LifetimeMax: number,
	-- Initial particle speed range (studs/second), fired opposite to the dash.
	SpeedMin: number,
	SpeedMax: number,
	-- Half-angle of the emission cone (degrees) — the "wind-cutting" spread.
	SpreadAngleDegrees: number,
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
	Trail: DashTrailConfig,
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
			ForwardAngleDegrees  = 22,
			SideAngleDegrees     = 10,
			WaistScale           = 0.5,
			ArmPitchDegrees      = 75,
			AnimationFadeSeconds = 0.1,
			EaseInSeconds        = 0.05,
			EaseOutSeconds       = 0.18,
			EasingStyle          = Enum.EasingStyle.Quad,
			EasingDirection      = Enum.EasingDirection.Out,
		},

		Camera = {
			FovBoost        = 8,
			EaseInSeconds   = 0.1,
			EaseOutSeconds  = 0.25,
			EasingStyle     = Enum.EasingStyle.Quad,
			EasingDirection = Enum.EasingDirection.Out,
		},

		Trail = {
			Texture            = "rbxasset://textures/particles/smoke_main.dds",
			EmitRate           = 60,
			LightEmission      = 0.75,
			LightInfluence     = 0,
			SizeStart          = 0.35,
			SizeEnd            = 2.5,
			TransparencyStart  = 0.35,
			TransparencyEnd    = 1,
			LifetimeMin        = 0.2,
			LifetimeMax        = 0.4,
			SpeedMin           = 10,
			SpeedMax           = 16,
			SpreadAngleDegrees = 15,
		},
	},
}

return MovementRegistry
