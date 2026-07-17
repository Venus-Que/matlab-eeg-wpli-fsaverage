%% 单条记录：计算delta/theta/alpha/beta wPLI并生成fsaverage三维图

clear;
clc;
close all;

example_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(example_dir);
addpath(fullfile(repo_root, 'src'));

%% 用户配置
fieldtrip_dir = '';
input_fif = '';
output_dir = '';
fsaverage_dir = '';

subject_id = 'sub-001';
phase_name = 'phase1';
condition_prefixes = {'O', 'S'};
n_edges_to_plot = 20;

assert(~isempty(fieldtrip_dir), '请填写fieldtrip_dir。');
assert(~isempty(input_fif), '请填写input_fif。');
assert(~isempty(output_dir), '请填写output_dir。');
assert(~isempty(fsaverage_dir), '请填写fsaverage_dir。');

%% O和S分别计算；不把两类试次混入同一个连接矩阵
for condition_idx = 1:numel(condition_prefixes)
    event_prefix = condition_prefixes{condition_idx};
    fprintf('\n开始条件%s。\n', event_prefix);

    [mat_path, matrix_png] = compute_one_subject_wpli( ...
        input_fif, output_dir, subject_id, phase_name, ...
        event_prefix, fieldtrip_dir);

    [brain_png, mapping_mat] = render_one_wpli_fsaverage( ...
        mat_path, fsaverage_dir, output_dir, ...
        n_edges_to_plot, fieldtrip_dir);

    fprintf('\n条件%s完成：\n%s\n%s\n%s\n%s\n', ...
        event_prefix, mat_path, matrix_png, brain_png, mapping_mat);
end
