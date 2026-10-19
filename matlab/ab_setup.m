function root = ab_setup()
%AB_SETUP  Put the ApproxBeat MATLAB folders on the path and return the repo root.
%   Run once per MATLAB session from the matlab/ folder:  >> ab_setup
here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here, 'io'), fullfile(here, 'model'), fullfile(here, 'eval'));
root = fileparts(here);
end
