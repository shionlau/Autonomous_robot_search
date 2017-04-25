%% Sim Setup
% addpath('/Users/changliu/Documents/MATLAB/Ipopt-3.11.8-linux64mac64win32win64-matlabmexfiles');
% addpath('/Users/changliu/Documents/MATLAB/studentSnopt')
addpath('C:\Program Files\MATLAB\Ipopt-3.11.8')
scale = 0.5; % scale the size of the field
set(0,'DefaultFigureWindowStyle','docked');% docked

sim_len = 50;
dt = 0.5;
plan_mode = 'nl'; % choose the mode of simulation: linear: use KF. nl: use gmm

if strcmp(plan_mode,'lin')
    sensor_type = 'lin'; % rb, ran, br, lin
elseif strcmp(plan_mode,'nl')
    sensor_type = 'rb'; % rb, ran, br, lin
end

inPara_sim = struct('dt',dt,'sim_len',sim_len,'sensor_type',sensor_type,'plan_mode',plan_mode);
sim = Sim(inPara_sim);

save_video = false;

%% Set field %%%
% target info
target.pos = [20;30];
% linear model, used for KF
target.A = eye(2);%[0.99 0;0 0.98];
target.B = [0;0]; %[0.3;-0.3];
% nonlinear model, used for EKF
target.f = @(x) x;
target.del_f = @(x) eye(2);
target.Q = 0.01*eye(2); % Covariance of process noise model for the target
target.model_idx = 1;
target.traj = target.pos;

xLength = 50;%*scale; 
yLength = 50;%*scale; 
xMin = 0;
yMin = 0;
xMax = xMin+xLength;
yMax = yMin+yLength;
grid_step = 0.5; % the side length of a probability cell
inPara_fld = struct('fld_cor',[xMin,xMax,yMin,yMax],'target',target,'dt',dt);
fld = Field(inPara_fld);

%% Set Robot %%%
% Robot
inPara_rbt = struct;
% robot state
inPara_rbt.state = [25;15;pi/4;0];%[40;40;pi/2;0];%;
% input constraint
inPara_rbt.a_lb = -3;
inPara_rbt.a_ub = 1;
inPara_rbt.w_lb = -pi/4;
inPara_rbt.w_ub = pi/4;
inPara_rbt.v_lb = 0;
inPara_rbt.v_ub = 3;
% robot kinematics
inPara_rbt.g = @(z,u) z+u*dt;
inPara_rbt.del_g = @(z,u) z+u*dt;

% sensor
%%% needs further revision
inPara_rbt.sensor_type = sensor_type;
inPara_rbt.theta0 = 60/180*pi;
inPara_rbt.range = 15;%4.5;
if strcmp(sensor_type,'rb')
    % range-bearing sensor
%     inPara_rbt.h = @(x) x-inPara_rbt.state(1:2);
%     inPara_rbt.del_h = @(x) eye(2);
%     inPara_rbt.R = 5*eye(2);
    inPara_rbt.h = @(x,z) x.^2-z.^2; %%%%% change this in the future to be linear, not quadratic
    inPara_rbt.del_h = @(x,z) [2*x(1) 0; 0 2*x(2)]; % z is the robot state.
    inPara_rbt.R = 1*eye(2);
    % inPara_rbt.dist_rb = 20;
elseif strcmp(sensor_type,'ran')
    % % range-only sensor
    % inPara_rbt.C_ran = eye(2);
    % inPara_rbt.R_ran = 5;
    % inPara_rbt.dist_rb = 50;
elseif strcmp(sensor_type,'br')
    % bearing-only sensor
    % inPara_rbt.C_brg = eye(2);
    % inPara_rbt.R_brg = 0.5;
elseif strcmp(sensor_type,'lin')
    % lienar sensor model for KF use
    inPara_rbt.h = @(x,z) x-z; %%%%% change this in the future to be linear, not quadratic
    inPara_rbt.del_h = @(x,z) [1 0; 0 1]; % z is the robot state.
    inPara_rbt.R = 5*eye(2);    
end

% define gamma model
% model parameters
alp1 = 10;
alp2 = 10;
alp3 = 10;
thr = 30;

% the gamma model used in ACC 17
    %{
    gam_den1 = @(z,x0,alp1) (1+alp1*norm(x0-z)^2); %%% this part does not involve range information. revise!
    gam_den2 = @(theta,theta_bar,alp2) (1+exp(alp2*(-cos(theta-theta_bar)+cos(inPara_rbt.theta0))));
    gam_den = @(z,theta,x0,theta_bar,alp1,alp2) (gam_den1(z,x0,alp1)*gam_den2(theta,theta_bar,alp2));
    % exact model
    gam = @(z,theta,x0,theta_bar,alp1,alp2) 1/gam_den(z,theta,x0,theta_bar,alp1,alp2);
    % gradient
    gam_grad = @(z,theta,x0,theta_bar,alp1,alp2) [2*alp1*(x0-z)/(gam_den1(z,x0,alp1)^2*gam_den2(theta,theta_bar,alp2));...
        -alp2*sin(theta-theta_bar)*(gam_den2(theta,theta_bar,alp2)-1)/...
        (gam_den2(theta,theta_bar,alp2)^2*gam_den1(z,x0,alp1))];
    % linearized model
    gam_aprx = @(z,theta,x0,theta_bar,z_ref,theta_ref,alp1,alp2) gam(z_ref,theta_ref,x0,theta_bar,alp1,alp2)...
        +gam_grad(z_ref,theta_ref,x0,theta_bar,alp1,alp2)'*[z-z_ref;theta-theta_ref];
    % linearized update rule for covariance
    p_aprx = @(z,theta,p1,p2,x0,theta_bar,t1,t2,z_ref,theta_ref,p1_ref,p2_ref,alp1,alp2) p1-...
        gam(z_ref,theta_ref,x0,theta_bar,alp1,alp2)*(t1*p1_ref+t2*p2_ref)+...
        (1-gam(z_ref,theta_ref,x0,theta_bar,alp1,alp2)*t1)*(p1-p1_ref)-...
        gam(z_ref,theta_ref,x0,theta_bar,alp1,alp2)*(p2-p2_ref)-(t1*p1_ref+t2*p2_ref)*...
        gam_grad(z_ref,theta_ref,x0,theta_bar,alp1,alp2)'*([z-z_ref;theta-theta_ref]);
    %}

inPara_rbt.alp1 = alp1; % parameters in gam
inPara_rbt.alp2 = alp2;
inPara_rbt.alp3 = alp3;
inPara_rbt.thr = thr; % the threshold to avoid very large exponential function value
inPara_rbt.tr_inc = 5; % increment factor of trust region
inPara_rbt.tr_dec = 1/2; % decrement factor of trust region

% estimation initialization
if strcmp(plan_mode,'lin')
    % KF
    inPara_rbt.est_pos = target.pos+ [5;-5];
    inPara_rbt.P = [100 0; 0 100];
elseif strcmp(plan_mode,'nl')    
    % xKF
    % inPara_rbt.est_pos = bsxfun(@plus,target.pos,[5,-10,10;-0.5,10,-5]);%[30;25];
    % inPara_rbt.P = {[100 0; 0 100];[100 0; 0 100];[100 0; 0 100]};
    
    % GSF
%     inPara_rbt.gmm_num = size(inPara_rbt.est_pos,2);
%     inPara_rbt.wt = ones(inPara_rbt.gmm_num,1)/inPara_rbt.gmm_num;
    % PF
    inPara_rbt.max_gmm_num = 3;
    [X,Y] = meshgrid((xMin+0.5):(xMax-0.5),(yMin+0.5):(yMax-0.5));
    inPara_rbt.particles = [X(:),Y(:)]';
    inPara_rbt.est_pos = target.pos+ [5;-5];
    inPara_rbt.P = {[100 0; 0 100];[100 0; 0 100];[100 0; 0 100]};
end

% planning
inPara_rbt.mpc_hor = 10;%3;
inPara_rbt.dt = dt;

% simulation parameters
inPara_rbt.max_step = sim_len;
% inPara_rbt.gam = 1;
rbt = Robot(inPara_rbt);