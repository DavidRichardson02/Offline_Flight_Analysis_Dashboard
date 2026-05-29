function fig = plotDashboard(T, events, replay, cfg)
%PLOTDASHBOARD Create the canonical V3 dashboard with integrated GPS/3D support.
arguments
    T table
    events struct
    replay = []
    cfg struct = struct()
end

hasGps = all(ismember(["gps_x","gps_y","gps_z"], string(T.Properties.VariableNames))) || ...
         all(ismember(["gps_vx","gps_vy","gps_vz"], string(T.Properties.VariableNames)));

est3d = table();
if hasGps
    vars = string(T.Properties.VariableNames);
    if ~all(ismember(["q_w","q_x","q_y","q_z"], vars))
        attitude = caelum.runAttitudeReplay(T, cfg);
        T.q_w = interp1(attitude.t, attitude.q_w, T.t, 'linear', 1);
        T.q_x = interp1(attitude.t, attitude.q_x, T.t, 'linear', 0);
        T.q_y = interp1(attitude.t, attitude.q_y, T.t, 'linear', 0);
        T.q_z = interp1(attitude.t, attitude.q_z, T.t, 'linear', 0);
    end
    est3d = caelum.run3DEKF(T, cfg);
end

fig = figure('Name', 'Caelum Flight Dashboard V3', 'Color', 'w', ...
    'Units', 'normalized', 'Position', [0.03 0.06 0.94 0.88]);

tl = tiledlayout(fig, 4, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, 'Caelum Integrated Dashboard V3');

nexttile(tl, 1);
plot(T.t, T.bmp_alt_rel, 'DisplayName', 'Baro alt'); hold on;
plot(T.t, T.kf_h, 'DisplayName', 'Logged KF alt');
if istable(replay) && ~isempty(replay), plot(replay.t, replay.h, '--', 'DisplayName', 'Replay KF alt'); end
if istable(est3d) && ~isempty(est3d), plot(est3d.t, est3d.pz, ':', 'DisplayName', '3D fused z'); end
grid on; legend('Location','best'); title('Altitude'); xlabel('t'); ylabel('m');

nexttile(tl, 2);
plot(T.t, T.kf_v, 'DisplayName', 'Logged KF v'); hold on;
if istable(replay) && ~isempty(replay), plot(replay.t, replay.v, '--', 'DisplayName', 'Replay KF v'); end
if istable(est3d) && ~isempty(est3d), plot(est3d.t, est3d.vz, ':', 'DisplayName', '3D fused v_z'); end
grid on; legend('Location','best'); title('Vertical Velocity'); xlabel('t'); ylabel('m/s');

nexttile(tl, 3);
plot(T.t, T.a_vertical, 'DisplayName', 'a_vertical'); hold on;
if ismember("smoothed_a_vertical", string(T.Properties.VariableNames))
    plot(T.t, T.smoothed_a_vertical, 'DisplayName', 'smoothed a_vertical');
end
grid on; legend('Location','best'); title('Vertical Acceleration'); xlabel('t');

nexttile(tl, 4);
plot(T.t, T.acc_norm, 'DisplayName', '|acc|'); hold on;
plot(T.t, T.gyro_norm, 'DisplayName', '|gyro|');
if ismember("g_norm", string(T.Properties.VariableNames))
    plot(T.t, T.g_norm, 'DisplayName', '|g_hat|');
end
grid on; legend('Location','best'); title('Sensor Health'); xlabel('t');

nexttile(tl, 5);
plot(T.t, T.kf_sigma_h, 'DisplayName', 'sigma_h'); hold on;
plot(T.t, T.kf_sigma_v, 'DisplayName', 'sigma_v');
if istable(est3d) && ~isempty(est3d)
    plot(est3d.t, est3d.sigma_pz, '--', 'DisplayName', 'sigma_pz');
    plot(est3d.t, est3d.sigma_vz, '--', 'DisplayName', 'sigma_vz');
end
grid on; legend('Location','best'); title('Estimator Uncertainty'); xlabel('t');

nexttile(tl, 6);
vars = string(T.Properties.VariableNames);
hasGpsPos = all(ismember(["gps_x","gps_y","gps_z"], vars));
if hasGpsPos
    plot(T.t, T.gps_x, 'DisplayName', 'gps_x'); hold on;
    plot(T.t, T.gps_y, 'DisplayName', 'gps_y');
    plot(T.t, T.gps_z, 'DisplayName', 'gps_z');
    if istable(est3d) && ~isempty(est3d)
        plot(est3d.t, est3d.px, '--', 'DisplayName', 'ekf_x');
        plot(est3d.t, est3d.py, '--', 'DisplayName', 'ekf_y');
        plot(est3d.t, est3d.pz, '--', 'DisplayName', 'ekf_z');
    end
    legend('Location','best');
else
    text(0.5,0.5,'GPS position unavailable','HorizontalAlignment','center'); axis off;
end
grid on; title('GPS / 3D Position');

nexttile(tl, 7);
hasGpsVel = all(ismember(["gps_vx","gps_vy","gps_vz"], vars));
if hasGpsVel
    plot(T.t, T.gps_vx, 'DisplayName', 'gps_vx'); hold on;
    plot(T.t, T.gps_vy, 'DisplayName', 'gps_vy');
    plot(T.t, T.gps_vz, 'DisplayName', 'gps_vz');
    if istable(est3d) && ~isempty(est3d)
        plot(est3d.t, est3d.vx + est3d.wx, '--', 'DisplayName', 'fused_gnd_vx');
        plot(est3d.t, est3d.vy + est3d.wy, '--', 'DisplayName', 'fused_gnd_vy');
        plot(est3d.t, est3d.vz + est3d.wz, '--', 'DisplayName', 'fused_gnd_vz');
    end
    legend('Location','best');
else
    text(0.5,0.5,'GPS velocity unavailable','HorizontalAlignment','center'); axis off;
end
grid on; title('GPS / Fused Ground Velocity');

nexttile(tl, 8);
if istable(est3d) && ~isempty(est3d)
    plot3(est3d.px, est3d.py, est3d.pz, 'DisplayName', '3D EKF'); hold on;
    if hasGpsPos, plot3(T.gps_x, T.gps_y, T.gps_z, '--', 'DisplayName', 'GPS'); end
    grid on; axis equal; view(3); xlabel('x'); ylabel('y'); zlabel('z');
    legend('Location','best');
else
    text(0.5,0.5,'3D state unavailable','HorizontalAlignment','center'); axis off;
end
title('3D Trajectory');

nexttile(tl, 9);
if istable(est3d) && ~isempty(est3d)
    plot(est3d.t, est3d.wx, 'DisplayName', 'w_x'); hold on;
    plot(est3d.t, est3d.wy, 'DisplayName', 'w_y');
    plot(est3d.t, est3d.wz, 'DisplayName', 'w_z');
    grid on; legend('Location','best');
else
    text(0.5,0.5,'Wind unavailable','HorizontalAlignment','center'); axis off;
end
title('Wind Estimate');

nexttile(tl, 10);
if istable(est3d) && ~isempty(est3d)
    plot(est3d.t, est3d.sigma_px, 'DisplayName', 'sig_px'); hold on;
    plot(est3d.t, est3d.sigma_py, 'DisplayName', 'sig_py');
    plot(est3d.t, est3d.sigma_pz, 'DisplayName', 'sig_pz');
    plot(est3d.t, est3d.sigma_wx, '--', 'DisplayName', 'sig_wx');
    plot(est3d.t, est3d.sigma_wy, '--', 'DisplayName', 'sig_wy');
    plot(est3d.t, est3d.sigma_wz, '--', 'DisplayName', 'sig_wz');
    grid on; legend('Location','best');
else
    text(0.5,0.5,'3D uncertainties unavailable','HorizontalAlignment','center'); axis off;
end
title('3D/Wind Uncertainty');

nexttile(tl, 11);
if istable(est3d) && ~isempty(est3d)
    stairs(est3d.t, double(est3d.gps_used), 'DisplayName', 'gps_used'); hold on;
    stairs(est3d.t, double(est3d.gps_rejected), 'DisplayName', 'gps_rejected');
    plot(est3d.t, est3d.innovation_pos_norm, 'DisplayName', 'pos innov norm');
    plot(est3d.t, est3d.innovation_vel_norm, 'DisplayName', 'vel innov norm');
    grid on; legend('Location','best');
else
    text(0.5,0.5,'GPS fusion metrics unavailable','HorizontalAlignment','center'); axis off;
end
title('GPS Fusion Health');

nexttile(tl, 12);
bar(categorical({'Launch','Burnout','Apogee','Landing'}), ...
    [events.launchTime_s, events.burnoutTime_s, events.apogeeTime_s, events.landingTime_s]);
title('Event Timing [s]'); ylabel('s'); grid on;

nexttile(tl, [1 4]); axis off;
lines = {};
lines{end+1} = 'Mission Summary';
lines{end+1} = sprintf('Peak KF altitude: %.3f m', max(T.kf_h, [], 'omitnan'));
lines{end+1} = sprintf('Peak baro altitude: %.3f m', max(T.bmp_alt_rel, [], 'omitnan'));
lines{end+1} = sprintf('Launch time: %.3f s', events.launchTime_s);
lines{end+1} = sprintf('Apogee time: %.3f s', events.apogeeTime_s);
if istable(est3d) && ~isempty(est3d)
    lines{end+1} = sprintf('Final fused position: [%.2f %.2f %.2f] m', est3d.px(end), est3d.py(end), est3d.pz(end));
    lines{end+1} = sprintf('Final wind: [%.2f %.2f %.2f] m/s', est3d.wx(end), est3d.wy(end), est3d.wz(end));
    lines{end+1} = sprintf('GPS acceptance rate: %.1f%%', 100 * mean(double(est3d.gps_used), 'omitnan'));
end
text(0.02, 0.98, strjoin(lines, newline), 'VerticalAlignment', 'top', 'FontName', 'Consolas');
end
