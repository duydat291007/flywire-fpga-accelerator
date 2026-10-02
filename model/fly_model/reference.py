"""Mathematical reference for the matrix-vector unit and the LIF neuron.

Deliberately naive: plain Python integers, a direct double loop, no tiling,
no knowledge of the array shape or memory layout. If the RTL tiling is wrong,
this model will not share the mistake.
"""

from .constants import W_MIN, W_MAX, X_MIN, X_MAX, ACC_MIN, ACC_MAX, V_MAX, U_MAX


def check_int8(value, lo, hi, name):
    if not (isinstance(value, int) and lo <= value <= hi):
        raise ValueError(f"{name}={value!r} outside [{lo}, {hi}]")


def matvec(weights, x, dim):
    """y[i] = sum_{j<dim} W[i][j] * x[j] for i < dim.  W is W[destination][source]."""
    if not 1 <= dim <= len(weights):
        raise ValueError(f"illegal dim {dim}")
    y = []
    for i in range(dim):
        total = 0
        for j in range(dim):
            w, xv = weights[i][j], x[j]
            check_int8(w, W_MIN, W_MAX, f"W[{i}][{j}]")
            check_int8(xv, X_MIN, X_MAX, f"x[{j}]")
            total += w * xv
        # Specification: legal inputs can never exceed the 32-bit accumulator.
        assert ACC_MIN <= total <= ACC_MAX, "accumulator range proof violated"
        y.append(total)
    return y


def lif_update(v, network_input, external_input, threshold):
    """One neuron, one timestep. Returns (next_potential, spike)."""
    if not 1 <= threshold <= V_MAX:
        raise ValueError("threshold must be in 1..65535")
    if not 0 <= v < threshold:
        raise ValueError(f"stored potential {v} violates 0 <= V < threshold")
    if not 0 <= external_input <= U_MAX:
        raise ValueError("external input must be 0..255")
    leaked = (15 * v) // 16
    candidate = leaked + network_input + external_input
    if candidate >= threshold:
        return 0, 1
    return max(0, candidate), 0
