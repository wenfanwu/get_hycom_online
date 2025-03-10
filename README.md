# get_hycom_online

A MATLAB function to download hycom data easily (1992-10-02 to present)

### New features (9 Mar, 2025)

1. get_hycom_online works for the latest hycom product after 2024-09-04 (ESPC-D-V02).
2. the downloaded file can be saved in NetCDF format.
3. the prefix name of downloaded files can be customized.

## Example-1: Download HYCOM data of a particular moment

```Matlab
clc;clearvars
aimpath = 'E:\data\';
region = [190 240 -5 5]; % Nino3.4
timeTick = datetime(2010,1,1);
varList = {'ssh','temp','salt','uvel','vvel'};    
D = get_hycom_online(aimpath, region, timeTick, varList);
```

## Example-2: Download HYCOM data in netcdf format and customize prefix names

```Matlab
clc;clearvars
aimpath = 'E:\data\';
region = [117.5 122.5 37 41]; % the Bohai Sea
timeTick = datetime(2010,1,1);
varList = {'ssh','temp','salt','uvel','vvel'};
D = get_hycom_online(aimpath, region, timeTick, varList, 'format', 'netcdf', 'prefix', 'bohai_sea');
```

## Example-3: Download HYCOM data in batch

```Matlab
clc;clearvars
aimpath = 'E:\data\';
region = [117.5 122.5 37 41]; % the Bohai Sea
timeList = datetime(2020,1,1):hours(3):datetime(2020,2,1);
varList = {'ssh','temp','salt','uvel','vvel'};

nTimes = numel(timeList);
for iTime = 1:nTimes
    timeTick = timeList(iTime);
    D = get_hycom_online(aimpath, region, timeTick, varList);
end
```

## Example-4: Download data from a specified HYCOM product

```Matlab
clc;clearvars
aimpath = 'E:\data\';
region = [261 280 17.5 32.5]; % the Gulf of Mexico
timeTick = datetime(2010,1,1);
varList = {'ssh','temp','salt','uvel','vvel'};    
URL = 'http://tds.hycom.org/thredds/dodsC/GLBy0.08/expt_93.0?';
D = get_hycom_online(aimpath, region, timeTick, varList, 'URL', URL);
```

## Sample Graph

![avatar](/figures/nino34.png)

## Notes

When a given longitude range includes the longitude boundaries of the original HYCOM product, you need to download it twice separately and splice it together to get the desired data. 

For example, the longitude range of hycom data is [-180 180], but your given longitude range is [150 200].
