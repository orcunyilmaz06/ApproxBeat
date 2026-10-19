function x = ab_read_212(file, nsig, nsamp)
%AB_READ_212  Read a WFDB format-212 signal file into an nsamp-by-nsig matrix of ADC units.
%   Format 212 packs two 12-bit two's-complement samples into three bytes:
%     s0 = b0 | (b1 & 0x0F) << 8,    s1 = b2 | (b1 & 0xF0) << 4
%   and interleaves the signals frame by frame.
fid = fopen(file, 'r');
assert(fid > 0, 'ab:io', 'cannot open %s', file);
closer = onCleanup(@() fclose(fid));
b = fread(fid, inf, 'uint8=>double');

if nargin < 3 || isnan(nsamp)
    nsamp = floor(numel(b) * 2 / 3 / nsig);
end
nval   = nsig * nsamp;
nbytes = 3 * ceil(nval / 2);
assert(numel(b) >= nbytes - 1, 'ab:io', '%s: expected %d bytes, found %d', file, nbytes, numel(b));
b(end+1:nbytes) = 0;                     % odd value count: the last triplet has two bytes
b  = reshape(b(1:nbytes), 3, []);
s0 = b(1,:) + 256 * bitand(b(2,:), 15);
s1 = b(3,:) +  16 * bitand(b(2,:), 240);
v  = reshape([s0; s1], [], 1);
v  = v(1:nval);
v  = v - 4096 * (v >= 2048);             % 12-bit two's complement
x  = reshape(v, nsig, nsamp).';
end
