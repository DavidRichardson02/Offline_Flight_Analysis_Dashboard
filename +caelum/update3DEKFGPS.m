function [xUpd, PUpd, info] = update3DEKFGPS(xPred, PPred, meas, cfg)
%UPDATE3DEKFGPS Update 3D state using GPS position and ground velocity.
arguments
    xPred (12,1) double
    PPred (12,12) double
    meas struct
    cfg struct = caelum.defaultConfig()
end
cfg = caelum.localResolve3DConfig(cfg);

xUpd = xPred;
PUpd = PPred;

info = struct();
info.gps_used = false;
info.gps_rejected = false;
info.innovation_pos_norm = NaN;
info.innovation_vel_norm = NaN;

z = []; h = []; H = []; R = [];
hasPos = all(isfinite([meas.gps_x meas.gps_y meas.gps_z]));
hasVel = all(isfinite([meas.gps_vx meas.gps_vy meas.gps_vz]));

if hasPos
    z = [z; meas.gps_x; meas.gps_y; meas.gps_z];
    h = [h; xPred(1:3)];
    H = [H; [eye(3), zeros(3,9)]];
    R = blkdiag(R, cfg.gpsPosSigma^2 * eye(3));
end

if hasVel
    z = [z; meas.gps_vx; meas.gps_vy; meas.gps_vz];
    h = [h; xPred(4:6) + xPred(10:12)];
    H = [H; [zeros(3,3), eye(3), zeros(3,3), eye(3)]];
    R = blkdiag(R, cfg.gpsVelSigma^2 * eye(3));
end

if isempty(z)
    return;
end

innovation = z - h;
S = H * PPred * H.' + R;
S = 0.5 * (S + S.');
if any(~isfinite(S(:))) || rcond(S) < 1e-12
    info.gps_rejected = true;
    return;
end

nis = innovation.' * (S \ innovation);
if isfinite(cfg.gpsNISGate) && nis > cfg.gpsNISGate
    info.gps_rejected = true;
    return;
end

K = PPred * H.' / S;
xUpd = xPred + K * innovation;
I = eye(size(PPred));
PUpd = (I - K * H) * PPred * (I - K * H).' + K * R * K.';
PUpd = 0.5 * (PUpd + PUpd.');
PUpd(1:13:end) = max(diag(PUpd), cfg.kCovarianceFloor);

if hasPos
    info.innovation_pos_norm = norm(innovation(1:3));
end
if hasVel
    info.innovation_vel_norm = norm(innovation(end-2:end));
end
info.gps_used = true;
end
