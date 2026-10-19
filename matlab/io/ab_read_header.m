function hdr = ab_read_header(file)
%AB_READ_HEADER  Parse a single-segment WFDB header (.hea) file.
%   hdr.record, hdr.nsig, hdr.fs, hdr.nsamp and hdr.sig(k) with fields
%   file, format, gain (adu per unit), baseline, units, adcres, adczero,
%   initval (first sample), checksum (16-bit sum of all samples), desc.
txt = fileread(file);
lines = strtrim(regexp(txt, '\r?\n', 'split'));
lines = lines(~cellfun('isempty', lines) & ~startsWith(lines, '#'));

f = strsplit(lines{1});
hdr.record = f{1};
hdr.nsig   = str2double(f{2});
hdr.fs     = str2double(regexp(f{3}, '^[\d.]+', 'match', 'once'));
hdr.nsamp  = str2double(f{4});

for k = 1:hdr.nsig
    f = strsplit(lines{1 + k});
    assert(numel(f) >= 8, 'ab:header', '%s: signal line %d is incomplete', file, k);
    s.file     = f{1};
    s.format   = str2double(regexp(f{2}, '^\d+', 'match', 'once'));
    s.gain     = str2double(regexp(f{3}, '^[-+\d.eE]+', 'match', 'once'));
    s.adcres   = str2double(f{4});
    s.adczero  = str2double(f{5});
    base       = regexp(f{3}, '\((-?\d+)\)', 'tokens', 'once');
    if isempty(base), s.baseline = s.adczero; else, s.baseline = str2double(base{1}); end
    units      = regexp(f{3}, '/(\S+)$', 'tokens', 'once');
    if isempty(units), s.units = 'mV'; else, s.units = units{1}; end
    s.initval  = str2double(f{6});
    s.checksum = str2double(f{7});
    s.desc     = strjoin(f(9:end), ' ');
    hdr.sig(k) = s;
end
end
