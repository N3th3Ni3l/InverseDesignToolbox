function m = preview_mesh(gm, divisions)
% PREVIEW_MESH  Coarse linear helper mesh for plots / face tables, robust to thin features.
% Tries Hmax = ext/divisions first; if the mesher fails (thin walls, small holes, sliver faces),
% retries with progressively finer Hmax until one succeeds.
%
%   m = preview_mesh(gm, 18)
%
%   gm        : fegeometry
%   divisions : first attempt uses Hmax = largest dimension / divisions (default 25)
%   m         : femodel with the mesh in m.Mesh
%
% Author: Dr. Osman Sayginer (InverseDesignToolbox)

    if nargin < 2 || isempty(divisions), divisions = 25; end
    ext = max(max(gm.Vertices) - min(gm.Vertices));
    tries = unique([divisions, 25, 40, 60, 90, 130], 'stable');
    tries = tries(tries >= divisions);
    lastErr = [];
    for k = 1:numel(tries)
        h = ext / tries(k);
        try
            m = generateMesh(femodel(AnalysisType="structuralStatic", Geometry=gm), ...
                             Hmax=h, GeometricOrder="linear");
            return;
        catch err
            lastErr = err;
        end
    end
    error('preview_mesh:Failed', ['Preview mesh failed even at Hmax = %.3g mm. The geometry may ' ...
        'have very thin features or defects.\nLast mesher error: %s'], h * 1e3, lastErr.message);
end
