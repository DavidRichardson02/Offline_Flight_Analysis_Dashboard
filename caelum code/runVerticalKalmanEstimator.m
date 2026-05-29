function est = runVerticalKalmanEstimator(t, a_vertical, z_meas, cfg)
%RUNVERTICALKALMANESTIMATOR Backward-compatible wrapper for the vertical EKF.

arguments
    t (:,1) double
    a_vertical (:,1) double
    z_meas (:,1) double
    cfg struct = caelum.defaultConfig()
end

est = caelum.runVerticalEKF(t, a_vertical, z_meas, cfg);
end
