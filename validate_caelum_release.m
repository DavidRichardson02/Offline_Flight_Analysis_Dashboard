function validation = validate_caelum_release()
%VALIDATE_CAELUM_RELEASE Run the release-facing vertical replay validation workflow.

addpath(genpath(fileparts(mfilename('fullpath'))));

fprintf('--- Caelum patched release validation ---\n');

try
    validation = validate_vertical_replay_stack();
    disp(validation.reportTable(:, ["caseName","modeName","check","passed","notes"]));
catch ME
    fprintf(2, 'validate_vertical_replay_stack failed:\n%s\n', getReport(ME, 'extended'));
    rethrow(ME);
end

if validation.overallPassed
    fprintf('--- Validation passed ---\n');
else
    error('caelum:validate_caelum_release:ValidationFailed', ...
        'Vertical replay validation reported one or more failures.');
end
end
