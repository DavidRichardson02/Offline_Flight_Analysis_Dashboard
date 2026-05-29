function est = run3DEKF(T, cfg)
%RUN3DEKF 3D inertial/GPS EKF with wind estimation.
arguments
    T table
    cfg struct = caelum.defaultConfig()
end
cfg = caelum.localResolve3DConfig(cfg);
n = height(T);
[x, P] = caelum.initialize3DEKFState(T, cfg);

xHist = nan(n, 12);
sigmaHist = nan(n, 12);
gps_used = false(n,1);
gps_rejected = false(n,1);
innovation_pos_norm = nan(n,1);
innovation_vel_norm = nan(n,1);

for k = 1:n
    if k == 1
        dt = 0;
    else
        dt = T.t(k) - T.t(k-1);
        if ~isfinite(dt) || dt <= 0
            dt = cfg.kfTs;
        end
    end
    accelBody = [T.ax(k); T.ay(k); T.az(k)];
    q = caelum.localExtractQuaternion(T, k);
    [xPred, PPred] = caelum.predict3DEKF(x, P, accelBody, q, dt, cfg);
    meas = caelum.localExtractGPSMeasurement(T, k);
    [x, P, info] = caelum.update3DEKFGPS(xPred, PPred, meas, cfg);

    xHist(k,:) = x.';
    sigmaHist(k,:) = sqrt(max(diag(P), 0)).';
    gps_used(k) = info.gps_used;
    gps_rejected(k) = info.gps_rejected;
    innovation_pos_norm(k) = info.innovation_pos_norm;
    innovation_vel_norm(k) = info.innovation_vel_norm;
end

est = table( ...
    T.t, ...
    xHist(:,1), xHist(:,2), xHist(:,3), ...
    xHist(:,4), xHist(:,5), xHist(:,6), ...
    xHist(:,7), xHist(:,8), xHist(:,9), ...
    xHist(:,10), xHist(:,11), xHist(:,12), ...
    sigmaHist(:,1), sigmaHist(:,2), sigmaHist(:,3), ...
    sigmaHist(:,4), sigmaHist(:,5), sigmaHist(:,6), ...
    sigmaHist(:,7), sigmaHist(:,8), sigmaHist(:,9), ...
    sigmaHist(:,10), sigmaHist(:,11), sigmaHist(:,12), ...
    gps_used, gps_rejected, innovation_pos_norm, innovation_vel_norm, ...
    'VariableNames', { ...
    't', ...
    'px','py','pz','vx','vy','vz','bax','bay','baz','wx','wy','wz', ...
    'sigma_px','sigma_py','sigma_pz','sigma_vx','sigma_vy','sigma_vz', ...
    'sigma_bax','sigma_bay','sigma_baz','sigma_wx','sigma_wy','sigma_wz', ...
    'gps_used','gps_rejected','innovation_pos_norm','innovation_vel_norm'});
end
