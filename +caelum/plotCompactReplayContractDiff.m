function [sampleAudit, fieldSummary] = plotCompactReplayContractDiff(ax, T, replay, cfg, options)
%PLOTCOMPACTREPLAYCONTRACTDIFF Axes-level firmware/replay contract strip.
%
% This compact dashboard view reuses buildReplayContractDiffAudit so the
% integrated dashboard shares the same comparison semantics as the standalone
% replay-contract validation artifact.
arguments
    ax (1,1) matlab.graphics.axis.Axes
    T table
    replay = table()
    cfg struct = caelum.defaultConfig()
    options.MaxSamples (1,1) double {mustBeInteger,mustBePositive} = 800
    options.Title (1,1) string = "Replay Contract Diff"
end

cla(ax);
sampleAudit = table();
fieldSummary = table();

if isempty(T) || height(T) < 1
    localShowUnavailable(ax, "Replay contract evidence unavailable.");
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

if ~istable(replay) || isempty(replay)
    localShowUnavailable(ax, "Replay contract evidence unavailable: replay table is empty.");
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

try
    [sampleAudit, fieldSummary] = caelum.buildReplayContractDiffAudit(T, replay, cfg);
catch ME
    localShowUnavailable(ax, "Replay contract evidence unavailable: " + string(ME.message));
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

if height(sampleAudit) < 1 || isempty(fieldSummary)
    localShowUnavailable(ax, "Replay contract audit produced no rows.");
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

idx = localSubsampleIndex((1:height(sampleAudit)).', options.MaxSamples);
A = sampleAudit(idx, :);
status = localStatusMatrix(A);
t = A.t(:).';

imagesc(ax, t, 1:size(status, 1), status);
set(ax, 'YDir', 'normal');
colormap(ax, localStatusColors());
caxis(ax, [1 5]);
yticks(ax, 1:size(status, 1));
yticklabels(ax, {'time','input','state','sigma','cov','update','label'});
xlabel(ax, 't [s]');
title(ax, localTitleText(options.Title, sampleAudit, fieldSummary), 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
end

function status = localStatusMatrix(audit)
n = height(audit);
status = 3 .* ones(7, n);

status(1, ~audit.time_aligned) = 5;
status(1, ~audit.replay_available) = 1;
status(1, audit.sample_gap) = 2;

status(2, audit.input_delta_high) = 5;
status(2, ~isfinite(audit.delta_a_vertical_mps2)) = 1;

status(3, audit.state_delta_high) = 5;
stateAvailable = isfinite(audit.delta_h_m) | isfinite(audit.delta_v_mps);
status(3, ~stateAvailable) = 1;

status(4, audit.sigma_delta_high) = 5;
sigmaAvailable = isfinite(audit.delta_sigma_h_m) | isfinite(audit.delta_sigma_v_mps);
status(4, ~sigmaAvailable) = 1;

status(5, audit.covariance_delta_high) = 5;
covAvailable = isfinite(audit.delta_P00) | isfinite(audit.delta_P11);
status(5, ~covAvailable) = 1;

status(6, :) = 2;
status(6, audit.replay_baro_used) = 4;
status(6, audit.replay_baro_rejected) = 5;

status(7, audit.contract_label == "contract_nominal") = 4;
status(7, audit.contract_label == "replay_baro_rejected") = 2;
warnLabels = ["input_contract_delta","state_contract_delta", ...
    "covariance_contract_delta","timebase_mismatch","firmware_warning_active"];
status(7, ismember(audit.contract_label, warnLabels)) = 5;
missingLabels = ["logged_firmware_incomplete","replay_incomplete"];
status(7, ismember(audit.contract_label, missingLabels)) = 1;
end

function titleText = localTitleText(baseTitle, audit, summary)
passCount = nnz(summary.pass);
fieldCount = height(summary);
stateRmseH = localRmse(audit.delta_h_m);
stateRmseV = localRmse(audit.delta_v_mps);
maxInputDelta = max(abs(audit.delta_a_vertical_mps2), [], 'omitnan');
latestIdx = find(audit.contract_label ~= "", 1, 'last');
if isempty(latestIdx)
    latestLabel = "unclassified";
else
    latestLabel = localCompactLabel(audit.contract_label(latestIdx));
end
titleText = sprintf('%s | fields %d/%d pass | h %.2f m | v %.2f m/s | a %.3g | %s', ...
    baseTitle, passCount, fieldCount, stateRmseH, stateRmseV, maxInputDelta, latestLabel);
end

function label = localCompactLabel(label)
label = erase(string(label), ["contract_","firmware_","replay_"]);
label = replace(label, "_", " ");
if strlength(label) > 26
    label = extractBefore(label, 27);
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

function colors = localStatusColors()
colors = [ ...
    0.14 0.14 0.14; ...
    0.25 0.40 0.70; ...
    0.20 0.66 0.38; ...
    0.72 0.30 0.82; ...
    0.93 0.46 0.17];
end

function localShowUnavailable(ax, message)
axis(ax, [0 1 0 1]);
axis(ax, 'off');
text(ax, 0.5, 0.5, message, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Interpreter', 'none');
end
