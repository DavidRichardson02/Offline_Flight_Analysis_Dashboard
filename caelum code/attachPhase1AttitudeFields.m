function [clean, attitude] = attachPhase1AttitudeFields(clean, attitude)
%ATTACHPHASE1ATTITUDEFIELDS Attach Phase 1 attitude diagnostics consistently.
%
% This helper is intended to be inserted into analyzeLog.m after
% runAttitudeReplay(clean, cfg) and before replayEstimator(clean, cfg).

if isempty(attitude)
    return;
end

fieldNames = [ ...
    "a_vertical_attitude", ...
    "roll_deg","pitch_deg","yaw_deg", ...
    "b_gx","b_gy","b_gz", ...
    "g_bx_att","g_by_att","g_bz_att", ...
    "gravity_update_used","gravity_innovation","gravity_residual","tilt_error_deg"];

for k = 1:numel(fieldNames)
    fieldName = fieldNames(k);
    if ~ismember(fieldName, string(attitude.Properties.VariableNames))
        continue;
    end

    if fieldName == "gravity_update_used"
        values = interp1(attitude.t, double(attitude.(char(fieldName))), clean.t, 'nearest', 0);
        clean.(char(fieldName)) = logical(values > 0.5);
    else
        clean.(char(fieldName)) = interp1(attitude.t, attitude.(char(fieldName)), clean.t, 'linear', NaN);
    end
end

% Phase 1 required diagnostics always present in replay table inputs
if ~ismember("vertical_input_mode", string(clean.Properties.VariableNames))
    clean.vertical_input_mode = repmat("legacy", height(clean), 1);
end
if ~ismember("a_vertical_used", string(clean.Properties.VariableNames))
    clean.a_vertical_used = clean.a_vertical;
end
if ~ismember("attitude_fallback_used", string(clean.Properties.VariableNames))
    clean.attitude_fallback_used = false(height(clean), 1);
end
end
