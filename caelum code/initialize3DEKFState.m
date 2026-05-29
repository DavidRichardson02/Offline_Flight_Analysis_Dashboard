function [x0, P0] = initialize3DEKFState(T, cfg)
%INITIALIZE3DEKFSTATE Initialize 3D EKF state and covariance.
arguments
    T table
    cfg struct = caelum.defaultConfig()
end
cfg = caelum.localResolve3DConfig(cfg);
x0 = zeros(12,1);

if ismember("gps_x", string(T.Properties.VariableNames))
    idx = find(isfinite(T.gps_x) & isfinite(T.gps_y) & isfinite(T.gps_z), 1, 'first');
    if ~isempty(idx)
        x0(1:3) = [T.gps_x(idx); T.gps_y(idx); T.gps_z(idx)];
    end
end

if ismember("gps_vx", string(T.Properties.VariableNames))
    idx = find(isfinite(T.gps_vx) & isfinite(T.gps_vy) & isfinite(T.gps_vz), 1, 'first');
    if ~isempty(idx)
        x0(4:6) = [T.gps_vx(idx); T.gps_vy(idx); T.gps_vz(idx)];
    end
end

P0 = diag([ ...
    cfg.gpsInitialSigmaPos^2 * ones(1,3), ...
    cfg.gpsInitialSigmaVel^2 * ones(1,3), ...
    cfg.accelBiasInitialSigma^2 * ones(1,3), ...
    cfg.windInitialSigma^2 * ones(1,3)]);
end
