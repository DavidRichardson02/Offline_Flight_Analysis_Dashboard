function est = runVerticalEKF(t, a_vertical, z_meas, cfg)
%RUNVERTICALEKF Run the Caelum vertical EKF replay with bias and drag states.

arguments
    t (:,1) double
    a_vertical (:,1) double
    z_meas (:,1) double
    cfg struct = caelum.defaultConfig()
end

cfg = localResolveConfig(cfg);
n = numel(t);

dt_used = zeros(n,1);
h = zeros(n,1);
v = zeros(n,1);
b_a = zeros(n,1);
beta = zeros(n,1);
sigma_h = zeros(n,1);
sigma_v = zeros(n,1);
sigma_b_a = zeros(n,1);
sigma_beta = zeros(n,1);

P00 = zeros(n,1);
P01 = zeros(n,1);
P02 = zeros(n,1);
P03 = zeros(n,1);
P10 = zeros(n,1);
P11 = zeros(n,1);
P12 = zeros(n,1);
P13 = zeros(n,1);
P20 = zeros(n,1);
P21 = zeros(n,1);
P22 = zeros(n,1);
P23 = zeros(n,1);
P30 = zeros(n,1);
P31 = zeros(n,1);
P32 = zeros(n,1);
P33 = zeros(n,1);

innovation_h = nan(n,1);
innovation_sigma_h = nan(n,1);
innovation_z_h = nan(n,1);
innovation_nis = nan(n,1);
baro_used = false(n,1);
baro_rejected = false(n,1);
accel_input = nan(n,1);
accel_effective = nan(n,1);
drag_accel = nan(n,1);
beta_learning_enabled = false(n,1);

[x, P] = caelum.initializeVerticalEKFState(t, a_vertical, z_meas, cfg);

for k = 1:n
    dtk = 0.0;
    if k > 1
        rawDt = t(k) - t(k-1);
        if isfinite(rawDt) && rawDt > 0
            dtk = rawDt;
        else
            dtk = cfg.kfTs;
        end
    end
    dt_used(k) = dtk;

    [xPred, PPred, predictInfo] = caelum.predictVerticalEKF(x, P, a_vertical(k), dtk, cfg);
    [x, P, updateInfo] = caelum.updateVerticalEKFBaro(xPred, PPred, z_meas(k), cfg);

    h(k) = x(1);
    v(k) = x(2);
    b_a(k) = x(3);
    beta(k) = x(4);

    sigma_h(k) = sqrt(max(P(1,1), 0));
    sigma_v(k) = sqrt(max(P(2,2), 0));
    sigma_b_a(k) = sqrt(max(P(3,3), 0));
    sigma_beta(k) = sqrt(max(P(4,4), 0));

    P00(k) = P(1,1);
    P01(k) = P(1,2);
    P02(k) = P(1,3);
    P03(k) = P(1,4);
    P10(k) = P(2,1);
    P11(k) = P(2,2);
    P12(k) = P(2,3);
    P13(k) = P(2,4);
    P20(k) = P(3,1);
    P21(k) = P(3,2);
    P22(k) = P(3,3);
    P23(k) = P(3,4);
    P30(k) = P(4,1);
    P31(k) = P(4,2);
    P32(k) = P(4,3);
    P33(k) = P(4,4);

    innovation_h(k) = updateInfo.innovation_h;
    innovation_sigma_h(k) = updateInfo.innovation_sigma_h;
    innovation_z_h(k) = updateInfo.innovation_z_h;
    innovation_nis(k) = updateInfo.innovation_nis;
    baro_used(k) = updateInfo.baro_used;
    baro_rejected(k) = updateInfo.baro_rejected;

    accel_input(k) = predictInfo.accel_input;
    accel_effective(k) = predictInfo.accel_effective;
    drag_accel(k) = predictInfo.drag_accel;
    beta_learning_enabled(k) = predictInfo.beta_learning_enabled;
end

est = table( ...
    t, dt_used, h, v, b_a, beta, ...
    sigma_h, sigma_v, sigma_b_a, sigma_beta, ...
    P00, P01, P02, P03, P10, P11, P12, P13, P20, P21, P22, P23, P30, P31, P32, P33, ...
    innovation_h, innovation_sigma_h, innovation_z_h, innovation_nis, ...
    baro_used, baro_rejected, accel_input, accel_effective, drag_accel, beta_learning_enabled, ...
    'VariableNames', { ...
    't','dt_used','h','v','b_a','beta', ...
    'sigma_h','sigma_v','sigma_b_a','sigma_beta', ...
    'P00','P01','P02','P03','P10','P11','P12','P13','P20','P21','P22','P23','P30','P31','P32','P33', ...
    'innovation_h','innovation_sigma_h','innovation_z_h','innovation_nis', ...
    'baro_used','baro_rejected','accel_input','accel_effective','drag_accel','beta_learning_enabled'});
end

function cfg = localResolveConfig(cfg)
defaults = caelum.defaultConfig();
names = fieldnames(defaults);
for k = 1:numel(names)
    name = names{k};
    if ~isfield(cfg, name) || isempty(cfg.(name))
        cfg.(name) = defaults.(name);
    end
end
end
