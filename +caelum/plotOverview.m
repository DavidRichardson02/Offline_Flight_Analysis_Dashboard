function figs = plotOverview(T, events, replay)
%PLOTOVERVIEW Create overview figures for offline analysis.

arguments
    T table
    events struct
    replay = []
end

figs = gobjects(0,1);
hasReplay = istable(replay) && ~isempty(replay);

figs(end+1) = figure('Name', 'Altitude Overview', 'Color', 'w'); %#ok<AGROW>
plot(T.t, T.bmp_alt_rel, 'DisplayName', 'Barometric relative altitude');
hold on;
plot(T.t, T.kf_h, 'DisplayName', 'Logged KF altitude');
if hasReplay
    plot(replay.t, replay.h, '--', 'DisplayName', 'Replayed KF altitude');
end
localEvent(T, events.launchIdx, 'Launch');
localEvent(T, events.apogeeIdx, 'Apogee');
localEvent(T, events.landingIdx, 'Landing');
xlabel('Time [s]');
ylabel('Altitude [m]');
grid on;
legend('Location', 'best');
title('Altitude Reconstruction');

figs(end+1) = figure('Name', 'Velocity Overview', 'Color', 'w'); %#ok<AGROW>
plot(T.t, T.kf_v, 'DisplayName', 'Logged KF velocity');
hold on;
if hasReplay
    plot(replay.t, replay.v, '--', 'DisplayName', 'Replayed KF velocity');
end
yline(0, ':', 'Zero velocity');
localEvent(T, events.launchIdx, 'Launch');
localEvent(T, events.apogeeIdx, 'Apogee');
xlabel('Time [s]');
ylabel('Vertical velocity [m/s]');
grid on;
legend('Location', 'best');
title('Vertical Velocity');

figs(end+1) = figure('Name', 'Acceleration Overview', 'Color', 'w'); %#ok<AGROW>
plot(T.t, T.a_vertical, 'DisplayName', 'Vertical acceleration');
hold on;
plot(T.t, T.smoothed_a_vertical, 'DisplayName', 'Smoothed vertical acceleration');
localEvent(T, events.launchIdx, 'Launch');
localEvent(T, events.burnoutIdx, 'Burnout / coast');
xlabel('Time [s]');
ylabel('Vertical acceleration [m/s^2]');
grid on;
legend('Location', 'best');
title('Vertical Acceleration');

figs(end+1) = figure('Name', 'Estimator Uncertainty', 'Color', 'w'); %#ok<AGROW>
plot(T.t, T.kf_sigma_h, 'DisplayName', 'Logged sigma_h');
hold on;
plot(T.t, T.kf_sigma_v, 'DisplayName', 'Logged sigma_v');
if hasReplay
    plot(replay.t, replay.sigma_h, '--', 'DisplayName', 'Replayed sigma_h');
    plot(replay.t, replay.sigma_v, '--', 'DisplayName', 'Replayed sigma_v');
end
xlabel('Time [s]');
ylabel('Sigma');
grid on;
legend('Location', 'best');
title('Estimator Uncertainty');

figs(end+1) = figure('Name', 'Sensor Health', 'Color', 'w'); %#ok<AGROW>
plot(T.t, T.acc_norm, 'DisplayName', 'BMI088 |a|');
hold on;
plot(T.t, T.g_norm, 'DisplayName', 'Estimated |g|');
plot(T.t, T.gyro_norm, 'DisplayName', 'BMI088 |gyro|');
plot(T.t, T.lis_acc_norm, 'DisplayName', 'LIS2DU12 |a|');
xlabel('Time [s]');
ylabel('Magnitude');
grid on;
legend('Location', 'best');
title('Sensor Magnitudes');
end

function localEvent(T, idx, label)
xline(T.t(idx), '--', label, ...
    'HandleVisibility', 'off', ...
    'LabelVerticalAlignment', 'middle');
end
