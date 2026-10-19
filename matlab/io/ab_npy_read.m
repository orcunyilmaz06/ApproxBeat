function A = ab_npy_read(file)
%AB_NPY_READ  Read an int32 .npy file in C order (as ab_npy_write writes) into a double matrix.
fid = fopen(file, 'r', 'ieee-le');
assert(fid > 0, 'ab:npy', 'cannot open %s', file);
closer = onCleanup(@() fclose(fid));
magic = fread(fid, 6, 'uint8=>double').';
assert(isequal(magic, [147, double('NUMPY')]), 'ab:npy', '%s is not a .npy file', file);
ver = fread(fid, 2, 'uint8=>double');
if ver(1) == 1, hlen = fread(fid, 1, 'uint16=>double'); else, hlen = fread(fid, 1, 'uint32=>double'); end
hdr = fread(fid, hlen, 'char=>char').';
assert(contains(hdr, '''<i4''') && contains(hdr, '''fortran_order'': False'), 'ab:npy', ...
       '%s: expected little-endian int32 in C order', file);
tok = regexp(hdr, '''shape'':\s*\((\d+),\s*(\d*)\)', 'tokens', 'once');
rows = str2double(tok{1});
cols = str2double(tok{2});
if isnan(cols), cols = 1; end                           % 1-D array: shape (N,)
A = double(reshape(fread(fid, rows * cols, 'int32=>int32'), cols, rows).');
end
