"""Weight kinds gallery — catalog, view, play, understand (CPU).

Lists tiny **and** large Spark stub configs (scale / multi-layer /
xl). Opt-in generate on RTX 5090; **never** the voice 6000.
Not production LLM weights. Dump/compile stay SoT for BC.
Does not beat Claude.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
from pathlib import Path
from typing import Any

from sparklang.model_lab.serve import run_tiny_forward
from sparklang.model_lab.weights import (
    emit_init_weights,
    read_safetensors,
)

ROOT_HINTS = (
    Path("."),
    Path(__file__).resolve().parents[3],
)

# Size profiles — tiny through xl (still stub control models).
PROFILES: dict[str, dict[str, Any]] = {
    "tiny": {
        "dim": 32,
        "n_layer": 2,
        "label": "Tiny control stub",
        "prefer_5090": False,
    },
    "scale": {
        "dim": 64,
        "n_layer": 4,
        "label": "F-lane scale fixture",
        "prefer_5090": False,
    },
    "large": {
        "dim": 128,
        "n_layer": 8,
        "label": "Large multi-layer + attn tensors",
        "prefer_5090": False,
    },
    "xl": {
        "dim": 256,
        "n_layer": 8,
        "label": "XL stub (opt-in 5090 generate)",
        "prefer_5090": True,
    },
}

# Kind catalog — what Spark produces / can produce.
KIND_SPECS: list[dict[str, Any]] = [
    {
        "id": "init",
        "title": "Init / dry ARTIFACT weights",
        "role": "SPARK_BC-seeded Xavier tensors; trained=false",
        "paths": [
            "docs/examples/spark-self.init.safetensors",
            "out/train/*/weights.safetensors",
        ],
        "make": "emit via model_lab / BUILD_MODELS",
    },
    {
        "id": "sgd",
        "title": "Post-STEP SGD weights",
        "role": (
            "lm_head (+ embed / attn0 when train_attn) "
            "after CPU or 5090 SGD"
        ),
        "paths": [
            "out/train/sgd-proof/weights.safetensors",
            "out/train/sgd-proof-scale/weights.safetensors",
        ],
        "make": "make spark-sgd-proof / spark-sgd-proof-scale",
    },
    {
        "id": "checkpoint",
        "title": "Checkpoints / loss-curve companions",
        "role": "checkpoint.json next to weights (not tensors)",
        "paths": [
            "out/train/sgd-proof/checkpoint.json",
            "models/spark-coder/checkpoint.json",
        ],
        "make": "written by apply_step / spark-coder-train",
    },
    {
        "id": "scale",
        "title": "Scale fixture weights (F-lane)",
        "role": "dim≥64, n_layer≥4 CPU-fast stubs",
        "paths": [
            "out/train/sgd-proof-scale/weights.safetensors",
            "out/gallery/scale/weights.safetensors",
        ],
        "make": "make spark-sgd-proof-scale or weight-gallery",
    },
    {
        "id": "spark-coder",
        "title": "Owned spark-coder TinyCoder",
        "role": "models/spark-coder trained in-repo",
        "paths": ["models/spark-coder/weights.safetensors"],
        "make": "make spark-coder-train",
    },
    {
        "id": "spark-coder-large",
        "title": "spark-coder larger variant (if present)",
        "role": "models/spark-coder-large or gallery large emit",
        "paths": [
            "models/spark-coder-large/weights.safetensors",
            "out/gallery/large/weights.safetensors",
            "out/gallery/xl/weights.safetensors",
        ],
        "make": "make weight-gallery PROFILE=large|xl",
    },
    {
        "id": "models-dir",
        "title": "Any safetensors under models/",
        "role": "scan models/**/*.safetensors",
        "paths": ["models/**/*.safetensors"],
        "make": "owned packs only",
    },
    {
        "id": "examples",
        "title": "Example / docs outputs",
        "role": "docs/examples + example train ARTIFACT siblings",
        "paths": [
            "docs/examples/*.safetensors",
            "examples/**/*.safetensors",
        ],
        "make": "checked-in init + generated",
    },
]

ROLE_EXPLAINERS: dict[str, str] = {
    "embed": (
        "Token/byte embedding table. Serve looks up rows for "
        "prompt bytes, then mean-pools or feeds attn0. "
        "Init mixes SPARK_BC bytes into early rows."
    ),
    "lm_head": (
        "Projects the final hidden vector to vocab logits. "
        "Primary STEP SGD target (CE on next-byte)."
    ),
    "norm": (
        "RMSNorm scale vector (final_norm or per-block). "
        "Stabilizes magnitudes before MLP / lm_head."
    ),
    "attn": (
        "Layer attention q/k/v/o (+ attn_norm). Allocated at "
        "init; used in serve when present; SGD when train_attn."
    ),
    "mlp": (
        "SwiGLU MLP (up/gate/down + mlp_norm). Layer-0 runs in "
        "tiny CPU serve when tensors exist."
    ),
    "other": (
        "Named Spark tensor outside the common embed/attn/mlp/"
        "lm_head map — still F32 stub weights, not HF imports."
    ),
}


def role_for_name(name: str) -> str:
    """Map tensor name → role bucket for gallery UI."""
    n = name.lower()
    if "embed" in n:
        return "embed"
    if "lm_head" in n:
        return "lm_head"
    if "norm" in n:
        return "norm"
    if any(x in n for x in (".q.", ".k.", ".v.", ".o.", "attn")):
        return "attn"
    if "mlp" in n:
        return "mlp"
    return "other"


def _repo_root(start: Path | None = None) -> Path:
    """Find repo root (has python/sparklang + docs/)."""
    cur = (start or Path.cwd()).resolve()
    for _ in range(8):
        if (cur / "python" / "sparklang").is_dir() and (
            cur / "docs"
        ).is_dir():
            return cur
        if cur.parent == cur:
            break
        cur = cur.parent
    return Path.cwd().resolve()


def _file_sha256(path: Path) -> str:
    """SHA-256 of whole file."""
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _tensor_sha256(blob: bytes) -> str:
    """SHA-256 of raw F32 payload."""
    return hashlib.sha256(blob).hexdigest()


def classify_kind(path: Path, meta: dict[str, str]) -> str:
    """Best-effort kind id from path + safetensors meta."""
    s = str(path).replace("\\", "/")
    trained = str(meta.get("trained", "false")).lower() in (
        "true",
        "1",
        "yes",
    )
    not_sgd = str(meta.get("not_sgd", "")).lower() in (
        "true",
        "1",
        "yes",
    )
    if "spark-coder-large" in s:
        return "spark-coder-large"
    if "spark-coder" in s:
        return "spark-coder"
    if "sgd-proof-scale" in s or "/gallery/scale/" in s:
        return "scale"
    if "/gallery/large/" in s or "/gallery/xl/" in s:
        return "spark-coder-large"
    if "sgd-proof" in s and trained and not not_sgd:
        return "sgd"
    if trained and not not_sgd:
        return "sgd"
    if not_sgd or meta.get("op") == "step":
        return "init"
    if s.endswith(".init.safetensors") or not trained:
        return "init"
    return "models-dir"


def size_class_from_arch(arch: dict[str, Any] | None) -> str:
    """Map arch dims to tiny|scale|large|xl."""
    if not arch:
        return "unknown"
    dim = int(arch.get("dim") or 0)
    n_layer = int(arch.get("n_layer") or 0)
    if dim >= 256:
        return "xl"
    if dim >= 128 or n_layer >= 8:
        return "large"
    if dim >= 64 or n_layer >= 4:
        return "scale"
    return "tiny"


def inspect_weights(path: str | Path) -> dict[str, Any]:
    """List tensors: name, shape, dtype, sha256, role."""
    p = Path(path)
    meta, tensors = read_safetensors(p)
    arch: dict[str, Any] | None = None
    raw_arch = meta.get("arch")
    if raw_arch:
        try:
            arch = json.loads(raw_arch)
        except json.JSONDecodeError:
            arch = None
    rows: list[dict[str, Any]] = []
    for name in sorted(tensors):
        shape, blob = tensors[name]
        role = role_for_name(name)
        rows.append(
            {
                "name": name,
                "shape": list(shape),
                "dtype": "F32",
                "nbytes": len(blob),
                "sha256": _tensor_sha256(blob),
                "role": role,
                "explainer": ROLE_EXPLAINERS[role],
            }
        )
    return {
        "path": str(p),
        "file_sha256": _file_sha256(p),
        "size_bytes": p.stat().st_size,
        "kind": classify_kind(p, meta),
        "size_class": size_class_from_arch(arch),
        "meta": meta,
        "arch": arch,
        "n_tensors": len(rows),
        "tensors": rows,
        "honesty": (
            "Tiny/large Spark stub weights — not a production LLM. "
            "Does not beat Claude. Never train on RTX PRO 6000."
        ),
    }


def _glob_safetensors(root: Path) -> list[Path]:
    """Collect safetensors under known trees."""
    found: list[Path] = []
    for rel in (
        "docs/examples",
        "models",
        "out/train",
        "out/gallery",
        "examples",
    ):
        base = root / rel
        if not base.exists():
            continue
        found.extend(sorted(base.rglob("*.safetensors")))
    # de-dupe
    uniq: dict[str, Path] = {}
    for p in found:
        uniq[str(p.resolve())] = p
    return sorted(uniq.values(), key=lambda x: str(x))


def catalog(
    root: str | Path | None = None,
) -> dict[str, Any]:
    """Catalog weight kinds + on-disk files (tiny and large)."""
    repo = _repo_root(Path(root) if root else None)
    files: list[dict[str, Any]] = []
    for path in _glob_safetensors(repo):
        try:
            info = inspect_weights(path)
        except (OSError, ValueError, KeyError) as exc:
            files.append(
                {
                    "path": str(path.relative_to(repo)),
                    "error": str(exc),
                }
            )
            continue
        files.append(
            {
                "path": str(path.relative_to(repo)),
                "kind": info["kind"],
                "size_class": info["size_class"],
                "file_sha256": info["file_sha256"],
                "n_tensors": info["n_tensors"],
                "arch": info.get("arch"),
                "trained": info["meta"].get("trained"),
                "roles": sorted(
                    {t["role"] for t in info["tensors"]}
                ),
            }
        )
    checkpoints: list[str] = []
    for rel in (
        "out/train/sgd-proof/checkpoint.json",
        "out/train/sgd-proof-scale/checkpoint.json",
        "models/spark-coder/checkpoint.json",
        "models/spark-coder-large/checkpoint.json",
        "out/gallery/scale/checkpoint.json",
        "out/gallery/large/checkpoint.json",
        "out/gallery/xl/checkpoint.json",
    ):
        if (repo / rel).is_file():
            checkpoints.append(rel)
    return {
        "root": str(repo),
        "kinds": KIND_SPECS,
        "profiles": PROFILES,
        "files": files,
        "checkpoints": checkpoints,
        "role_explainers": ROLE_EXPLAINERS,
        "note": (
            "Gallery lists tiny and large stub configs. "
            "Opt-in XL generate prefers 5090; never 6000."
        ),
    }


def _unpack_f32(blob: bytes) -> list[float]:
    n = len(blob) // 4
    return list(struct.unpack("<%df" % n, blob))


def tensor_stats(
    path: str | Path,
    *,
    name: str | None = None,
    bins: int = 16,
) -> dict[str, Any]:
    """CPU histogram / norms for one or all tensors."""
    p = Path(path)
    _meta, tensors = read_safetensors(p)
    names = [name] if name else sorted(tensors)
    out: list[dict[str, Any]] = []
    for tn in names:
        if tn not in tensors:
            raise KeyError("missing tensor %s" % tn)
        shape, blob = tensors[tn]
        vals = _unpack_f32(blob)
        if not vals:
            continue
        n = float(len(vals))
        mean = sum(vals) / n
        var = sum((v - mean) ** 2 for v in vals) / n
        rms = math.sqrt(sum(v * v for v in vals) / n)
        lo, hi = min(vals), max(vals)
        bcount = max(4, min(int(bins), 64))
        width = (hi - lo) or 1e-12
        hist = [0] * bcount
        for v in vals:
            idx = int((v - lo) / width * bcount)
            if idx >= bcount:
                idx = bcount - 1
            if idx < 0:
                idx = 0
            hist[idx] += 1
        out.append(
            {
                "name": tn,
                "shape": list(shape),
                "role": role_for_name(tn),
                "count": len(vals),
                "min": round(lo, 6),
                "max": round(hi, 6),
                "mean": round(mean, 6),
                "std": round(math.sqrt(var), 6),
                "l2": round(math.sqrt(sum(v * v for v in vals)), 6),
                "rms": round(rms, 6),
                "hist_bins": bcount,
                "hist": hist,
            }
        )
    return {
        "path": str(p),
        "device": "cpu",
        "never": "rtx-pro-6000",
        "tensors": out,
    }


def compare_weights(
    a: str | Path,
    b: str | Path,
) -> dict[str, Any]:
    """Diff two weight files by per-tensor L2 / max-abs."""
    pa, pb = Path(a), Path(b)
    _ma, ta = read_safetensors(pa)
    _mb, tb = read_safetensors(pb)
    names = sorted(set(ta) | set(tb))
    rows: list[dict[str, Any]] = []
    for name in names:
        if name not in ta or name not in tb:
            rows.append(
                {
                    "name": name,
                    "status": "missing_in_one",
                    "in_a": name in ta,
                    "in_b": name in tb,
                }
            )
            continue
        sa, ba = ta[name]
        sb, bb = tb[name]
        if sa != sb:
            rows.append(
                {
                    "name": name,
                    "status": "shape_mismatch",
                    "shape_a": list(sa),
                    "shape_b": list(sb),
                }
            )
            continue
        va, vb = _unpack_f32(ba), _unpack_f32(bb)
        diff = [va[i] - vb[i] for i in range(len(va))]
        l2 = math.sqrt(sum(d * d for d in diff))
        max_abs = max(abs(d) for d in diff) if diff else 0.0
        rows.append(
            {
                "name": name,
                "status": "ok",
                "role": role_for_name(name),
                "shape": list(sa),
                "l2_diff": round(l2, 6),
                "max_abs_diff": round(max_abs, 6),
                "same": l2 == 0.0,
            }
        )
    return {
        "a": str(pa),
        "b": str(pb),
        "file_sha_a": _file_sha256(pa),
        "file_sha_b": _file_sha256(pb),
        "identical_files": _file_sha256(pa) == _file_sha256(pb),
        "tensors": rows,
    }


def play_forward(
    path: str | Path,
    *,
    prompt: str = "hi",
) -> dict[str, Any]:
    """Tiny CPU forward/predict on any size stub weights."""
    p = Path(path)
    meta, tensors = read_safetensors(p)
    raw = prompt.encode("utf-8") or b"\0"
    ids = [int(b) for b in raw[:32]]
    fwd = run_tiny_forward(tensors, ids)
    arch = None
    if meta.get("arch"):
        try:
            arch = json.loads(meta["arch"])
        except json.JSONDecodeError:
            arch = None
    return {
        "op": "play_forward",
        "path": str(p),
        "prompt": prompt,
        "kind": classify_kind(p, meta),
        "size_class": size_class_from_arch(arch),
        "trained": meta.get("trained"),
        "forward": fwd,
        "device": "cpu",
        "never": "rtx-pro-6000",
        "note": (
            "Stub forward only — not production generation. "
            "Does not beat Claude."
        ),
    }


def _pick_device_for_generate(prefer_5090: bool) -> dict[str, Any]:
    """Reuse spark-coder device pick; never 6000."""
    from sparklang.spark_coder.device import pick_device

    force = "5090" if prefer_5090 else "cpu"
    if prefer_5090:
        return pick_device(prefer_gpu=True, force="5090")
    return pick_device(prefer_gpu=False, force=force)


def generate_profile(
    profile: str,
    dest: str | Path,
    *,
    sparkbc: str | Path = "docs/examples/spark-train-step.sparkbc",
    prefer_5090: bool | None = None,
    root: str | Path | None = None,
) -> dict[str, Any]:
    """Emit init weights for a size profile (tiny…xl).

    XL prefers 5090 when available; still writes via CPU emit
    (deterministic SPARK_BC seed). Never uses the 6000.
    """
    if profile not in PROFILES:
        raise ValueError(
            "unknown profile %r; choose %s"
            % (profile, ",".join(PROFILES))
        )
    spec = PROFILES[profile]
    repo = _repo_root(Path(root) if root else None)
    bc = Path(sparkbc)
    if not bc.is_file():
        bc = repo / sparkbc
    out = Path(dest)
    if not out.is_absolute():
        out = repo / out
    want_5090 = (
        bool(prefer_5090)
        if prefer_5090 is not None
        else bool(spec["prefer_5090"])
    )
    device = _pick_device_for_generate(want_5090)
    if device.get("device") == "cpu" and want_5090:
        # Fall back to CPU emit; report why 5090 missed.
        pass
    # Soft refuse if somehow pointed at forbidden GPU name.
    tdev = device.get("torch_device")
    if tdev is not None:
        try:
            import torch

            idx = int(str(tdev).split(":")[-1])
            name = str(torch.cuda.get_device_name(idx))
            if "6000" in name.upper():
                raise RuntimeError(
                    "refused: RTX PRO 6000 is voice-only"
                )
        except ImportError:
            pass
    result = emit_init_weights(
        bc,
        out,
        source=str(bc),
        command=(
            "weight-gallery generate profile=%s dim=%s "
            "n_layer=%s device=%s"
            % (
                profile,
                spec["dim"],
                spec["n_layer"],
                device.get("device"),
            )
        ),
        dim=int(spec["dim"]),
        n_layer=int(spec["n_layer"]),
    )
    result["profile"] = profile
    result["size_class"] = profile
    result["device_pick"] = device
    result["never"] = "rtx-pro-6000"
    result["label"] = spec["label"]
    return result


def write_catalog_json(
    dest: str | Path,
    *,
    root: str | Path | None = None,
) -> Path:
    """Write website/docs catalog JSON for the gallery page."""
    repo = _repo_root(Path(root) if root else None)
    out = Path(dest)
    if not out.is_absolute():
        out = repo / out
    out.parent.mkdir(parents=True, exist_ok=True)
    payload = catalog(repo)
    out.write_text(
        json.dumps(payload, indent=2) + "\n",
        encoding="utf-8",
    )
    return out
