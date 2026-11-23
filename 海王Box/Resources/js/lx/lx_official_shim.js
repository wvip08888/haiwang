/**
 * Host adapter for the official lx-music-mobile `user-api-preload.js`.
 *
 * The official preload exposes a fully asynchronous API: scripts call
 * lx.request(url, options, callback), which fires a native "request" event and
 * expects the host to call back globalThis.__lx_native__(key, 'response', ...)
 * once the HTTP result is ready. All Promise chaining lives in the preload.
 *
 * This shim bridges that contract onto our existing synchronous __host HTTP /
 * crypto primitives:
 *   - registers the native globals the preload captures in lx_setup()
 *   - turns native "request" events into synchronous __host HTTP (httpStart +
 *     httpPoll) and immediately feeds the result back via __lx_native__
 *   - captures init declarations + musicUrl results in slots the host can read
 *
 * Nothing is logged: LX sources often embed API keys in URLs and console text.
 */
(function () {
  'use strict';

  var host = globalThis.__host;
  var KEY = '__hw_lx__';

  function safeHost(action, arg) {
    try {
      return String(host(action, arg) || '');
    } catch (error) {
      return '';
    }
  }
  function jsonArg(value) {
    try {
      return JSON.stringify(value == null ? {} : value);
    } catch (error) {
      return '{}';
    }
  }

  var initSlot = null;
  var lastInit = null;
  var resultSlot = null;
  var timers = [];
  var timersFlushed = 0;
  var scriptsReady = false;

  // ---------------------------------------------------------------- helpers

  function toBase64(value) {
    if (value == null) return '';
    if (typeof value === 'string') {
      // host base64encode expects hex, so convert UTF-8 string -> hex first.
      var bytes = new TextEncoder().encode(value);
      var hex = '';
      for (var i = 0; i < bytes.length; i++) hex += ('0' + bytes[i].toString(16)).slice(-2);
      return safeHost('base64encode', hex);
    }
    if (value instanceof Uint8Array || Array.isArray(value)) {
      return safeHost('base64encode', Buffer.from(value).toString('hex'));
    }
    return safeHost('base64encode', Buffer.from(String(value), 'utf8').toString('hex'));
  }

  function bufFromBase64(text) {
    var hex = safeHost('base64decode', String(text == null ? '' : text));
    return Buffer.from(hex, 'hex');
  }

  // ------------------------------------------- native funcs captured by lx_setup

  globalThis.__lx_native_call__set_timeout = function (id, timeout) {
    timers.push({ id: Number(id), at: Date.now() + (Number(timeout) || 0) });
  };

  globalThis.__lx_native_call__utils_str2b64 = function (text) {
    return toBase64(text);
  };

  globalThis.__lx_native_call__utils_b642buf = function (text) {
    var bytes = bufFromBase64(text);
    var out = [];
    for (var i = 0; i < bytes.length; i++) out.push(bytes[i] & 0xff);
    return jsonArg(out);
  };

  globalThis.__lx_native_call__utils_str2md5 = function (encoded) {
    // Official md5(str) passes encodeURIComponent(str) to native, which URL-decodes
    // then computes UTF-8 MD5. Net effect: MD5 of the original string.
    var text = encoded;
    try { text = decodeURIComponent(String(encoded)); } catch (error) { /* keep raw */ }
    return safeHost('md5', text);
  };

  globalThis.__lx_native_call__utils_aes_encrypt = function (dataB64, keyB64, ivB64, mode) {
    var ecb = /ecb/i.test(String(mode));
    var answer = safeHost('crypto', jsonArg({
      op: 'aes', encrypt: true, mode: ecb ? 'ECB' : 'CBC', padding: true,
      data: String(dataB64 == null ? '' : dataB64),
      key: String(keyB64 == null ? '' : keyB64),
      iv: ecb ? '' : String(ivB64 == null ? '' : ivB64),
    }));
    try { return JSON.parse(answer).data || ''; } catch (error) { return ''; }
  };

  globalThis.__lx_native_call__utils_rsa_encrypt = function (dataB64, key, padding) {
    var answer = safeHost('crypto', jsonArg({
      op: 'rsaRaw', encrypt: true, key: String(key == null ? '' : key),
      data: String(dataB64 == null ? '' : dataB64),
    }));
    try { return JSON.parse(answer).data || ''; } catch (error) { return ''; }
  };

  // ---------------------------------------- nativeCall (JS -> host) dispatcher

  globalThis.__lx_native_call__ = function (key, action, dataJson) {
    var data = {};
    try { data = JSON.parse(dataJson); } catch (error) { /* ignore */ }

    switch (action) {
      case 'request': {
        // data = { requestKey, url, options:{method,headers,body,form,formData,binary,timeout} }
        var url = String(data.url || '');
        var options = data.options || {};
        var method = String(options.method || 'get').toUpperCase();
        var headers = options.headers || {};
        // Official request.js injects a desktop Chrome UA + Accept on every
        // request; script headers override these defaults.
        var fields = {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36',
          'Accept': 'application/json',
        };
        Object.keys(headers).forEach(function (k) {
          if (headers[k] != null) {
            var base = k.toLowerCase();
            Object.keys(fields).forEach(function (existing) {
              if (existing.toLowerCase() === base) delete fields[existing];
            });
            fields[k] = String(headers[k]);
          }
        });
        var body = null;
        var bodyBase64 = null;
        if (options.body != null) {
          if (options.body instanceof Uint8Array || options.binary === true) {
            bodyBase64 = toBase64(options.body);
          } else if (typeof options.body === 'string') {
            body = options.body;
          } else {
            body = jsonArg(options.body);
            if (!hasHeader('content-type')) fields['Content-Type'] = 'application/json';
          }
        } else if (options.form != null || options.formData != null) {
          var form = options.form == null ? options.formData : options.form;
          if (typeof form === 'string') {
            body = form;
          } else {
            var pairs = [];
            Object.keys(form).forEach(function (k) {
              pairs.push(encodeURIComponent(k) + '=' + encodeURIComponent(form[k]));
            });
            body = pairs.join('&');
          }
          if (!hasHeader('content-type')) fields['Content-Type'] = 'application/x-www-form-urlencoded';
        }
        function hasHeader(name) {
          return Object.keys(fields).some(function (k) { return k.toLowerCase() === name; });
        }
        var timeoutMs = typeof options.timeout === 'number' && options.timeout > 0
          ? Math.min(options.timeout, 13000) : 13000;
        var req = {
          url: url,
          method: method,
          headers: fields,
          timeout: timeoutMs,
        };
        if (body != null) req.body = body;
        if (bodyBase64 != null) req.bodyBase64 = bodyBase64;

        var answer = { failed: 'request failed' };
        var handle = safeHost('httpStart', jsonArg(req));
        if (handle && handle !== '0') {
          var deadline = Date.now() + timeoutMs + 800;
          for (;;) {
            var polled = safeHost('httpPoll', handle);
            if (polled && polled !== 'null' && polled !== '') {
              try { answer = JSON.parse(polled); } catch (error) { answer = { failed: 'bad response' }; }
              break;
            }
            if (Date.now() >= deadline) {
              safeHost('httpCancel', handle);
              answer = { failed: 'request timeout' };
              break;
            }
          }
        }

        // Build needle/fetch-shaped response and feed it back into the official preload.
        var response;
        if (answer && answer.failed) {
          response = null;
        } else {
          var rawBytes = bufFromBase64(answer && answer.base64 ? answer.base64 : '');
          var text = Buffer.from(rawBytes).toString('utf8');
          var parsed = text;
          try { parsed = JSON.parse(text); } catch (error) { /* keep text */ }
          response = {
            statusCode: answer && answer.code ? answer.code : 0,
            statusMessage: '',
            headers: (answer && answer.headers) || {},
            body: parsed,
          };
        }
        try {
          globalThis.__lx_native__(KEY, 'response', jsonArg({
            requestKey: data.requestKey,
            error: response == null ? 'request failed' : null,
            response: response,
          }));
        } catch (error) { /* a dead callback must not break the runtime */ }
        break;
      }
      case 'response': {
        // data = { requestKey, status, result:{source,action,data:{type,url}} }
        resultSlot = data;
        break;
      }
      case 'init': {
        // data = { info:{sources:{...}}, status, errorMessage }
        initSlot = data;
        if (data && data.status === true) lastInit = data;
        break;
      }
      case 'cancelRequest':
      case 'showUpdateAlert':
      default:
        break;
    }
  };

  // ------------------------------------------------------- host driver (__lx_official)

  globalThis.__lx_official = {
    /** Runs lx_setup() then evaluates the user script. Returns {ready,error}. */
    load: function (name, description, version, author, homepage, rawScript) {
      if (scriptsReady) return jsonArg({ ready: true });
      var setupError = '';
      try {
        globalThis.lx_setup(KEY, name || '', name || '', description || '', version || '', author || '', homepage || '', rawScript || '');
      } catch (error) {
        setupError = String((error && error.message) || error);
      }
      // lx_setup 末尾会对 globalThis 做递归 freeze 加固。真机 QuickJS 上，
      // globalThis 里的宿主桥接对象（__host，Java JSCallFunction）可能让这段
      // 加固抛异常。此时 globalThis.lx、__lx_native__、request 分发都已就绪，
      // 绝不能因此判定加载失败——否则会出现「能力探测正常、取址却被门控挡掉」
      // 的假死现象（表现为排行榜/搜索都解析失败）。
      if (!globalThis.lx || typeof globalThis.__lx_native__ !== 'function') {
        return jsonArg({ ready: false, error: 'setup failed' });
      }
      scriptsReady = true;
      return jsonArg({ ready: true, setupError: setupError });
    },

    /** Flushes due timers into the official preload (drives delayed handlers). */
    pump: function () {
      var now = Date.now();
      var remain = [];
      for (var i = 0; i < timers.length; i++) {
        var timer = timers[i];
        if (timer.at <= now) {
          try { globalThis.__lx_native__(KEY, '__set_timeout__', timer.id); } catch (error) { /* ignore */ }
          timersFlushed++;
        } else {
          remain.push(timer);
        }
      }
      timers = remain;
      return timersFlushed;
    },

    takeInit: function () {
      var value = initSlot == null ? 'null' : jsonArg(initSlot);
      initSlot = null;
      return value;
    },

    /**
     * Capability snapshot for the importer: maps the official init declaration
     * into { ready, sources:{key:[qualitys]}, handler } used by LxProbeMapper.
     * Does not consume initSlot (takeInit does that for capability loading).
     */
    snapshot: function () {
      var seen = lastInit || initSlot;
      if (seen == null) {
        return jsonArg({ ready: false, handler: scriptsReady });
      }
      var status = seen.status === true;
      var info = seen.info || {};
      var declared = info.sources || {};
      var sources = {};
      Object.keys(declared).forEach(function (key) {
        var entry = declared[key] || {};
        var actions = entry.actions || [];
        var hasMusicUrl = actions.some(function (a) { return /musicurl/i.test(String(a)); });
        if (!hasMusicUrl) return;
        var qualitys = entry.qualitys || [];
        sources[key.toLowerCase()] = qualitys.map(function (q) { return String(q).toLowerCase(); });
      });
      var platforms = Object.keys(sources);
      return jsonArg({
        ready: status && platforms.length > 0,
        handler: scriptsReady,
        sources: sources,
        error: platforms.length > 0 ? '' : '未声明可用平台',
      });
    },

    takeResult: function () {
      var value = resultSlot == null ? 'null' : jsonArg(resultSlot);
      resultSlot = null;
      return value;
    },

    clearResult: function () { resultSlot = null; },

    /**
     * Fires an official request event: globalThis.__lx_native__(KEY,'request',{...}).
     * The preload's handleRequest calls events.request.call(lx, data) and, once the
     * script resolves, reports back through nativeCall('response') -> resultSlot.
     */
    startRequest: function (source, action, type, musicInfo) {
      if (!scriptsReady) return false;
      var data = {
        source: source,
        action: action || 'musicUrl',
        info: { type: type || '128k', musicInfo: musicInfo },
      };
      try {
        globalThis.__lx_native__(KEY, 'request', jsonArg({ requestKey: String(Date.now()) + Math.random(), data: data }));
        return true;
      } catch (error) {
        return false;
      }
    },

    /** Returns the resolved musicUrl string, or '' when not ready / failed. */
    takeResultUrl: function () {
      if (resultSlot == null) return '';
      var status = resultSlot.status;
      var result = resultSlot.result;
      var url = '';
      if (status === true && result && result.data && typeof result.data.url === 'string') {
        url = result.data.url;
      }
      resultSlot = null;
      return url;
    },

    hasHandler: function () {
      // The official preload keeps events.request private; infer from progress.
      return scriptsReady;
    },
  };
})();
