%% This program aims to automatically download hycom products.
%% Parse inputs
clc;clearvars
aimpath = 'E:\HYCOM-dataset\HYCOM_ChesBay\';

region = [281.5 288 33 41 ]; % ChesBay
timespan = datetime(2019,1,1):hours(3):datetime(2024,1,1);
%% Begin to download
maxTries = 5;
nTimes = numel(timespan);
for iTime = 1:nTimes
    timeTick = timespan(iTime);
    disp(datestr(timeTick, 1)) %#ok<DATST>

    numTries = 0;
    success = false;
    while ~success && numTries < maxTries
        try
            numTries = numTries + 1;
            D = get_hycom_online(aimpath, region, timeTick); %#ok<*NASGU>
            success = true;
        catch ME
            fprintf('Fails to download %d, Error Message: %s\n', numTries, ME.message);
            pause(1);
        end
    end
end
%% END