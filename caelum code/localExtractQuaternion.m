function q = localExtractQuaternion(T, k)
%LOCALEXTRACTQUATERNION Extract quaternion from table if present, else identity.
vars = string(T.Properties.VariableNames);
if all(ismember(["q_w","q_x","q_y","q_z"], vars)) && ...
        all(isfinite([T.q_w(k), T.q_x(k), T.q_y(k), T.q_z(k)]))
    q = [T.q_w(k); T.q_x(k); T.q_y(k); T.q_z(k)];
else
    q = [1; 0; 0; 0];
end
q = caelum.normalizeQuaternion(q);
end
