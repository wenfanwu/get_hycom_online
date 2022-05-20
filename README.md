# get_hycom_online
A MATLAB function to download hycom data easily

```Matlab
%% Example-1: Download HYCOM data at a particular moment
clc;clearvars
aimpath = 'E:/data/';
region = [190 240 -5 5]; % Nino3.4
timeTick = datetime(2010,1,1);
varList = {'ssh','temp','salt','u','v'};    
D = get_hycom_online(aimpath, region, timeTick, varList);
```

```Matlab
%% Example-2: Download HYCOM data in bulk
clc;clearvars
aimpath = 'E:/data/';
region = [117.5 122.5 37 41]; % the Bohai Sea
timeList = datetime(2020,1,1):hours(3):datetime(2020,2,1);
varList = {'ssh','temp','salt','u','v'};

nTimes = numel(timeList);
for iTime = 1:nTimes
    timeTick = timeList(iTime);
    D = get_hycom_online(aimpath, region, timeTick, varList);
end
```

```Matlab
%% Example-3: Download data from a specified HYCOM product
 clc;clearvars
 aimpath = 'E:/data/';
 region = [261 280 17.5 32.5]; % the Gulf of Mexico
 timeTick = datetime(2010,1,1);
 varList = {'ssh','temp','salt','u','v'};    
 URL = 'http://tds.hycom.org/thredds/dodsC/GLBy0.08/expt_93.0?';
 D = get_hycom_online(aimpath, region, timeTick, varList, URL);
```
