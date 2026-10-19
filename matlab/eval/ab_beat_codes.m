function [isbeat, symbol] = ab_beat_codes()
%AB_BEAT_CODES  WFDB annotation code tables, indexed by code + 1 (codes 0..49).
%   isbeat(code+1) - true for QRS annotations, as WFDB isqrs():
%                    N L R a V F J A S E j / Q B ? ! e n f r
%   symbol(code+1) - WFDB mnemonic of the code
map = {1,'N'; 2,'L'; 3,'R'; 4,'a'; 5,'V'; 6,'F'; 7,'J'; 8,'A'; 9,'S'; 10,'E'; ...
       11,'j'; 12,'/'; 13,'Q'; 14,'~'; 16,'|'; 18,'s'; 19,'T'; 20,'*'; 21,'D'; ...
       22,'"'; 23,'='; 24,'p'; 25,'B'; 26,'^'; 27,'t'; 28,'+'; 29,'u'; 30,'?'; ...
       31,'!'; 32,'['; 33,']'; 34,'e'; 35,'n'; 36,'@'; 37,'x'; 38,'f'; 39,'('; ...
       40,')'; 41,'r'};
symbol = repmat(' ', 1, 50);
for k = 1:size(map, 1)
    symbol(map{k, 1} + 1) = map{k, 2};
end
isbeat = false(1, 50);
isbeat([1:13, 25, 30, 31, 34, 35, 38, 41] + 1) = true;
end
