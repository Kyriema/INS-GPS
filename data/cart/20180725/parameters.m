  % --------------- Parameters ---------------
num_epochs_static= 20000; % default (10000) --Osama-- Number of epochs the cart is static initially 20000
lidarRange= 25; % [m]
m_F= 2; % measurements per feature/landmark
dt_imu= 1/125; % IMU sampling time
dt_cal= 1/10; % KF Update period during initial calibration
dt_virt_z= 1/10; % Virtual msmt update period
dt_virt_y= 1/10; % Virtual msmt update period
sig_cal_pos= 0.005; % 3cm   -- do not reduce too much or bias get instable
sig_cal_vel= 0.005; % 3cm/s -- do not reduce too much or bias get instable
sig_cal_E= deg2rad(0.1); % 0.1 deg
sig_yaw0= deg2rad(5); % 5 deg -- Initial uncertatinty in attitude
sig_phi0= deg2rad(1); % 2 deg -- Initial uncertatinty in attitude
sig_ba= 0.05; % 0.1 m/s2 -- Initial acc bias uncertainty
sig_bw= deg2rad(0.1); % 0.2 deg/s -- Initial gyros bias uncertainty
sig_virt_vz= 0.01; % 5cm/s -- virtual msmt SD in z
sig_virt_vy= 0.01; % 5cm/s -- virtual msmt SD in y
sig_lidar= 0.3; % 20cm -- lidar measurement in the nav frame
min_vel_gps= 2/3.6; % 2 km/h
min_vel_yaw= 2/3.6; % 2 km/h
taua_normal_operation= 3000; % Tau for acc bias -- from manufacturer
tauw_normal_operation= 3000; % Tau for gyro bias -- from manufacturer
taua_calibration= 100; % 200 acc tau value during initial calibration
tauw_calibration= 100; % 200 gyro tau value during initial calibration
g_val= 9.80279; % value of g [m/s2] at the IIT
r_IMU2rearAxis= 0.9; % distance from IMU to rear axis
alpha_NN= 0.05; % prob of discard good features in NN
threshold_new_landmark= 15; % Threshold in NIS to create a new landmark
sig_minLM= 0.1; % minimum SD for the landmarks
mult_factor_acc_imu= 30; % multiplicative factor for the accel SD
mult_factor_gyro_imu= 30; % multiplicative factor for the gyros SD
mult_factor_pose_gps= 3; % multiplicative factor for the GPS pose SD
mult_factor_vel_gps= 20;  % multiplicative factor for the GPS velocity SD
feature_height= 1.5; % height of the features
initial_yaw_angle= -90; % [deg] initial yaw angle (different for each experiment) % smooth_turn(180)
preceding_horizon_size= 2;
continuity_requirement= 1e-5;
alert_limit= 1;
% -------------------------------------------