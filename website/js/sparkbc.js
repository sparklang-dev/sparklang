/*
 * SparkBC — client-side SPARK_BC parser / disassembler.
 *
 * Port of python/sparklang/model_lab/bc_dump.py. Parses real
 * .sparkbc bytes in the browser (no server). Does not invent
 * opcodes or hex. Loaded by /ide-web.html and by the node parity
 * gate tools/spark-bc-dump/js_parity.js (CommonJS export).
 */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }
  if (root) {
    root.SparkBC = api;
  }
})(typeof self !== "undefined" ? self : globalThis, function () {
  "use strict";

  var MAGIC = [0x53, 0x50, 0x42, 0x43]; // 'SPBC'
  var VERSION = 1;

  // Operand count = number of u16 const indices. Mirrors
  // bc_dump.OP_ARITY (docs/SPARK_BC.md + bootstrap/bc_opcodes.h).
  var OP_ARITY = {
    0x00: 0, // HALT
    0x01: 1, // MODEL
    0x02: 2, // ASK
    0x03: 1, // PRINT
    0x04: 2, // LET
    0x05: 2, // CLASSIFY
    0x06: 3, // EXTRACT
    0x07: 0, // PIPELINE
    0x09: 1, // LISTEN
    0x0a: 1, // SPEAK
    0x0d: 0, // VOICE
    0x0e: 2, // ENGINE_FETCH
    0x0f: 2, // ENGINE_FETCH_PARSE
    0x10: 2, // ENGINE_PARSE
    0x11: 1, // ENGINE_CSS
    0x12: 1, // ENGINE_LAYOUT
    0x13: 1, // ENGINE_PAINT_BOXES
    0x14: 1, // ENGINE_PAINT_FIXTURE
    0x15: 2, // ENGINE_SHOW
    0x16: 1, // ENGINE_RENDER
    0x17: 2, // IDE_OPEN
    0x18: 1, // IDE_RUN
    0x19: 1, // IDE_ASK
    0x1a: 2, // IDE_SHOW
    0x1b: 2, // REVIEW_PATH
    0x1c: 2, // REVIEW_TEXT
    0x1d: 2, // BROWSER_RUN
    0x1e: 2, // BROWSER_GOTO
    0x1f: 1, // MITM_ENABLE
    0x20: 1, // TOOL
    0x21: 1, // WITH
    0x22: 0, // WITH_END
    0x23: 2, // EMBED
    0x24: 2, // RETRIEVE
    0x25: 3, // EXPECT
    0x26: 5, // TRAIN
    0x27: 2, // TRAIN_STATUS
    0x28: 2, // STEP
  };

  var OP_NAME = {
    0x00: "HALT",
    0x01: "MODEL",
    0x02: "ASK",
    0x03: "PRINT",
    0x04: "LET",
    0x05: "CLASSIFY",
    0x06: "EXTRACT",
    0x07: "PIPELINE",
    0x09: "LISTEN",
    0x0a: "SPEAK",
    0x0d: "VOICE",
    0x0e: "ENGINE_FETCH",
    0x0f: "ENGINE_FETCH_PARSE",
    0x10: "ENGINE_PARSE",
    0x11: "ENGINE_CSS",
    0x12: "ENGINE_LAYOUT",
    0x13: "ENGINE_PAINT_BOXES",
    0x14: "ENGINE_PAINT_FIXTURE",
    0x15: "ENGINE_SHOW",
    0x16: "ENGINE_RENDER",
    0x17: "IDE_OPEN",
    0x18: "IDE_RUN",
    0x19: "IDE_ASK",
    0x1a: "IDE_SHOW",
    0x1b: "REVIEW_PATH",
    0x1c: "REVIEW_TEXT",
    0x1d: "BROWSER_RUN",
    0x1e: "BROWSER_GOTO",
    0x1f: "MITM_ENABLE",
    0x20: "TOOL",
    0x21: "WITH",
    0x22: "WITH_END",
    0x23: "EMBED",
    0x24: "RETRIEVE",
    0x25: "EXPECT",
    0x26: "TRAIN",
    0x27: "TRAIN_STATUS",
    0x28: "STEP",
  };

  function hex2(n) {
    return n.toString(16).padStart(2, "0");
  }

  function hex8(n) {
    return n.toString(16).padStart(8, "0");
  }

  function u16(bytes, off) {
    if (off + 2 > bytes.length) {
      throw new Error("truncated u16 at offset " + off);
    }
    return [(bytes[off] | (bytes[off + 1] << 8)) >>> 0, off + 2];
  }

  function u32(bytes, off) {
    if (off + 4 > bytes.length) {
      throw new Error("truncated u32 at offset " + off);
    }
    var v =
      (bytes[off] |
        (bytes[off + 1] << 8) |
        (bytes[off + 2] << 16) |
        (bytes[off + 3] << 24)) >>>
      0;
    return [v, off + 4];
  }

  function decodeUtf8(bytes) {
    // errors="replace" parity with Python bytes.decode.
    return new TextDecoder("utf-8", { fatal: false }).decode(bytes);
  }

  async function sha256Hex(bytes) {
    var digest = await crypto.subtle.digest("SHA-256", bytes);
    var view = new Uint8Array(digest);
    var out = "";
    for (var i = 0; i < view.length; i++) {
      out += hex2(view[i]);
    }
    return out;
  }

  // Python repr() for str — quote choice + escapes. Fixtures are
  // ASCII; control chars escape as \xNN like CPython.
  function pyRepr(text) {
    var hasSingle = text.indexOf("'") !== -1;
    var hasDouble = text.indexOf('"') !== -1;
    var quote = hasSingle && !hasDouble ? '"' : "'";
    var out = quote;
    for (var i = 0; i < text.length; i++) {
      var cp = text.codePointAt(i);
      var ch = String.fromCodePoint(cp);
      if (cp > 0xffff) {
        i++; // skip surrogate pair tail
      }
      if (ch === "\\") {
        out += "\\\\";
      } else if (ch === quote) {
        out += "\\" + quote;
      } else if (ch === "\n") {
        out += "\\n";
      } else if (ch === "\r") {
        out += "\\r";
      } else if (ch === "\t") {
        out += "\\t";
      } else if (cp < 0x20 || cp === 0x7f) {
        out += "\\x" + hex2(cp);
      } else {
        out += ch;
      }
    }
    return out + quote;
  }

  // Parse a real SPARK_BC byte buffer. Throws on bad structure —
  // fail loud, never invent. sha256 filled by parseSparkBC (async).
  function parseSparkBCBytes(bytes, sha256) {
    if (bytes.length < 7) {
      throw new Error("file too short for SPARK_BC header");
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] !== MAGIC[i]) {
        throw new Error("bad magic (want SPBC)");
      }
    }
    var version = bytes[4];
    if (version !== VERSION) {
      throw new Error("version " + version + " (want 1)");
    }
    var off = 5;
    var r;
    r = u16(bytes, off);
    var nstrs = r[0];
    off = r[1];
    var strings = [];
    for (var s = 0; s < nstrs; s++) {
      r = u16(bytes, off);
      var nbytes = r[0];
      off = r[1];
      if (off + nbytes > bytes.length) {
        throw new Error("truncated string pool");
      }
      strings.push(bytes.slice(off, off + nbytes));
      off += nbytes;
    }
    r = u16(bytes, off);
    var nconsts = r[0];
    off = r[1];
    var consts = [];
    for (var c = 0; c < nconsts; c++) {
      if (off + 3 > bytes.length) {
        throw new Error("truncated const pool");
      }
      var kind = bytes[off];
      var payload = (bytes[off + 1] | (bytes[off + 2] << 8)) >>> 0;
      off += 3;
      consts.push({ kind: kind, payload: payload });
    }
    r = u32(bytes, off);
    var ncode = r[0];
    off = r[1];
    if (off + ncode > bytes.length) {
      throw new Error("truncated code section");
    }
    if (off + ncode !== bytes.length) {
      throw new Error("trailing bytes after code");
    }
    return {
      raw: bytes,
      size: bytes.length,
      sha256: sha256,
      magic: "SPBC",
      version: version,
      strings: strings,
      consts: consts,
      code: bytes.slice(off, off + ncode),
      code_off: off,
      ncode: ncode,
    };
  }

  // Full async parse: bytes (Uint8Array | ArrayBuffer) → bc object
  // with sha256. Browser and node >= 19 both have crypto.subtle.
  async function parseSparkBC(input) {
    var bytes =
      input instanceof Uint8Array ? input : new Uint8Array(input);
    var sha = await sha256Hex(bytes);
    return parseSparkBCBytes(bytes, sha);
  }

  function constText(bc, idx) {
    if (idx >= bc.consts.length) {
      return "const" + idx + "(OOB)";
    }
    var c = bc.consts[idx];
    if (c.kind !== 0) {
      return "const" + idx + "(kind=" + c.kind + ")";
    }
    var si = c.payload;
    if (si >= bc.strings.length) {
      return "const" + idx + "->str" + si + "(OOB)";
    }
    return 'const' + idx + ' "' + decodeUtf8(bc.strings[si]) + '"';
  }

  // Walk the code section; throw on unknown / truncated ops.
  function decodeOps(bc) {
    var code = bc.code;
    var ip = 0;
    var ops = [];
    while (ip < code.length) {
      var op = code[ip];
      var name = OP_NAME[op];
      if (name === undefined) {
        throw new Error(
          "unknown opcode 0x" + hex2(op) + " at code+" + ip
        );
      }
      var arity = OP_ARITY[op];
      var need = 1 + 2 * arity;
      if (ip + need > code.length) {
        throw new Error("truncated " + name + " at code+" + ip);
      }
      var operands = [];
      var pos = ip + 1;
      for (var a = 0; a < arity; a++) {
        operands.push((code[pos] | (code[pos + 1] << 8)) >>> 0);
        pos += 2;
      }
      var hexBytes = [];
      for (var h = ip; h < pos; h++) {
        hexBytes.push(hex2(code[h]));
      }
      ops.push({
        ip: ip,
        op: op,
        name: name,
        operands: operands,
        hex: hexBytes.join(" "),
      });
      ip = pos;
      if (name === "HALT") {
        break;
      }
    }
    if (ip !== code.length) {
      throw new Error("code bytes remain after HALT");
    }
    return ops;
  }

  function hexPreview(raw, n) {
    var out = [];
    var lim = Math.min(n || 32, raw.length);
    for (var i = 0; i < lim; i++) {
      out.push(hex2(raw[i]));
    }
    return out.join(" ");
  }

  // xxd-style hex+ASCII dump of the whole buffer.
  function formatXxd(raw, width) {
    width = width || 16;
    var lines = [];
    for (var i = 0; i < raw.length; i += width) {
      var chunk = raw.slice(i, Math.min(i + width, raw.length));
      var hx = [];
      var ascii = "";
      for (var j = 0; j < chunk.length; j++) {
        hx.push(hex2(chunk[j]));
        var b = chunk[j];
        ascii += b >= 32 && b < 127 ? String.fromCharCode(b) : ".";
      }
      var hxStr = hx.join(" ");
      while (hxStr.length < width * 3 - 1) {
        hxStr += " ";
      }
      lines.push(hex8(i) + ": " + hxStr + "  " + ascii);
    }
    return lines.join("\n");
  }

  function symbolTable(bc) {
    var out = [];
    for (var i = 0; i < bc.strings.length; i++) {
      out.push({
        id: "str" + i,
        kind: "string",
        index: i,
        bytes: bc.strings[i].length,
        text: decodeUtf8(bc.strings[i]),
      });
    }
    return out;
  }

  // Const↔string and opcode→const cross-refs (SPARK_BC-native).
  function buildXrefs(bc) {
    var ops = decodeOps(bc);
    var constToOps = {};
    var strToConsts = {};
    for (var i = 0; i < bc.consts.length; i++) {
      var c = bc.consts[i];
      if (c.kind === 0) {
        var key = "str" + c.payload;
        if (!strToConsts[key]) {
          strToConsts[key] = [];
        }
        strToConsts[key].push(i);
      }
    }
    for (var o = 0; o < ops.length; o++) {
      var op = ops[o];
      for (var a = 0; a < op.operands.length; a++) {
        var ckey = "const" + op.operands[a];
        if (!constToOps[ckey]) {
          constToOps[ckey] = [];
        }
        constToOps[ckey].push({ ip: op.ip, name: op.name, op: op.op });
      }
    }
    var nRefs = 0;
    Object.keys(constToOps).forEach(function (k) {
      nRefs += constToOps[k].length;
    });
    return {
      const_to_ops: constToOps,
      str_to_consts: strToConsts,
      n_ops: ops.length,
      n_const_refs: nRefs,
    };
  }

  // Byte-range sections of a SPARK_BC buffer.
  function structuredSections(bc) {
    var raw = bc.raw;
    var off = 5;
    var r = u16(raw, off);
    var nstrs = r[0];
    off = r[1];
    var strStart = off;
    for (var s = 0; s < nstrs; s++) {
      r = u16(raw, off);
      off = r[1] + r[0];
    }
    var strEnd = off;
    r = u16(raw, off);
    var nconsts = r[0];
    off = r[1];
    var constStart = off;
    off += 3 * nconsts;
    var constEnd = off;
    r = u32(raw, off);
    off = r[1];
    var codeStart = off;
    return [
      { name: "magic", off: 0, size: 4, note: "SPBC" },
      { name: "version", off: 4, size: 1, note: "u8" },
      {
        name: "string_pool",
        off: strStart,
        size: strEnd - strStart,
        note: "nstrings=" + nstrs,
      },
      {
        name: "const_pool",
        off: constStart,
        size: constEnd - constStart,
        note: "nconsts=" + nconsts,
      },
      {
        name: "code",
        off: codeStart,
        size: bc.ncode,
        note: "ncode=" + bc.ncode,
      },
    ];
  }

  // Structured analysis — mirrors bc_dump.analyze_bc.
  function analyzeBc(bc) {
    var ops = decodeOps(bc);
    return {
      format: "SPARK_BC",
      sha256: bc.sha256,
      size: bc.size,
      magic: bc.magic,
      version: bc.version,
      nstrings: bc.strings.length,
      nconsts: bc.consts.length,
      ncode: bc.ncode,
      code_off: bc.code_off,
      first32_hex: hexPreview(bc.raw, 32),
      sections: structuredSections(bc),
      symbols: symbolTable(bc),
      xrefs: buildXrefs(bc),
      ops: ops.map(function (o) {
        return {
          ip: o.ip,
          op: o.op,
          name: o.name,
          operands: o.operands,
          hex: o.hex,
          args_text: o.operands.map(function (a) {
            return constText(bc, a);
          }),
        };
      }),
      privacy: "local-only",
      note:
        "Deterministic SPARK_BC inspect — not ELF/PE decompile, " +
        "not lossless .spark source recovery.",
    };
  }

  // Human dump — byte-parity with bc_dump.format_dump.
  function formatDump(bc, opts) {
    opts = opts || {};
    var source = opts.source || "";
    var command = opts.command || "";
    var label = opts.label || "SPARK_BC dump";
    var a = analyzeBc(bc);
    var lines = [
      "# " + label,
      "# SPARK_BC is orchestration bytecode — not neural weights.",
      "# Not HuggingFace. Not imported tensors. Spark's own binary.",
      "#",
      "# Source: " + source,
      "# Command: " + command,
      "# sha256: " + bc.sha256,
      "# size: " + bc.size + " bytes",
      "#",
      "# First 32 hex bytes:",
      "# " + hexPreview(bc.raw, 32),
      "#",
      "# File layout (little-endian, docs/SPARK_BC.md):",
      "#   offset 0  magic 'S''P''B''C'",
      "#   offset 4  version 0x01",
      "#   then u16 nstrings, string pool, u16 nconsts,",
      "#   const pool (u8 kind + u16 payload), u32 ncode, code",
      "",
      "## xxd",
      formatXxd(bc.raw),
      "",
      "## Header",
      "magic: " + bc.magic,
      "version: " + bc.version,
      "nstrings: " + bc.strings.length,
      "nconsts: " + bc.consts.length,
      "ncode: " + bc.ncode,
      "code_off: " + bc.code_off,
      "",
      "## Sections",
    ];
    a.sections.forEach(function (sec) {
      lines.push(
        sec.name +
          "  off=" +
          sec.off +
          " size=" +
          sec.size +
          "  " +
          sec.note
      );
    });
    lines.push("");
    lines.push("## Symbols (string pool)");
    a.symbols.forEach(function (sym) {
      lines.push(
        sym.id + "  " + pyRepr(sym.text) + " (" + sym.bytes + " bytes)"
      );
    });
    lines.push("");
    lines.push("## String pool");
    bc.strings.forEach(function (s, i) {
      lines.push(
        i + ": " + pyRepr(decodeUtf8(s)) + " (" + s.length + " bytes)"
      );
    });
    lines.push("");
    lines.push("## Constant pool (kind 0 = STR → string index)");
    bc.consts.forEach(function (c, i) {
      var extra = "";
      if (c.kind === 0 && c.payload < bc.strings.length) {
        extra = " → " + pyRepr(decodeUtf8(bc.strings[c.payload]));
      }
      lines.push(
        i + ": kind=" + c.kind + " payload=" + c.payload + extra
      );
    });
    var xrefs = a.xrefs;
    lines.push("");
    lines.push("## Xrefs (const → ops; str → consts)");
    lines.push("n_ops: " + xrefs.n_ops);
    lines.push("n_const_refs: " + xrefs.n_const_refs);
    Object.keys(xrefs.const_to_ops)
      .sort()
      .forEach(function (ckey) {
        var ips = xrefs.const_to_ops[ckey]
          .map(function (r) {
            return r.name + "@" + r.ip;
          })
          .join(", ");
        lines.push(ckey + " → " + ips);
      });
    Object.keys(xrefs.str_to_consts)
      .sort()
      .forEach(function (skey) {
        lines.push(
          skey + " ← consts " + xrefs.str_to_consts[skey].join(", ")
        );
      });
    lines.push("");
    lines.push("## Code (opcode + u16le const indices)");
    a.ops.forEach(function (op) {
      lines.push(
        "code+" +
          op.ip +
          "  " +
          op.hex +
          "  " +
          op.name +
          " (0x" +
          hex2(op.op) +
          ") " +
          op.args_text.join(" ")
      );
    });
    lines.push("");
    return lines.join("\n");
  }

  // Parse a real .safetensors header (u64le length + JSON).
  // Returns {metadata, tensors:[{name,dtype,shape,data_offsets}]}.
  function parseSafetensors(input) {
    var bytes =
      input instanceof Uint8Array ? input : new Uint8Array(input);
    if (bytes.length < 8) {
      throw new Error("file too short for safetensors header");
    }
    var view = new DataView(
      bytes.buffer,
      bytes.byteOffset,
      bytes.byteLength
    );
    var lo = view.getUint32(0, true);
    var hi = view.getUint32(4, true);
    var headerLen = hi * 0x100000000 + lo;
    if (8 + headerLen > bytes.length) {
      throw new Error("truncated safetensors header");
    }
    var headerBytes = bytes.slice(8, 8 + headerLen);
    var header = JSON.parse(decodeUtf8(headerBytes));
    var metadata = header.__metadata__ || {};
    var tensors = [];
    Object.keys(header)
      .sort()
      .forEach(function (name) {
        if (name === "__metadata__") {
          return;
        }
        var t = header[name];
        tensors.push({
          name: name,
          dtype: t.dtype,
          shape: t.shape,
          data_offsets: t.data_offsets,
        });
      });
    return {
      metadata: metadata,
      tensors: tensors,
      size: bytes.length,
      header_bytes: headerLen,
    };
  }

  return {
    MAGIC: MAGIC,
    VERSION: VERSION,
    OP_ARITY: OP_ARITY,
    OP_NAME: OP_NAME,
    parseSparkBC: parseSparkBC,
    parseSparkBCBytes: parseSparkBCBytes,
    decodeOps: decodeOps,
    analyzeBc: analyzeBc,
    formatDump: formatDump,
    formatXxd: formatXxd,
    hexPreview: hexPreview,
    symbolTable: symbolTable,
    buildXrefs: buildXrefs,
    structuredSections: structuredSections,
    parseSafetensors: parseSafetensors,
    pyRepr: pyRepr,
    sha256Hex: sha256Hex,
  };
});
