function p = ab_paths()
%AB_PATHS  Repository folders used by the MATLAB code.
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % <root>/matlab/io/ab_paths.m
p.root    = root;
p.mitdb   = fullfile(root, 'data', 'mitdb');
p.results = fullfile(root, 'results');
end
