function [png_path, mapping_path] = render_one_wpli_fsaverage( ...
        result_mat, fsaverage_dir, output_dir, ...
        n_edges_to_plot, fieldtrip_dir)
%% 将一条59导或64导wPLI结果投影到fsaverage皮层表面
% 输入参数：
%   result_mat      - compute_one_subject_wpli生成的MAT文件。
%   fsaverage_dir   - FreeSurfer fsaverage被试目录。
%   output_dir      - 图片和节点映射的输出目录。
%   n_edges_to_plot - 每个频段显示的最强正连接数，默认20。
%   fieldtrip_dir   - FieldTrip根目录；已加载时可传空字符串。
%
% 输出参数：
%   png_path     - theta/alpha双面板三维脑表面PNG。
%   mapping_path - standard_1005电极到fsaverage表面的可视化映射。
%
% 解释边界：这是传感器空间网络的fsaverage投影可视化，不是源空间wPLI。
% 不得将该图表述为皮层脑区之间的功能连接。

if nargin < 5
    fieldtrip_dir = '';
end
if nargin < 4 || isempty(n_edges_to_plot)
    n_edges_to_plot = 20;
end
assert(nargin >= 3, ...
    '必须提供result_mat、fsaverage_dir和output_dir。');

%% 2. 初始化FieldTrip
if exist('ft_defaults', 'file') == 2
    fieldtrip_dir = fileparts(which('ft_defaults'));
elseif ~isempty(fieldtrip_dir) && isfolder(fieldtrip_dir)
    addpath(fieldtrip_dir);
else
    error(['没有检测到FieldTrip。请先执行addpath(''FieldTrip根目录''); ', ...
        'ft_defaults，然后重新运行。']);
end
ft_defaults;

assert(isfile(result_mat), '找不到wPLI结果：%s', result_mat);
assert(isfolder(fsaverage_dir), '找不到fsaverage目录：%s', fsaverage_dir);
if ~isfolder(output_dir)
    mkdir(output_dir);
end

%% 3. 读取wPLI结果和通道标签
result = load(result_mat);
required_fields = {'theta_matrix', 'alpha_matrix', 'params'};
for k = 1:numel(required_fields)
    assert(isfield(result, required_fields{k}), ...
        '结果MAT缺少变量：%s', required_fields{k});
end

if isfield(result, 'channel_labels')
    channel_labels = result.channel_labels;
else
    assert(isfield(result.params, 'input_fif'), ...
        '旧MAT没有channel_labels，也没有params.input_fif。');
    hdr = ft_read_header(result.params.input_fif);
    channel_labels = hdr.label;
end
channel_labels = channel_labels(:);
n_channels = numel(channel_labels);
% 绘图沿用结果MAT中的原始节点集合，不补节点、不删节点、不插值连接。
assert(ismember(n_channels, [59, 64]), ...
    '当前结果为%d导；本流程仅支持59导或64导。', n_channels);
if n_channels == 59
    channel_title = '59导（非64导，仅个体展示）';
    title_color = [0.75, 0.10, 0.10];
else
    channel_title = '64导';
    title_color = [0.10, 0.10, 0.10];
end

%% 4. 读取standard_1005标准电极位置
standard_elec_file = fullfile(fieldtrip_dir, 'template', ...
    'electrode', 'standard_1005.elc');
assert(isfile(standard_elec_file), ...
    '找不到标准电极文件：%s', standard_elec_file);
template_elec = ft_read_sens(standard_elec_file);
[data_idx, template_idx] = match_str(channel_labels, template_elec.label);
assert(numel(data_idx) == numel(channel_labels), ...
    '有%d个通道无法匹配standard_1005.elc。', ...
    numel(channel_labels) - numel(data_idx));

electrode_pos = nan(numel(channel_labels), 3);
electrode_pos(data_idx, :) = template_elec.chanpos(template_idx, :);

%% 5. 读取fsaverage左右半球pial表面
lh_file = fullfile(fsaverage_dir, 'surf', 'lh.pial');
rh_file = fullfile(fsaverage_dir, 'surf', 'rh.pial');
assert(isfile(lh_file) && isfile(rh_file), ...
    'fsaverage/surf中缺少lh.pial或rh.pial。');

lh = ft_read_headshape(lh_file);
rh = ft_read_headshape(rh_file);
lh = ft_convert_units(lh, 'mm');
rh = ft_convert_units(rh, 'mm');

brain_vertices = [lh.pos; rh.pos];
brain_faces = [lh.tri; rh.tri + size(lh.pos, 1)];
brain_center = (min(brain_vertices, [], 1) + max(brain_vertices, [], 1)) ./ 2;

% 降低绘图面数，不改变节点映射使用的原始表面。
[plot_faces, plot_vertices] = reducepatch(brain_faces, brain_vertices, 0.08);

%% 6. 按头皮方向把标准电极投影到皮层外表面
node_pos = project_electrodes_to_surface(electrode_pos, ...
    brain_vertices, brain_center);

%% 7. 绘制theta和alpha三维脑网络
fig = figure('Color', 'w', 'Position', [80 80 1600 760], ...
    'Renderer', 'opengl');
layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(layout);
draw_brain_network(ax1, plot_vertices, plot_faces, node_pos, ...
    result.theta_matrix, n_edges_to_plot, brain_center);
title(ax1, sprintf('theta 4-8 Hz：fsaverage皮层上的最强%d条连接', ...
    n_edges_to_plot), 'FontSize', 13);

ax2 = nexttile(layout);
draw_brain_network(ax2, plot_vertices, plot_faces, node_pos, ...
    result.alpha_matrix, n_edges_to_plot, brain_center);
title(ax2, sprintf('alpha 8-13 Hz：fsaverage皮层上的最强%d条连接', ...
    n_edges_to_plot), 'FontSize', 13);
rotate3d(fig, 'on');

[~, result_name] = fileparts(result_mat);
sgtitle(fig, sprintf('%s | %s去偏平方wPLI传感器网络投影', ...
    result_name, channel_title), ...
    'Interpreter', 'none', 'FontSize', 15, 'FontWeight', 'bold', ...
    'Color', title_color);

png_path = fullfile(output_dir, [result_name, '_fsaverage脑表面.png']);
mapping_path = fullfile(output_dir, [result_name, '_fsaverage节点映射.mat']);
exportgraphics(fig, png_path, 'Resolution', 220);
save(mapping_path, 'node_pos', 'channel_labels', 'electrode_pos', ...
    'brain_center', 'n_edges_to_plot');

fprintf('\nfsaverage脑网络图已生成：\n%s\n', png_path);
fprintf('节点映射已保存：\n%s\n', mapping_path);
close(fig);

end

%% 局部函数
function node_pos = project_electrodes_to_surface(electrode_pos, ...
        surface_vertices, surface_center)
    sensor_center = mean(electrode_pos, 1, 'omitnan');
    sensor_vectors = electrode_pos - sensor_center;
    sensor_vectors = sensor_vectors ./ vecnorm(sensor_vectors, 2, 2);

    surface_vectors = surface_vertices - surface_center;
    surface_radius = vecnorm(surface_vectors, 2, 2);
    surface_unit = surface_vectors ./ surface_radius;
    node_pos = nan(size(electrode_pos));

    for q = 1:size(electrode_pos, 1)
        angular_score = surface_unit * sensor_vectors(q, :).';
        n_candidates = max(1, ceil(0.001 * numel(angular_score)));
        [~, candidates] = maxk(angular_score, n_candidates);
        [~, farthest_idx] = max(surface_radius(candidates));
        surface_idx = candidates(farthest_idx);
        node_pos(q, :) = surface_center + 1.035 * surface_vectors(surface_idx, :);
    end
end

function draw_brain_network(ax, vertices, faces, node_pos, matrix, ...
        n_edges, brain_center)
    cla(ax);
    hold(ax, 'on');

    patch(ax, 'Faces', faces, 'Vertices', vertices, ...
        'FaceColor', [0.78 0.80 0.83], 'EdgeColor', 'none', ...
        'FaceAlpha', 0.34, 'FaceLighting', 'gouraud', ...
        'AmbientStrength', 0.42, 'DiffuseStrength', 0.62);

    matrix = (matrix + matrix.') ./ 2;
    matrix(1:size(matrix, 1)+1:end) = 0;
    upper_indices = find(triu(true(size(matrix)), 1));
    edge_values = max(matrix(upper_indices), 0);
    [~, order] = sort(edge_values, 'descend');
    order = order(1:min(n_edges, numel(order)));
    color_map = turbo(256);

    for q = 1:numel(order)
        linear_idx = upper_indices(order(q));
        [i, j] = ind2sub(size(matrix), linear_idx);
        weight = edge_values(order(q));
        if ~isfinite(weight) || weight <= 0
            continue;
        end
        curve = make_arc(node_pos(i, :), node_pos(j, :), brain_center);
        color_idx = max(1, min(256, round(weight * 255) + 1));
        plot3(ax, curve(:, 1), curve(:, 2), curve(:, 3), ...
            'Color', color_map(color_idx, :), ...
            'LineWidth', 0.8 + 4.0 * min(weight, 1));
    end

    scatter3(ax, node_pos(:, 1), node_pos(:, 2), node_pos(:, 3), ...
        27, [0.08 0.08 0.08], 'filled', 'MarkerEdgeColor', 'w', ...
        'LineWidth', 0.35);

    axis(ax, 'equal');
    axis(ax, 'off');
    view(ax, 0, 90);
    colormap(ax, color_map);
    caxis(ax, [0 1]);
    colorbar(ax, 'southoutside');
    camlight(ax, 'headlight');
    material(ax, 'dull');
end

function curve = make_arc(p1, p2, center)
    midpoint = (p1 + p2) ./ 2;
    outward = midpoint - center;
    outward_norm = norm(outward);
    if outward_norm < eps
        outward = [0 0 1];
    else
        outward = outward ./ outward_norm;
    end
    arc_height = 0.16 * norm(p2 - p1) + 7;
    control = midpoint + arc_height * outward;
    t = linspace(0, 1, 60).';
    curve = ((1 - t).^2) .* p1 + 2 .* (1 - t) .* t .* control + (t.^2) .* p2;
end
