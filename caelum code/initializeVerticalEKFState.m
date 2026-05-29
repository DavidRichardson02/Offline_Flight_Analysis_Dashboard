function [x0, P0, initInfo] = initializeVerticalEKFState(t, a_vertical, z_meas, cfg)
%INITIALIZEVERTICALEKFSTATE Initialize the vertical EKF state and covariance.

arguments
    t (:,1) double
    a_vertical (:,1) double
    z_meas (:,1) double
    cfg struct = caelum.defaultConfig()
end

n = max([numel(t), numel(a_vertical), numel(z_meas)]);

h0 = 0.0;
zIdx = find(isfinite(z_meas), 1, 'first');
if ~isempty(zIdx)
    h0 = z_meas(zIdx);
end

v0 = 0.0;
b_a0 = cfg.kBiasA0;

if n > 0
    biasWindow = min(n, max(1, round(cfg.kInitialBiasWindowSamples)));
    biasSlice = a_vertical(1:biasWindow);
    biasSlice = biasSlice(isfinite(biasSlice));
    if ~isempty(biasSlice)
        b_a0 = median(biasSlice, 'omitnan');
    end
end

b_a0 = min(max(b_a0, -cfg.kBiasAMax), cfg.kBiasAMax);
beta0 = min(max(cfg.kBeta0, cfg.kBetaMin), cfg.kBetaMax);

x0 = [h0; v0; b_a0; beta0];
P0 = diag([ ...
    cfg.kInitialSigmaH^2, ...
    cfg.kInitialSigmaV^2, ...
    cfg.kInitialSigmaBiasA^2, ...
    cfg.kInitialSigmaBeta^2]);

initInfo = struct();
initInfo.h0 = h0;
initInfo.v0 = v0;
initInfo.b_a0 = b_a0;
initInfo.beta0 = beta0;
initInfo.biasSamplesUsed = min(n, max(1, round(cfg.kInitialBiasWindowSamples)));
end
