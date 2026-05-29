function [T, report] = importLog(filename)
%IMPORTLOG Import a Caelum CSV file using canonical V3 schema support.
arguments
    filename (1,1) string
end

if ~isfile(filename)
    error('caelum:importLog:FileNotFound', 'File not found: %s', filename);
end

opts = detectImportOptions(filename, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
opts.CommentStyle = '#';
opts = setvartype(opts, 'double');
T = readtable(filename, opts);

baseMinimal = [ ...
    "t_us","bmp_T","bmp_P","bmp_alt", ...
    "ax","ay","az","gx","gy","gz", ...
    "lis_ax","lis_ay","lis_az"];

baseFull = [ ...
    "t_us","bmp_T","bmp_P","bmp_alt","bmp_alt_rel", ...
    "ax","ay","az","gx","gy","gz", ...
    "lis_ax","lis_ay","lis_az", ...
    "g_bx","g_by","g_bz", ...
    "a_vertical","kf_h","kf_v", ...
    "P00","P01","P10","P11"];

gpsSet = ["gps_x","gps_y","gps_z","gps_vx","gps_vy","gps_vz"];
vars = string(T.Properties.VariableNames);

hasBaseMinimal = all(ismember(baseMinimal, vars));
hasBaseFull = all(ismember(baseFull, vars));

if ~hasBaseMinimal && ~hasBaseFull
    error('caelum:importLog:MissingColumns', ...
        'File does not match the canonical Caelum schema set.');
end

for k = 1:numel(gpsSet)
    if ~ismember(gpsSet(k), vars)
        T.(char(gpsSet(k))) = nan(height(T), 1);
    end
end

if isempty(T)
    error('caelum:importLog:EmptyLog', ...
        'No numeric log rows were imported from %s', filename);
end

report = struct();
report.importMode = "strict";
report.schemaMode = "minimal";
if hasBaseFull
    report.schemaMode = "full";
end
report.gpsChannelsPresent = sum(ismember(gpsSet, vars));
report.totalRawLines = NaN;
report.commentLinesRemoved = NaN;
report.emptyLinesRemoved = NaN;
report.repeatedHeadersRemoved = 0;
report.droppedMalformedRows = 0;
report.validRowsImported = height(T);
end
