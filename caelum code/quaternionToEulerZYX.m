function [rollDeg, pitchDeg, yawDeg] = quaternionToEulerZYX(q)
%QUATERNIONTOEULERZYX Convert scalar-first body-to-nav quaternion to ZYX Euler angles.

arguments
    q (4,1) double
end

q = caelum.normalizeQuaternion(q);
qw = q(1);
qx = q(2);
qy = q(3);
qz = q(4);

sinr_cosp = 2 * (qw*qx + qy*qz);
cosr_cosp = 1 - 2 * (qx^2 + qy^2);
roll = atan2(sinr_cosp, cosr_cosp);

sinp = 2 * (qw*qy - qz*qx);
sinp = min(max(sinp, -1), 1);
pitch = asin(sinp);

siny_cosp = 2 * (qw*qz + qx*qy);
cosy_cosp = 1 - 2 * (qy^2 + qz^2);
yaw = atan2(siny_cosp, cosy_cosp);

rollDeg = rad2deg(roll);
pitchDeg = rad2deg(pitch);
yawDeg = rad2deg(yaw);
end
