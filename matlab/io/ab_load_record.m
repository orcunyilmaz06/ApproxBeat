function r = ab_load_record(rec, fs)
%AB_LOAD_RECORD  Load an MIT-BIH record the way the chip will see it.
%   r = AB_LOAD_RECORD('100') reads data/mitdb/100.*, verifies the WFDB checksums,
%   and turns the MLII lead (the first signal if a record has no MLII) into a
%   200 Hz, 11-bit ADC stream: band-limited resampling from 360 Hz followed by
%   rounding and clipping to the ADC range.
%   r = AB_LOAD_RECORD(rec, fs) resamples to fs instead.
%
%   r.adu      - ADC codes at r.fs (column vector, 0 .. 2^adcres-1)
%   r.fs, r.fs_orig, r.lead, r.gain (adu/mV), r.adczero, r.adcres
%   r.ann      - reference annotations (sample indices at r.fs_orig), see ab_read_annotations
if nargin < 2, fs = 200; end
P   = ab_paths();
hdr = ab_read_header(fullfile(P.mitdb, [rec '.hea']));
assert(all([hdr.sig.format] == 212) && numel(unique({hdr.sig.file})) == 1, ...
       'ab:io', '%s: expected all signals in one format-212 file', rec);
sig = ab_read_212(fullfile(P.mitdb, hdr.sig(1).file), hdr.nsig, hdr.nsamp);
for k = 1:hdr.nsig
    assert(sig(1, k) == hdr.sig(k).initval && ab_checksum16(sig(:, k)) == hdr.sig(k).checksum, ...
           'ab:io', '%s signal %d fails the WFDB checksum - re-download the record', rec, k);
end

ch = find(strcmp({hdr.sig.desc}, 'MLII'), 1);
if isempty(ch), ch = 1; end
s = hdr.sig(ch);
g = gcd(fs, hdr.fs);
y = ab_resample(sig(:, ch), fs / g, hdr.fs / g);

r.record  = rec;
r.fs      = fs;
r.fs_orig = hdr.fs;
r.lead    = s.desc;
r.gain    = s.gain;
r.adczero = s.adczero;
r.adcres  = s.adcres;
r.adu     = min(max(round(y), 0), 2^s.adcres - 1);
r.ann     = ab_read_annotations(fullfile(P.mitdb, [rec '.atr']));
end
