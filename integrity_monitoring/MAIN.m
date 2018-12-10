
clear; format short; clc; close all;
dbstop if error

addpath('../utils/functions')
addpath('../utils/classes')

% create objects
params= ParametersClass();
im= IntegrityMonitoringClass(params);
gps= GPSClass(params.num_epochs_static * params.dt_imu, params);
lidar= LidarClass(params, gps.timeInit);
imu= IMUClass(params, gps.timeInit);
estimator= EstimatorClass(imu.msmt(1:3, params.num_epochs_incl_calibration), params);
data_obj= DataClass(imu.num_readings);
counters= CountersClass(gps, lidar);

GPS_Index_exceeded = 0;   % TODO: osama is this needeed?
LIDAR_Index_exceeded = 0; % TODO: osama is this needeed?

% Initial discretization for cov. propagation
estimator.linearize_discretize( imu.msmt(:,1), params.dt_imu, params );

% ----------------------------------------------------------
% -------------------------- LOOP --------------------------
for epoch= 1:imu.num_readings - 1
    disp(strcat('Epoch -> ', num2str(epoch)));
    
    % set the simulation time to the IMU time
    counters.time_sim= imu.time(epoch);
    
    % Turn off GPS updates if start moving
    if epoch == params.num_epochs_static
        params.SWITCH_CALIBRATION= 0; 
        estimator.PX(7,7)= params.sig_phi0^2;
        estimator.PX(8,8)= params.sig_phi0^2;
        estimator.PX(9,9)= params.sig_yaw0^2;
    end
        
    % Increase time count
    counters.increase_time_sums(params);
    
    % ------------- IMU -------------
    estimator.imu_update( imu.msmt(:,epoch), params );
    % -------------------------------
    
    % Store data
    data_obj.store_prediction(epoch, estimator, counters.time_sim);
    
    % ------------- Calibration -------------
    if counters.time_sum >= params.dt_cal && params.SWITCH_CALIBRATION
        
        % create a fake msmt and do a KF update to set biases 
        estimator.calibration(imu.msmt(:,epoch), params); 
        
        % Store data
        counters.k_update= data_obj.store_update(counters.k_update, estimator, counters.time_sim);
        counters.reset_time_sum();
    end
    % ------------------------------------
    
    % ------------- virtual msmt update >> Z vel  -------------  
    if counters.time_sum_virt_z >= params.dt_virt_z && params.SWITCH_VIRT_UPDATE_Z && ~params.SWITCH_CALIBRATION
        estimator.vel_update_z(params.R_virt_Z);
        counters.reset_time_sum_virt_z();
    end
    % ---------------------------------------------------------
    
    % ------------- virtual msmt update >> Y vel  -------------  
    if counters.time_sum_virt_y >= params.dt_virt_y && params.SWITCH_VIRT_UPDATE_Y && ~params.SWITCH_CALIBRATION
         
        % Yaw update
        if params.SWITCH_YAW_UPDATE && norm(estimator.XX(4:6)) > params.min_vel_yaw
            disp('yaw udpate');
            estimator.yaw_update( imu.msmt(4:6,epoch), params);
        end
        counters.reset_time_sum_virt_y();
    end
    % ---------------------------------------------------------
    
    
    % ------------------- GPS -------------------
    if (counters.time_sim + params.dt_imu) > counters.time_gps && ~GPS_Index_exceeded
        
        if ~params.SWITCH_CALIBRATION && params.SWITCH_GPS_UPDATE
            % GPS update -- only use GPS vel if it's fast
            estimator.gps_update( gps.msmt(:,counters.k_gps), gps.R(:,counters.k_gps), params);
            
            % Yaw update
            if params.SWITCH_YAW_UPDATE && norm(estimator.XX(4:6)) > params.min_vel_yaw
                disp('yaw udpate');
                estimator.yaw_update( imu.msmt(4:6,epoch), params );
            end
            estimator.linearize_discretize( imu.msmt(:,epoch), params.dt_imu, params);

            % Store data
            counters.k_update= data_obj.store_update( counters.k_update, estimator, counters.time_sim );
        end
        
        % Time GPS counter
        counters.increase_gps_counter();
        
        % -----Osama----- TODO: Osama what is this??
        if counters.k_gps <= size(gps.time,1)
            counters.time_gps= gps.time(counters.k_gps);
        else
           counters.k_gps = counters.k_gps -1 ;
           GPS_Index_exceeded = 1;
        end
    end
    % ----------------------------------------
    
    % ------------- LIDAR -------------
    if (counters.time_sim + params.dt_imu) > counters.time_lidar && params.SWITCH_LIDAR_UPDATE
        
        if epoch > params.num_epochs_static + 1500 % TODO: adding 1500 to remove people
            % Read the lidar features
            epochLIDAR= lidar.time(counters.k_lidar,1);
            lidar.get_msmt( epochLIDAR, params );
            
            % Remove people-features for the data set
            lidar.remove_features_in_areas(estimator.XX(1:9));
            
            % NN data association
            association= estimator.nearest_neighbor_localization(lidar.msmt(:,1:2), params);
            
            % Lidar update
            estimator.lidar_update_localization(lidar.msmt(:,1:2), association, params);

            % Lineariza and discretize
            estimator.linearize_discretize( imu.msmt(:,epoch), params.dt_imu, params);
            
            % Store data
            data_obj.store_msmts( body2nav(lidar.msmt, estimator.XX(1:9)) );% Add current msmts in Nav-frame
            counters.k_update= data_obj.store_update(counters.k_update, estimator, counters.time_sim);
        end
        
        % Increase counter
        counters.increase_lidar_counter();
        
        % -----Osama----- TODO: osama, what is this again?
        if counters.k_lidar <= length(lidar.time)
            counters.time_lidar= lidar.time(counters.k_lidar,2);
        else
           counters.k_lidar = counters.k_lidar -1 ;
           LIDAR_Index_exceeded = 1;
        end
    end
    % ---------------------------------
end
% ------------------------- END LOOP -------------------------
% ------------------------------------------------------------




% Store data for last epoch
data_obj.store_update(counters.k_update, estimator, counters.time_sim);
data_obj.remove_extra_allocated_memory(counters.k_update)


% ------------- PLOTS -------------
% data_obj.plot_map(gps, imu.num_readings, params)
data_obj.plot_map_localization(estimator, gps, imu.num_readings, params)
data_obj.plot_estimates();
% ------------------------------------------------------------


