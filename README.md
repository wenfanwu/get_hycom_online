# get_hycom_online
A MATLAB function to download hycom data easily (1992-10-02 to present)

## Updates (25 Sep, 2024)
New features:
1. the coordinat system of returned longitute vector will always follow your provided longitude range (would be [0, 360] or [-180, 180])
2. the function will report an error when provided longitude range hits the longitudinal bound of selected hycom product.

## Example-1: Download HYCOM data of a particular moment
```Matlab
clc;clearvars
aimpath = 'E:/data/';
region = [190 240 -5 5]; % Nino3.4
timeTick = datetime(2010,1,1);
varList = {'ssh','temp','salt','u','v'};    
D = get_hycom_online(aimpath, region, timeTick, varList);
```
## Example-2: Download HYCOM data in bulk
```Matlab
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
## Example-3: Download data from a specified HYCOM product
```Matlab
clc;clearvars
aimpath = 'E:/data/';
region = [261 280 17.5 32.5]; % the Gulf of Mexico
timeTick = datetime(2010,1,1);
varList = {'ssh','temp','salt','u','v'};    
URL = 'http://tds.hycom.org/thredds/dodsC/GLBy0.08/expt_93.0?';
D = get_hycom_online(aimpath, region, timeTick, varList, URL);
```

## Sample Graph
![avatar](/figures/nino34.png)

## Notes
When a given longitude range includes the longitude boundaries of the original HYCOM product, you need to download it twice separately and splice it together to get the desired data. 

For example, the longitude range of hycom data is [-180 180], but your given longitude range is [150 200].
