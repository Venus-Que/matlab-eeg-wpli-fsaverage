function [mat_path, png_path] = compute_one_subject_wpli( ...
        input_fif, output_dir, subject_name, phase_name, ...
        event_prefix, fieldtrip_dir)
%% 计算一条记录的59导或64导去偏平方wPLI
% 依赖：MATLAB R2020a或更新版本、FieldTrip
%
% 输入参数：
%   input_fif    - 预处理后的连续FIF文件。
%   output_dir   - 当前记录的独立输出目录。
%   subject_name - 脱敏后的被试ID，例如sub-001。
%   phase_name   - 阶段名称，例如phase1。
%   event_prefix - 事件前缀；O匹配O1-O6，P匹配P1-P6。
%   fieldtrip_dir- FieldTrip根目录；已加载FieldTrip时可传空字符串。
%
% 输出参数：
%   mat_path - 包含theta/alpha 59x59或64x64矩阵及质量控制参数的MAT文件。
%   png_path - 矩阵和二维网络汇总图。
%
% 重要：当前参数（6试次、500微伏阈值、0.5-2.5秒）来自特定预实验，
% 不应在其他数据集上未经验证直接视为最佳参数。

if nargin < 6
    fieldtrip_dir = '';
end
if nargin < 5 || isempty(event_prefix)
    event_prefix = 'O';
end
assert(nargin >= 4, ...
    '必须提供input_fif、output_dir、subject_name和phase_name。');

%% 1. 固定分析参数
tmin_sec = 0.5;           % 事件后0.5秒开始
tmax_sec = 2.5;           % 事件后2.5秒结束
reject_uv = 500;          % 任一通道峰峰值超过500微伏则剔除该试次
n_epochs = 6;             % 预实验固定试次数；正式研究前应评估可靠性
random_seed = 20260712;
n_edges_to_plot = 20;     % 每个网络图显示最强20条正连接

%% 2. 初始化FieldTrip
if exist('ft_defaults', 'file') == 2
    fieldtrip_dir = fileparts(which('ft_defaults'));
elseif ~isempty(fieldtrip_dir) && isfolder(fieldtrip_dir)
    addpath(fieldtrip_dir); % 不要使用addpath(genpath(...))
else
    error(['没有检测到FieldTrip。请先在命令窗口执行 ', ...
        'addpath(''你的FieldTrip根目录''); ft_defaults，然后重新运行。']);
end
fprintf('FieldTrip目录：%s\n', fieldtrip_dir);
ft_defaults;

assert(isfile(input_fif), '找不到输入FIF：%s', input_fif);
if ~isfolder(output_dir)
    mkdir(output_dir);
end

%% 3. 读取头信息和事件
hdr = ft_read_header(input_fif);
events = ft_read_event(input_fif);
fs = hdr.Fs;

% MNE写入FIF的annotations可能不会被FieldTrip的ft_read_event识别。
% 此时自动读取同一phase目录下1.1_标签清洗/markers.csv。
event_source = 'FIF annotations';
if isempty(events)
    phase_dir = fileparts(fileparts(input_fif));
    marker_csv = fullfile(phase_dir, '1.1_标签清洗', 'markers.csv');
    assert(isfile(marker_csv), ...
        ['FieldTrip没有读到FIF事件，并且找不到事件侧表：%s。', ...
        '请确认markers.csv位于1.1_标签清洗目录。'], marker_csv);

    marker_table = readtable(marker_csv, ...
        'VariableNamingRule', 'preserve', 'TextType', 'string');
    column_names = string(marker_table.Properties.VariableNames);
    lower_names = lower(column_names);
    time_col = find(contains(column_names, "时间") ...
        | contains(lower_names, "time") ...
        | contains(lower_names, "onset"), 1);
    label_col = find(contains(column_names, "标记") ...
        | contains(column_names, "名称") ...
        | contains(lower_names, "label") ...
        | contains(lower_names, "marker") ...
        | contains(lower_names, "description"), 1, 'last');

    % 兼容标准4列格式和部分被试的3列格式。
    if isempty(time_col)
        time_col = 1 + (width(marker_table) >= 4);
    end
    if isempty(label_col)
        label_col = width(marker_table);
    end
    assert(time_col <= width(marker_table) && label_col <= width(marker_table), ...
        '无法识别markers.csv的时间列或标记列。列名：%s', ...
        strjoin(column_names, ', '));

    marker_times_sec = marker_table{:, time_col};
    if ~isnumeric(marker_times_sec)
        marker_times_sec = str2double(string(marker_times_sec));
    end
    marker_labels = strtrim(string(marker_table{:, label_col}));
    valid_marker = isfinite(marker_times_sec) & ~ismissing(marker_labels) ...
        & strlength(marker_labels) > 0;
    marker_times_sec = marker_times_sec(valid_marker);
    marker_labels = marker_labels(valid_marker);
    assert(~isempty(marker_times_sec), ...
        'markers.csv中没有可用的时间和标记记录。');

    events = repmat(struct('type', '', 'value', '', 'sample', 0), ...
        numel(marker_times_sec), 1);
    for k = 1:numel(marker_times_sec)
        events(k).type = char(marker_labels(k));
        events(k).value = char(marker_labels(k));
        events(k).sample = round(marker_times_sec(k) * fs) + 1;
    end
    event_source = marker_csv;
    fprintf('FIF中未读取到事件，已自动导入markers.csv。\n');
end

fprintf('采样率：%.1f Hz\n', fs);
fprintf('原始通道数：%d\n', numel(hdr.label));
fprintf('事件总数：%d\n', numel(events));
fprintf('事件来源：%s\n', event_source);
fprintf('前30个事件如下（用于核对%s类事件）：\n', event_prefix);
for k = 1:min(30, numel(events))
    fprintf('%3d  sample=%d  type=%s  value=%s\n', ...
        k, events(k).sample, event_to_text(events(k), 'type'), ...
        event_to_text(events(k), 'value'));
end

%% 4. 保留输入文件中实际存在的59个或64个EEG通道
% 不把59导补成64导，不把64导删成59导，也不对连接矩阵补零或插值。
% 不同布局的联合分析应从原始记录统一选择公共通道后重新计算。
if isfield(hdr, 'chantype') && numel(hdr.chantype) == numel(hdr.label)
    eeg_mask = strcmpi(hdr.chantype, 'eeg');
    eeg_labels = hdr.label(eeg_mask);
else
    eeg_labels = hdr.label;
end

n_channels = numel(eeg_labels);
assert(ismember(n_channels, [59, 64]), ...
    '当前检测到%d个EEG通道；本流程仅支持59导或64导。', n_channels);

if n_channels == 59
    channel_title = '59导（非64导，仅个体展示）';
    title_color = [0.75, 0.10, 0.10];
    comparability_warning = ...
        '59导结果仅用于个体展示，不得与64导矩阵直接合并或逐边比较。';
else
    channel_title = '64导';
    title_color = [0.10, 0.10, 0.10];
    comparability_warning = '';
end

%% 5. 根据目标事件建立事件后0.5-2.5秒的试次
target_mask = false(numel(events), 1);
for k = 1:numel(events)
    target_mask(k) = is_target_event(events(k), event_prefix);
end
target_events = events(target_mask);

assert(~isempty(target_events), ...
    '没有找到以%s开头的1-6编号事件。请核对阶段与event_prefix。', ...
    event_prefix);

total_samples = hdr.nSamples * max(1, hdr.nTrials);
trl = zeros(0, 3);
for k = 1:numel(target_events)
    begin_sample = round(target_events(k).sample + tmin_sec * fs);
    end_sample = round(target_events(k).sample + tmax_sec * fs);
    offset = round(tmin_sec * fs);
    if begin_sample >= 1 && end_sample <= total_samples
        trl(end + 1, :) = [begin_sample, end_sample, offset]; %#ok<AGROW>
    end
end
fprintf('找到目标事件%d个，可切出完整时间窗%d个。\n', ...
    numel(target_events), size(trl, 1));

%% 6. 读取并线性去趋势
cfg = [];
cfg.dataset = input_fif;
cfg.trl = trl;
cfg.channel = eeg_labels;
cfg.demean = 'no';
cfg.detrend = 'yes';
data = ft_preprocessing(cfg);

%% 7. 500微伏峰峰值剔除
keep_mask = false(1, numel(data.trial));
epoch_max_ptp_uv = nan(1, numel(data.trial));
for k = 1:numel(data.trial)
    channel_ptp_uv = (max(data.trial{k}, [], 2) - min(data.trial{k}, [], 2)) * 1e6;
    epoch_max_ptp_uv(k) = max(channel_ptp_uv);
    keep_mask(k) = epoch_max_ptp_uv(k) <= reject_uv;
end

fprintf('振幅剔除前%d个试次，剔除后%d个试次。\n', numel(keep_mask), sum(keep_mask));
fprintf('试次最大峰峰值中位数：%.1f微伏。\n', median(epoch_max_ptp_uv));

cfg = [];
cfg.trials = find(keep_mask);
data = ft_selectdata(cfg, data);

assert(numel(data.trial) >= n_epochs, ...
    '剔除后只有%d个试次，少于要求的%d个；本记录不应进入统一分析。', ...
    numel(data.trial), n_epochs);

%% 8. 固定随机种子，统一选择6个试次
rng(random_seed, 'twister');
selected_trials = sort(randperm(numel(data.trial), n_epochs));
cfg = [];
cfg.trials = selected_trials;
data = ft_selectdata(cfg, data);
fprintf('本次选择的试次序号：%s\n', mat2str(selected_trials));

%% 9. 减去跨试次诱发平均，降低共同事件锁定成分
cfg = [];
evoked = ft_timelockanalysis(cfg, data);
for k = 1:numel(data.trial)
    data.trial{k} = data.trial{k} - evoked.avg;
end

%% 10. 多窗频谱估计
cfg = [];
cfg.method = 'mtmfft';
cfg.output = 'fourier';
cfg.taper = 'dpss';
cfg.foilim = [4 13];
cfg.tapsmofrq = 1.0;      % 约对应2 Hz完整带宽，与Python mt_bandwidth=2接近
cfg.keeptrials = 'yes';
cfg.keeptapers = 'yes';
cfg.pad = 'nextpow2';
freq = ft_freqanalysis(cfg, data);

%% 11. 计算FieldTrip去偏平方wPLI
cfg = [];
cfg.method = 'wpli_debiased';
conn = ft_connectivityanalysis(cfg, freq);

assert(isfield(conn, 'wpli_debiasedspctrm'), ...
    'FieldTrip结果中没有wpli_debiasedspctrm，请检查FieldTrip版本。');

full_matrix = connectivity_to_dense(conn, data.label);
theta_mask = conn.freq >= 4 & conn.freq <= 8;
alpha_mask = conn.freq >= 8 & conn.freq <= 13;
assert(any(theta_mask) && any(alpha_mask), '频率范围中缺少theta或alpha频点。');

theta_matrix = mean(full_matrix(:, :, theta_mask), 3, 'omitnan');
alpha_matrix = mean(full_matrix(:, :, alpha_mask), 3, 'omitnan');
theta_matrix = force_symmetric(theta_matrix);
alpha_matrix = force_symmetric(alpha_matrix);

%% 12. 使用标准1005模板获取统一电极坐标
% 当前MNE FIF中的电极坐标不完整，直接使用会得到NaN并画出空白圆图。
% 当前59或64个EEG通道名称应与FieldTrip标准1005模板一一匹配。
standard_elec_file = fullfile(fieldtrip_dir, 'template', ...
    'electrode', 'standard_1005.elc');
assert(isfile(standard_elec_file), ...
    '找不到FieldTrip标准电极文件：%s', standard_elec_file);
template_elec = ft_read_sens(standard_elec_file);
[data_elec_idx, template_elec_idx] = match_str(data.label, template_elec.label);
assert(numel(data_elec_idx) == numel(data.label), ...
    '有%d个通道无法匹配standard_1005.elc。', ...
    numel(data.label) - numel(data_elec_idx));

electrode_3d = nan(numel(data.label), 3);
electrode_3d(data_elec_idx, :) = template_elec.chanpos(template_elec_idx, :);
channel_labels = data.label;

layout_cfg = [];
layout_cfg.channel = data.label;
layout_cfg.elec = template_elec;
layout = ft_prepare_layout(layout_cfg, data);
[data_idx, layout_idx] = match_str(data.label, layout.label);
assert(numel(data_idx) == numel(data.label), ...
    '部分通道在FieldTrip布局中没有坐标，请先检查FIF中的电极位置信息。');

xy = nan(numel(data.label), 2);
xy(data_idx, :) = layout.pos(layout_idx, :);
xy = xy - mean(xy, 1);
xy = xy ./ (max(vecnorm(xy, 2, 2)) * 1.08);

%% 13. 计算全脑独立边平均
upper_mask = triu(true(n_channels), 1);
theta_global_mean = mean(theta_matrix(upper_mask), 'omitnan');
alpha_global_mean = mean(alpha_matrix(upper_mask), 'omitnan');

%% 14. 绘制矩阵和脑网络
fig = figure('Color', 'w', 'Position', [100 80 1450 900]);
tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile;
imagesc(ax1, theta_matrix);
axis(ax1, 'image');
colorbar(ax1);
caxis(ax1, [-0.5 1]);
title(ax1, sprintf('theta去偏平方wPLI矩阵，全局平均=%.4f', theta_global_mean));
xlabel(ax1, '电极');
ylabel(ax1, '电极');
set_matrix_ticks(ax1, data.label);

ax2 = nexttile;
imagesc(ax2, alpha_matrix);
axis(ax2, 'image');
colorbar(ax2);
caxis(ax2, [-0.5 1]);
title(ax2, sprintf('alpha去偏平方wPLI矩阵，全局平均=%.4f', alpha_global_mean));
xlabel(ax2, '电极');
ylabel(ax2, '电极');
set_matrix_ticks(ax2, data.label);

ax3 = nexttile;
draw_network(ax3, theta_matrix, xy, n_edges_to_plot);
title(ax3, sprintf('theta最强%d条正连接', n_edges_to_plot));

ax4 = nexttile;
draw_network(ax4, alpha_matrix, xy, n_edges_to_plot);
title(ax4, sprintf('alpha最强%d条正连接', n_edges_to_plot));

sgtitle(fig, sprintf('%s / %s / %s1-%s6 / %s去偏平方wPLI', ...
    subject_name, phase_name, event_prefix, event_prefix, channel_title), ...
    'FontSize', 16, 'FontWeight', 'bold', 'Color', title_color);

%% 15. 保存MAT和PNG
params = struct;
params.input_fif = input_fif;
params.event_source = event_source;
params.event_prefix = event_prefix;
params.time_window_sec = [tmin_sec, tmax_sec];
params.reject_uv = reject_uv;
params.n_epochs = n_epochs;
params.random_seed = random_seed;
params.n_channels = n_channels;
params.channel_layout_label = channel_title;
params.comparability_warning = comparability_warning;
params.bands = struct('theta', [4 8], 'alpha', [8 13]);
params.method = 'FieldTrip wpli_debiased (debiased squared wPLI)';

file_prefix = sprintf('%s_%s_%s_去偏平方wPLI', ...
    subject_name, phase_name, event_prefix);
mat_path = fullfile(output_dir, [file_prefix, '.mat']);
png_path = fullfile(output_dir, [file_prefix, '.png']);

save(mat_path, 'theta_matrix', 'alpha_matrix', ...
    'theta_global_mean', 'alpha_global_mean', 'xy', 'params', ...
    'channel_labels', 'electrode_3d', 'selected_trials', ...
    'epoch_max_ptp_uv', '-v7.3');

if exist('exportgraphics', 'file') == 2
    exportgraphics(fig, png_path, 'Resolution', 200);
else
    print(fig, png_path, '-dpng', '-r200');
end

fprintf('\n计算完成。\nMAT：%s\nPNG：%s\n', mat_path, png_path);
close(fig);

end

%% 本脚本使用的局部函数
function out = event_to_text(event_item, field_name)
    if ~isfield(event_item, field_name) || isempty(event_item.(field_name))
        out = '';
        return;
    end
    value = event_item.(field_name);
    if ischar(value)
        out = value;
    elseif isstring(value)
        out = char(value);
    elseif isnumeric(value) || islogical(value)
        out = mat2str(value);
    else
        out = class(value);
    end
end

function matched = is_target_event(event_item, prefix)
    candidates = {event_to_text(event_item, 'type'), ...
        event_to_text(event_item, 'value')};
    expression = ['^', upper(prefix), '[1-6]$'];
    matched = false;
    for q = 1:numel(candidates)
        current_text = upper(strtrim(candidates{q}));
        if ~isempty(regexp(current_text, expression, 'once'))
            matched = true;
            return;
        end
    end
end

function dense = connectivity_to_dense(conn, channel_labels)
    values = conn.wpli_debiasedspctrm;
    n_channels = numel(channel_labels);
    n_freqs = numel(conn.freq);

    if ndims(values) == 3 && size(values, 1) == n_channels ...
            && size(values, 2) == n_channels
        dense = values;
        return;
    end

    assert(isfield(conn, 'labelcmb'), ...
        '无法识别wPLI矩阵维度，且结果中没有labelcmb。');
    dense = nan(n_channels, n_channels, n_freqs);
    for q = 1:size(conn.labelcmb, 1)
        i = find(strcmp(channel_labels, conn.labelcmb{q, 1}), 1);
        j = find(strcmp(channel_labels, conn.labelcmb{q, 2}), 1);
        if isempty(i) || isempty(j)
            continue;
        end
        current_value = reshape(values(q, :), 1, 1, []);
        dense(i, j, :) = current_value;
        dense(j, i, :) = current_value;
    end
    for q = 1:n_channels
        dense(q, q, :) = 0;
    end
end

function matrix = force_symmetric(matrix)
    matrix = (matrix + matrix.') ./ 2;
    matrix(1:size(matrix, 1)+1:end) = 0;
end

function set_matrix_ticks(ax, labels)
    spacing = 8;
    ticks = unique([1:spacing:numel(labels), numel(labels)]);
    ax.XTick = ticks;
    ax.YTick = ticks;
    ax.XTickLabel = labels(ticks);
    ax.YTickLabel = labels(ticks);
    ax.XTickLabelRotation = 45;
    ax.FontSize = 8;
end

function draw_network(ax, matrix, xy, n_edges)
    cla(ax);
    hold(ax, 'on');
    axis(ax, 'equal');
    axis(ax, 'off');

    angle_values = linspace(0, 2*pi, 400);
    plot(ax, 1.02*cos(angle_values), 1.02*sin(angle_values), ...
        'Color', [0.35 0.35 0.35], 'LineWidth', 1.2);

    upper_indices = find(triu(true(size(matrix)), 1));
    edge_values = max(matrix(upper_indices), 0);
    [~, order] = sort(edge_values, 'descend');
    order = order(1:min(n_edges, numel(order)));
    color_map = parula(256);

    for q = 1:numel(order)
        linear_index = upper_indices(order(q));
        [i, j] = ind2sub(size(matrix), linear_index);
        weight = edge_values(order(q));
        if weight <= 0
            continue;
        end
        color_index = max(1, min(256, round(weight * 255) + 1));
        plot(ax, xy([i j], 1), xy([i j], 2), ...
            'Color', color_map(color_index, :), ...
            'LineWidth', 0.5 + 2.8 * min(weight, 1));
    end

    scatter(ax, xy(:, 1), xy(:, 2), 22, 'k', 'filled');
    colormap(ax, color_map);
    caxis(ax, [0 1]);
    colorbar(ax);
    xlim(ax, [-1.1 1.1]);
    ylim(ax, [-1.1 1.1]);
end
