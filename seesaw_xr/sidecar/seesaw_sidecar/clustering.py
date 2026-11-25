"""Cosine k-means and the 'stable colours' matching between successive probes."""
import numpy as np


def l2n(a, axis=-1):
    return a / (np.linalg.norm(a, axis=axis, keepdims=True) + 1e-8)


def kmeans(x, k, iters=25, seed=0):
    """Cosine k-means with k-means++ init. x: (N, C) L2-normalised."""
    rng = np.random.default_rng(seed)
    c = [x[rng.integers(len(x))]]
    for _ in range(1, k):
        d = 1.0 - np.max(x @ np.stack(c).T, axis=1)
        d = np.clip(d, 0, None) + 1e-9
        c.append(x[rng.choice(len(x), p=d / d.sum())])
    c = np.stack(c)
    for _ in range(iters):
        lab = np.argmax(x @ c.T, axis=1)
        for j in range(k):
            m = x[lab == j]
            if len(m):
                c[j] = m.mean(0)
        c = l2n(c)
    return np.argmax(x @ c.T, axis=1), c


def match_to_previous(cent, prev):
    """Reorder clusters so they best match the previous probe (same group keeps its colour)."""
    cost = -(cent @ prev.T)
    try:
        from scipy.optimize import linear_sum_assignment
        rows, cols = linear_sum_assignment(cost)
        perm = np.empty(len(cent), int)
        perm[cols] = rows          # new slot `col` takes old cluster `row`
        return perm
    except ImportError:            # greedy fallback
        perm, used = np.full(len(cent), -1), set()
        for col in range(len(prev)):
            order = np.argsort(cost[:, col])
            row = next(r for r in order if r not in used)
            perm[col] = row
            used.add(row)
        return perm
