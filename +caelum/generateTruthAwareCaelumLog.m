function [T, truth] = generateTruthAwareCaelumLog(filename, opts)
%GENERATETRUTHAWARECAELUMLOG Generate a physically consistent Caelum SD log.

arguments
    filename (1,1) string = "LOG_TRUTH_AWARE.CSV"
    opts.fs (1,1) double = 50
    opts.duration_s (1,1) double = 14
    opts.seaLevelPressurePa (1,1) double = 101325
    opts.temperatureC (1,1) double = 20
    opts.gravity (1,1) double = 9.8
    opts.seed (1,1) double = 42

    opts.launchDelay_s (1,1) double = 1.0
    opts.boostDuration_s (1,1) double = 1.2
    opts.tailoffDuration_s (1,1) double = 0.8
    opts.boostAccel_mps2 (1,1) double = 19.0
    opts.tailoffStartAccel_mps2 (1,1) double = 10.0
    opts.dragCoeff (1,1) double = 0.020
    opts.landClampVelocity_mps (1,1) double = 0.5

    opts.baroAltNoise_m (1,1) double = 0.20
    opts.baroTempNoise_C (1,1) double = 0.03
    opts.accelNoise_mps2 (1,1) double = 0.12
    opts.gyroNoise_rps (1,1) double = 0.015
    opts.lisNoise_mps2 (1,1) double = 0.18
    opts.accelBiasXYZ (1,3) double = [0.03 -0.02 0.04]
    opts.gyroBiasXYZ (1,3) double = [0.002 -0.001 0.0015]
    opts.lisBiasXYZ (1,3) double = [0.05 -0.03 0.06]

    opts.addTimingJitter (1,1) logical = false
    opts.timingJitterStd_s (1,1) double = 0.0015
    opts.addNaNs (1,1) logical = false
    opts.nanFraction (1,1) double = 0.01
    opts.addDropouts (1,1) logical = false
    opts.dropoutFraction (1,1) double = 0.02
    opts.addDuplicateTimestamps (1,1) logical = false
    opts.duplicateFraction (1,1) double = 0.005

    opts.kSigmaH2 (1,1) double = 5.71e-3
    opts.kSigmaA2 (1,1) double = 2.73e-3
    opts.kAlphaG (1,1) double = 0.02
end

rng(opts.seed);

dtNom = 1 / opts.fs;
N = floor(opts.duration_s * opts.fs);
t = (0:N-1)' * dtNom;

if opts.addTimingJitter
    t = t + opts.timingJitterStd_s * randn(size(t));
    t = max(t, 0);
    t = cummax(t);
end

t_us = uint64(round(t * 1e6));

h_true = zeros(N,1);
v_true = zeros(N,1);
a_true = zeros(N,1);
thrust_accel = zeros(N,1);
drag_accel = zeros(N,1);
landed = false;

for k = 2:N
    tk = t(k);

    if landed
        a_true(k) = 0;
        v_true(k) = 0;
        h_true(k) = 0;
        continue;
    end

    if tk < opts.launchDelay_s
        thrust_accel(k) = 0;
    elseif tk < opts.launchDelay_s + opts.boostDuration_s
        thrust_accel(k) = opts.boostAccel_mps2;
    elseif tk < opts.launchDelay_s + opts.boostDuration_s + opts.tailoffDuration_s
        tau = (tk - (opts.launchDelay_s + opts.boostDuration_s)) / opts.tailoffDuration_s;
        thrust_accel(k) = (1 - tau) * opts.tailoffStartAccel_mps2;
    else
        thrust_accel(k) = 0;
    end

    drag_accel(k) = -opts.dragCoeff * v_true(k-1) * abs(v_true(k-1));
    a_true(k) = thrust_accel(k) + drag_accel(k) - opts.gravity;

    dtk = max(t(k) - t(k-1), eps);
    v_true(k) = v_true(k-1) + a_true(k) * dtk;
    h_true(k) = h_true(k-1) + v_true(k-1) * dtk + 0.5 * a_true(k) * dtk^2;

    if h_true(k) <= 0 && tk > opts.launchDelay_s + 1.0
        h_true(k) = 0;
        if abs(v_true(k)) <= opts.landClampVelocity_mps || v_true(k) < 0
            v_true(k) = 0;
            a_true(k) = 0;
            landed = true;
        end
    end
end

a_vertical_true = a_true;

pressureExponent = 1 / 0.19029495718;
altitudeClamped = min(max(h_true, 0), 44000);
bmp_P_true = opts.seaLevelPressurePa * (1 - altitudeClamped / 44330) .^ pressureExponent;
bmp_T_true = opts.temperatureC - 0.0065 * altitudeClamped;

bmp_alt_true = h_true;
bmp_alt_rel_true = h_true - h_true(1);

bmp_P = bmp_P_true + 8.0 * randn(N,1);
bmp_T = bmp_T_true + opts.baroTempNoise_C * randn(N,1);
bmp_alt = bmp_alt_true + opts.baroAltNoise_m * randn(N,1);
bmp_alt_rel = bmp_alt - bmp_alt(1);

ax_true = 0.08 * sin(2*pi*0.7*t);
ay_true = 0.06 * cos(2*pi*0.5*t);
az_true = opts.gravity + a_vertical_true;

gx_true = 0.02 * exp(-0.3*t) .* sin(2*pi*0.8*t);
gy_true = 0.015 * exp(-0.35*t) .* cos(2*pi*0.6*t);
gz_true = 0.01 * exp(-0.25*t) .* sin(2*pi*0.9*t);

ax = ax_true + opts.accelBiasXYZ(1) + opts.accelNoise_mps2 * randn(N,1);
ay = ay_true + opts.accelBiasXYZ(2) + opts.accelNoise_mps2 * randn(N,1);
az = az_true + opts.accelBiasXYZ(3) + opts.accelNoise_mps2 * randn(N,1);

gx = gx_true + opts.gyroBiasXYZ(1) + opts.gyroNoise_rps * randn(N,1);
gy = gy_true + opts.gyroBiasXYZ(2) + opts.gyroNoise_rps * randn(N,1);
gz = gz_true + opts.gyroBiasXYZ(3) + opts.gyroNoise_rps * randn(N,1);

lis_ax = ax_true + opts.lisBiasXYZ(1) + opts.lisNoise_mps2 * randn(N,1);
lis_ay = ay_true + opts.lisBiasXYZ(2) + opts.lisNoise_mps2 * randn(N,1);
lis_az = az_true + opts.lisBiasXYZ(3) + opts.lisNoise_mps2 * randn(N,1);

g_bx = zeros(N,1);
g_by = zeros(N,1);
g_bz = zeros(N,1);
g_bx(1) = 0;
g_by(1) = 0;
g_bz(1) = opts.gravity;

a_vertical = nan(N,1);

for k = 1:N
    a_mag = sqrt(ax(k)^2 + ay(k)^2 + az(k)^2);
    if abs(a_mag - opts.gravity) < 3.0
        if k == 1
            g_bx(k) = (1 - opts.kAlphaG) * g_bx(1) + opts.kAlphaG * ax(k);
            g_by(k) = (1 - opts.kAlphaG) * g_by(1) + opts.kAlphaG * ay(k);
            g_bz(k) = (1 - opts.kAlphaG) * g_bz(1) + opts.kAlphaG * az(k);
        else
            g_bx(k) = (1 - opts.kAlphaG) * g_bx(k-1) + opts.kAlphaG * ax(k);
            g_by(k) = (1 - opts.kAlphaG) * g_by(k-1) + opts.kAlphaG * ay(k);
            g_bz(k) = (1 - opts.kAlphaG) * g_bz(k-1) + opts.kAlphaG * az(k);
        end

        normg = sqrt(g_bx(k)^2 + g_by(k)^2 + g_bz(k)^2);
        if normg > 1e-6
            scale = opts.gravity / normg;
            g_bx(k) = g_bx(k) * scale;
            g_by(k) = g_by(k) * scale;
            g_bz(k) = g_bz(k) * scale;
        end
    else
        if k > 1
            g_bx(k) = g_bx(k-1);
            g_by(k) = g_by(k-1);
            g_bz(k) = g_bz(k-1);
        end
    end

    normg = sqrt(g_bx(k)^2 + g_by(k)^2 + g_bz(k)^2);
    if normg > 1e-6
        zux = g_bx(k) / normg;
        zuy = g_by(k) / normg;
        zuz = g_bz(k) / normg;
        a_up_meas = ax(k) * zux + ay(k) * zuy + az(k) * zuz;
        a_vertical(k) = a_up_meas - opts.gravity;
    end
end

filterCfg = struct();
filterCfg.kfTs = 1 / opts.fs;
filterCfg.kSigmaH2 = opts.kSigmaH2;
filterCfg.kSigmaA2 = opts.kSigmaA2;
filterCfg.kAlphaG = opts.kAlphaG;

kf = caelum.runVerticalEKF(t, a_vertical, bmp_alt_rel, filterCfg);
kf_h = kf.h;
kf_v = kf.v;
P00 = kf.P00;
P01 = kf.P01;
P10 = kf.P10;
P11 = kf.P11;

if opts.addNaNs
    nBad = max(1, round(opts.nanFraction * N));

    idxBaro = randperm(N, nBad);
    bmp_P(idxBaro) = NaN;
    bmp_alt(idxBaro) = NaN;
    bmp_alt_rel(idxBaro) = NaN;

    idxImu = randperm(N, nBad);
    ax(idxImu) = NaN;
    ay(idxImu) = NaN;
    az(idxImu) = NaN;
    a_vertical(idxImu) = NaN;

    idxCov = randperm(N, max(1, round(0.5 * nBad)));
    P00(idxCov) = NaN;
    P11(idxCov) = NaN;
end

if opts.addDropouts
    nDrop = max(2, round(opts.dropoutFraction * N));

    s1 = randi([10, max(10, N - nDrop)]);
    e1 = min(N, s1 + nDrop - 1);
    bmp_T(s1:e1) = NaN;
    bmp_P(s1:e1) = NaN;
    bmp_alt(s1:e1) = NaN;
    bmp_alt_rel(s1:e1) = NaN;

    s2 = randi([10, max(10, N - nDrop)]);
    e2 = min(N, s2 + nDrop - 1);
    ax(s2:e2) = NaN;
    ay(s2:e2) = NaN;
    az(s2:e2) = NaN;
    gx(s2:e2) = NaN;
    gy(s2:e2) = NaN;
    gz(s2:e2) = NaN;
    a_vertical(s2:e2) = NaN;

    s3 = randi([10, max(10, N - nDrop)]);
    e3 = min(N, s3 + nDrop - 1);
    lis_ax(s3:e3) = NaN;
    lis_ay(s3:e3) = NaN;
    lis_az(s3:e3) = NaN;
end

if opts.addDuplicateTimestamps
    nDup = max(1, round(opts.duplicateFraction * N));
    dupIdx = randperm(N-1, nDup) + 1;
    t_us(dupIdx) = t_us(dupIdx - 1);
end

T = table( ...
    t_us, ...
    bmp_T, bmp_P, bmp_alt, bmp_alt_rel, ...
    ax, ay, az, gx, gy, gz, ...
    lis_ax, lis_ay, lis_az, ...
    g_bx, g_by, g_bz, ...
    a_vertical, ...
    kf_h, kf_v, ...
    P00, P01, P10, P11, ...
    'VariableNames', { ...
    't_us','bmp_T','bmp_P','bmp_alt','bmp_alt_rel', ...
    'ax','ay','az','gx','gy','gz', ...
    'lis_ax','lis_ay','lis_az', ...
    'g_bx','g_by','g_bz', ...
    'a_vertical','kf_h','kf_v', ...
    'P00','P01','P10','P11'});

fid = fopen(filename, 'w');
if fid < 0
    error('caelum:generateTruthAwareCaelumLog:FileOpenFailed', ...
        'Could not open file for writing: %s', filename);
end

fprintf(fid, 't_us,bmp_T,bmp_P,bmp_alt,bmp_alt_rel,ax,ay,az,gx,gy,gz,lis_ax,lis_ay,lis_az,g_bx,g_by,g_bz,a_vertical,kf_h,kf_v,P00,P01,P10,P11\n');
fprintf(fid, '#BOOT,t_us=%u,ms=%u\n', t_us(1), round(double(t_us(1))/1000));
fclose(fid);

writetable(T, filename, 'WriteMode', 'append');

truth = struct();
truth.t = t;
truth.t_us = t_us;
truth.h_true = h_true;
truth.v_true = v_true;
truth.a_true = a_true;
truth.a_vertical_true = a_vertical_true;
truth.beta_true = opts.dragCoeff * ones(N,1);
truth.accel_bias_vertical_true = opts.accelBiasXYZ(3) * ones(N,1);
truth.thrust_accel = thrust_accel;
truth.drag_accel = drag_accel;
truth.bmp_P_true = bmp_P_true;
truth.bmp_T_true = bmp_T_true;
truth.bmp_alt_true = bmp_alt_true;
truth.bmp_alt_rel_true = bmp_alt_rel_true;
truth.ax_true = ax_true;
truth.ay_true = ay_true;
truth.az_true = az_true;
truth.gx_true = gx_true;
truth.gy_true = gy_true;
truth.gz_true = gz_true;
truth.kf_b_a = kf.b_a;
truth.kf_beta = kf.beta;
truth.q_true = repmat([1 0 0 0], N, 1);
truth.roll_true_deg = zeros(N,1);
truth.pitch_true_deg = zeros(N,1);
truth.yaw_true_deg = zeros(N,1);
end
