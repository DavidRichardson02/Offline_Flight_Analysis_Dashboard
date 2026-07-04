function figs = plotOverview3D(est3d, T)
%PLOTOVERVIEW3D Create 3D/GPS overview figures.
arguments
    est3d table
    T table
end
figs = gobjects(0,1);
if isempty(est3d)
    return;
end
vars = string(T.Properties.VariableNames);
hasGpsPos = all(ismember(["gps_x","gps_y","gps_z"], vars));
hasGpsVel = all(ismember(["gps_vx","gps_vy","gps_vz"], vars));

figs(end+1) = figure('Name', '3D Trajectory', 'Color', 'w'); %#ok<AGROW>
plot3(est3d.px, est3d.py, est3d.pz, 'DisplayName', 'EKF 3D trajectory');
hold on;
if hasGpsPos
    plot3(T.gps_x, T.gps_y, T.gps_z, '--', 'DisplayName', 'GPS trajectory');
end
xlabel('X [m]'); ylabel('Y [m]'); zlabel('Z [m]');
grid on; axis equal; legend('Location','best'); title('3D Position Trajectory');

figs(end+1) = figure('Name', 'Wind Estimate', 'Color', 'w'); %#ok<AGROW>
plot(est3d.t, est3d.wx, 'DisplayName', 'w_x'); hold on;
plot(est3d.t, est3d.wy, 'DisplayName', 'w_y');
plot(est3d.t, est3d.wz, 'DisplayName', 'w_z');
xlabel('Time [s]'); ylabel('Wind component [m/s]');
grid on; legend('Location','best'); title('Estimated Wind Components');

if hasGpsVel
    figs(end+1) = figure('Name', 'GPS Velocity Fusion', 'Color', 'w'); %#ok<AGROW>
    plot(est3d.t, est3d.vx + est3d.wx, 'DisplayName', 'Fused ground v_x'); hold on;
    plot(est3d.t, est3d.vy + est3d.wy, 'DisplayName', 'Fused ground v_y');
    plot(est3d.t, est3d.vz + est3d.wz, 'DisplayName', 'Fused ground v_z');
    plot(T.t, T.gps_vx, '--', 'DisplayName', 'GPS v_x');
    plot(T.t, T.gps_vy, '--', 'DisplayName', 'GPS v_y');
    plot(T.t, T.gps_vz, '--', 'DisplayName', 'GPS v_z');
    xlabel('Time [s]'); ylabel('Velocity [m/s]');
    grid on; legend('Location','best'); title('Ground Velocity Fusion');
end
end
