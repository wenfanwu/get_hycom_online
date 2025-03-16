function D = get_hycom_online(aimpath, region, timeTick, varList, varargin)
% Download the hycom data in a flexible way
%
%% Syntax
% D = get_hycom_online(aimpath, region, timeTick)
% D = get_hycom_online(aimpath, region, timeTick, varList)
% D = get_hycom_online(aimpath, region, timeTick, varList, varargin)
%
%% Description
% D = get_hycom_online(aimpath, region, timeTick) downloads hycom data of a
%       particular moment and region, then saves them into a specified folder.
% D = get_hycom_online(aimpath, region, timeTick, varList) specifies the
%       required variables. 
% D = get_hycom_online(aimpath, region, timeTick, varList, varargin) specifies
%       the hycom product, file format or prefix name.
%
%% Example-1: Download HYCOM data of a particular moment
% clc;clearvars
% aimpath = 'E:/data/';
% region = [190 240 -5 5]; % Nino3.4
% % region = [160 210 -5 5]; % Niño 4 
% timeTick = datetime(2010,1,1);
% varList = {'ssh','temp','salt','uvel','vvel'};
% D = get_hycom_online(aimpath, region, timeTick, varList);
%
%% Example-2: Download HYCOM data in netcdf format and customize prefix names
% clc;clearvars
% aimpath = 'E:\data\';
% region = [117.5 122.5 37 41]; % the Bohai Sea
% timeTick = datetime(2010,1,1);
% varList = {'ssh','temp','salt','uvel','vvel'};
% D = get_hycom_online(aimpath, region, timeTick, varList, 'format', 'netcdf', 'prefix', 'bohai_sea');
%
%% Example-3: Download HYCOM data in batch
% clc;clearvars
% aimpath = 'E:\data\';
% region = [117.5 122.5 37 41]; % the Bohai Sea
% timeList = datetime(2020,1,1):hours(3):datetime(2020,2,1);
% varList = {'ssh','temp','salt','uvel','vvel'};
%
% nTimes = numel(timeList);
% for iTime = 1:nTimes
%     timeTick = timeList(iTime);
%     D = get_hycom_online(aimpath, region, timeTick, varList);  
% end
%
%% Example-4: Download data from a specified HYCOM product
% clc;clearvars
% aimpath = 'E:\data\';
% region = [261 280 17.5 32.5]; % the Gulf of Mexico
% timeTick = datetime(2010,1,1);
% varList = {'ssh','temp','salt','uvel','vvel'};
% URL = 'http://tds.hycom.org/thredds/dodsC/GLBy0.08/expt_93.0?';
% D = get_hycom_online(aimpath, region, timeTick, varList, 'URL', URL);
%
%% Input Arguments
% aimpath - the storage folder; string;
%       the folder where the hycom data is stored. It doesn't matter
%       whether the folder name ends with a backslash. 
% region - the region of interest; numeric;
%       the region of interest. region = [lon_west, lon_east, lat_south, lat_north];
%       the longitude can be in [0, 360] or [-180,180], while latitude must be in [-80, 80]. 
% timeTick - the time moment; datetime;
%       the specified time moment with datetime format. e.g., timeTick = datetime(2010,1,1); 
% varList - variable list; cell/string;
%       the requested variable list, default: varList = {'ssh','temp','salt','uvel','vvel'}; 
% varargin - options; char
%       three options available in this function (case-insensitive):
%       1) 'URL' - the URL of specified hycom product. see the bottom of this
%           function to find the URLs for different products. 
%       2) 'format' - the format of downloaded file (netcdf or mat). the
%           default format is 'mat', you can set 'format' as 'netcdf' or 'nc'
%           to save the file as NetCDF.
%       3) 'prefix' - the prefix name of downloaded files; the prefix file
%           name is automatically created by the required region by default.
%
%% Output Arguments
% D - the returned data; datastruct;
%       a datastruct containing all the variables you need. Note that the
%       dev_time field means the deviation (in hours) between the actual
%       time of the downloaded data and your specified time. 
%
%% Notes
% Three things to note before you use this function:
%
% (1) this function aims to download the hycom data of a particular moment,
% and it will search the hycom data at the nearest moment relative to your
% given time.
%
% (2) before downloading, this function will check if you have ever made
% the same request, if so, it will load the available one directly.
%
% (3) this function integrates 14 types of hycom products, all of which
% have latitude vectors from -80 to 80. However, there are 9 products
% whose longitude vectors are from 0 to 360, whereas those of the other 5
% products are from -180 to 180 (see the bottom of this function). If the
% provided region crosses the longitudinal boundaries of selected hycom
% product, this function will automatically splice the west and east parts
% together to get your desired data. 
%
%% Tips
% The network of HYCOM website seems to be unstable, so it may take
% a long time to download data sometimes, or encountered netCDF errors,
% just re-run the function in this case.
%
% What if the HYCOM data of the particular time is missing? You can increase
% the 'tole_time' parameter at Line 196 to replace missing data with data on
% adjacent days. It means tolerance time bias. e.g. tole_time = days(3);
%
%% Author Info
% Created by Wenfan Wu, Virginia Institute of Marine Science in 2021.
% Last Updated on 14 Mar 2025.
% Email: wwu@vims.edu
%
% See also: ncread

%% Parse inputs
tic
ind_url = find(strncmpi(varargin, 'url', 3), 1, 'last'); % only the last one is valid
if ~isempty(ind_url); URL = varargin{ind_url+1}; end

fmt = 'mat'; % default format
ind_fmt = find(strncmpi(varargin, 'format', 4), 1, 'last');
if ~isempty(ind_fmt); fmt = lower(varargin{ind_fmt+1}); end
if strcmp(fmt, 'netcdf'); fmt = 'nc'; end

ind_hd = find(strncmpi(varargin, 'prefix', 4), 1, 'last');
if ~isempty(ind_hd); prefix_name = varargin{ind_hd+1}; end

if exist(aimpath,'dir')~=7
    disp('the aimpath does not exist and has been created automatically')
    mkdir(aimpath);
end

varBase = {'ssh','temp','salt','uvel','vvel'};
stdBase = {'surf_el', 'water_temp','salinity','water_u','water_v'};

if nargin<4
    varList = {'ssh','temp','salt','uvel','vvel'};                                     % variable name list
    stdList = {'surf_el', 'water_temp','salinity','water_u','water_v'};  % standard name list
end

varList = lower(varList);
ind_vars = cellfun(@(x) find(contains(varBase, x)), varList);
if numel(ind_vars)~=numel(varList)
    warning on
    warning('some variable names are unrecognized!')
end
varList = varBase(ind_vars);
stdList = stdBase(ind_vars);

time_part1 = datetime(1992,10,2):datetime(2014,7,1,12,0,0);
time_part2 = datetime(2014,7,1, 12, 0, 0):hours(3):dateshift(datetime(datevec(now-1)), 'start', 'day'); %#ok<*TNOW1>
time_pool = [time_part1(:); time_part2(:)];

if timeTick<time_pool(1) ||  timeTick>time_pool(end)
    error(['No available HYCOM data before 1992-10-02 or after ',datestr(now-1, 'yyyy-mm-dd'),'!']) %#ok<*DATST>
end

ind_rtime = wisefind(time_pool, timeTick);
time_hycom = time_pool(ind_rtime);

reg = round(region);
geo_tag = ['W',num2str(reg(1)),'E',num2str(reg(2)),'S',num2str(reg(3)),'N',num2str(reg(4))];
geo_tag = strrep(geo_tag, '-', 'n'); % to avoid unnecessary issues on Linux system; n means negative.
if isempty(ind_hd); prefix_name = geo_tag; end
aimfile = fullfile(aimpath, [prefix_name, '_',datestr(time_hycom,'yyyymmddTHHMMZ'),'.', fmt]);

%% Download
nVars = numel(stdList);
if exist(aimfile, 'file')~=0
    disp('It has been downloaded before')
    switch fmt
        case 'mat'
            D = load(aimfile);
        case 'nc'
            D = read_nc(aimfile);
    end
else
    if isempty(ind_url)
        URL = get_URL(time_hycom);
        URLs = repmat({URL}, 1,nVars);
        if timeTick >= datetime(2024,9,4)
            svars = {'ssh','t3z','s3z','u3z','v3z'};
            URL = [URL,'/',num2str(year(timeTick))];
            URLs = cellfun(@(x,y) strrep(x, 't3z', y), repmat({URL}, 1,nVars), svars(ind_vars), 'UniformOutput', false);
        end
    else
        URLs = repmat({URL}, 1,nVars);
    end
    % ncdisp(URL)  % debug
    nc_dims = {'lon','lat','depth','time'};
    lonAll = ncread(URL, nc_dims{1}); 
    latAll = ncread(URL, nc_dims{2});
    depAll = ncread(URL, nc_dims{3});
    timeAll = datetime(datevec(ncread(URL, nc_dims{4})/24+datenum(2000,1,1))); %#ok<*DATNM>

    % check the consistency of coordinate systems
    lonReg = region(1:2); lon_flag = 0;
    if max(lonAll)>180 && min(lonReg)<0
        lon_flag = -1;
        lonReg(lonReg<0) = lonReg(lonReg<0)+360;
    end
    if min(lonAll)<0 && max(lonReg)>180
        lon_flag = 1;
        lonReg(lonReg>180) = lonReg(lonReg>180)-360;
    end
    region(1:2) = lonReg;
    hit_flag = 0;

    % check the availability of time span when URL was manually specified
    if time_hycom<min(timeAll)-days(1) || time_hycom>max(timeAll)+days(1)
        error('the given time is outside the time range of the specified HYCOM product!')
    end

    % begin to subset data
    indLons = wisefind(lonAll, region(1:2));  
    if indLons(1)>indLons(2); hit_flag=1; end  % lonAll must be in ascending order.
    
    indLats = wisefind(latAll, region(3:4));
    indTime = wisefind(timeAll, time_hycom);
    if hit_flag == 0
        D.lon = lonAll(min(indLons):max(indLons));
    elseif hit_flag==1
        D.lon = [lonAll(max(indLons):end); lonAll(1:min(indLons))];
    end
    D.lat = latAll(min(indLats):max(indLats));
    D.depth = depAll;
    D.time = timeAll(indTime);

    % restore the longitude
    switch lon_flag
        case -1
            D.lon(D.lon>180) = D.lon(D.lon>180)-360;
        case 1
            D.lon(D.lon<0) = D.lon(D.lon<0)+360;
    end

    tole_time = days(1); % increase this value to replace missing data with data on adjacent days
    dev_time = D.time-timeTick;
    if abs(dev_time) > tole_time
        warning on
        warning(['HYCOM data is missing on ', datestr(time_hycom, 'yyyy-mm-dd') ,', and this function has stopped'])
        return
    end
    D.dev_time = dev_time;
    
    nLons = numel(lonAll); nLayers = numel(D.depth);
    for iVar = 1:nVars
        stdName = stdList{iVar};
        varName = varList{iVar};
        URL = URLs{iVar};
        if strcmp(varName, 'ssh')
            if timeTick >= datetime(2024,9,4) % ssh is hourly rather than 3-hourly
                timeAll = datetime(datevec(ncread(URL, 'time')/24+datenum(2000,1,1))); %#ok<*DATNM>
                indTime2 = wisefind(timeAll, time_hycom);
            else
                indTime2 = indTime;
            end
            if hit_flag==0
                varData = squeeze(ncread(URL, stdName, [min(indLons),min(indLats),indTime2], [abs(diff(indLons))+1,abs(diff(indLats))+1,1])); %#ok<*NASGU>
            elseif hit_flag==1
                varData1 = squeeze(ncread(URL, stdName, [max(indLons), min(indLats),indTime2], [nLons-max(indLons)+1,abs(diff(indLats))+1,1]));
                varData2 = squeeze(ncread(URL, stdName, [1, min(indLats),indTime2], [min(indLons),abs(diff(indLats))+1,1]));
                varData = cat(1, varData1, varData2);
            end
        else
            if hit_flag==0
                varData = squeeze(ncread(URL, stdName, [min(indLons),min(indLats),1,indTime], [abs(diff(indLons))+1,abs(diff(indLats))+1,nLayers,1]));
            elseif hit_flag==1
                varData1 = squeeze(ncread(URL, stdName, [max(indLons), min(indLats),1, indTime], [nLons-max(indLons)+1,abs(diff(indLats))+1, nLayers, 1]));
                varData2 = squeeze(ncread(URL, stdName, [1, min(indLats),1, indTime], [min(indLons),abs(diff(indLats))+1,nLayers, 1]));
                varData = cat(1, varData1, varData2);
            end
        end
        D.(varName) = varData;
        clear varData
    end
    switch fmt
        case 'mat'
            save(aimfile, '-struct', 'D')
        case 'nc'
            save_nc(aimfile, D)
    end
end
cst = toc;

disp(['It takes ', num2str(cst,'%.2f'),' secs to download ', datestr(time_hycom,'yyyymmddTHHMMZ'), '.', fmt])
end

function URL = get_URL(timeTick)
% Automatically select a HYCOM product according to the given time
% DO NOT arbitrarily change the order below

if timeTick < datetime(1992,10,2)
    error('No available HYCOM data set before 1992-10-02!')

    % ------ESPC-D-V02 (2024-9-4 to present, 3-hourly or 1-hourly (ssh), 40 levels, 0.08*0.04)
elseif timeTick >= datetime(2024,9,4)
    URL = 'http://tds.hycom.org/thredds/dodsC/ESPC-D-V02/t3z'; % checked  0-360, -80-90

    % ------GLBv0.08 (2014-7-1 to 2020-2-19, 3-hourly, 40 levels, 0.08*0.08)
elseif timeTick >= datetime(2018,1,1,12,0,0) && timeTick <= datetime(2020,2,19,9,0,0)  % checked  0-360, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBv0.08/expt_93.0?';
elseif timeTick >= datetime(2017,10,1,12,0,0) && timeTick <= datetime(2018,3,20,9,0,0)  % checked  0-360, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBv0.08/expt_92.9?';
elseif timeTick >= datetime(2017,6,1,12,0,0) && timeTick <= datetime(2017,10,1,9,0,0)    % checked   -180-180, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBv0.08/expt_57.7?';
elseif timeTick >= datetime(2017,2,1,12,0,0) && timeTick <= datetime(2017,6,1,9,0,0)      % checked  0-360, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBv0.08/expt_92.8?';
elseif timeTick >= datetime(2016,5,1,12,0,0) && timeTick <= datetime(2017,2,1,9,0,0)       % checked   -180-180, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBv0.08/expt_57.2?';
elseif timeTick >= datetime(2014,7,1,12,0,0) && timeTick <= datetime(2016,9,30,9,0,0)     % checked   -180-180, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBv0.08/expt_56.3?';

    % ------GLBy0.08 (2018-12-4 to 2024-9-4, 3-hourly, 40 levels, 0.08*0.04)
elseif timeTick >= datetime(2018,12,4,12,0,0)                                                    % checked  0-360, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBy0.08/expt_93.0?';

    % ------GLBu0.08 (1992-10-2 to 2018-11-20, daily, 40 levels, 0.08*0.08)
elseif timeTick >= datetime(2016,4,18) && timeTick <= datetime(2018,11,20)  % checked   0-360, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBu0.08/expt_91.2?';
elseif timeTick >= datetime(2014,4,7) && timeTick <= datetime(2016,4,18)      % checked    0-360, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBu0.08/expt_91.1?';
elseif timeTick >= datetime(2013,8,17) && timeTick <= datetime(2014,4,8)      % checked    0-360, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBu0.08/expt_91.0?';
elseif timeTick >= datetime(1995,8,1) && timeTick <= datetime(2012,12,31)     % checked   -180-180, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBu0.08/expt_19.1?';
elseif timeTick >= datetime(2012,1,25) && timeTick <= datetime(2013,8,20)    % checked    0-360, -80-80 (20120903-20121202 are missing)
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBu0.08/expt_90.9?';
elseif timeTick >= datetime(1992,10,2) && timeTick <= datetime(1995,7,31)     % checked   -180-180, -80-80
    URL = 'http://tds.hycom.org/thredds/dodsC/GLBu0.08/expt_19.0?';
end

idx = strfind(URL, '/');
expName = URL(idx(end-1)+1:end);
disp(['HYCOM_',expName, ' is being downloaded, please wait...'])
end

function save_nc(filepath, D)
% Save the downloaded file as netcdf format

nx = numel(D.lon);
ny = numel(D.lat);
nz = numel(D.depth);

nccreate(filepath, 'lon', 'Dimensions', {'lon', nx},'Datatype', 'double', 'Format', 'netcdf4')
ncwrite(filepath, 'lon', D.lon);

nccreate(filepath, 'lat', 'Dimensions', {'lat', ny},'Datatype', 'double', 'Format', 'netcdf4')
ncwrite(filepath, 'lat', D.lat);

nccreate(filepath, 'depth', 'Dimensions', {'depth', nz},'Datatype', 'double', 'Format', 'netcdf4')
ncwrite(filepath, 'depth', D.depth);

nccreate(filepath, 'time', 'Dimensions', {'one', 1},'Datatype', 'double', 'Format', 'netcdf4')
ncwrite(filepath, 'time', datenum(D.time));

nccreate(filepath, 'dev_time', 'Dimensions', {'one', 1},'Datatype', 'double', 'Format', 'netcdf4')
ncwrite(filepath, 'dev_time', D.dev_time/hours(1));

varList = {'ssh','temp','salt','uvel','vvel'};
for iVar = 1:5
    varName = varList{iVar};
    if isfield(D, varName)
        switch varName
            case 'ssh'
                nccreate(filepath, varName, 'Dimensions', {'lon', nx, 'lat', ny},'Datatype', 'double', 'Format', 'netcdf4')
            otherwise
                nccreate(filepath, varName, 'Dimensions', {'lon', nx, 'lat', ny, 'depth', nz},'Datatype', 'double', 'Format', 'netcdf4')
        end
        ncwrite(filepath, varName, D.(varName));
    end
end
end

function D = read_nc(aimfile)
% Read the netcdf file

nc_info = ncinfo(aimfile);
varList = {nc_info.Variables.Name};

for iVar = 1:numel(varList)
    varName = varList{iVar};
    D.(varName) = ncread(aimfile, varName);
end
D.time = datetime(datevec(D.time));
D.dev_time = hours(D.dev_time);

end


function indMin = wisefind(varBase, varFind)
% Find the closest index

varBase = varBase(:)';
varFind = varFind(:);
diff_vals = abs(varBase-varFind);  % This line might give an error when running on some older versions of MATLAB? I am not sure.
[~, indMin] = sort(diff_vals, 2);
indMin = indMin(:, 1);
end

%% All HYCOM products (global)
% GLBy0.08
% expt_93.0
%
% GLBv0.08
%  expt_93.0; expt_92.9; expt_57.7; expt_92.8; expt_57.2; expt_56.3;
%  expt_53.X (GOFS 3.1-Reanalysis) --------- this data set is not used.
%
% GLBa0.08 --------- this product has quite different coordinate system, and it is not used.
% expt_91.2; expt_91.1; expt_91.0; expt_90.9; expt_90.8; expt_90.6
%
% GLBu0.08
% expt_91.2; expt_91.1;expt_91.0; expt_90.9;
% expt_19.1; expt_19.0  (GOFS 3.0-Reanalysis)
%
% 1) ESPC-D-V02 (latest modeling system)
%       Global Analysis
% 2) GOFS 3.1
%       Global Analysis
%       Global Reanalysis
% 3) GOFS 3.0
%       Global Analysis
%       Global Reanalysis
%
%% Debug
% timeList = [datetime(1993,1,1) datetime(1996,1,1) datetime(2012, 3,1) datetime(2014, 1,1) ...
%     datetime(2014, 5,1) datetime(2015, 1,1) datetime(2016, 1,1) datetime(2017, 5,1) ...
%     datetime(2017, 9,1) datetime(2018, 2,1) datetime(2019, 3,1) datetime(2022, 5,1)];

