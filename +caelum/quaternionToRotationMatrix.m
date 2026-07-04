function Rbn = quaternionToRotationMatrix(q)
%QUATERNIONTOROTATIONMATRIX Convert scalar-first body-to-nav quaternion to rotation matrix.
arguments
    q (4,1) double
end
q = caelum.normalizeQuaternion(q);
qw = q(1); qx = q(2); qy = q(3); qz = q(4);
Rbn = [ ...
    1 - 2*(qy^2 + qz^2),   2*(qx*qy - qw*qz),       2*(qx*qz + qw*qy);
    2*(qx*qy + qw*qz),     1 - 2*(qx^2 + qz^2),     2*(qy*qz - qw*qx);
    2*(qx*qz - qw*qy),     2*(qy*qz + qw*qx),       1 - 2*(qx^2 + qy^2)];
end
