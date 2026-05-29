function meas = localExtractGPSMeasurement(T, k)
%LOCALEXTRACTGPSMEASUREMENT Extract one GPS measurement struct from table row.
vars = string(T.Properties.VariableNames);
meas = struct( ...
    'gps_x', NaN, 'gps_y', NaN, 'gps_z', NaN, ...
    'gps_vx', NaN, 'gps_vy', NaN, 'gps_vz', NaN);

names = fieldnames(meas);
for i = 1:numel(names)
    name = string(names{i});
    if ismember(name, vars)
        meas.(names{i}) = T.(char(name))(k);
    end
end
end
