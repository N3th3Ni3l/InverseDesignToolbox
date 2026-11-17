function bricks = idt_make_bricks_multi(geom, D)
% IDT_MAKE_BRICKS_MULTI  Design domain made of SEVERAL parts on one shared brick grid.
%
%   bricks = idt_make_bricks_multi(geom, P.Design)      (called by idt_make_bricks when numel(P.Design.Part) > 1)
%
%   geom : from idt_import_geometry
%   D    : P.Design with .Part = list of part indices, e.g. [2 4], plus MinPrintSize, Density, Layers,
%          MinFill, MaxOverlap (same meaning as for one part, see docs/01_model_setup.md)
%
% One grid covers the bounding box of all design parts. A grid cell is a brick if
%   - at least MinFill of it is material of the design parts (counted together), and
%   - at most MaxOverlap of it is material of the OTHER parts (e.g. a fixed frame lying between two design frames).
% The result uses the engine's 'box' mode (core/build_model.m): elements whose centroid lies in a brick become
% switchable. With MaxOverlap = 0 a brick holds (almost) no material of a non-design part, so only the design
% parts are changed. Cells that are not bricks stay solid, as for one design part.
%
% OUTPUT bricks: same fields as create_bricks (.Mode = 'box', .Grid, .Present, .Fill, .Overlap, ...), plus
%   .DesignParts (the list of parts). .DesignPart is [] as in box mode.
%
% Author: Dr. Osman Sayginer (InverseDesignToolbox)

    ips = unique(D.Part(:))';
    bbs = cat(1, geom.Parts(ips).BBox);                       % [xmin xmax ymin ymax zmin zmax] per part [m]
    bb  = [min(bbs(:,1)) max(bbs(:,2)) min(bbs(:,3)) max(bbs(:,4)) min(bbs(:,5)) max(bbs(:,6))];
    grid = brick_grid_from_density(bb, 'MinPrintSize', D.MinPrintSize, 'Density', D.Density, 'Layers', D.Layers);
    N = grid.N; bs = grid.Size;

    % 4 x 4 x 4 sample points per cell, as in create_bricks
    S = 4; offs = ((1:S) - 0.5) / S - 0.5;
    [ox, oy, oz] = ndgrid(offs, offs, offs); O = [ox(:) oy(:) oz(:)];
    [I, J, K] = ndgrid(1:N(1), 1:N(2), 1:N(3));
    C = grid.Min + ([I(:) J(:) K(:)] - 0.5) .* bs;            % cell centers [m]

    isDes = false(size(C, 1), size(O, 1));                    % sample point inside ANY design part
    isOth = false(size(C, 1), size(O, 1));                    % sample point inside any OTHER part
    for q = 1:numel(geom.Parts)
        TR = triangulation(geom.Parts(q).Tets, geom.Parts(q).Nodes);
        for s = 1:size(O, 1)
            in = ~isnan(pointLocation(TR, C + O(s, :) .* bs));
            if ismember(q, ips), isDes(:, s) = isDes(:, s) | in; else, isOth(:, s) = isOth(:, s) | in; end
        end
    end
    fill    = reshape(mean(isDes, 2), N);
    overlap = reshape(mean(isOth & ~isDes, 2), N);            % where parts overlap, design material wins the sample

    present = fill >= D.MinFill & overlap <= D.MaxOverlap + 1e-9;
    nExcl = nnz(fill > 0 & ~present);
    names = strjoin({geom.Parts(ips).Name}, ' + ');

    bricks = struct('Mode', 'box', 'DesignPart', [], 'DesignParts', ips, 'Box', bb, 'Name', names, ...
                    'Grid', grid, 'Present', present, 'Fill', fill, 'Overlap', overlap, ...
                    'NumPresent', nnz(present), 'NumExcluded', nExcl);
    fprintf('  Design parts: %s\n', names);
    fprintf('  Bricks: %d (cells with design material excluded for sliver/overlap: %d)\n\n', bricks.NumPresent, nExcl);
end
