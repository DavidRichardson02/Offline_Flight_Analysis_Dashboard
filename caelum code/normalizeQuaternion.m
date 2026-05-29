function q = normalizeQuaternion(q, floorValue)
%NORMALIZEQUATERNION Normalize a scalar-first quaternion.

arguments
    q (4,1) double
    floorValue (1,1) double = 1.0e-9
end

qn = norm(q);
if ~isfinite(qn) || qn < floorValue
    q = [1; 0; 0; 0];
    return;
end

q = q / qn;
if q(1) < 0
    q = -q;
end
end
