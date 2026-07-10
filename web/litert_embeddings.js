import { m as E, d as R, s as A, r as S } from "./tensorflow.js";
import { l as k, a as y, T as h } from "./litert.js";
import { S as M } from "./sentencepiece.js";
const z = "task: search result | query: ", F = "title: none | text: ", p = 2, T = 1, b = 0;
let c = 256;
const g = 768;
let s = null, d = null, u = !1, m = !1;
async function x(o) {
  try {
    const n = await fetch(o);
    if (!n.ok)
      throw new Error(`Failed to fetch tokenizer: ${n.status} ${n.statusText}`);
    const r = await n.arrayBuffer(), t = new M();
    if (typeof t.loadFromBuffer == "function")
      await t.loadFromBuffer(new Uint8Array(r));
    else {
      const e = new Uint8Array(r);
      let a = "";
      for (let l = 0; l < e.length; l++)
        a += String.fromCharCode(e[l]);
      const i = btoa(a);
      await t.loadFromB64StringModel(i);
    }
    return d = {
      encode: (e, a = !1) => {
        const i = t.encodeIds(e);
        return a ? [p, ...i, T] : i;
      },
      decode: (e) => t.decodeIds(e),
      processor: t
    }, d;
  } catch (n) {
    throw new Error("Failed to load SentencePiece tokenizer: " + n.message);
  }
}
async function C(o, n = "/wasm/") {
  try {
    console.log(`[LiteRT] Loading model from: ${o}`), console.log(`[LiteRT] WASM loaded flag: ${m}`), await A("webgl"), await S(), m ? console.log("[LiteRT] WASM runtime already loaded, reusing") : (console.log(`[LiteRT] Loading WASM runtime from: ${n}`), await k(n), m = !0, console.log("[LiteRT] WASM runtime loaded successfully"));
    try {
      console.log("[LiteRT] Attempting to compile model with WebGPU..."), s = await y(o, {
        accelerator: "webgpu"
      }), console.log("[LiteRT] Model compiled with WebGPU successfully");
    } catch (r) {
      console.warn("[LiteRT] WebGPU not available, falling back to WASM:", r.message), s = await y(o, {
        accelerator: "wasm"
      }), console.log("[LiteRT] Model compiled with WASM successfully");
    }
    try {
      const r = s.getInputDetails();
      if (r && r.length > 0) {
        const t = r[0].shape;
        if (t && t.length >= 2) {
          const e = t[1];
          e !== c && (c = e, console.log(`[LiteRT] Auto-detected maxSequenceLength: ${c}`));
        }
      }
    } catch (r) {
      console.warn("[LiteRT] Failed to auto-detect sequence length, using default:", r);
    }
    return s;
  } catch (r) {
    throw new Error("Failed to load LiteRT model: " + r.message);
  }
}
function D(o) {
  const n = d.encode(z, !1), r = "▁" + o, t = d.encode(r, !1);
  let e = [...n, ...t];
  if (e.unshift(p), e.push(T), e.length > c)
    e = e.slice(0, c);
  else if (e.length < c) {
    const a = c - e.length;
    e = [...e, ...new Array(a).fill(b)];
  }
  return e;
}
function I(o) {
  const n = d.encode(F, !1), r = "▁" + o, t = d.encode(r, !1);
  let e = [...n, ...t];
  if (e.unshift(p), e.push(T), e.length > c)
    e = e.slice(0, c);
  else if (e.length < c) {
    const a = c - e.length;
    e = [...e, ...new Array(a).fill(b)];
  }
  return e;
}
async function L(o) {
  if (!s || !d)
    throw new Error("Model or tokenizer not initialized. Call loadLiteRtEmbeddings first.");
  const n = D(o), r = new Int32Array(n), t = new h(r, [1, c]);
  let e = t;
  s.accelerator === "webgpu" && (e = await t.moveTo("webgpu"));
  try {
    const i = s.run(e)[0];
    let l = i;
    i.accelerator === "webgpu" && (l = await i.moveTo("wasm"));
    const w = l.toTypedArray(), f = Array.from(w);
    return f.length !== g && console.warn(`Unexpected embedding dimension: ${f.length}, expected ${g}`), e !== t && !e.deleted && e.delete(), t.deleted || t.delete(), l !== i && !l.deleted && l.delete(), i.deleted || i.delete(), f;
  } catch (a) {
    try {
      e !== t && !e.deleted && e.delete(), t.deleted || t.delete();
    } catch (i) {
      console.warn("[LiteRT] Tensor cleanup failed:", i);
    }
    throw a;
  }
}
async function _(o) {
  if (!s || !d)
    throw new Error("Model or tokenizer not initialized. Call loadLiteRtEmbeddings first.");
  const n = I(o), r = new Int32Array(n), t = new h(r, [1, c]);
  let e = t;
  s.accelerator === "webgpu" && (e = await t.moveTo("webgpu"));
  try {
    const i = s.run(e)[0];
    let l = i;
    i.accelerator === "webgpu" && (l = await i.moveTo("wasm"));
    const w = l.toTypedArray(), f = Array.from(w);
    return f.length !== g && console.warn(`Unexpected embedding dimension: ${f.length}, expected ${g}`), e !== t && !e.deleted && e.delete(), t.deleted || t.delete(), l !== i && !l.deleted && l.delete(), i.deleted || i.delete(), f;
  } catch (a) {
    try {
      e !== t && !e.deleted && e.delete(), t.deleted || t.delete();
    } catch (i) {
      console.warn("[LiteRT] Tensor cleanup failed:", i);
    }
    throw a;
  }
}
window.loadLiteRtEmbeddings = async function(o, n, r) {
  try {
    if (u) {
      console.log("[LiteRT] Cleaning up previous model before reinitialization (hot restart detected)");
      try {
        await window.cleanupLiteRtEmbeddings();
      } catch (e) {
        console.warn("[LiteRT] Non-fatal cleanup error (will reinitialize anyway):", e), s = null, d = null, m = !1, u = !1;
      }
    }
    const t = r ?? "/wasm/";
    await x(n), await C(o, t), u = !0;
  } catch (t) {
    throw u = !1, new Error("Failed to initialize LiteRT embeddings: " + t.message);
  }
};
window.generateEmbedding = async function(o) {
  if (!u)
    throw new Error("LiteRT embeddings not initialized. Call loadLiteRtEmbeddings first.");
  if (typeof o != "string" || o.trim().length === 0)
    throw new Error("Text must be a non-empty string");
  const n = await L(o);
  return new Float32Array(n);
};
window.generateDocumentEmbedding = async function(o) {
  if (!u)
    throw new Error("LiteRT embeddings not initialized. Call loadLiteRtEmbeddings first.");
  if (typeof o != "string" || o.trim().length === 0)
    throw new Error("Text must be a non-empty string");
  const n = await _(o);
  return new Float32Array(n);
};
window.generateEmbeddings = async function(o) {
  if (!u)
    throw new Error("LiteRT embeddings not initialized. Call loadLiteRtEmbeddings first.");
  if (!Array.isArray(o))
    throw new Error("texts must be an array");
  const n = [];
  for (const r of o) {
    if (typeof r != "string" || r.trim().length === 0)
      throw new Error("All texts must be non-empty strings");
    const t = await L(r);
    n.push(new Float32Array(t));
  }
  return n;
};
window.getLiteRtEmbeddingDimension = function() {
  return g;
};
window.cleanupLiteRtEmbeddings = async function() {
  if (console.log("[LiteRT] ========================================"), console.log("[LiteRT] Starting cleanup..."), console.log("[LiteRT] ========================================"), s)
    try {
      typeof s.delete == "function" && !s.deleted && (s.delete(), console.log("[LiteRT] ✅ Model deleted"));
    } catch (o) {
      console.warn("[LiteRT] ⚠️  Error deleting model (non-fatal):", o);
    }
  if (s = null, d)
    try {
      d.processor && typeof d.processor.delete == "function" && (d.processor.delete(), console.log("[LiteRT] ✅ Tokenizer deleted"));
    } catch (o) {
      console.warn("[LiteRT] ⚠️  Error deleting tokenizer (non-fatal):", o);
    }
  d = null;
  try {
    const n = E().numTensors;
    n > 0 && (console.log(`[LiteRT] Disposing ${n} TensorFlow.js tensors`), R(), console.log("[LiteRT] ✅ Tensors disposed"));
  } catch (o) {
    console.warn("[LiteRT] ⚠️  Error disposing tensors (non-fatal):", o);
  }
  console.log("[LiteRT] ✅ Keeping WASM runtime (reusable across models)"), c = 256, console.log("[LiteRT] ✅ Reset MAX_SEQUENCE_LENGTH to default"), u = !1, console.log("[LiteRT] ========================================"), console.log("[LiteRT] ✅ Cleanup completed"), console.log("[LiteRT] ========================================");
};
window.isLiteRtEmbeddingsInitialized = function() {
  return u;
};
console.log("LiteRT Embeddings module loaded successfully");
