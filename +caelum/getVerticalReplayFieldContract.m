function fieldContract = getVerticalReplayFieldContract(contractPath)
%GETVERTICALREPLAYFIELDCONTRACT Load the checked-in replay/firmware field contract.
arguments
    contractPath (1,1) string = localDefaultContractPath()
end

if ~isfile(contractPath)
    error('caelum:getVerticalReplayFieldContract:MissingContract', ...
        'Field contract file not found: %s', contractPath);
end

opts = detectImportOptions(contractPath, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
fieldContract = readtable(contractPath, opts);
textColumns = ["domain","source_name","export_name","units","type","notes"];
for k = 1:numel(textColumns)
    name = textColumns(k);
    if ismember(name, string(fieldContract.Properties.VariableNames))
        fieldContract.(char(name)) = string(fieldContract.(char(name)));
    end
end

logicalColumns = ["required_for_firmware","parity_checked"];
for k = 1:numel(logicalColumns)
    name = logicalColumns(k);
    if ~ismember(name, string(fieldContract.Properties.VariableNames))
        continue;
    end
    values = fieldContract.(char(name));
    if islogical(values)
        continue;
    end
    fieldContract.(char(name)) = strcmpi(string(values), "true");
end
end

function contractPath = localDefaultContractPath()
packageDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(packageDir);
contractPath = fullfile(repoRoot, 'vertical_replay_field_contract.csv');
end
