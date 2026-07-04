function wind = estimateWind(est3d)
%ESTIMATEWIND Extract compact wind summaries from the 3D EKF output.
arguments
    est3d table
end
wind = struct();
if isempty(est3d)
    wind.mean = [NaN NaN NaN];
    wind.final = [NaN NaN NaN];
    wind.speedMean = NaN;
    wind.speedFinal = NaN;
    return;
end
wind.mean = [mean(est3d.wx,'omitnan'), mean(est3d.wy,'omitnan'), mean(est3d.wz,'omitnan')];
idx = find(isfinite(est3d.wx) & isfinite(est3d.wy) & isfinite(est3d.wz), 1, 'last');
if isempty(idx)
    wind.final = [NaN NaN NaN];
else
    wind.final = [est3d.wx(idx), est3d.wy(idx), est3d.wz(idx)];
end
wind.speedMean = norm(wind.mean);
wind.speedFinal = norm(wind.final);
end
