function audit = plotCompactAttitudeGravityProvenance(ax, T, cfg, options)
%PLOTCOMPACTATTITUDEGRAVITYPROVENANCE Axes-level attitude/gravity source strip.
%
% This compact view reuses buildAttitudeGravityProvenanceAudit so dashboard
% semantics match the standalone validation artifact.
arguments
    ax (1,1) matlab.graphics.axis.Axes
    T table
    cfg struct = caelum.defaultConfig()
    options.MaxSamples (1,1) double {mustBeInteger,mustBePositive} = 800
    options.Title (1,1) string = "Attitude / Gravity Provenance"
end

cla(ax);
audit = table();

if isempty(T) || height(T) < 1
    localShowUnavailable(ax, "Attitude/gravity evidence unavailable.");
    title(ax, options.Title);
    return;
end

vars = string(T.Properties.VariableNames);
required = ["t","ax","ay","az","gx","gy","gz","g_bx","g_by","g_bz","a_vertical"];
missing = setdiff(required, vars, 'stable');
if ~isempty(missing)
    localShowUnavailable(ax, "Attitude/gravity evidence unavailable: missing " + ...
        localFormatFieldList(missing, 4));
    title(ax, options.Title);
    return;
end

try
    attitude = caelum.runAttitudeReplay(T, cfg);
    [Tlocal, attitude] = caelum.attachPhase1AttitudeFields(T, attitude);
    audit = caelum.buildAttitudeGravityProvenanceAudit(Tlocal, attitude, cfg);
catch ME
    localShowUnavailable(ax, "Attitude/gravity evidence unavailable: " + string(ME.message));
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

if height(audit) < 1
    localShowUnavailable(ax, "Attitude/gravity audit produced no rows.");
    title(ax, options.Title);
    return;
end

idx = localSubsampleIndex((1:height(audit)).', options.MaxSamples);
A = audit(idx, :);
t = A.t(:).';
status = localBuildStatusMatrix(A);

imagesc(ax, t, 1:size(status, 1), status);
set(ax, 'YDir', 'normal');
colormap(ax, localStatusColors());
caxis(ax, [1 5]);
yticks(ax, 1:size(status, 1));
yticklabels(ax, {'raw IMU','logged g','attitude g','logged a_v','attitude a_v','gravity update','delta / gate'});
xlabel(ax, 't [s]');
title(ax, localTitleText(options.Title, audit), 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
end

function status = localBuildStatusMatrix(audit)
n = height(audit);
status = ones(7, n);

status(1, :) = localAvailableStatus(audit.raw_imu_available);

status(2, :) = localAvailableStatus(audit.logged_gravity_available);
loggedGravityWarn = audit.logged_gravity_available & ...
    abs(audit.logged_g_norm_error_mps2) > audit.gravity_norm_tolerance_mps2;
status(2, loggedGravityWarn) = 5;

status(3, :) = localAvailableStatus(audit.attitude_gravity_available);
attitudeGravityWarn = audit.attitude_gravity_available & ...
    abs(audit.attitude_g_norm_error_mps2) > audit.gravity_norm_tolerance_mps2;
status(3, attitudeGravityWarn) = 5;

status(4, :) = localAvailableStatus(audit.logged_vertical_available);
status(5, :) = localAvailableStatus(audit.attitude_vertical_available);

status(6, audit.attitude_evidence_available) = 2;
status(6, audit.gravity_update_used) = 4;

status(7, audit.raw_imu_available & audit.logged_vertical_available) = 3;
warnLabels = ["logged_gravity_norm_bad","attitude_gravity_norm_bad", ...
    "tilt_error_high","gravity_residual_high","vertical_accel_disagreement", ...
    "truth_accel_error_high"];
status(7, ismember(audit.evidence_label, warnLabels)) = 5;
status(7, audit.sample_gap) = 2;
end

function values = localAvailableStatus(mask)
values = ones(1, numel(mask));
values(mask(:).') = 3;
end

function colors = localStatusColors()
colors = [ ...
    0.14 0.14 0.14; ...
    0.24 0.39 0.67; ...
    0.20 0.66 0.38; ...
    0.72 0.30 0.82; ...
    0.93 0.46 0.17];
end

function titleText = localTitleText(baseTitle, audit)
latestIdx = find(audit.evidence_label ~= "", 1, 'last');
if isempty(latestIdx)
    latestLabel = "unclassified";
else
    latestLabel = localCompactLabel(audit.evidence_label(latestIdx));
end
updateFraction = mean(double(audit.gravity_update_used), 'omitnan');
deltaRmse = localRmse(audit.logged_minus_attitude_a_vertical_mps2);
titleText = sprintf('%s | upd %.2f | dA %.2f | %s', ...
    baseTitle, updateFraction, deltaRmse, latestLabel);
end

function label = localCompactLabel(label)
label = erase(string(label), ["telemetry_","attitude_","gravity_","vertical_"]);
label = replace(label, "_", " ");
if strlength(label) > 24
    label = extractBefore(label, 25);
end
end

function value = localRmse(x)
valid = isfinite(x);
if ~any(valid)
    value = NaN;
else
    value = sqrt(mean(x(valid).^2, 'omitnan'));
end
end

function idxOut = localSubsampleIndex(idxIn, maxCount)
idxIn = idxIn(:);
if numel(idxIn) <= maxCount
    idxOut = idxIn;
else
    pick = unique(round(linspace(1, numel(idxIn), maxCount))).';
    idxOut = idxIn(pick);
end
end

function localShowUnavailable(ax, message)
axis(ax, [0 1 0 1]);
axis(ax, 'off');
text(ax, 0.5, 0.5, message, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Interpreter', 'none');
end

function textOut = localFormatFieldList(fields, maxFields)
fields = string(fields(:)).';
if isempty(fields)
    textOut = "none";
    return;
end

if numel(fields) > maxFields
    shown = fields(1:maxFields);
    textOut = string(sprintf('%s, +%d more', strjoin(cellstr(shown), ', '), numel(fields) - maxFields));
else
    textOut = string(strjoin(cellstr(fields), ', '));
end
end
