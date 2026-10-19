function x = ab_pt_stream(adu, p)
%AB_PT_STREAM  The exact sample stream the detector processes for a recording.
%   x = AB_PT_STREAM(adu, p) appends 1 s (p.fs samples) of the last ADC code to adu,
%   so that the filter pipeline flushes and a beat at the very end completes. The
%   golden vectors and the RTL testbench feed exactly this stream.
x = [adu(:); repmat(adu(end), p.fs, 1)];
end
