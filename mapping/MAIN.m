
clear; format short; clc; close all;
dbstop if error

addpath('../utils/')

% create objects
params= ParametersClass();
gps= GPSClass(params.numEpochStatic * params.dT_IMU, params);
lidar= LidarClass(params, gps.timeInit);
imu= IMUClass(params, gps.timeInit);
estimator= EstimatorClass(imu.msmt(1:3, params.numEpochInclCalibration), params);
data_obj= DataClass(imu.num_readings);


% Initialize loop variables
timeSum= 0;
timeSumVirt_Z= 0;
timeSumVirt_Y= 0;
timeGPS= gps.time(1); % this is zero, as the GPS time is the reference
timeLIDAR= lidar.time(1,2);
k_update= 1;
k_GPS= 1;
k_LIDAR= 1;
taua= params.taua_calibration;
tauw= params.tauw_calibration;
GPS_Index_exceeded = 0;
LIDAR_Index_exceeded = 0;

% Initial discretization for cov. propagation
estimator.linearize_discretize( imu.msmt(:,1), params.S_cal, taua, tauw, params.dT_IMU );

% ----------------------------------------------------------
% -------------------------- LOOP --------------------------
for k= 1:imu.num_readings-1
    disp(strcat('Epoch -> ', num2str(k)));
    
    % set the simulation time to the IMU time
    timeSim= imu.time(k);
    
    % Turn off GPS updates if start moving
    if k == params.numEpochStatic
        params.SWITCH_CALIBRATION= 0; 
        estimator.PX(7,7)= params.sig_phi0^2;
        estimator.PX(8,8)= params.sig_phi0^2;
        estimator.PX(9,9)= params.sig_yaw0^2;
        taua= params.taua0;
        tauw= params.tauw0;
    end
        
    % Increase time count
    timeSum= timeSum + params.dT_IMU;
    timeSumVirt_Z= timeSumVirt_Z + params.dT_IMU;
    timeSumVirt_Y= timeSumVirt_Y + params.dT_IMU;
    
    % ------------- IMU -------------
    estimator.imu_update( imu.msmt(:,k), taua, tauw, params );
    % -------------------------------
    
    % Store data
    data_obj.store_prediction(k, estimator, timeSim);
    
    % ------------- Calibration -------------
    if timeSum >= params.dT_cal && params.SWITCH_CALIBRATION
        
        % create a fake msmt and make a KF update
        msmt= [zeros(6,1); estimator.initial_attitude];
        estimator.calibration(msmt, params.H_cal, params.R_cal); % Kf update
        
        % linearize and discretize after every non-IMU update
        estimator.linearize_discretize( imu.msmt(:,k), params.S_cal, taua, tauw, params.dT_IMU);
        
        % If GPS is calibrating initial biases, increse bias variance
        estimator.D_bar(10:12,10:12)= estimator.D_bar(10:12,10:12) +...
            diag( [params.sig_ba,params.sig_ba,params.sig_ba] ).^2;
        estimator.D_bar(13:15,13:15)= estimator.D_bar(13:15,13:15) +...
            diag( [params.sig_bw,params.sig_bw,params.sig_bw] ).^2;
        
        % Store data
        k_update= data_obj.store_update(k_update, estimator, timeSim);

        % Reset counter
        timeSum= 0;
    end
    % ------------------------------------
    
    % ------------- virtual msmt update >> Z vel  -------------  
    if timeSumVirt_Z >= params.dT_virt_Z && params.SWITCH_VIRT_UPDATE_Z && ~params.SWITCH_CALIBRATION
        
        zVelocityUpdate( params.R_virt_Z);
        
        % Reset counter
        timeSumVirt_Z= 0;
    end
    % ---------------------------------------------------------
    
    % ------------- virtual msmt update >> Y vel  -------------  
    if timeSumVirt_Y >= params.dT_virt_Y && params.SWITCH_VIRT_UPDATE_Y && ~params.SWITCH_CALIBRATION
         
        % Yaw update
        if params.SWITCH_YAW_UPDATE && norm(estimator.XX(4:6)) > params.minVelocityYaw
            disp('yaw udpate');
            estimator.yaw_update(...
                imu.msmt(4:6,k), params.R_yaw_fn( norm(estimator.XX(4:6))), params.r_IMU2rearAxis );
        end
        
        % Reset counter
        timeSumVirt_Y= 0;
    end
    % ---------------------------------------------------------
    
    
    % ------------------- GPS -------------------
    if (timeSim + params.dT_IMU) > timeGPS && ~GPS_Index_exceeded
        
        if ~params.SWITCH_CALIBRATION && params.SWITCH_GPS_UPDATE
            % GPS update -- only use GPS vel if it's fast
            estimator.gps_update( gps.msmt(:,k_GPS), gps.R(:,k_GPS), params);
            
            % Yaw update
            if params.SWITCH_YAW_UPDATE && norm(estimator.XX(4:6)) > params.minVelocityYaw
                disp('yaw udpate');
                estimator.yaw_update(...
                   imu.msmt(4:6,k), params.R_yaw_fn( norm(estimator.XX(4:6))), params.r_IMU2rearAxis );
            end
            estimator.linearize_discretize( imu.msmt(:,k),params.S,taua,tauw,params.dT_IMU);

            % Store data
            k_update= data_obj.store_update(k_update, estimator, timeSim);
        end
        
        % Time GPS counter
        k_GPS= k_GPS + 1;
        
        % -----Osama----- TODO: Osama what is this??
        if k_GPS <= size(gps.time,1)
            timeGPS= gps.time(k_GPS);
        else
           k_GPS = k_GPS -1 ;
           GPS_Index_exceeded = 1;
        end
    end
    % ----------------------------------------
    
    % ------------- LIDAR -------------
    if (timeSim + params.dT_IMU) > timeLIDAR && params.SWITCH_LIDAR_UPDATE
        
        if k > params.numEpochStatic + 1500 % TODO: osama, why are you adding 1500
            % Read the lidar features
            epochLIDAR= lidar.time(k_LIDAR,1);
            lidar.get_msmt( epochLIDAR, params );
            
            % Remove people-features for the data set 
            for i= 1:size(lidar.areas_to_remove,1)
                lidar.remove_features_in_area(estimator.XX(1:9), lidar.areas_to_remove(i,:));
            end
                        
            % NN data association
            [association]= estimator.nearest_neighbor(lidar.msmt(:,1:2), params);
            
            % Lidar update
            estimator.lidarUpdate(lidar.msmt(:,1:2), association, ...
                params.R_lidar, params.SWITCH_CALIBRATION);

            % Increase landmark covariance to the minimum
            estimator.increase_landmarks_cov(params.R_minLM);
            
            % Add new landmarks
            estimator.addNewLM( lidar.msmt(association' == -1,:), params.R_lidar );
            
            % Lineariza and discretize
            estimator.linearize_discretize( imu.msmt(:,k), params.S, taua, tauw, params.dT_IMU);
            
            % Store data
            % Add the current msmts in Nav-frame to plot
            data_obj.store_msmts( body2nav(lidar.msmt, estimator.XX(1:9)) );
            k_update= data_obj.store_update(k_update, estimator, timeSim);
        end
        
        % Increase counters
        k_LIDAR= k_LIDAR + 1;
        
        % -----Osama----- TODO: osama, what is this again?
        if k_LIDAR <= length(lidar.time)
            timeLIDAR= lidar.time(k_LIDAR,2);
        else
           k_LIDAR = k_LIDAR -1 ;
           LIDAR_Index_exceeded = 1;
        end
    end
    % ---------------------------------
    
end

% Store data for last epoch
data_obj.store_update(k_update, estimator, timeSim);
% ------------------------- END LOOP -------------------------
% ------------------------------------------------------------

% remove extra allocated space 
data_obj.update.XX(:, k_update+1:end)= [];
data_obj.update.PX(:, k_update+1:end)= [];
data_obj.update.time(k_update+1:end)= [];


% ------------- PLOTS -------------
data_obj.plot_map(gps, imu.num_readings, params)
data_obj.plot_estimates();
% ------------------------------------------------------------


% timeComplete= 0:params.dT_IMU:timeSim+params.dT_IMU/2;
% timeMove= timeComplete(params.numEpochStatic:end);

% % Plot estimates
% figure; hold on;
% 
% subplot(3,3,1); hold on; grid on;
% plot(timeComplete,DATA.pred.XX(1,:));
% ylabel('x [m]');
% 
% subplot(3,3,2); hold on; grid on;
% plot(timeComplete,DATA.pred.XX(2,:));
% ylabel('y [m]');
% 
% subplot(3,3,3); hold on; grid on; 
% plot(timeComplete,DATA.pred.XX(3,:))
% ylabel('z [m]');
% 
% subplot(3,3,4); hold on; grid on;
% plot(timeComplete,DATA.pred.XX(4,:))
% ylabel('v_x [m/s]');
% 
% subplot(3,3,5); hold on; grid on;
% plot(timeComplete,DATA.pred.XX(5,:))
% ylabel('v_y [m/s]');
% 
% subplot(3,3,6); hold on; grid on;
% plot(timeComplete,DATA.pred.XX(6,:));
% ylabel('v_z [m/s]');
% 
% subplot(3,3,7); hold on; grid on;
% plot(timeComplete,rad2deg(DATA.pred.XX(7,:)))
% ylabel('\phi [deg]');
% 
% subplot(3,3,8); hold on; grid on;
% plot(timeComplete,rad2deg(DATA.pred.XX(8,:)))
% ylabel('\theta [deg]');
% 
% subplot(3,3,9); hold on; grid on;
% plot(timeComplete,rad2deg(DATA.pred.XX(9,:)))
% ylabel('\psi [deg]');


% % Plot variance estimates
% SD= sqrt( data_obj.update.PX(:,1:k_update) );
% update_time= data_obj.update.time(1:k_update);
% 
% % Plot SD -- pose
% figure; hold on; title('Standard Deviations');
% 
% subplot(3,3,1); hold on; grid on;
% plot(update_time, SD(1,:),'b-','linewidth',2);
% ylabel('x [m]');
% 
% subplot(3,3,2); hold on; grid on;
% plot(update_time, SD(2,:),'r-','linewidth',2);
% ylabel('y [m]');
% 
% subplot(3,3,3); hold on; grid on;
% plot(update_time, SD(3,:),'g-','linewidth',2);
% ylabel('z [m]');
% 
% subplot(3,3,4); hold on; grid on;
% plot(update_time, SD(4,:),'b-','linewidth',2);
% ylabel('v_x [m/s]');
% 
% subplot(3,3,5); hold on; grid on;
% plot(update_time, SD(5,:),'r-','linewidth',2);
% ylabel('v_y [m/s]');
% 
% subplot(3,3,6); hold on; grid on;
% plot(update_time, SD(6,:),'g-','linewidth',2);
% ylabel('v_z [m/s]');
% 
% subplot(3,3,7); hold on; grid on;
% plot(update_time, rad2deg(SD(7,:)),'b-','linewidth',2);
% ylabel('\phi [deg]'); xlabel('Time [s]');
% 
% subplot(3,3,8); hold on; grid on;
% plot(update_time, rad2deg(SD(8,:)),'r-','linewidth',2);
% ylabel('\theta [deg]'); xlabel('Time [s]');
% 
% subplot(3,3,9); hold on; grid on;
% plot(update_time, rad2deg(SD(9,:)),'g-','linewidth',2);
% ylabel('\psi [deg]'); xlabel('Time [s]');






% % Plot SD -- Biases
% figure; hold on;
% 
% subplot(2,3,1); hold on; grid on;
% plot(update_time, SD(10,:),'b-','linewidth',2);
% ylabel('a_x');
% 
% subplot(2,3,2); hold on; grid on;
% plot(update_time, SD(11,:),'r-','linewidth',2);
% ylabel('a_y');
% 
% subplot(2,3,3); hold on; grid on;
% plot(update_time, SD(12,:),'g-','linewidth',2);
% ylabel('a_z');
% 
% subplot(2,3,4); hold on; grid on;
% plot(update_time, SD(13,:),'b--','linewidth',2);
% ylabel('w_x'); xlabel('Time [s]')
% 
% subplot(2,3,5); hold on; grid on;
% plot(update_time, SD(14,:),'r--','linewidth',2);
% ylabel('w_y'); xlabel('Time [s]')
% 
% subplot(2,3,6); hold on; grid on;
% plot(update_time, SD(15,:),'g--','linewidth',2);
% ylabel('w_z'); xlabel('Time [s]')


% % Plot biases
% figure; hold on; grid on; title('biases in accelerometers');
% plot(timeComplete, DATA.pred.XX(10,:), 'linewidth',2)
% plot(timeComplete, DATA.pred.XX(11,:), 'linewidth',2)
% plot(timeComplete, DATA.pred.XX(12,:), 'linewidth',2)
% ylabel('m/s^2')
% legend('x','y','z')
% 
% figure; hold on; grid on; title('biases in gyros');
% plot(timeComplete, rad2deg(DATA.pred.XX(13,:)), 'linewidth',2)
% plot(timeComplete, rad2deg(DATA.pred.XX(14,:)), 'linewidth',2)
% plot(timeComplete, rad2deg(DATA.pred.XX(15,:)), 'linewidth',2)
% ylabel('deg');
% legend('w_x','w_y','w_z')


% % Plot GPS positions
% figure; hold on; grid on; title('GPS positions');
% plot(1:gps.num_readings, gps.msmt(1,:), 'linewidth',2)
% plot(1:gps.num_readings, gps.msmt(2,:), 'linewidth',2)
% plot(1:gps.num_readings, gps.msmt(3,:), 'linewidth',2)
% ylabel('m')
% legend('r_x','r_y','r_z')

% % Plot GPS velocities
% figure; hold on; grid on; title('GPS velocities');
% plot(1:gps.num_readings, gps.msmt(4,:), 'linewidth',2)
% plot(1:gps.num_readings, gps.msmt(5,:), 'linewidth',2)
% plot(1:gps.num_readings, gps.msmt(6,:), 'linewidth',2)
% ylabel('m/s')
% legend('v_x','v_y','v_z')


% % Plot measurements
% figure; hold on; grid on;
% u_ax_filter= filter(ones(1,500)/500,1,u(1,:));
% u_ay_filter= filter(ones(1,500)/500,1,u(2,:));
% plot(timeComplete, u_ax_filter(:));
% plot(timeComplete, u_ay_filter(:));
% legend('accX','accY')









