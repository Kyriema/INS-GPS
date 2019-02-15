
classdef PredictionDataClass < handle
    properties
        XX
        time
    end
    
    methods
        function obj= PredictionDataClass(num_readings, params)
            % allocate memory
            obj.XX= zeros(params.m, num_readings);
            obj.time= zeros(num_readings, 1);
        end
        % ----------------------------------------------
        % ----------------------------------------------
        function store(obj, epoch, estimator, time)
            obj.XX(:,epoch)= estimator.XX(1:15);
            obj.time(epoch)= time;
        end
        % ----------------------------------------------
        % ----------------------------------------------
        function store_sim(obj, epoch, estimator, time)
            obj.XX(:,epoch)= estimator.XX;
            obj.time(epoch)= time;
        end
        % ----------------------------------------------
        % ----------------------------------------------
        function store_FG(obj, epoch, estimator, time)
            obj.XX(:,epoch)= estimator.x_true;
            obj.time(epoch)= time;
        end
        % ----------------------------------------------
        % ----------------------------------------------
        
    end
end


