function ann = ab_read_annotations(file)
%AB_READ_ANNOTATIONS  Read a WFDB annotation file in MIT format (e.g. 100.atr).
%   ann.sample  - 0-based sample index at the record's sampling frequency
%   ann.type    - WFDB annotation code (1 = N, 5 = V, 28 = rhythm, ...; see ab_beat_codes)
%   ann.subtype, ann.chan, ann.num - WFDB fields
%   ann.aux     - auxiliary text per annotation (e.g. '(AFIB' for rhythm changes)
%
%   Every annotation is a little-endian 16-bit word: a 6-bit code A and a 10-bit
%   time step I. A = 59 (SKIP) carries a 32-bit step in the next four bytes
%   (high word first). A = 60/61/62 (NUM/SUB/CHN) and 63 (AUX, I = byte count)
%   modify the annotation before them. The word 0x0000 ends the file.
fid = fopen(file, 'r');
assert(fid > 0, 'ab:io', 'cannot open %s', file);
closer = onCleanup(@() fclose(fid));
b = fread(fid, inf, 'uint8=>double');

cap = floor(numel(b) / 2);
sample = zeros(cap, 1); type = zeros(cap, 1); subtype = zeros(cap, 1);
chan = zeros(cap, 1); num = zeros(cap, 1); aux = repmat({''}, cap, 1);
t = 0; n = 0; cur_chan = 0; cur_num = 0; i = 1;
while i + 1 <= numel(b)
    w = b(i) + 256 * b(i+1);
    i = i + 2;
    if w == 0, break; end
    A = floor(w / 1024);
    I = w - 1024 * A;
    switch A
        case 59                                   % SKIP
            step = 65536 * (b(i) + 256 * b(i+1)) + b(i+2) + 256 * b(i+3);
            if step >= 2^31, step = step - 2^32; end
            t = t + step;
            i = i + 4;
        case 60                                   % NUM (sticky)
            cur_num = I; if n > 0, num(n) = I; end
        case 61                                   % SUB
            if n > 0, subtype(n) = I; end
        case 62                                   % CHN (sticky)
            cur_chan = I; if n > 0, chan(n) = I; end
        case 63                                   % AUX: I bytes of text, padded to even
            if n > 0
                s = char(b(i:i+I-1)).';
                aux{n} = s(s ~= 0);
            end
            i = i + I + mod(I, 2);
        otherwise                                 % an actual annotation
            t = t + I;
            n = n + 1;
            sample(n) = t; type(n) = A; chan(n) = cur_chan; num(n) = cur_num;
    end
end
k = 1:n;
ann = struct('sample', sample(k), 'type', type(k), 'subtype', subtype(k), ...
             'chan', chan(k), 'num', num(k));
ann.aux = aux(k);
end
