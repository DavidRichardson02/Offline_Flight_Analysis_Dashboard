function [xUpd, PUpd, updateInfo] = updateVerticalEKFBaro(xPred, PPred, z_meas, cfg)
%UPDATEVERTICALEKFBARO Apply the barometric altitude update to the vertical EKF.

arguments
    xPred (4,1) double
    PPred (4,4) double
    z_meas (1,1) double
    cfg struct = caelum.defaultConfig()
end

xUpd = xPred;
PUpd = localRegularizeCovariance(PPred, cfg.kCovarianceFloor);

updateInfo = struct();
updateInfo.innovation_h = NaN;
updateInfo.innovation_sigma_h = NaN;
updateInfo.innovation_z_h = NaN;
updateInfo.innovation_nis = NaN;
updateInfo.baro_used = false;
updateInfo.baro_rejected = false;
updateInfo.baro_gate_threshold = cfg.kBaroNISGate;

if ~isfinite(z_meas)
    return;
end

H = [1 0 0 0];
R = cfg.kSigmaH2;

innovation = z_meas - xPred(1);
S = PPred(1,1) + R;

updateInfo.innovation_h = innovation;
if ~isfinite(S) || S <= cfg.kCovarianceFloor
    updateInfo.baro_rejected = true;
    return;
end

innovationSigma = sqrt(S);
innovationZ = innovation / innovationSigma;
innovationNis = innovationZ^2;

updateInfo.innovation_sigma_h = innovationSigma;
updateInfo.innovation_z_h = innovationZ;
updateInfo.innovation_nis = innovationNis;

if isfinite(cfg.kBaroNISGate) && innovationNis > cfg.kBaroNISGate
    updateInfo.baro_rejected = true;
    return;
end

K = PPred(:,1) / S;
xUpd = xPred + K * innovation;

if cfg.kUseJosephForm
    I = eye(4);
    KH = K * H;
    PUpd = (I - KH) * PPred * (I - KH).' + K * R * K.';
else
    PUpd = PPred - K * H * PPred;
end

xUpd(3) = min(max(xUpd(3), -cfg.kBiasAMax), cfg.kBiasAMax);
xUpd(4) = min(max(xUpd(4), cfg.kBetaMin), cfg.kBetaMax);
PUpd = localRegularizeCovariance(PUpd, cfg.kCovarianceFloor);

updateInfo.baro_used = true;
end

function P = localRegularizeCovariance(P, floorValue)
P = 0.5 * (P + P.');
diagP = diag(P);
diagP = max(diagP, floorValue);
P(1:5:end) = diagP;
end
