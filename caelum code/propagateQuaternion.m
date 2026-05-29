function qNext = propagateQuaternion(q, omegaBody, dt)
%PROPAGATEQUATERNION Propagate a body-to-navigation quaternion with body gyro rates.

arguments
    q (4,1) double
    omegaBody (3,1) double
    dt (1,1) double
end

q = caelum.normalizeQuaternion(q);

if ~isfinite(dt) || dt <= 0 || ~all(isfinite(omegaBody))
    qNext = q;
    return;
end

angle = norm(omegaBody) * dt;
if angle < 1.0e-12
    dq = [1; 0; 0; 0];
else
    axis = omegaBody / norm(omegaBody);
    halfAngle = 0.5 * angle;
    dq = [cos(halfAngle); axis * sin(halfAngle)];
end

qNext = localQuatMultiply(q, dq);
qNext = caelum.normalizeQuaternion(qNext);
end

function q = localQuatMultiply(q1, q2)
w1 = q1(1); x1 = q1(2); y1 = q1(3); z1 = q1(4);
w2 = q2(1); x2 = q2(2); y2 = q2(3); z2 = q2(4);

q = [ ...
    w1*w2 - x1*x2 - y1*y2 - z1*z2;
    w1*x2 + x1*w2 + y1*z2 - z1*y2;
    w1*y2 - x1*z2 + y1*w2 + z1*x2;
    w1*z2 + x1*y2 - y1*x2 + z1*w2];
end
