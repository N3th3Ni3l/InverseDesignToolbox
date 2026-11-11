function T = list_faces(geom, verbose)
% LIST_FACES  Face IDs of the ASSEMBLY with centroid and size, to pick faces by rule.
%
%   T = list_faces(geom);
%   holes = T.ID(T.Extent(:,3) >= 4.9e-3 & abs(T.Centroid(:,1)) > 20e-3);
%
% T.Centroid, T.Extent (bounding-box size) are in meters and come from a coarse mesh.
%
% Author: Dr. Osman Sayginer (InverseDesignToolbox)

    if nargin < 2, verbose = true; end
    gm = geom.Assembly;
    m = preview_mesh(gm, 25);       % retries finer if the coarse preview mesh fails
    nd = m.Mesh.Nodes;
    nf = gm.NumFaces;
    ID = (1:nf)'; C = zeros(nf, 3); E = zeros(nf, 3);
    for f = 1:nf
        k = findNodes(m.Mesh, 'region', 'Face', f);
        C(f, :) = mean(nd(:, k), 2)';
        E(f, :) = (max(nd(:, k), [], 2) - min(nd(:, k), [], 2))';
    end
    T = table(ID, C, E, 'VariableNames', {'ID', 'Centroid', 'Extent'});
    if verbose
        fprintf('Assembly faces (mm):\n  ID |     centroid (x y z)      |   extent (x y z)\n');
        for f = 1:nf
            fprintf(' %3d | %7.2f %7.2f %7.2f | %6.1f %6.1f %6.1f\n', f, C(f,:)*1e3, E(f,:)*1e3);
        end
        fprintf('\n');
    end
end
