function profile = irecMissionProfile(options)
%IRECMISSIONPROFILE Return source-backed IREC mission scoring constants.
%
% The competition target is a mission contract, not a sensor measurement. Keep
% it separate from firmware telemetry fields such as target_apogee and
% target_effective so plots can compare the flight computer's policy target
% against the scoring class without overwriting recorded evidence.
arguments
    options.TargetApogee_ft (1,1) double {mustBePositive} = 10000
end

allowedTargets_ft = [10000 30000 45000];
if ~ismember(options.TargetApogee_ft, allowedTargets_ft)
    error('caelum:irecMissionProfile:InvalidTargetApogee', ...
        'TargetApogee_ft must be one of the IREC scoring classes: 10000, 30000, or 45000 ft AGL.');
end

ftToM = 0.3048;
target_ft = options.TargetApogee_ft;
target_m = target_ft * ftToM;
scoringWindowFraction = 0.30;

profile = struct();
profile.name = sprintf('IREC 2026 %.0f ft AGL scoring profile', target_ft);
profile.ruleSet = "IREC Rules and Requirements Document 2026 v.1.0";
profile.targetApogee_ft = target_ft;
profile.targetApogee_m = target_m;
profile.targetReference = "AGL";
profile.allowedTargetApogees_ft = allowedTargets_ft;
profile.allowedTargetApogees_m = allowedTargets_ft .* ftToM;
profile.scoringWindowFraction = scoringWindowFraction;
profile.scoringWindowLow_ft = (1.0 - scoringWindowFraction) * target_ft;
profile.scoringWindowHigh_ft = (1.0 + scoringWindowFraction) * target_ft;
profile.scoringWindowLow_m = profile.scoringWindowLow_ft * ftToM;
profile.scoringWindowHigh_m = profile.scoringWindowHigh_ft * ftToM;
profile.totalFlightPerformancePoints = 500;
profile.apogeeAccuracyPoints = 350;
profile.payloadMinimum_lb = 4.4;
profile.payloadMinimum_kg = profile.payloadMinimum_lb * 0.45359237;
profile.officialAltitudeSource = ...
    "COTS barometric pressure altimeter with on-board data storage";
profile.telemetryAltitudeNote = ...
    "Telemetry is not the primary official altitude source unless accepted under the IREC rules.";
profile.referencePages = struct( ...
    'competitionTargets', 8, ...
    'officialAltitudeLogging', 13, ...
    'technicalReportPredictedFlightData', 19, ...
    'flightPerformanceScoring', 30);
end
