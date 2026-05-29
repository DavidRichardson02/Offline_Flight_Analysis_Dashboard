function [T, truth] = generateTruthAwareCaelumLogV2(filename, opts)
%GENERATETRUTHAWARECAELUMLOGV2 Generate synthetic Caelum logs with GPS and 3D truth.
arguments
    filename (1,1) string = "LOG_TRUTH_AWARE_V2.CSV"
    opts.seed (1,1) double = 42
    opts.fs (1,1) double = 50
    opts.gpsRateHz (1,1) double = 10
    opts.windXYZ (1,3) double = [1.5 -0.8 0.2]
    opts.addTimingJitter (1,1) logical = false
    opts.timingJitterStd_s (1,1) double = 0.0015
    opts.addNaNs (1,1) logical = false
    opts.nanFraction (1,1) double = 0.01
    opts.addDropouts (1,1) logical = false
    opts.dropoutFraction (1,1) double = 0.02
    opts.addDuplicateTimestamps (1,1) logical = false
    opts.duplicateFraction (1,1) double = 0.005
end

[Tbase, truth] = caelum.generateTruthAwareCaelumLog(filename, ...
    seed=opts.seed, ...
    fs=opts.fs, ...
    addTimingJitter=opts.addTimingJitter, ...
    timingJitterStd_s=opts.timingJitterStd_s, ...
    addNaNs=opts.addNaNs, ...
    nanFraction=opts.nanFraction, ...
    addDropouts=opts.addDropouts, ...
    dropoutFraction=opts.dropoutFraction, ...
    addDuplicateTimestamps=opts.addDuplicateTimestamps, ...
    duplicateFraction=opts.duplicateFraction);
n = height(Tbase);
t = double(Tbase.t_us - Tbase.t_us(1)) * 1e-6;

rng(opts.seed + 1000);
x_true = 2.0 * sin(0.25 * t);
y_true = 1.5 * cos(0.20 * t);
z_true = truth.h_true;
dt = [max(1/opts.fs, eps); diff(t)];
vx_true = [0; diff(x_true) ./ dt(2:end)];
vy_true = [0; diff(y_true) ./ dt(2:end)];
vz_true = truth.v_true;

gps_x = nan(n,1); gps_y = nan(n,1); gps_z = nan(n,1);
gps_vx = nan(n,1); gps_vy = nan(n,1); gps_vz = nan(n,1);

gpsStep = max(1, round(opts.fs / opts.gpsRateHz));
gpsIdx = 1:gpsStep:n;
gps_x(gpsIdx) = x_true(gpsIdx) + 1.0 * randn(numel(gpsIdx),1);
gps_y(gpsIdx) = y_true(gpsIdx) + 1.0 * randn(numel(gpsIdx),1);
gps_z(gpsIdx) = z_true(gpsIdx) + 1.5 * randn(numel(gpsIdx),1);
gps_vx(gpsIdx) = vx_true(gpsIdx) + opts.windXYZ(1) + 0.3 * randn(numel(gpsIdx),1);
gps_vy(gpsIdx) = vy_true(gpsIdx) + opts.windXYZ(2) + 0.3 * randn(numel(gpsIdx),1);
gps_vz(gpsIdx) = vz_true(gpsIdx) + opts.windXYZ(3) + 0.3 * randn(numel(gpsIdx),1);

T = Tbase;
T.gps_x = gps_x; T.gps_y = gps_y; T.gps_z = gps_z;
T.gps_vx = gps_vx; T.gps_vy = gps_vy; T.gps_vz = gps_vz;

writetable(T, filename);

truth.x_true = x_true;
truth.y_true = y_true;
truth.z_true = z_true;
truth.vx_true = vx_true;
truth.vy_true = vy_true;
truth.vz_true = vz_true;
truth.wind_true = repmat(opts.windXYZ, n, 1);
end
