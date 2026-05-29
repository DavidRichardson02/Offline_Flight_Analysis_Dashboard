function attitude = runAttitudeReplay(T, cfg)
%RUNATTITUDEREPLAY Quaternion-based attitude replay with gravity correction and gyro-bias adaptation.
%
% Additional outputs for Phase 1:
%   - g_bx_att, g_by_att, g_bz_att : gravity estimate in body frame [m/s^2]
%   - a_vertical_attitude          : attitude-derived vertical acceleration
%
% These fields are intended to be logged and consumed downstream without
% recomputation.

arguments
    T table
    cfg struct = caelum.defaultConfig()
end

n = height(T);

dt_used = zeros(n,1);
q_w = zeros(n,1);
q_x = zeros(n,1);
q_y = zeros(n,1);
q_z = zeros(n,1);
roll_deg = zeros(n,1);
pitch_deg = zeros(n,1);
yaw_deg = zeros(n,1);
b_gx = zeros(n,1);
b_gy = zeros(n,1);
b_gz = zeros(n,1);

g_bx_att = zeros(n,1);
g_by_att = zeros(n,1);
g_bz_att = zeros(n,1);

a_vertical_attitude = nan(n,1);
accel_norm = nan(n,1);
gyro_norm = nan(n,1);
gravity_update_used = false(n,1);
gravity_innovation = nan(n,1);
gravity_residual = nan(n,1);
tilt_error_deg = nan(n,1);

q = [1; 0; 0; 0];
biasWindow = min(n, max(1, round(cfg.attitudeInitialGyroBiasWindowSamples)));
gyroBias0 = [0; 0; 0];
if biasWindow > 0
    gyroSlice = [T.gx(1:biasWindow), T.gy(1:biasWindow), T.gz(1:biasWindow)];
    validRows = all(isfinite(gyroSlice), 2);
    if any(validRows)
        gyroBias0 = mean(gyroSlice(validRows, :), 1, 'omitnan').';
    end
end
b_g = gyroBias0;

for k = 1:n
    dtk = cfg.kfTs;
    if k > 1
        rawDt = T.t(k) - T.t(k-1);
        if isfinite(rawDt) && rawDt > 0
            dtk = rawDt;
        end
    else
        dtk = 0;
    end
    dt_used(k) = dtk;

    accelMeas = [T.ax(k); T.ay(k); T.az(k)];
    gyroMeas = [T.gx(k); T.gy(k); T.gz(k)];
    accelNormK = norm(accelMeas);
    gyroNormK = norm(gyroMeas);

    if isfinite(accelNormK)
        accel_norm(k) = accelNormK;
        gravity_residual(k) = accelNormK - cfg.gravity;
    end
    if isfinite(gyroNormK)
        gyro_norm(k) = gyroNormK;
    end

    omegaBody = zeros(3,1);
    if all(isfinite(gyroMeas))
        omegaBody = gyroMeas - b_g;
    end

    qPred = caelum.propagateQuaternion(q, omegaBody, dtk);
    ghatPred = caelum.gravityBodyFromQuaternion(qPred);
    corr = zeros(3,1);

    canUseGravity = all(isfinite(accelMeas)) && ...
        isfinite(accelNormK) && accelNormK > cfg.attitudeQuatNormFloor && ...
        abs(accelNormK - cfg.gravity) <= cfg.attitudeAccelNormTolerance && ...
        (~isfinite(gyroNormK) || gyroNormK <= cfg.attitudeMaxGyroForAccelUpdate);

    if canUseGravity
        aUnit = accelMeas / accelNormK;
        innovationVec = cross(aUnit, ghatPred);
        innovationNorm = norm(innovationVec);
        gravity_innovation(k) = innovationNorm;
        tilt_error_deg(k) = rad2deg(acos(min(max(dot(aUnit, ghatPred), -1), 1)));
        gravity_update_used(k) = true;

        corr = cfg.attitudeKp * innovationVec;
        corrNorm = norm(corr);
        if corrNorm > cfg.attitudeMaxCorrectionRate
            corr = corr * (cfg.attitudeMaxCorrectionRate / corrNorm);
        end

        b_g = b_g - cfg.attitudeKi * innovationVec * dtk;
        b_g = min(max(b_g, -cfg.attitudeGyroBiasMax), cfg.attitudeGyroBiasMax);
    end

    q = caelum.propagateQuaternion(q, omegaBody + corr, dtk);
    q = caelum.normalizeQuaternion(q, cfg.attitudeQuatNormFloor);
    ghat = caelum.gravityBodyFromQuaternion(q);

    q_w(k) = q(1);
    q_x(k) = q(2);
    q_y(k) = q(3);
    q_z(k) = q(4);
    [roll_deg(k), pitch_deg(k), yaw_deg(k)] = caelum.quaternionToEulerZYX(q);

    b_gx(k) = b_g(1);
    b_gy(k) = b_g(2);
    b_gz(k) = b_g(3);

    g_bx_att(k) = ghat(1) * cfg.gravity;
    g_by_att(k) = ghat(2) * cfg.gravity;
    g_bz_att(k) = ghat(3) * cfg.gravity;

    if all(isfinite(accelMeas))
        aNav = caelum.quaternionToRotationMatrix(q) * accelMeas;
        a_vertical_attitude(k) = aNav(3) - cfg.gravity;
    end
end

attitude = table( ...
    T.t, dt_used, ...
    q_w, q_x, q_y, q_z, ...
    roll_deg, pitch_deg, yaw_deg, ...
    b_gx, b_gy, b_gz, ...
    g_bx_att, g_by_att, g_bz_att, ...
    a_vertical_attitude, accel_norm, gyro_norm, ...
    gravity_update_used, gravity_innovation, gravity_residual, tilt_error_deg, ...
    'VariableNames', { ...
    't','dt_used', ...
    'q_w','q_x','q_y','q_z', ...
    'roll_deg','pitch_deg','yaw_deg', ...
    'b_gx','b_gy','b_gz', ...
    'g_bx_att','g_by_att','g_bz_att', ...
    'a_vertical_attitude','accel_norm','gyro_norm', ...
    'gravity_update_used','gravity_innovation','gravity_residual','tilt_error_deg'});
end
