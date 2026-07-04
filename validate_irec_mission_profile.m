function validation = validate_irec_mission_profile(options)
%VALIDATE_IREC_MISSION_PROFILE Validate rule-derived IREC target constants.
arguments
    options.NumericTolerance (1,1) double = 1e-9
end

addpath(genpath(fileparts(mfilename('fullpath'))));

profile = caelum.irecMissionProfile(TargetApogee_ft=10000);
cfg = caelum.defaultConfig();

reportTable = localEmptyValidationTable();
reportTable = [reportTable; localValidationRow("mission", "target_class_ft", ...
    profile.targetApogee_ft == 10000, string(profile.targetApogee_ft), "10000", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("mission", "target_class_m", ...
    abs(profile.targetApogee_m - 3048.0) <= options.NumericTolerance, ...
    string(profile.targetApogee_m), "3048.0", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("mission", "scoring_window_low_ft", ...
    abs(profile.scoringWindowLow_ft - 7000.0) <= options.NumericTolerance, ...
    string(profile.scoringWindowLow_ft), "7000.0", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("mission", "scoring_window_high_ft", ...
    abs(profile.scoringWindowHigh_ft - 13000.0) <= options.NumericTolerance, ...
    string(profile.scoringWindowHigh_ft), "13000.0", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("mission", "default_config_uses_10k_ft", ...
    isfield(cfg, 'mission') && isfield(cfg.mission, 'targetApogee_ft') && cfg.mission.targetApogee_ft == 10000, ...
    string(cfg.mission.targetApogee_ft), "10000", "")]; %#ok<AGROW>

validation = struct();
validation.generatedAt = string(datetime("now", "TimeZone", "local", "Format", "yyyy-MM-dd HH:mm:ss Z"));
validation.profile = profile;
validation.reportTable = reportTable;
validation.overallPassed = all(reportTable.passed);

disp(reportTable(:, ["scope","check","passed","actual","expected","notes"]));
if validation.overallPassed
    fprintf('IREC mission profile validation passed.\n');
else
    fprintf(2, 'IREC mission profile validation reported failures.\n');
end
end

function rows = localEmptyValidationTable()
rows = table('Size', [0 6], ...
    'VariableTypes', {'string','string','logical','string','string','string'}, ...
    'VariableNames', {'scope','check','passed','actual','expected','notes'});
end

function row = localValidationRow(scope, check, passed, actual, expected, notes)
row = table(string(scope), string(check), logical(passed), ...
    string(actual), string(expected), string(notes), ...
    'VariableNames', {'scope','check','passed','actual','expected','notes'});
end
