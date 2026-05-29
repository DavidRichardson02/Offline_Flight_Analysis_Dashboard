function [xPred, PPred] = predict3DEKF(x, P, accelBody, q, dt, cfg)
%PREDICT3DEKF Predict 3D navigation state using body acceleration and attitude.
arguments
    x (12,1) double
    P (12,12) double
    accelBody (3,1) double
    q (4,1) double
    dt (1,1) double
    cfg struct = caelum.defaultConfig()
end
cfg = caelum.localResolve3DConfig(cfg);

if ~isfinite(dt) || dt < 0
    dt = cfg.kfTs;
end
if ~all(isfinite(accelBody))
    accelBody = zeros(3,1);
end

Rbn = caelum.quaternionToRotationMatrix(q);
aNav = Rbn * accelBody - [0; 0; cfg.gravity];
b = x(7:9);
aEff = aNav - b;

xPred = x;
xPred(1:3) = x(1:3) + x(4:6) * dt + 0.5 * aEff * dt^2;
xPred(4:6) = x(4:6) + aEff * dt;

F = eye(12);
F(1,4) = dt; F(2,5) = dt; F(3,6) = dt;
F(1,7) = -0.5 * dt^2; F(2,8) = -0.5 * dt^2; F(3,9) = -0.5 * dt^2;
F(4,7) = -dt; F(5,8) = -dt; F(6,9) = -dt;

Q = zeros(12);
qAcc = cfg.gpsProcessAccelSigma^2;
for i = 1:3
    ii = i;
    vv = i + 3;
    Q(ii,ii) = 0.25 * dt^4 * qAcc;
    Q(vv,vv) = dt^2 * qAcc;
end
Q(7:9,7:9) = cfg.accelBiasProcessSigma^2 * max(dt, cfg.kfTs) * eye(3);
Q(10:12,10:12) = cfg.windProcessSigma^2 * max(dt, cfg.kfTs) * eye(3);

PPred = F * P * F.' + Q;
PPred = 0.5 * (PPred + PPred.');
PPred(1:13:end) = max(diag(PPred), cfg.kCovarianceFloor);
end
