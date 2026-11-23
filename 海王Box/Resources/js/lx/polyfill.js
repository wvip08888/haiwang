/**
 * Minimal Node-ish polyfills for LX Music custom sources running on QuickJS.
 * Only what the LX user API needs: Buffer, URLSearchParams and timers. Base64 is
 * delegated to the host so no large JS implementation has to be shipped.
 */
(function () {
  'use strict';

  var host = globalThis.__host;

  function fromHex(text) {
    var source = String(text || '');
    var bytes = new Uint8Array(Math.floor(source.length / 2));
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = parseInt(source.substr(i * 2, 2), 16) & 0xff;
    }
    return bytes;
  }

  function toHex(bytes) {
    var digits = '0123456789abcdef';
    var out = '';
    for (var i = 0; i < bytes.length; i++) {
      var value = bytes[i] & 0xff;
      out += digits.charAt(value >> 4) + digits.charAt(value & 15);
    }
    return out;
  }

  function encodeUtf8(text) {
    var value = String(text == null ? '' : text);
    var out = [];
    for (var i = 0; i < value.length; i++) {
      var code = value.charCodeAt(i);
      if (code < 0x80) {
        out.push(code);
      } else if (code < 0x800) {
        out.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
      } else if (code >= 0xd800 && code <= 0xdbff && i + 1 < value.length) {
        var low = value.charCodeAt(i + 1);
        if (low >= 0xdc00 && low <= 0xdfff) {
          var point = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
          out.push(
            0xf0 | (point >> 18),
            0x80 | ((point >> 12) & 0x3f),
            0x80 | ((point >> 6) & 0x3f),
            0x80 | (point & 0x3f),
          );
          i++;
        } else {
          out.push(0xef, 0xbf, 0xbd);
        }
      } else if (code >= 0xd800 && code <= 0xdfff) {
        out.push(0xef, 0xbf, 0xbd);
      } else {
        out.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
      }
    }
    return new Uint8Array(out);
  }

  function decodeUtf8(bytes) {
    var out = '';
    var i = 0;
    while (i < bytes.length) {
      var first = bytes[i++] & 0xff;
      if (first < 0x80) {
        out += String.fromCharCode(first);
        continue;
      }
      var point = 0;
      var extra = 0;
      if ((first & 0xe0) === 0xc0) {
        point = first & 0x1f;
        extra = 1;
      } else if ((first & 0xf0) === 0xe0) {
        point = first & 0x0f;
        extra = 2;
      } else if ((first & 0xf8) === 0xf0) {
        point = first & 0x07;
        extra = 3;
      } else {
        out += '\ufffd';
        continue;
      }
      var malformed = false;
      for (var j = 0; j < extra; j++) {
        if (i >= bytes.length) {
          malformed = true;
          break;
        }
        point = (point << 6) | (bytes[i++] & 0x3f);
      }
      if (malformed) {
        out += '\ufffd';
      } else if (point < 0x10000) {
        out += String.fromCharCode(point);
      } else {
        point -= 0x10000;
        out += String.fromCharCode(0xd800 | (point >> 10), 0xdc00 | (point & 0x3ff));
      }
    }
    return out;
  }

  function latin1Bytes(text) {
    var value = String(text == null ? '' : text);
    var out = new Uint8Array(value.length);
    for (var i = 0; i < value.length; i++) out[i] = value.charCodeAt(i) & 0xff;
    return out;
  }

  function latin1String(bytes) {
    var out = '';
    for (var i = 0; i < bytes.length; i++) out += String.fromCharCode(bytes[i] & 0xff);
    return out;
  }

  function base64Bytes(text) {
    return fromHex(String(host('base64decode', String(text == null ? '' : text)) || ''));
  }

  function bytesBase64(bytes) {
    return String(host('base64encode', toHex(bytes)) || '');
  }

  /** Buffer subset used by LX sources: from / toString / slice / equals / concat. */
  class Buffer extends Uint8Array {
    constructor(value) {
      super(typeof value === 'number' ? Math.max(0, value | 0) : 0);
    }

    toString(encoding, start, end) {
      var from = start == null ? 0 : Math.max(0, start | 0);
      var to = end == null ? this.length : Math.min(this.length, end | 0);
      if (to < from) to = from;
      var bytes = new Uint8Array(to - from);
      for (var i = from; i < to; i++) bytes[i - from] = this[i] & 0xff;
      var mode = String(encoding || 'utf8').toLowerCase();
      if (mode === 'base64' || mode === 'base64url') {
        var text = bytesBase64(bytes);
        return mode === 'base64url' ? text.replace(/\+/g, '-').replace(/\//g, '_') : text;
      }
      if (mode === 'hex') return toHex(bytes);
      if (mode === 'latin1' || mode === 'binary') return latin1String(bytes);
      if (mode === 'ascii') {
        var ascii = '';
        for (var k = 0; k < bytes.length; k++) ascii += String.fromCharCode(bytes[k] & 0x7f);
        return ascii;
      }
      return decodeUtf8(bytes);
    }

    toJSON() { return { type: 'Buffer', data: Array.prototype.slice.call(this) }; }

    slice(start, end) { return Buffer.from(Uint8Array.prototype.slice.call(this, start, end)); }

    subarray(start, end) { return this.slice(start, end); }

    equals(other) {
      var bytes = other instanceof Uint8Array ? other : Buffer.from(other);
      if (bytes.length !== this.length) return false;
      for (var i = 0; i < this.length; i++) if ((this[i] & 0xff) !== (bytes[i] & 0xff)) return false;
      return true;
    }
  }

  Buffer.from = function (value, encoding) {
    var mode = String(encoding || 'utf8').toLowerCase();
    if (value == null) return new Buffer(0);
    if (typeof value === 'number') {
      var allocated = new Buffer(Math.max(0, value | 0));
      for (var k = 0; k < allocated.length; k++) allocated[k] = 0;
      return allocated;
    }
    var bytes;
    if (typeof value === 'string') {
      if (mode === 'base64' || mode === 'base64url') {
        bytes = base64Bytes(value.replace(/-/g, '+').replace(/_/g, '/'));
      } else if (mode === 'hex') {
        bytes = fromHex(value);
      } else if (mode === 'latin1' || mode === 'binary' || mode === 'ascii') {
        bytes = latin1Bytes(value);
      } else {
        bytes = encodeUtf8(value);
      }
    } else if (value instanceof Uint8Array || Array.isArray(value)) {
      bytes = new Uint8Array(value.length);
      for (var i = 0; i < value.length; i++) bytes[i] = value[i] & 0xff;
    } else if (value.buffer instanceof ArrayBuffer) {
      bytes = new Uint8Array(value.buffer, value.byteOffset || 0, value.byteLength || 0);
    } else if (typeof value.length === 'number') {
      bytes = new Uint8Array(value.length);
      for (var n = 0; n < value.length; n++) bytes[n] = value[n] & 0xff;
    } else {
      bytes = encodeUtf8(String(value));
    }
    var result = new Buffer(bytes.length);
    for (var index = 0; index < bytes.length; index++) result[index] = bytes[index] & 0xff;
    return result;
  };

  Buffer.alloc = function (size, fill) {
    var result = new Buffer(Math.max(0, size | 0));
    if (fill != null) {
      var pattern = typeof fill === 'number' ? new Uint8Array([fill]) : Buffer.from(fill);
      for (var i = 0; i < result.length; i++) result[i] = pattern[i % pattern.length];
    }
    return result;
  };
  Buffer.allocUnsafe = Buffer.alloc;
  Buffer.isBuffer = function (value) { return value instanceof Buffer; };
  Buffer.concat = function (list, total) {
    var items = Array.isArray(list) ? list : [];
    var length = 0;
    var i;
    if (typeof total === 'number' && total >= 0) {
      length = total;
    } else {
      for (i = 0; i < items.length; i++) length += items[i].length;
    }
    var result = new Buffer(length);
    var offset = 0;
    for (i = 0; i < items.length && offset < length; i++) {
      var item = items[i] instanceof Uint8Array ? items[i] : Buffer.from(items[i]);
      for (var j = 0; j < item.length && offset < length; j++) result[offset++] = item[j] & 0xff;
    }
    return result;
  };

  globalThis.Buffer = Buffer;

  /** Form-urlencoded object / string / pair-list handling. */
  function URLSearchParams(init) {
    this._pairs = [];
    var self = this;
    if (typeof init === 'string') {
      String(init).split('&').forEach(function (pair) {
        if (!pair) return;
        var at = pair.indexOf('=');
        var key = at < 0 ? pair : pair.substring(0, at);
        var value = at < 0 ? '' : pair.substring(at + 1);
        self.append(decodeForm(key), decodeForm(value));
      });
    } else if (Array.isArray(init)) {
      init.forEach(function (pair) {
        if (Array.isArray(pair)) self.append(pair[0], pair[1]);
      });
    } else if (init && typeof init === 'object') {
      Object.keys(init).forEach(function (key) {
        var value = init[key];
        if (Array.isArray(value)) value.forEach(function (item) { self.append(key, item); });
        else self.append(key, value);
      });
    }
  }
  function decodeForm(text) {
    try {
      return decodeURIComponent(String(text).replace(/\+/g, ' '));
    } catch (error) {
      return String(text);
    }
  }
  function encodeForm(text) {
    return encodeURIComponent(String(text == null ? '' : text)).replace(/%20/g, '+');
  }
  URLSearchParams.prototype.append = function (key, value) {
    this._pairs.push([String(key == null ? '' : key), String(value == null ? '' : value)]);
  };
  URLSearchParams.prototype.set = function (key, value) {
    var name = String(key);
    this._pairs = this._pairs.filter(function (pair) { return pair[0] !== name; });
    this.append(name, value);
  };
  URLSearchParams.prototype.get = function (key) {
    var name = String(key);
    for (var i = 0; i < this._pairs.length; i++) if (this._pairs[i][0] === name) return this._pairs[i][1];
    return null;
  };
  URLSearchParams.prototype.getAll = function (key) {
    var name = String(key);
    return this._pairs.filter(function (pair) { return pair[0] === name; }).map(function (pair) { return pair[1]; });
  };
  URLSearchParams.prototype.has = function (key) { return this.get(key) !== null; };
  URLSearchParams.prototype.delete = function (key) {
    var name = String(key);
    this._pairs = this._pairs.filter(function (pair) { return pair[0] !== name; });
  };
  URLSearchParams.prototype.forEach = function (callback, thisArg) {
    this._pairs.forEach(function (pair) { callback.call(thisArg, pair[1], pair[0]); });
  };
  URLSearchParams.prototype.keys = function () { return this._pairs.map(function (pair) { return pair[0]; }); };
  URLSearchParams.prototype.values = function () { return this._pairs.map(function (pair) { return pair[1]; }); };
  URLSearchParams.prototype.entries = function () { return this._pairs.slice(); };
  URLSearchParams.prototype.toString = function () {
    return this._pairs.map(function (pair) {
      return encodeForm(pair[0]) + '=' + encodeForm(pair[1]);
    }).join('&');
  };
  globalThis.URLSearchParams = URLSearchParams;

  /** Timers without an event loop: callbacks are fired when __lx drives a step. */
  var timers = [];
  var nextTimer = 1;
  globalThis.setTimeout = function (callback, delay, args) {
    if (typeof callback !== 'function') return 0;
    var id = nextTimer++;
    var wait = typeof delay === 'number' && isFinite(delay) ? Math.max(0, delay) : 0;
    timers.push({ id: id, due: Date.now() + wait, fn: callback, args: Array.prototype.slice.call(arguments, 2) });
    return id;
  };
  globalThis.setImmediate = function (callback) { return globalThis.setTimeout(callback, 0); };
  globalThis.clearTimeout = function (id) {
    timers = timers.filter(function (timer) { return timer.id !== id; });
  };
  globalThis.clearImmediate = globalThis.clearTimeout;
  globalThis.__lxTimers = {
    flush: function () {
      var now = Date.now();
      var ran = 0;
      while (ran < 512) {
        var chosen = -1;
        for (var i = 0; i < timers.length; i++) {
          if (timers[i].due <= now && (chosen < 0 || timers[i].due < timers[chosen].due)) chosen = i;
        }
        if (chosen < 0) break;
        var job = timers.splice(chosen, 1)[0];
        ran++;
        try {
          job.fn.apply(null, job.args);
        } catch (error) {
          // A broken timer must not stop the remaining ones.
        }
      }
      return ran;
    },
    pending: function () { return timers.length; },
    clear: function () { timers = []; },
  };
})();
