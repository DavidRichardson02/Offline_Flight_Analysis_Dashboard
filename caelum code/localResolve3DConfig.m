function cfg = localResolve3DConfig(cfg)
%LOCALRESOLVE3DCONFIG Fill defaults needed by the 3D/GPS/wind pipeline.
defaults = struct();
defaults.gpsPosSigma = 3.0;
defaults.gpsVelSigma = 0.75;
defaults.gpsNISGate = 30.0;
defaults.gpsProcessAccelSigma = 2.5;
defaults.gpsInitialSigmaPos = 10.0;
defaults.gpsInitialSigmaVel = 5.0;
defaults.accelBiasInitialSigma = 0.50;
defaults.accelBiasProcessSigma = 0.03;
defaults.windInitialSigma = 3.0;
defaults.windProcessSigma = 0.20;
defaults.enable3DReplay = true;
defaults.enableGPSFusion = true;
defaults.export3DFigures = true;

base = caelum.defaultConfig();
baseNames = fieldnames(base);
for k = 1:numel(baseNames)
    name = baseNames{k};
    if ~isfield(cfg, name) || isempty(cfg.(name))
        cfg.(name) = base.(name);
    end
end

names = fieldnames(defaults);
for k = 1:numel(names)
    name = names{k};
    if ~isfield(cfg, name) || isempty(cfg.(name))
        cfg.(name) = defaults.(name);
    end
end
end
