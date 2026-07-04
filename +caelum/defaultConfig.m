function cfg = defaultConfig()
%DEFAULTCONFIG Default configuration for Caelum offline analysis.

cfg = struct();

cfg.sampleRateHz = 50;
cfg.sampleGapThreshold = 0.03;
cfg.gravity = 9.8;
cfg.smoothWindow = 7;

cfg.launchAccelThreshold = 5.0;
cfg.launchPersistenceSamples = 4;
cfg.burnoutAccelThreshold = 1.0;
cfg.burnoutSearchDelay_s = 0.25;
cfg.burnoutPersistenceSamples = 3;
cfg.burnoutVelocityThreshold = 1.0;
cfg.landingVelocityThreshold = 0.5;
cfg.landingAltitudeWindow_m = 1.0;

cfg.kfTs = 1 / 50;
cfg.kSigmaH2 = 5.71e-3;
cfg.kSigmaA2 = 2.73e-3;
cfg.kAlphaG = 0.02;
cfg.kBiasA0 = 0.0;
cfg.kBeta0 = 0.020;
cfg.kSigmaBiasA2 = 1.0e-4;
cfg.kSigmaBeta2 = 1.0e-6;
cfg.kInitialSigmaH = 1.0;
cfg.kInitialSigmaV = 1.0;
cfg.kInitialSigmaBiasA = 0.5;
cfg.kInitialSigmaBeta = 0.02;
cfg.kInitialBiasWindowSamples = 25;
cfg.kBaroNISGate = 16.0;
cfg.kCovarianceFloor = 1.0e-9;
cfg.kUseJosephForm = true;
cfg.kBetaLearningMinVelocity = 3.0;
cfg.kBetaMin = 0.0;
cfg.kBetaMax = 0.08;
cfg.kBiasAMax = 20.0;
cfg.kMaxAccelInput = 60.0;
cfg.enableAttitudeReplay = true;
cfg.useAttitudeVerticalInput = false;
cfg.attitudeInitialGyroBiasWindowSamples = 25;
cfg.attitudeAccelNormTolerance = 1.5;
cfg.attitudeMaxGyroForAccelUpdate = 2.5;
cfg.attitudeKp = 1.5;
cfg.attitudeKi = 0.08;
cfg.attitudeMaxCorrectionRate = 3.0;
cfg.attitudeGyroBiasMax = 0.5;
cfg.attitudeQuatNormFloor = 1.0e-9;
cfg.consistencySigmaThreshold = 3.0;
cfg.consistencyMinSigma = 1e-6;

cfg.gpsPosSigma = 3.0;
cfg.gpsVelSigma = 0.75;
cfg.gpsNISGate = 30.0;
cfg.gpsProcessAccelSigma = 2.5;
cfg.gpsInitialSigmaPos = 10.0;
cfg.gpsInitialSigmaVel = 5.0;
cfg.accelBiasInitialSigma = 0.50;
cfg.accelBiasProcessSigma = 0.03;
cfg.windInitialSigma = 3.0;
cfg.windProcessSigma = 0.20;
cfg.enable3DReplay = true;
cfg.enableGPSFusion = true;
cfg.export3DFigures = true;

cfg.truth = struct();
cfg.truthMetrics = struct();
cfg.consistencyMetrics = struct();
cfg.mission = caelum.irecMissionProfile(TargetApogee_ft=10000);
end
