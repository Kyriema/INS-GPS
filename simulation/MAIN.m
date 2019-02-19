
clear; format short; clc; %close all;
dbstop if error

addpath('../utils/functions')
addpath('../utils/classes')


% create objects
params= ParametersClass("simulation_kf");
im= IntegrityMonitoringClass(params);
estimator= EstimatorClass([], params);
data_obj= DataClass(params.num_epochs_sim, params.num_epochs_sim, params);
counters= CountersClass([], [], params);

% ----------------------------------------------------------
% -------------------------- LOOP --------------------------
for epoch= 1:params.num_epochs_sim
    disp(strcat('Epoch -> ', num2str(epoch)));
     
    % ------------- Odometry -------------
    estimator.odometry_update_sim( params );
    % -------------------------------
    
    % Store data
    data_obj.store_prediction_sim(epoch, estimator, counters.time_sim);
    
    % ------------------- GPS -------------------
    if params.SWITCH_GPS_UPDATE && counters.time_sum >= params.dt_gps
        % GPS update 
        z_gps= estimator.get_gps_msmt_sim(params);
        estimator.gps_update_sim( z_gps, params );
        
        % save GPS measurements
        data_obj.store_gps_msmts(z_gps);
        
        % reset counter for GPS
        counters.reset_time_sum();
    end
    % ----------------------------------------
    
    % ----------------- LIDAR ----------------
    if params.SWITCH_LIDAR_UPDATE
        
        % Simulate lidar feature measurements
        z_lidar= estimator.get_lidar_msmt_sim( params );
        
        % NN data association
        estimator.nearest_neighbor_localization_sim(z_lidar, params);
        
%         % introduce miss-association
%         if estimator.x_true(1) < 70.5
%             for i= 1:length(estimator.association_true)
%                 if estimator.association_true(i) == 4
%                     estimator.association(i)= 6;
%                 elseif estimator.association_true(i) == 6
%                     estimator.association(i)= 0;
%                 elseif estimator.association_true(i) == 5
%                     estimator.association(i)= 0;
%                 elseif estimator.association_true(i) == 7
%                     estimator.association(i)= 5;
%                 end
%             end
%         end

        % Evaluate the probability of mis-associations
        im.prob_of_MA( estimator, params);
        im.P_MA_k(:)= 0;
        
        % Lidar update
        estimator.lidar_update_localization(z_lidar, params);
        
        % integrity monitoring
        im.monitor_integrity(estimator, counters, data_obj, params);
        
        % Add current msmts in Nav-frame
        data_obj.store_msmts( body2nav_2D(z_lidar, estimator.XX, estimator.XX(3)) ); 
        
        % Store data
        counters.k_update=...
            data_obj.store_update_sim(counters.k_update, estimator, counters.time_sim, params);
        
        % increase integrity counter
        counters.increase_integrity_monitoring_counter();
    end
    % -----------------------------------------
    
    % increase time
    counters.increase_time_sum_sim(params);
    counters.increase_time_sim(params);
end
% ------------------------- END LOOP -------------------------
% ------------------------------------------------------------




% Store data for last epoch
data_obj.delete_extra_allocated_memory(counters)


% ------------- PLOTS -------------
data_obj.plot_map_localization_sim(estimator, params.num_epochs_sim, params)
data_obj.plot_number_of_landmarks(params);
% data_obj.plot_number_epochs_in_preceding_horizon(params);
% data_obj.plot_estimates();
data_obj.plot_integrity_risk(params);
% data_obj.plot_MA_probabilities();
data_obj.plot_error(params);
% data_obj.plot_P_H();
data_obj.plot_detector(params);
% ------------------------------------------------------------



