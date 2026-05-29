function figs = plotMonteCarloSummary(mc)
%PLOTMONTECARLOSUMMARY Canonical V3 Monte Carlo summary for GPS/3D runs.
arguments
    mc struct
end
M = mc.runMetrics;
if ismember("success", string(M.Properties.VariableNames))
    M = M(M.success, :);
end
figs = gobjects(0,1);

if isempty(M)
    figs(end+1) = figure('Name','Monte Carlo Summary','Color','w'); %#ok<AGROW>
    axes('Parent', figs(end));
    text(0.5,0.5,'No successful Monte Carlo runs to summarize.', 'HorizontalAlignment','center', 'FontWeight','bold');
    axis off;
    return;
end

figs(end+1) = figure('Name', 'Monte Carlo Histograms', 'Color', 'w'); %#ok<AGROW>
tiledlayout(2,2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile; histogram(M.rmse_pz); xlabel('RMSE p_z [m]'); ylabel('Count'); title('Altitude RMSE');
nexttile; histogram(M.rmse_vz); xlabel('RMSE v_z [m/s]'); ylabel('Count'); title('Vertical velocity RMSE');
nexttile; histogram(M.gpsAcceptanceRate); xlabel('GPS acceptance rate'); ylabel('Count'); title('GPS acceptance');
nexttile; histogram(M.windError); xlabel('Final wind vector error [m/s]'); ylabel('Count'); title('Wind estimation error');
end
