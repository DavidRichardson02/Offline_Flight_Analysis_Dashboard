function est = runFirmwareVerticalEstimator(T, cfg)
%RUNFIRMWAREVERTICALESTIMATOR Replicate the firmware SD logger / live vertical estimator.
arguments
    T table
    cfg struct = caelum.defaultConfig()
end

vars = string(T.Properties.VariableNames);
required = ["ax","ay","az","bmp_alt_rel"];
missing = setdiff(required, vars);
if ~isempty(missing)
    error('caelum:runFirmwareVerticalEstimator:MissingColumns', ...
        'Missing columns required for firmware replay: %s', strjoin(cellstr(missing), ', '));
end

n = height(T);
t = localTimeVector(T, cfg);

g_bx = zeros(n, 1);
g_by = zeros(n, 1);
g_bz = zeros(n, 1);
a_vertical = nan(n, 1);
h = zeros(n, 1);
v = zeros(n, 1);
P00 = zeros(n, 1);
P01 = zeros(n, 1);
P10 = zeros(n, 1);
P11 = zeros(n, 1);
sigma_h = zeros(n, 1);
sigma_v = zeros(n, 1);
innovation_h = nan(n, 1);
baro_used = false(n, 1);
accel_used = false(n, 1);

gState = [0; 0; -cfg.gravity];
hState = 0.0;
vState = 0.0;
PState = [1.0 0.0; 0.0 1.0];

q00 = cfg.kSigmaA2 * (cfg.kfTs^4 / 4.0);
q01 = cfg.kSigmaA2 * (cfg.kfTs^3 / 2.0);
q10 = q01;
q11 = cfg.kSigmaA2 * (cfg.kfTs^2);
rBaro = cfg.kSigmaH2;

for k = 1:n
    ax = T.ax(k);
    ay = T.ay(k);
    az = T.az(k);
    accelValid = all(isfinite([ax, ay, az]));
    zMeas = T.bmp_alt_rel(k);
    baroValid = isfinite(zMeas);

    if accelValid
        aMag = sqrt(ax * ax + ay * ay + az * az);
        if abs(aMag - cfg.gravity) < 3.0
            gState(1) = (1.0 - cfg.kAlphaG) * gState(1) + cfg.kAlphaG * ax;
            gState(2) = (1.0 - cfg.kAlphaG) * gState(2) + cfg.kAlphaG * ay;
            gState(3) = (1.0 - cfg.kAlphaG) * gState(3) + cfg.kAlphaG * az;

            normG = norm(gState);
            if normG > 1.0e-6
                gState = gState * (cfg.gravity / normG);
            end
        end

        normG = norm(gState);
        if normG > 1.0e-6
            zDir = gState / normG;
            aDownMeas = ax * zDir(1) + ay * zDir(2) + az * zDir(3);
            aDownLinear = aDownMeas - cfg.gravity;
            a_vertical(k) = -aDownLinear;
            accelUsed(k) = true;

            hPred = hState + vState * cfg.kfTs + 0.5 * a_vertical(k) * cfg.kfTs * cfg.kfTs;
            vPred = vState + a_vertical(k) * cfg.kfTs;

            p00 = PState(1,1) + cfg.kfTs * (PState(2,1) + PState(1,2)) + cfg.kfTs * cfg.kfTs * PState(2,2) + q00;
            p01 = PState(1,2) + cfg.kfTs * PState(2,2) + q01;
            p10 = PState(2,1) + cfg.kfTs * PState(2,2) + q10;
            p11 = PState(2,2) + q11;

            hState = hPred;
            vState = vPred;
            PState = [p00 p01; p10 p11];
        end
    end

    if baroValid
        s = PState(1,1) + rBaro;
        if s > 1.0e-9
            k0 = PState(1,1) / s;
            k1 = PState(2,1) / s;
            innov = zMeas - hState;

            p00Old = PState(1,1);
            p01Old = PState(1,2);
            p10Old = PState(2,1);
            p11Old = PState(2,2);

            hState = hState + k0 * innov;
            vState = vState + k1 * innov;
            PState(1,1) = (1.0 - k0) * p00Old;
            PState(1,2) = (1.0 - k0) * p01Old;
            PState(2,1) = p10Old - k1 * p00Old;
            PState(2,2) = p11Old - k1 * p01Old;

            innovation_h(k) = innov;
            baro_used(k) = true;
        end
    end

    g_bx(k) = gState(1);
    g_by(k) = gState(2);
    g_bz(k) = gState(3);
    h(k) = hState;
    v(k) = vState;
    P00(k) = PState(1,1);
    P01(k) = PState(1,2);
    P10(k) = PState(2,1);
    P11(k) = PState(2,2);
    sigma_h(k) = sqrt(max(PState(1,1), 0));
    sigma_v(k) = sqrt(max(PState(2,2), 0));
end

est = table( ...
    t, g_bx, g_by, g_bz, a_vertical, h, v, P00, P01, P10, P11, ...
    sigma_h, sigma_v, innovation_h, baro_used, accel_used, ...
    'VariableNames', {'t','g_bx','g_by','g_bz','a_vertical','h','v','P00','P01','P10','P11', ...
    'sigma_h','sigma_v','innovation_h','baro_used','accel_used'});
end

function t = localTimeVector(T, cfg)
if ismember("t", string(T.Properties.VariableNames))
    t = T.t;
elseif ismember("t_us", string(T.Properties.VariableNames))
    t = double(T.t_us - T.t_us(1)) * 1e-6;
else
    t = (0:height(T)-1).' * cfg.kfTs;
end
end
