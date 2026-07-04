function [xPred, PPred, predictInfo] = predictVerticalEKF(x, P, a_vertical, dt, cfg)
%PREDICTVERTICALEKF Predict the vertical EKF with bias and drag states.
%
% State:
%   x = [h; v; b_a; beta]
%
% Continuous model:
%   h_dot    = v
%   v_dot    = a_vertical - b_a - beta * v * |v|
%   b_a_dot  = w_b
%   beta_dot = w_beta

arguments
    x (4,1) double
    P (4,4) double
    a_vertical (1,1) double
    dt (1,1) double
    cfg struct = caelum.defaultConfig()
end

if ~isfinite(dt) || dt < 0
    dt = cfg.kfTs;
end

u = 0.0;
accelInputValid = false;
if isfinite(a_vertical)
    u = min(max(a_vertical, -cfg.kMaxAccelInput), cfg.kMaxAccelInput);
    accelInputValid = true;
end

h = x(1);
v = x(2);
b_a = x(3);
beta = min(max(x(4), cfg.kBetaMin), cfg.kBetaMax);

vAbs = abs(v);
vAbsTerm = v * vAbs;
dragAccel = beta * vAbsTerm;
aEff = u - b_a - dragAccel;

dAdv = -2 * beta * vAbs;
dAdb = -1;
dAdBeta = -vAbsTerm;

xPred = zeros(4,1);
xPred(1) = h + v * dt + 0.5 * aEff * dt^2;
xPred(2) = v + aEff * dt;
xPred(3) = b_a;
xPred(4) = beta;

F = eye(4);
F(1,2) = dt + 0.5 * dt^2 * dAdv;
F(1,3) = 0.5 * dt^2 * dAdb;
F(1,4) = 0.5 * dt^2 * dAdBeta;
F(2,2) = 1 + dt * dAdv;
F(2,3) = dt * dAdb;
F(2,4) = dt * dAdBeta;

G = [0.5 * dt^2; dt; 0; 0];
Q = cfg.kSigmaA2 * (G * G.');
Q(3,3) = Q(3,3) + cfg.kSigmaBiasA2 * dt;

betaLearningEnabled = abs(v) >= cfg.kBetaLearningMinVelocity;
if betaLearningEnabled
    Q(4,4) = Q(4,4) + cfg.kSigmaBeta2 * dt;
end

PPred = F * P * F.' + Q;
PPred = localRegularizeCovariance(PPred, cfg.kCovarianceFloor);

xPred(3) = min(max(xPred(3), -cfg.kBiasAMax), cfg.kBiasAMax);
xPred(4) = min(max(xPred(4), cfg.kBetaMin), cfg.kBetaMax);

predictInfo = struct();
predictInfo.accel_input = u;
predictInfo.accel_input_valid = accelInputValid;
predictInfo.accel_effective = aEff;
predictInfo.drag_accel = dragAccel;
predictInfo.beta_learning_enabled = betaLearningEnabled;
predictInfo.Qdiag = diag(Q);
end

function P = localRegularizeCovariance(P, floorValue)
P = 0.5 * (P + P.');
diagP = diag(P);
diagP = max(diagP, floorValue);
P(1:5:end) = diagP;
end
