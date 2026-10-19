function ab_npy_write(file, A)
%AB_NPY_WRITE  Write a 2-D integer matrix as a NumPy .npy file (int32, little-endian, C order).
%   AB_NPY_WRITE(file, A) for an integer-valued matrix A within the int32 range. In
%   Python, numpy.load(file) returns the same matrix with shape size(A). NPY format
%   version 1.0: magic, version, header length, a dict literal padded so that the data
%   starts on a 64-byte boundary, then the rows one after another.
assert(ismatrix(A) && isnumeric(A) && all(A(:) == round(A(:))) && all(abs(A(:)) < 2^31), ...
       'ab:npy', 'ab_npy_write expects an integer matrix within the int32 range');
hdr = sprintf('{''descr'': ''<i4'', ''fortran_order'': False, ''shape'': (%d, %d), }', ...
              size(A, 1), size(A, 2));
pad = mod(-(10 + numel(hdr) + 1), 64);
hdr = [hdr, repmat(' ', 1, pad), newline];
fid = fopen(file, 'w', 'ieee-le');
assert(fid > 0, 'ab:npy', 'cannot write %s', file);
closer = onCleanup(@() fclose(fid));
fwrite(fid, [147, double('NUMPY'), 1, 0], 'uint8');   % \x93NUMPY, version 1.0
fwrite(fid, numel(hdr), 'uint16');
fwrite(fid, hdr, 'char');
fwrite(fid, int32(A.'), 'int32');                       % row-major
end
