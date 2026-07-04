function replay = replayEstimator(T, cfg)
%REPLAYESTIMATOR Offline replay of the vertical EKF with selectable attitude input.
%
% Behavior:
%   - cfg.useAttitudeVerticalInput = false:
%       uses legacy T.a_vertical
%   - cfg.useAttitudeVerticalInput = true:
%       prefers T.a_vertical_attitude, but falls back to T.a_vertical when
%       attitude-derived input is invalid or gravity updates are unavailable.
%
% Logging:
%   The returned replay table always includes:
%       vertical_input_mode
%       a_vertical_used
%       attitude_fallback_used

arguments
    T table
    cfg struct = caelum.defaultConfig()
end

vars = string(T.Properties.VariableNames);
n = height(T);

legacyInput = T.a_vertical;
attitudeAvailable = ismember("a_vertical_attitude", vars);
gravityFlagAvailable = ismember("gravity_update_used", vars);

a_vertical_used = legacyInput;
attitude_fallback_used = false(n,1);
vertical_input_mode = repmat("legacy", n, 1);

if isfield(cfg, 'useAttitudeVerticalInput') && cfg.useAttitudeVerticalInput && attitudeAvailable
    vertical_input_mode(:) = "attitude";

    for k = 1:n
        canUseAttitude = isfinite(T.a_vertical_attitude(k));

        if gravityFlagAvailable
            canUseAttitude = canUseAttitude && logical(T.gravity_update_used(k));
        end

        if canUseAttitude
            a_vertical_used(k) = T.a_vertical_attitude(k);
        else
            a_vertical_used(k) = legacyInput(k);
            attitude_fallback_used(k) = true;
        end
    end
end

replay = caelum.runVerticalEKF(T.t, a_vertical_used, T.bmp_alt_rel, cfg);

replay.vertical_input_mode = vertical_input_mode;
replay.a_vertical_used = a_vertical_used;
replay.attitude_fallback_used = attitude_fallback_used;
end
