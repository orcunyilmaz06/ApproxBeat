function m = ab_match_beats(t_ref, t_det, tol)
%AB_MATCH_BEATS  One-to-one beat matching within +-tol seconds (ANSI/AAMI EC57 style).
%   m = AB_MATCH_BEATS(t_ref, t_det, tol) walks both time-sorted lists once. A
%   detection within tol of the current reference beat is a true positive (when
%   the next detection is even closer, the earlier one is counted as extra), an
%   earlier detection is a false positive, and a reference beat without a
%   detection within tol is a false negative.
%   m.tp, m.fn, m.fp, m.ref_hit / m.det_hit (logical per sorted beat),
%   m.err - t_det - t_ref of every matched pair (s)
t_ref = sort(t_ref(:)); t_det = sort(t_det(:));
nr = numel(t_ref); nd = numel(t_det);
ref_hit = false(nr, 1); det_hit = false(nd, 1);
err = zeros(min(nr, nd), 1); ne = 0;
i = 1; j = 1;
while i <= nr && j <= nd
    d = t_det(j) - t_ref(i);
    if abs(d) <= tol
        if j < nd && abs(t_det(j+1) - t_ref(i)) < abs(d)
            j = j + 1;                       % an extra detection just before the match
            continue
        end
        ref_hit(i) = true; det_hit(j) = true;
        ne = ne + 1; err(ne) = d;
        i = i + 1; j = j + 1;
    elseif d < 0
        j = j + 1;                           % detection with no beat nearby
    else
        i = i + 1;                           % beat with no detection nearby
    end
end
m.tp = ne;
m.fn = nr - ne;
m.fp = nd - ne;
m.ref_hit = ref_hit;
m.det_hit = det_hit;
m.err = err(1:ne);
end
