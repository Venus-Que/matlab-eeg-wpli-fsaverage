function check_environment(fieldtrip_dir, fsaverage_dir)
%% 检查FieldTrip和fsaverage是否满足本项目的最小运行条件

assert(nargin == 2, '用法：check_environment(fieldtrip_dir, fsaverage_dir)');
assert(isfolder(fieldtrip_dir), '找不到FieldTrip目录：%s', fieldtrip_dir);
assert(isfolder(fsaverage_dir), '找不到fsaverage目录：%s', fsaverage_dir);

addpath(fieldtrip_dir);
ft_defaults;

required_functions = { ...
    'ft_read_header', 'ft_read_event', 'ft_preprocessing', ...
    'ft_freqanalysis', 'ft_connectivityanalysis', ...
    'ft_read_sens', 'ft_read_headshape'};

for k = 1:numel(required_functions)
    assert(exist(required_functions{k}, 'file') == 2, ...
        'FieldTrip缺少函数：%s', required_functions{k});
end

standard_elec = fullfile(fieldtrip_dir, 'template', ...
    'electrode', 'standard_1005.elc');
lh_pial = fullfile(fsaverage_dir, 'surf', 'lh.pial');
rh_pial = fullfile(fsaverage_dir, 'surf', 'rh.pial');

assert(isfile(standard_elec), '缺少standard_1005.elc：%s', standard_elec);
assert(isfile(lh_pial), '缺少fsaverage左半球表面：%s', lh_pial);
assert(isfile(rh_pial), '缺少fsaverage右半球表面：%s', rh_pial);

fprintf('环境检查通过。\n');
fprintf('FieldTrip：%s\n', fieldtrip_dir);
fprintf('fsaverage：%s\n', fsaverage_dir);
end
