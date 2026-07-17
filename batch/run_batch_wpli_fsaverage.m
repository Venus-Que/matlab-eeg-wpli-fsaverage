%% 多人wPLI与fsaverage脑图批处理
% GitHub发布版：默认扫描全部记录但不计算。
% 首次使用先检查扫描表，再运行少量预实验，最后才运行全量数据。
% 每条记录独立计算和保存，不跨被试合并试次。

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
event_prefix_phase13 = 'O'; % phase1和phase3使用O1-O6
event_prefix_phase2 = 'P';  % phase2默认P；扫描markers.csv后按每条记录自动识别O/P
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

    cohort(end + 1, 1) = string(current_cohort); %#ok<SAGROW>
    subject(end + 1, 1) = string(current_subject); %#ok<SAGROW>
    phase(end + 1, 1) = string(current_phase); %#ok<SAGROW>
    fif_path(end + 1, 1) = string(current_fif); %#ok<SAGROW>
    current_marker = fullfile(phase_dir, '1.1_标签清洗', 'markers.csv');
    marker_path(end + 1, 1) = string(current_marker); %#ok<SAGROW>
    record_output(end + 1, 1) = string(fullfile( ...
        output_root, current_cohort, current_subject, current_phase)); %#ok<SAGROW>
    if strcmp(current_phase, 'phase2')
        current_prefix = event_prefix_phase2;
        if isfile(current_marker)
            marker_text = fileread(current_marker);
            has_o_events = contains(marker_text, 'O1');
            has_p_events = contains(marker_text, 'P1');
            if has_o_events && ~has_p_events
                current_prefix = 'O';
            elseif has_p_events && ~has_o_events
                current_prefix = 'P';
            end
        end
        record_event_prefix(end + 1, 1) = string(current_prefix); %#ok<SAGROW>
    else
        record_event_prefix(end + 1, 1) = string(event_prefix_phase13); %#ok<SAGROW>
    end
end

records = table(cohort, subject, phase, record_event_prefix, ...
    fif_path, marker_path, record_output);
records = sortrows(records, {'cohort', 'subject', 'phase'});
assert(~isempty(records), '筛选phase后没有可运行记录。');

% 标记同一组别、同一被试是否同时具有phase1和phase3。
records.has_phase1 = false(height(records), 1);
records.has_phase3 = false(height(records), 1);
records.paired_phase1_phase3 = false(height(records), 1);
for k = 1:height(records)
    same_subject = records.cohort == records.cohort(k) ...
        & records.subject == records.subject(k);
    records.has_phase1(k) = any(records.phase(same_subject) == "phase1");
    records.has_phase3(k) = any(records.phase(same_subject) == "phase3");
    records.paired_phase1_phase3(k) = ...
        records.has_phase1(k) && records.has_phase3(k);
end
n_phase_records = height(records);

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

progress_csv = fullfile(output_root, '批处理进度与错误.csv');
writetable(records, progress_csv, 'Encoding', 'UTF-8');
fprintf('共准备运行%d条记录，模式：%s。\n', height(records), run_mode);
fprintf('全部ica_clean.fif共%d条；当前阶段筛选后%d条。\n', ...
    numel(files), n_phase_records);

if scan_only
    fprintf(['当前scan_only=true：仅完成扫描，尚未计算。\n', ...
        '请检查%s，确认后将scan_only改为false再运行。\n'], progress_csv);
    return;
end

%% 4. 逐条计算；每完成一条就更新CSV
for k = 1:height(records)
    fprintf('\n[%d/%d] %s / %s / %s\n', k, height(records), ...
        records.cohort(k), records.subject(k), records.phase(k));
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

    current_output = char(records.record_output(k));
    current_subject = char(records.subject(k));
    current_phase = char(records.phase(k));
    current_event_prefix = char(records.record_event_prefix(k));
    expected_prefix = sprintf('%s_%s_%s_去偏平方wPLI', ...
        current_subject, current_phase, current_event_prefix);
    expected_mat = fullfile(current_output, [expected_prefix, '.mat']);
    expected_brain = fullfile(current_output, ...
        [expected_prefix, '_fsaverage脑表面.png']);

    if ~overwrite_existing && isfile(expected_mat) ...
            && (~make_brain_images || isfile(expected_brain))
        if eeg_channel_count == 59
            records.status(k) = "跳过-已有59导结果";
            records.message(k) = ...
                "59导结果仅用于个体展示，不与64导矩阵直接比较。";
        else
            records.status(k) = "跳过-已有结果";
        end
        records.result_mat(k) = string(expected_mat);
        if isfile(expected_brain)
            records.brain_png(k) = string(expected_brain);
        end
        records.elapsed_sec(k) = toc(started);
        writetable(records, progress_csv, 'Encoding', 'UTF-8');
        continue;
    end

    try
        [mat_path, ~] = compute_one_subject_wpli( ...
            char(records.fif_path(k)), current_output, ...
            current_subject, current_phase, current_event_prefix, fieldtrip_dir);
        records.result_mat(k) = string(mat_path);

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
