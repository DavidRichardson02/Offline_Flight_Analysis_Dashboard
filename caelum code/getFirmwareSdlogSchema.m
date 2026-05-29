function schema = getFirmwareSdlogSchema(schemaPath)
%GETFIRMWARESDLOGSCHEMA Load the checked-in firmware SD log schema reference.
arguments
    schemaPath (1,1) string = localDefaultSchemaPath()
end

if ~isfile(schemaPath)
    error('caelum:getFirmwareSdlogSchema:MissingSchema', ...
        'Firmware SD log schema file not found: %s', schemaPath);
end

opts = detectImportOptions(schemaPath, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
schema = readtable(schemaPath, opts);
schema.field = string(schema.field);
schema.units = string(schema.units);
schema.type = string(schema.type);
schema.notes = string(schema.notes);

if islogical(schema.required)
    return;
end
schema.required = strcmpi(string(schema.required), "true");
end

function schemaPath = localDefaultSchemaPath()
packageDir = fileparts(mfilename('fullpath'));
repoRoot = fileparts(packageDir);
schemaPath = fullfile(repoRoot, 'firmware_sdlog_schema.csv');
end
