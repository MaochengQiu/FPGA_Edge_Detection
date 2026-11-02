"""Independent E3 oracle: unchanged E2 union strict seeded tangent runs."""
import numpy as np
from e2_model import local_link


def weak_runs(candidate, seed, direction):
    h, w = candidate.shape
    out = np.zeros_like(candidate)
    for y in range(2, h - 2):
        for x in range(2, w - 2):
            # Horizontal, vertical, descending diagonal, ascending diagonal.
            for dx, dy, normal in ((1, 0, 2), (0, 1, 0), (1, 1, 3), (1, -1, 1)):
                points = [(y + k * dy, x + k * dx) for k in range(-2, 3)]
                if all(candidate[yy, xx] and direction[yy, xx] == normal for yy, xx in points):
                    if any(seed[yy, xx] for yy, xx in points):
                        out[y, x] = True
                        break
    return out


def e3_link(eligible, candidate, seed, direction, bridge=True, enabled=True):
    base = local_link(eligible, candidate, seed, direction, bridge=bridge)
    return base | weak_runs(candidate, seed, direction) if enabled else base
