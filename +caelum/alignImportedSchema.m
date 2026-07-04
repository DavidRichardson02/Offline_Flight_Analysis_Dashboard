function T = alignImportedSchema(T, cfg)
%ALIGNIMPORTEDSCHEMA Expand imported schema into the dashboard working schema.
%
% The offline dashboard predates the current Teensy SD logger and expects a
% canonical analysis surface with fields such as kf_h, kf_v, q_w, and
% bmp_alt_rel.  The firmware source of truth now publishes estimator and
% attitude values as est_h/est_v/est_a and q0/q1/q2/q3.  This function is the
% compatibility boundary: it preserves older synthetic and Monte Carlo logs
% while making the latest firmware fields first-class inputs for analysis.
arguments
    T table
    cfg struct = caelum.defaultConfig()
end

vars = string(T.Properties.VariableNames);
n = height(T);

T = localApplyFirmwareMetadataAliases(T);
vars = string(T.Properties.VariableNames);

if ismember("est_h", vars) && ~ismember("kf_h", vars)
    T.kf_h = T.est_h;
end

if ismember("est_v", vars) && ~ismember("kf_v", vars)
    T.kf_v = T.est_v;
end

if ismember("est_a", vars) && ~ismember("kf_a", vars)
    T.kf_a = T.est_a;
end

if all(ismember(["q0","q1","q2","q3"], vars))
    if ~ismember("q_w", vars), T.q_w = T.q0; end
    if ~ismember("q_x", vars), T.q_x = T.q1; end
    if ~ismember("q_y", vars), T.q_y = T.q2; end
    if ~ismember("q_z", vars), T.q_z = T.q3; end
end

vars = string(T.Properties.VariableNames);

if all(ismember(["q_w","q_x","q_y","q_z"], vars))
    if ~ismember("q0", vars), T.q0 = T.q_w; end
    if ~ismember("q1", vars), T.q1 = T.q_x; end
    if ~ismember("q2", vars), T.q2 = T.q_y; end
    if ~ismember("q3", vars), T.q3 = T.q_z; end
end

vars = string(T.Properties.VariableNames);

if ~ismember("bmp_T", vars)
    T.bmp_T = nan(n, 1);
end

if ~ismember("bmp_P", vars)
    T.bmp_P = nan(n, 1);
end

if ~ismember("bmp_alt", vars)
    if ismember("bmp_alt_rel", vars)
        T.bmp_alt = T.bmp_alt_rel;
    else
        T.bmp_alt = nan(n, 1);
    end
end

vars = string(T.Properties.VariableNames);

if ~ismember("bmp_alt_rel", vars)
    baseline = localFirstFinite(T.bmp_alt);
    if isfinite(baseline)
        T.bmp_alt_rel = T.bmp_alt - baseline;
    else
        T.bmp_alt_rel = nan(n, 1);
    end
end

vars = string(T.Properties.VariableNames);

lisSet = ["lis_ax","lis_ay","lis_az"];
imuFallback = ["ax","ay","az"];
for k = 1:numel(lisSet)
    if ~ismember(lisSet(k), vars)
        fallback = imuFallback(k);
        if ismember(fallback, vars)
            T.(char(lisSet(k))) = T.(char(fallback));
        else
            T.(char(lisSet(k))) = nan(n, 1);
        end
    end
end

vars = string(T.Properties.VariableNames);

if ~all(ismember(["g_bx","g_by","g_bz"], vars))
    g_bx = zeros(n,1);
    g_by = zeros(n,1);
    g_bz = cfg.gravity * ones(n,1);

    alpha = cfg.kAlphaG;
    for k = 2:n
        aNorm = hypot(hypot(T.ax(k), T.ay(k)), T.az(k));
        if isfinite(aNorm) && abs(aNorm - cfg.gravity) < 3
            g_bx(k) = (1-alpha)*g_bx(k-1) + alpha*T.ax(k);
            g_by(k) = (1-alpha)*g_by(k-1) + alpha*T.ay(k);
            g_bz(k) = (1-alpha)*g_bz(k-1) + alpha*T.az(k);

            gn = hypot(hypot(g_bx(k), g_by(k)), g_bz(k));
            if gn > 1e-9
                scale = cfg.gravity / gn;
                g_bx(k) = g_bx(k) * scale;
                g_by(k) = g_by(k) * scale;
                g_bz(k) = g_bz(k) * scale;
            end
        else
            g_bx(k) = g_bx(k-1);
            g_by(k) = g_by(k-1);
            g_bz(k) = g_bz(k-1);
        end
    end

    T.g_bx = g_bx;
    T.g_by = g_by;
    T.g_bz = g_bz;
end

vars = string(T.Properties.VariableNames);

if ~ismember("a_vertical", vars)
    if ismember("est_a", vars)
        T.a_vertical = T.est_a;
    else
        a_vertical = nan(n,1);
        for k = 1:n
            gn = hypot(hypot(T.g_bx(k), T.g_by(k)), T.g_bz(k));
            if gn > 1e-9
                zux = T.g_bx(k) / gn;
                zuy = T.g_by(k) / gn;
                zuz = T.g_bz(k) / gn;
                a_up_meas = T.ax(k) * zux + T.ay(k) * zuy + T.az(k) * zuz;
                a_vertical(k) = a_up_meas - cfg.gravity;
            end
        end
        T.a_vertical = a_vertical;
    end
end

vars = string(T.Properties.VariableNames);

if ~ismember("kf_h", vars)
    T.kf_h = T.bmp_alt_rel;
end

vars = string(T.Properties.VariableNames);

if ~ismember("kf_v", vars)
    dt = [NaN; diff(T.t_us) * 1e-6];
    kf_v = nan(n, 1);
    if n >= 1
        kf_v(1) = 0;
    end
    if n >= 2
        validDt = dt(2:end) > 0;
        kf_v(2:end) = diff(T.bmp_alt_rel) ./ dt(2:end);
        kf_v([false; ~validDt]) = NaN;
    end
    T.kf_v = kf_v;
end

vars = string(T.Properties.VariableNames);

if ~ismember("P00", vars), T.P00 = nan(n,1); end
if ~ismember("P01", vars), T.P01 = nan(n,1); end
if ~ismember("P10", vars), T.P10 = nan(n,1); end
if ~ismember("P11", vars), T.P11 = nan(n,1); end

gpsSet = ["gps_x","gps_y","gps_z","gps_vx","gps_vy","gps_vz"];
vars = string(T.Properties.VariableNames);
for k = 1:numel(gpsSet)
    if ~ismember(gpsSet(k), vars)
        T.(char(gpsSet(k))) = nan(n,1);
    end
end

vars = string(T.Properties.VariableNames);

if ~ismember("gps_speed", vars)
    T.gps_speed = hypot(hypot(T.gps_vx, T.gps_vy), T.gps_vz);
end
end

function value = localFirstFinite(x)
idx = find(isfinite(x), 1, 'first');
if isempty(idx)
    value = NaN;
else
    value = x(idx);
end
end

function T = localApplyFirmwareMetadataAliases(T)
% Normalize abbreviated Serial HDR metadata to the SD/dashboard field names.
aliases = [ ...
    "baro_upd", "baro_updated"; ...
    "imu_upd", "imu_updated"; ...
    "aux_upd", "aux_updated"; ...
    "att_upd", "att_updated"; ...
    "auxvz_upd", "auxvz_updated"; ...
    "est_upd", "est_updated"];

vars = string(T.Properties.VariableNames);
for k = 1:size(aliases, 1)
    sourceName = aliases(k, 1);
    targetName = aliases(k, 2);
    if ismember(sourceName, vars) && ~ismember(targetName, vars)
        T.(char(targetName)) = T.(char(sourceName));
        vars = string(T.Properties.VariableNames);
    end
end
end
