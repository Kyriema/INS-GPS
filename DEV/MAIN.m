
clear; format short; clc; close all;

% Parameters
dT_GNSS= 1/10; % KF Update period
dT_IMU= 1/125;
g_val= 9.80279;
numEpochStatic= 20000;
numEpochInclCalibration= round(numEpochStatic/2);
SWITCH_GPS= 1;
sig_GPS_pos= 0.001; % 5cm
sig_GPS_vel= 0.001; % m/s
sig_GPS_E= deg2rad(0.1); % 0.1 deg
sig_E= deg2rad(5); % 5 deg -- Initial uncertatinty in attitude
sig_ba= 0.1; % m/s2 -- Initial acc bias uncertainty
sig_bw= deg2rad(0.1); % 0.1 deg -- Initial gyros bias uncertainty
taua0= 3600; % Tau for acc bias -- from manufacturer
tauw0= 3600; % Tau for gyro bias -- from manufacturer
taua_calibration= 200; % acc tau value during initial calibration
tauw_calibration= 200; % gyro tau value during initial calibration

% --------------- Initial biases ---------------
% Without LPF 125Hz
invC= [ diag([0.994903778878319, 1.000610776153152, 0.995712486712822]), zeros(3);
        zeros(3), eye(3)];
b0= [-0.073230349005496; -0.029256994675470; 0.032181184395398;...
      -0.000971671383361; 0.000168722253567; 0.000040755306224];
iinvC= diag([0.994586564371092, 0.992541425246288, 1.009732096070968]);
ib0= [-0.044470763684614; -0.066164936056311; 0.099883152249655];
% With LPF 125Hz
% invC= [ diag([0.999730138420152, 1.005885117649553 , 0.983767954068044]), zeros(3);
%         zeros(3), eye(3)];
% b0= [-0.021760161883734; 0.020787087269599; -0.089159163008672;...
%       -0.000968802390264; 0.000129944741751; 0.000110380074963];
% ---------------------------------------------

% G estimation
g_N= [0; 0; g_val];

% Build parameters
sig_GPS_pos_blkMAtrix= diag([sig_GPS_pos, sig_GPS_pos, sig_GPS_pos]);
sig_GPS_vel_blkMAtrix= diag([sig_GPS_vel, sig_GPS_vel, sig_GPS_vel]);
sig_GPS_E_blkMAtrix= diag([sig_GPS_E, sig_GPS_E, sig_GPS_E]).^2;
R= blkdiag(sig_GPS_pos_blkMAtrix, sig_GPS_vel_blkMAtrix, sig_GPS_E_blkMAtrix);
% R= [diag([sig_GPS_pos, sig_GPS_pos, sig_GPS_pos]), zeros(3);
%    zeros(3), diag([sig_GPS_vel, sig_GPS_vel, sig_GPS_vel]); ].^2; % GPS noise
H= [eye(9), zeros(9,6)]; % Observation matrix

% IMU -- white noise specs
VRW= 0.07; %
sig_IMU_acc= VRW * sqrt( 2000 / 3600 );
ARW= 0.15; % deg
sig_IMU_gyr= deg2rad( ARW * sqrt( 2000 / 3600 ) ); % rad
V= diag([sig_IMU_acc; sig_IMU_acc; sig_IMU_acc; sig_IMU_gyr; sig_IMU_gyr; sig_IMU_gyr]).^2;
Sv= V * dT_IMU; % Convert to PSD

% Biases -- PSD of white noise
sn_f= ( 0.05 * 9.80279 / 1000 )^2; Sn_f= diag([sn_f, sn_f, sn_f]);
sn_w= ( deg2rad(0.3/3600) )^2;     Sn_w= diag([sn_w, sn_w, sn_w]);
Sn= blkdiag(Sn_f, Sn_w);

% PSD for continuous model
S= blkdiag(Sv, Sn);
S= S*0;

% ---------------- Read data ----------------
file= strcat('../DATA_MOVE/1longline_cart_125Hz_LPF262/20180405_1.txt');

[~, gyrox, gyroy, gyroz, accx, accy, accz,...
    incx, incy, incz, gyroSts, accSts, ~, ~, ~, ~]= DataRead(file); % rads
% -------------------------------------------

% Set paramters
iu= [incx, incy, incz]';
u= [accx, accy, accz, gyrox, gyroy, gyroz]';
N_IMU= length(accx);
N_GNSS= round( N_IMU*dT_IMU / dT_GNSS );

% Rotation to nav frame (NED)
R_NB= R_NB_rot(0,deg2rad(180),0);
R_NB_init= blkdiag(R_NB,R_NB);

% calibrate with constant bias and scale factor
iu= (iinvC * iu) - ib0;
u= (invC * u) - b0;
% u= R_NB_init * u;

% Initial attitude from inclinometers
[phi0, theta0]= initial_attitude(iu(:,numEpochInclCalibration));

% Allocate variables
P_store= zeros(15, N_GNSS);
P_store_time= zeros(1,N_GNSS);
x= zeros(15,N_IMU);

% Initialize estimate
P= zeros(15); 
% P(7:9,7:9)= diag( [sig_E,sig_E,sig_E] ).^2;
P(10:12,10:12)= diag( [sig_ba,sig_ba,sig_ba] ).^2;
P(13:15,13:15)= diag( [sig_bw,sig_bw,sig_bw] ).^2;
x(7,1)= phi0;
x(8,1)= theta0;

% Initialize loop variables
timeSim= 0;
timeSum= 0;
k_update= 1;
taua= taua_calibration;
tauw= tauw_calibration;

% Compute the F and G matrices (linear continuous time)
[F,G]= FG_fn(u(1,1),u(2,1),u(3,1),u(5,1),u(6,1),...
             x(7,1),x(8,1),x(9,1),x(10,1),x(11,1),x(12,1),x(14,1),x(15,1),taua,tauw);

% Discretize system for IMU (only for variance calculations)
[Phi,D_bar]= discretize(F, G, H, S, dT_IMU);

% --------------------- LOOP ---------------------
for k= 1:N_IMU-1
    
    % Turn off GPS updates if start moving
    if k > numEpochStatic
        SWITCH_GPS= 0; 
        taua= taua0;
        tauw= tauw0;
    end
    
    % Increase time count
    timeSim= timeSim + dT_IMU;
    timeSum= timeSum + dT_IMU;
    
    % Update position mean
    x(:,k+1)= IMU_update(x(:,k),u(:,k),g_N,taua, tauw,dT_IMU);
    
    % Update cov matrix
    P= Phi*P*Phi' + D_bar;
    
    % KF update
    if timeSum >= dT_GNSS
        
        % Compute the F and G matrices (linear continuous time)
        [F,G]= FG_fn(u(1,k),u(2,k),u(3,k),u(5,k),u(6,k),...
            x(7,k+1),x(8,k+1),x(9,k+1),x(10,k+1),x(11,k+1),x(12,k+1),x(14,k+1),x(15,k+1),taua,tauw);
        
        % Discretize system for IMU time (only for variance calculations)
        [Phi,D_bar]= discretize(F, G, H, S, dT_IMU);
        
        if SWITCH_GPS
            L= P*H' / (H*P*H' + R);
            z= [zeros(6,1); phi0; theta0; 0];
            z_hat= H*x(:,k+1);
            innov= z - z_hat;
            x(:,k+1)= x(:,k+1) + L*innov;
            P= P - L*H*P;
            
            % If GPS is calibrating initial biases, increse bias variance
            D_bar(10:12,10:12)= D_bar(10:12,10:12) + diag( [sig_ba,sig_ba,sig_ba] ).^2;
            D_bar(13:15,13:15)= D_bar(13:15,13:15) + diag( [sig_bw,sig_bw,sig_bw] ).^2;
        end
        
        % Store cov matrix
        P_store(:,k_update) = diag(P);
        P_store_time(k_update)= timeSim;
        
        % Time counters
        timeSum= 0;
        k_update= k_update+1;
    end
    
end
% Store final variance
P_store(:, k_update)= diag(P);
P_store_time(k_update)= timeSim;
% --------------------- END LOOP ---------------------

x_time= 0:dT_IMU:timeSim+dT_IMU/2;


% Plot estimates
figure; hold on; grid on;
plot3(x(1,:),x(2,:),x(3,:),'b.');
xlabel('x [m]'); ylabel('y [m]'); zlabel('z [m]');
axis equal

% Plot estimates
figure; hold on;

subplot(3,3,1); hold on;
plot(x_time,x(1,:));
ylabel('x [m]');

subplot(3,3,2); hold on;
plot(x_time,x(2,:));
ylabel('y [m]');

subplot(3,3,3); hold on;
plot(x_time,x(3,:))
ylabel('z [m]');

subplot(3,3,4); hold on;
plot(x_time,x(4,:))
ylabel('v_x [m/s]');

subplot(3,3,5); hold on;
plot(x_time,x(5,:))
ylabel('v_y [m/s]');

subplot(3,3,6); hold on;
plot(x_time,x(6,:));
ylabel('v_z [m/s]');

subplot(3,3,7); hold on;
plot(x_time,rad2deg(x(7,:)))
ylabel('\phi [deg]');

subplot(3,3,8); hold on;
plot(x_time,rad2deg(x(8,:)))
ylabel('\theta [deg]');

subplot(3,3,9); hold on;
plot(x_time,rad2deg(x(9,:)))
ylabel('\psi [deg]');


figure; hold on; grid on; title('biases in accelerometers');
plot(x_time, x(10,:), 'linewidth',2)
plot(x_time, x(11,:), 'linewidth',2)
plot(x_time, x(12,:), 'linewidth',2)
ylabel('m/s^2')
legend('x','y','z')

figure; hold on; grid on; title('biases in gyros');
plot(x_time, rad2deg(x(13,:)), 'linewidth',2)
plot(x_time, rad2deg(x(14,:)), 'linewidth',2)
plot(x_time, rad2deg(x(15,:)), 'linewidth',2)
ylabel('deg');
legend('w_x','w_y','w_z')



SD= sqrt(P_store(:,1:k_update));
P_store_time= P_store_time(1:k_update);

% figure; hold on; grid on;
% % plot(x_time, x(1,:), 'linewidth',2);
% plot(P_store_time, SD(1,:),'b-','linewidth',2);
% plot(P_store_time, -SD(1,:),'b-','linewidth',2);



% figure; hold on; grid on;
% plot(x_time, x(1,:), 'linewidth',2);
% ylabel('x [m]');
% 
% figure; hold on; grid on;
% plot(x_time, x(2,:), 'linewidth',2);
% ylabel('y [m]');
% 
% figure; hold on; grid on;
% plot(x_time, x(3,:), 'linewidth',2);
% ylabel('z [m]');

%{
% Plots
subplot(3,3,1); hold on;
plot(P_store_time, SD(1,:), 'r.')
plot(P_store_time, -SD(1,:), 'r.')

subplot(3,3,2); hold on;
plot(P_store_time, SD(2,:), 'r.')
plot(P_store_time, -SD(2,:), 'r.')

subplot(3,3,3); hold on;
plot(P_store_time, SD(3,:), 'r.')
plot(P_store_time, -SD(3,:), 'r.')

subplot(3,3,4); hold on;
plot(P_store_time, SD(4,:), 'r.')
plot(P_store_time, -SD(4,:), 'r.')

subplot(3,3,5); hold on;
plot(P_store_time, SD(5,:), 'r.')
plot(P_store_time, -SD(5,:), 'r.')

subplot(3,3,6); hold on;
plot(P_store_time, SD(6,:), 'r.')
plot(P_store_time, -SD(6,:), 'r.')

subplot(3,3,7); hold on;
plot(P_store_time,rad2deg(x(7,1) + SD(7,:)), 'r.')
plot(P_store_time,rad2deg(x(7,1) - SD(7,:)), 'r.')

subplot(3,3,8); hold on;
plot(P_store_time,rad2deg(x(8,1) + SD(8,:)), 'r.')
plot(P_store_time,rad2deg(x(8,1) - SD(8,:)), 'r.')

subplot(3,3,9); hold on;
plot(P_store_time,rad2deg(SD(9,:)), 'r.')
plot(P_store_time,-rad2deg(SD(9,:)), 'r.')
%}



