function c = ab_checksum16(v)
%AB_CHECKSUM16  WFDB signal checksum: sum of all samples as a 16-bit two's-complement number.
c = mod(sum(v), 65536);
c = c - 65536 * (c >= 32768);
end
