function T = alignImportedSchema(T, cfg)
%ALIGNIMPORTEDSCHEMA Expand imported schema into full working schema with GPS support.
arguments
    T table
    cfg struct = caelum.defaultConfig()
end

vars = string(T.Properties.VariableNames);

if ~ismember("bmp_T", vars)
    T.bmp_T = nan(height(T), 1);
end

if ~ismember("bmp_P", vars)
    T.bmp_P = nan(height(T), 1);
end

if ~ismember("bmp_alt", vars)
    if ismember("bmp_alt_rel", vars)
        T.bmp_alt = T.bmp_alt_rel;
    else
        T.bmp_alt = nan(height(T), 1);
    end
end

if ~ismember("bmp_alt_rel", vars)
    T.bmp_alt_rel = T.bmp_alt - T.bmp_alt(1);
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
            T.(char(lisSet(k))) = nan(height(T), 1);
        end
    end
end

if ~all(ismember(["g_bx","g_by","g_bz"], vars))
    n = height(T);
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

if ~ismember("a_vertical", vars)
    n = height(T);
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

if ~ismember("kf_h", vars)
    T.kf_h = T.bmp_alt_rel;
end

if ~ismember("kf_v", vars)
    dt = [NaN; diff(T.t_us) * 1e-6];
    T.kf_v = [0; diff(T.bmp_alt_rel) ./ dt(2:end)];
end

if ~ismember("P00", vars), T.P00 = nan(height(T),1); end
if ~ismember("P01", vars), T.P01 = nan(height(T),1); end
if ~ismember("P10", vars), T.P10 = nan(height(T),1); end
if ~ismember("P11", vars), T.P11 = nan(height(T),1); end

gpsSet = ["gps_x","gps_y","gps_z","gps_vx","gps_vy","gps_vz"];
vars = string(T.Properties.VariableNames);
for k = 1:numel(gpsSet)
    if ~ismember(gpsSet(k), vars)
        T.(char(gpsSet(k))) = nan(height(T),1);
    end
end

if ~ismember("gps_speed", vars)
    T.gps_speed = hypot(hypot(T.gps_vx, T.gps_vy), T.gps_vz);
end
end
