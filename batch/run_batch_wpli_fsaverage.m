%% 多人四频段wPLI与fsaverage脑图批处理
% GitHub发布版：默认扫描全部记录但不计算。
% 首次使用先检查扫描表，再运行少量预实验，最后才运行全量数据。
% 每个被试、阶段和O/S条件独立计算和保存，不混合条件或跨被试合并试次。

clear;
clc;
close all;

%% 1. 运行设置
script_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(script_dir);
addpath(fullfile(repo_root, 'src'));

% 必填：使用者自己的目录。发布包不包含FieldTrip、fsaverage或EEG数据。
fieldtrip_dir = '';
data_root = '';
output_root = '';
fsaverage_dir = '';

run_mode = 'all';       % 'all'扫描/全量；'pilot'仅运行前pilot_count条记录
pilot_count = 4;
scan_only = true;      % 第一次必须保持true，只生成清单，不计算
phases_to_run = {'phase1', 'phase2', 'phase3'};
condition_prefixes = {'O', 'S'}; % 有O/S时分别计算，不合并两类试次
legacy_fallback_prefix = 'P';    % 仅含P事件的旧phase2记录继续按P计算
make_brain_images = true;
n_edges_to_plot = 20;
overwrite_existing = false;

%% 2. 初始化FieldTrip
assert(~isempty(fieldtrip_dir), '请先填写fieldtrip_dir。');
assert(~isempty(data_root), '请先填写data_root。');
assert(~isempty(output_root), '请先填写output_root。');
assert(~isempty(fsaverage_dir), '请先填写fsaverage_dir。');
assert(isfolder(fieldtrip_dir), '找不到FieldTrip：%s', fieldtrip_dir);
addpath(fieldtrip_dir);
ft_defaults;
assert(isfolder(data_root), '找不到数据根目录：%s', data_root);
assert(isfolder(fsaverage_dir), '找不到fsaverage：%s', fsaverage_dir);
if ~isfolder(output_root)
    mkdir(output_root);
end

%% 3. 扫描记录并解析组别、姓名和阶段
files = dir(fullfile(data_root, '**', '1.2_ICA', 'ica_clean.fif'));
assert(~isempty(files), '没有找到ica_clean.fif。');

cohort = strings(0, 1);
subject = strings(0, 1);
phase = strings(0, 1);
fif_path = strings(0, 1);
marker_path = strings(0, 1);
record_output = strings(0, 1);
record_event_prefix = strings(0, 1);
marker_event_count = zeros(0, 1);
condition_rule = strings(0, 1);
n_phase_records = 0;

for k = 1:numel(files)
    current_fif = fullfile(files(k).folder, files(k).name);
    ica_dir = fileparts(current_fif);
    phase_dir = fileparts(ica_dir);
    [subject_dir, current_phase] = fileparts(phase_dir);
    [cohort_dir, current_subject] = fileparts(subject_dir);
    [~, current_cohort] = fileparts(cohort_dir);

    if ~any(strcmp(current_phase, phases_to_run))
        continue;
    end

    current_marker = fullfile(phase_dir, '1.1_标签清洗', 'markers.csv');
    marker_text = '';
    if isfile(current_marker)
        marker_text = fileread(current_marker);
    end
    n_phase_records = n_phase_records + 1;

    requested_counts = zeros(1, numel(condition_prefixes));
    for condition_idx = 1:numel(condition_prefixes)
        requested_counts(condition_idx) = count_condition_events( ...
            marker_text, condition_prefixes{condition_idx});
    end
    fallback_count = count_condition_events(marker_text, legacy_fallback_prefix);
    if ~any(requested_counts) && fallback_count > 0
        current_condition_prefixes = {legacy_fallback_prefix};
        current_condition_rule = "仅P事件回退";
    else
        current_condition_prefixes = condition_prefixes;
        current_condition_rule = "O/S双条件";
    end

    for condition_idx = 1:numel(current_condition_prefixes)
        current_prefix = current_condition_prefixes{condition_idx};
        cohort(end + 1, 1) = string(current_cohort); %#ok<SAGROW>
        subject(end + 1, 1) = string(current_subject); %#ok<SAGROW>
        phase(end + 1, 1) = string(current_phase); %#ok<SAGROW>
        fif_path(end + 1, 1) = string(current_fif); %#ok<SAGROW>
        marker_path(end + 1, 1) = string(current_marker); %#ok<SAGROW>
        record_output(end + 1, 1) = string(fullfile( ...
            output_root, current_cohort, current_subject, current_phase)); %#ok<SAGROW>
        record_event_prefix(end + 1, 1) = string(current_prefix); %#ok<SAGROW>
        marker_event_count(end + 1, 1) = count_condition_events( ...
            marker_text, current_prefix); %#ok<SAGROW>
        condition_rule(end + 1, 1) = current_condition_rule; %#ok<SAGROW>
    end
end

records = table(cohort, subject, phase, record_event_prefix, ...
    marker_event_count, condition_rule, fif_path, marker_path, record_output);
records = sortrows(records, ...
    {'cohort', 'subject', 'phase', 'record_event_prefix'});
assert(~isempty(records), '筛选phase后没有可运行记录。');

% 按同一组别、同一被试和同一条件标记是否同时具有phase1和phase3。
records.has_phase1 = false(height(records), 1);
records.has_phase3 = false(height(records), 1);
records.paired_phase1_phase3 = false(height(records), 1);
for k = 1:height(records)
    same_subject_condition = records.cohort == records.cohort(k) ...
        & records.subject == records.subject(k) ...
        & records.record_event_prefix == records.record_event_prefix(k);
    records.has_phase1(k) = any( ...
        records.phase(same_subject_condition) == "phase1");
    records.has_phase3(k) = any( ...
        records.phase(same_subject_condition) == "phase3");
    records.paired_phase1_phase3(k) = ...
        records.has_phase1(k) && records.has_phase3(k);
end
n_condition_records = height(records);
n_p_fallback_records = sum(records.record_event_prefix == ...
    string(legacy_fallback_prefix));

if strcmpi(run_mode, 'pilot')
    records = records(1:min(pilot_count, height(records)), :);
elseif ~strcmpi(run_mode, 'all')
    error('run_mode只能是pilot或all。');
end

records.status = repmat("待运行", height(records), 1);
records.message = strings(height(records), 1);
records.elapsed_sec = nan(height(records), 1);
records.result_mat = strings(height(records), 1);
records.brain_png = strings(height(records), 1);
records.total_channel_count = nan(height(records), 1);
records.eeg_channel_count = nan(height(records), 1);
records.band_count = nan(height(records), 1);

progress_csv = fullfile(output_root, '批处理进度与错误.csv');
writetable(records, progress_csv, 'Encoding', 'UTF-8');
fprintf('共准备运行%d条条件记录，模式：%s。\n', height(records), run_mode);
fprintf(['全部ica_clean.fif共%d条；当前阶段筛选后%d条；', ...
    '按O/S展开并保留P回退后%d条条件记录，其中P回退%d条。\n'], ...
    numel(files), n_phase_records, n_condition_records, n_p_fallback_records);

if scan_only
    fprintf(['当前scan_only=true：仅完成扫描，尚未计算。\n', ...
        '请检查%s，确认后将scan_only改为false再运行。\n'], progress_csv);
    return;
end

%% 4. 逐条计算；每完成一条就更新CSV
for k = 1:height(records)
    fprintf('\n[%d/%d] %s / %s / %s / 条件%s\n', k, height(records), ...
        records.cohort(k), records.subject(k), records.phase(k), ...
        records.record_event_prefix(k));
    started = tic;

    % 先审查通道数。59导和64导均按原始节点集合计算，不补导或删导；
    % 其他导数只标记不计算，59导与64导结果不得直接逐边合并。
    try
        current_hdr = ft_read_header(char(records.fif_path(k)));
        total_channel_count = numel(current_hdr.label);
        if isfield(current_hdr, 'chantype') ...
                && numel(current_hdr.chantype) == total_channel_count
            eeg_channel_count = sum(strcmpi(current_hdr.chantype, 'eeg'));
            if eeg_channel_count == 0
                eeg_channel_count = total_channel_count;
            end
        else
            eeg_channel_count = total_channel_count;
        end
        records.total_channel_count(k) = total_channel_count;
        records.eeg_channel_count(k) = eeg_channel_count;
    catch header_err
        records.status(k) = "失败-无法读取头信息";
        records.message(k) = string(header_err.message);
        records.elapsed_sec(k) = toc(started);
        writetable(records, progress_csv, 'Encoding', 'UTF-8');
        continue;
    end

    if ~ismember(eeg_channel_count, [59, 64])
        records.status(k) = "跳过-不支持的导数";
        records.message(k) = sprintf( ...
            '总通道%d，EEG通道%d；本流程仅支持59导或64导。', ...
            total_channel_count, eeg_channel_count);
        records.elapsed_sec(k) = toc(started);
        fprintf(2, '跳过：%s\n', records.message(k));
        writetable(records, progress_csv, 'Encoding', 'UTF-8');
        continue;
    end

    if ~isfile(records.marker_path(k))
        records.status(k) = "失败";
        records.message(k) = "缺少markers.csv";
        records.elapsed_sec(k) = toc(started);
        writetable(records, progress_csv, 'Encoding', 'UTF-8');
        continue;
    end

    if records.marker_event_count(k) == 0
        records.status(k) = "失败-缺少条件事件";
        records.message(k) = sprintf( ...
            'markers.csv中没有检测到%s1-%s6事件；另一条件仍可独立运行。', ...
            records.record_event_prefix(k), records.record_event_prefix(k));
        records.elapsed_sec(k) = toc(started);
        writetable(records, progress_csv, 'Encoding', 'UTF-8');
        continue;
    end

    current_output = char(records.record_output(k));
    current_subject = char(records.subject(k));
    current_phase = char(records.phase(k));
    current_event_prefix = char(records.record_event_prefix(k));
    expected_prefix = sprintf('%s_%s_%s_去偏平方wPLI', ...
        current_subject, current_phase, current_event_prefix);
    expected_mat = fullfile(current_output, [expected_prefix, '.mat']);
    expected_brain = fullfile(current_output, ...
        [expected_prefix, '_fsaverage脑表面.png']);
    expected_mapping = fullfile(current_output, ...
        [expected_prefix, '_fsaverage节点映射.mat']);
    required_matrices = {'delta_matrix', 'theta_matrix', ...
        'alpha_matrix', 'beta_matrix'};

    % v0.1.x结果只有theta/alpha。旧MAT或旧脑图不能作为四频段完整结果跳过。
    existing_mat_complete = false;
    existing_brain_complete = ~make_brain_images;
    if isfile(expected_mat)
        try
            mat_variables = whos('-file', expected_mat);
            variable_names = {mat_variables.name};
            existing_mat_complete = all(ismember(required_matrices, variable_names));
        catch
            existing_mat_complete = false;
        end
    end
    if make_brain_images && isfile(expected_brain) && isfile(expected_mapping)
        try
            mapping_variables = whos('-file', expected_mapping);
            mapping_names = {mapping_variables.name};
            if ismember('band_names', mapping_names)
                mapping_info = load(expected_mapping, 'band_names');
                existing_brain_complete = numel(mapping_info.band_names) == 4;
            end
        catch
            existing_brain_complete = false;
        end
    end

    if ~overwrite_existing && existing_mat_complete && existing_brain_complete
        if eeg_channel_count == 59
            records.status(k) = "跳过-已有59导结果";
            records.message(k) = ...
                "59导结果仅用于个体展示，不与64导矩阵直接比较。";
        else
            records.status(k) = "跳过-已有结果";
        end
        records.result_mat(k) = string(expected_mat);
        records.band_count(k) = 4;
        if isfile(expected_brain)
            records.brain_png(k) = string(expected_brain);
        end
        records.elapsed_sec(k) = toc(started);
        writetable(records, progress_csv, 'Encoding', 'UTF-8');
        continue;
    end

    try
        if ~overwrite_existing && existing_mat_complete
            mat_path = expected_mat;
            fprintf('复用已有四频段MAT，仅补绘缺失或旧版脑图。\n');
        else
            [mat_path, ~] = compute_one_subject_wpli( ...
                char(records.fif_path(k)), current_output, ...
                current_subject, current_phase, current_event_prefix, fieldtrip_dir);
        end
        records.result_mat(k) = string(mat_path);
        result_variables = whos('-file', mat_path);
        result_variable_names = {result_variables.name};
        records.band_count(k) = sum( ...
            ismember(required_matrices, result_variable_names));
        assert(records.band_count(k) == 4, ...
            '结果MAT只检测到%d/4个频段矩阵，已停止该记录。', ...
            records.band_count(k));

        if make_brain_images
            [brain_png, ~] = render_one_wpli_fsaverage( ...
                mat_path, fsaverage_dir, current_output, ...
                n_edges_to_plot, fieldtrip_dir);
            records.brain_png(k) = string(brain_png);
        end

        if eeg_channel_count == 59
            records.status(k) = "成功-59导仅个体展示";
            records.message(k) = ...
                "59导结果已生成并在图标题标注；不与64导矩阵直接比较。";
        else
            records.status(k) = "成功";
            records.message(k) = "";
        end
    catch err
        records.status(k) = "失败";
        records.message(k) = string(err.message);
        fprintf(2, '失败：%s\n', err.message);
    end

    records.elapsed_sec(k) = toc(started);
    writetable(records, progress_csv, 'Encoding', 'UTF-8');
    close all;
end

%% 5. 汇总
summary_csv = fullfile(output_root, '批处理最终汇总.csv');
writetable(records, summary_csv, 'Encoding', 'UTF-8');
fprintf('\n批处理结束。\n进度表：%s\n汇总表：%s\n', progress_csv, summary_csv);
disp(groupsummary(records, 'status'));

%% 局部函数
function event_count = count_condition_events(marker_text, event_prefix)
    if isempty(marker_text)
        event_count = 0;
        return;
    end
    expression = ['(?<![A-Za-z0-9])', upper(event_prefix), ...
        '[1-6](?![0-9])'];
    matches = regexp(upper(marker_text), expression, 'match');
    event_count = numel(matches);
end
