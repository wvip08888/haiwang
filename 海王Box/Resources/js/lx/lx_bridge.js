/**
 * LX Music user API (version 2.0.0, mobile environment) reduced to the `musicUrl`
 * action, plus the __lx driver used by LxJsRuntime on Android/QuickJS.
 *
 * The host owns the script text, the HTTP transport and the crypto primitives.
 * Scripts run as classic scripts through indirect eval, exactly as LX Music does.
 */
(function () {
  'use strict';

  var host = globalThis.__host;
  var EVENT_NAMES = Object.freeze({ request: 'request', inited: 'inited', updateAlert: 'updateAlert' });
  var qualities = ['128k', '320k', 'flac', 'flac24bit'];
  // Aligned with lx-music-mobile's request.js default timeout (13s).
  var requestLimit = 13000;

  var requestHandler = null;
  var inited = null;
  var initedResolve = null;
  var initedPromise = new Promise(function (resolve) { initedResolve = resolve; });
  var scriptLoaded = false;
  var scriptError = '';
  var pendingUrl = null;

  function safeHost(action, argument) {
    try {
      return String(host(action, argument) || '');
    } catch (error) {
      return '';
    }
  }

  function toBuffer(value) {
    if (value instanceof Uint8Array) return Buffer.from(value);
    return Buffer.from(String(value == null ? '' : value), 'utf8');
  }

  function crypto(request) {
    try {
      return JSON.parse(safeHost('crypto', JSON.stringify(request)));
    } catch (error) {
      return {};
    }
  }

  function formBody(data) {
    return typeof data === 'string' ? data : new URLSearchParams(data).toString();
  }

  function send(eventName, data) {
    return new Promise(function (resolve, reject) {
      if (eventName === EVENT_NAMES.inited) {
        if (inited) {
          reject(new Error('Script is inited'));
          return;
        }
        inited = data || {};
        if (initedResolve) initedResolve();
        resolve();
        return;
      }
      if (eventName === EVENT_NAMES.updateAlert) {
        resolve();
        return;
      }
      reject(new Error('The event is not supported: ' + eventName));
    });
  }

  function on(eventName, handler) {
    if (eventName !== EVENT_NAMES.request) {
      return Promise.reject(new Error('The event is not supported: ' + eventName));
    }
    requestHandler = handler;
    return Promise.resolve();
  }

  /** needle's response shape as LX sources use it. */
  function deliver(answer, callback) {
    if (!callback) return;
    if (answer && answer.failed) {
      try {
        callback.call(null, new Error(String(answer.failed).slice(0, 120)), null, null);
      } catch (error) {
        /* A broken callback must not break the runtime. */
      }
      return;
    }
    var raw = Buffer.from(answer && answer.base64 ? answer.base64 : '', 'base64');
    var parsed = raw.toString('utf8');
    try {
      parsed = JSON.parse(parsed);
    } catch (error) {
      /* Keep the text when the body is not JSON. */
    }
    try {
      callback.call(
        null,
        null,
        {
          statusCode: answer && answer.code ? answer.code : 0,
          statusMessage: '',
          headers: (answer && answer.headers) || {},
          bytes: raw.length,
          raw: raw,
          body: parsed,
        },
        parsed,
      );
    } catch (error) {
      /* A broken callback must not break the runtime. */
    }
  }

  /**
   * Host HTTP is asynchronous; the JS side polls it. Each poll waits briefly on
   * the host, so parallel requests still overlap and the JS thread stays simple.
   */
  function request(url, options, callback) {
    if (typeof options === 'function') {
      callback = options;
      options = {};
    }
    var settings = options || {};
    var method = settings.method || 'get';
    var headers = settings.headers || {};
    // lx-music-mobile injects a desktop browser UA + Accept on every request;
    // many lyric/MV/sign APIs branch on UA, so omit it and they return no url.
    var fields = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36',
      'Accept': 'application/json',
    };
    Object.keys(headers).forEach(function (key) {
      if (headers[key] != null) {
        // Script-provided header overrides the default, case-insensitively.
        var base = key.toLowerCase();
        Object.keys(fields).forEach(function (existing) {
          if (existing.toLowerCase() === base) delete fields[existing];
        });
        fields[key] = String(headers[key]);
      }
    });
    var hasHeader = function (name) {
      return Object.keys(fields).some(function (key) { return key.toLowerCase() === name; });
    };
    var payload = null;
    if (settings.body != null) {
      if (typeof settings.body === 'string' || settings.body instanceof Uint8Array) {
        payload = settings.body;
      } else if (hasHeader('content-type') && /json/i.test(
        fields[Object.keys(fields).find(function (key) { return key.toLowerCase() === 'content-type'; })]
      )) {
        payload = JSON.stringify(settings.body);
      } else {
        payload = formBody(settings.body);
        if (!hasHeader('content-type')) fields['Content-Type'] = 'application/x-www-form-urlencoded';
      }
    } else if (settings.form != null || settings.formData != null) {
      payload = formBody(settings.form == null ? settings.formData : settings.form);
      if (!hasHeader('content-type')) fields['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    var wait = typeof settings.timeout === 'number' && settings.timeout > 0
      ? Math.min(settings.timeout, requestLimit)
      : requestLimit;
    var binary = payload instanceof Uint8Array;
    var id = Number(safeHost('httpStart', JSON.stringify({
      url: String(url),
      method: String(method).toUpperCase(),
      headers: fields,
      timeout: wait,
      body: payload == null || binary ? null : String(payload),
      bodyBase64: binary ? Buffer.from(payload).toString('base64') : null,
    })));
    if (!(id > 0)) {
      deliver({ failed: 'request failed' }, callback);
      return function () {};
    }
    var deadline = Date.now() + wait;
    for (;;) {
      var text = safeHost('httpPoll', String(id));
      if (text && text !== 'null') {
        safeHost('httpCancel', String(id));
        var answer = null;
        try {
          answer = JSON.parse(text);
        } catch (error) {
          answer = { failed: 'bad response' };
        }
        deliver(answer, callback);
        break;
      }
      if (Date.now() >= deadline) {
        safeHost('httpCancel', String(id));
        deliver({ failed: 'request timeout' }, callback);
        break;
      }
    }
    return function () { safeHost('httpCancel', String(id)); };
  }

  var utils = {
    crypto: {
      aesEncrypt: function (buffer, mode, key, iv) {
        var ecb = /ecb/i.test(String(mode));
        var answer = crypto({
          op: 'aes', encrypt: true, mode: ecb ? 'ECB' : 'CBC', padding: true,
          data: toBuffer(buffer).toString('base64'),
          key: toBuffer(key).toString('base64'),
          iv: ecb ? '' : toBuffer(iv == null ? '' : iv).toString('base64'),
        });
        return Buffer.from(answer.data || '', 'base64');
      },
      aesDecrypt: function (buffer, mode, key, iv) {
        var ecb = /ecb/i.test(String(mode));
        var answer = crypto({
          op: 'aes', encrypt: false, mode: ecb ? 'ECB' : 'CBC', padding: true,
          data: toBuffer(buffer).toString('base64'),
          key: toBuffer(key).toString('base64'),
          iv: ecb ? '' : toBuffer(iv == null ? '' : iv).toString('base64'),
        });
        return Buffer.from(answer.data || '', 'base64');
      },
      rsaEncrypt: function (buffer, key) {
        var answer = crypto({ op: 'rsaRaw', encrypt: true, key: String(key), data: toBuffer(buffer).toString('base64') });
        return Buffer.from(answer.data || '', 'base64');
      },
      rsaDecrypt: function (buffer, key) {
        var answer = crypto({ op: 'rsaRaw', encrypt: false, key: String(key), data: toBuffer(buffer).toString('base64') });
        return Buffer.from(answer.data || '', 'base64');
      },
      randomBytes: function (size) {
        var answer = crypto({ op: 'random', count: Number(size) || 16 });
        return Buffer.from(answer.data || '', 'base64');
      },
      md5: function (value) {
        if (typeof value === 'string') return safeHost('md5', value);
        return crypto({ op: 'hash', alg: 'md5', data: toBuffer(value).toString('base64') }).hex || '';
      },
      sha1: function (value) {
        return crypto({ op: 'hash', alg: 'sha1', data: toBuffer(value).toString('base64') }).hex || '';
      },
      sha256: function (value) {
        return crypto({ op: 'hash', alg: 'sha256', data: toBuffer(value).toString('base64') }).hex || '';
      },
    },
    buffer: {
      from: function () { return Buffer.from.apply(null, arguments); },
      bufToString: function (buffer, format) {
        return (typeof buffer === 'string' ? Buffer.from(buffer, 'binary') : toBuffer(buffer)).toString(format);
      },
    },
    zlib: {
      inflate: function (buffer) {
        var answer = crypto({ op: 'inflate', data: toBuffer(buffer).toString('base64'), output: 'base64' });
        return Promise.resolve(Buffer.from(answer.data || '', 'base64'));
      },
      deflate: function (data) {
        var answer = crypto({ op: 'deflate', data: toBuffer(data).toString('base64'), output: 'base64' });
        return Promise.resolve(Buffer.from(answer.data || '', 'base64'));
      },
    },
  };

  var info = {};
  try {
    info = JSON.parse(safeHost('module', 'lx://info')) || {};
  } catch (error) {
    info = {};
  }
  var silent = function () {};
  globalThis.console = new Proxy({}, { get: function () { return silent; } });
  globalThis.lx = Object.freeze({
    EVENT_NAMES: EVENT_NAMES,
    request: request,
    send: send,
    on: on,
    utils: utils,
    version: '2.0.0',
    env: 'mobile',
    currentScriptInfo: Object.freeze({ name: info.name || '', version: info.version || '', description: info.description || '', author: info.author || '', rawScript: '' }),
  });

  function flush() {
    if (globalThis.__lxTimers) globalThis.__lxTimers.flush();
  }

  /** 脚本对某个平台是否声明了取址能力；兼容 actions 为数组/字符串/对象/函数键。 */
  function hasMusicUrl(entry) {
    if (entry == null) return false;
    if (typeof entry === 'string') return /musicurl/i.test(entry);
    if (typeof entry !== 'object') return false;
    if (typeof entry.musicUrl === 'function') return true;
    var raw = entry.actions != null ? entry.actions : entry.action;
    if (typeof raw === 'string' && /musicurl/i.test(raw)) return true;
    if (Array.isArray(raw) && raw.some(function (item) { return /musicurl/i.test(String(item)); })) return true;
    if (raw && typeof raw === 'object') {
      var matched = Object.keys(raw).some(function (key) {
        return /musicurl/i.test(key) && raw[key] !== false && raw[key] != null;
      });
      if (matched) return true;
    }
    return Object.keys(entry).some(function (key) {
      return /musicurl/i.test(key) && typeof entry[key] === 'function';
    });
  }

  function declaredQualities(entry) {
    var raw = entry && typeof entry === 'object'
      ? (entry.qualitys != null ? entry.qualitys : (entry.qualities != null ? entry.qualities : entry.quality))
      : null;
    var list = Array.isArray(raw) ? raw
      : typeof raw === 'string' ? raw.split(/[,\s]+/)
        : [];
    return list.map(function (item) { return String(item).trim().toLowerCase(); })
      .filter(function (item) { return qualities.indexOf(item) >= 0; });
  }

  /**
   * 收集真实 inited 声明里的平台能力。
   *
   * 不再要求 type === 'music'、actions 必须是数组、也不要求此刻已注册 requestHandler：
   * 混淆脚本常见 type 缺失、actions 为字符串、或先 send(inited) 再异步 on(request)。
   * 只要 inited 声明里能证明支持 musicUrl，就算能力探测通过；handler 单独上报，
   * 由取址探测与播放阶段决定是否真正可用。
   */
  function collectDeclaredSources(declared) {
    var result = {};
    var add = function (key, entry) {
      var normalized = String(key == null ? '' : key).trim().toLowerCase();
      if (!normalized || normalized === 'length' || !hasMusicUrl(entry)) return;
      result[normalized] = declaredQualities(entry);
    };
    if (Array.isArray(declared)) {
      declared.forEach(function (item) {
        if (typeof item === 'string') {
          // 数组形态的 inited.sources 本身就是平台清单，musicUrl 由全局 handler 提供。
          add(item, { musicUrl: function () {} });
        } else if (item && typeof item === 'object') {
          add(item.key != null ? item.key : (item.source != null ? item.source : (item.id != null ? item.id : item.name)), item);
        }
      });
    } else if (declared && typeof declared === 'object') {
      Object.keys(declared).forEach(function (key) { add(key, declared[key]); });
    } else if (typeof declared === 'string') {
      declared.split(/[,\s]+/).forEach(function (key) { add(key, { musicUrl: function () {} }); });
    }
    return result;
  }

  function sourceSnapshot() {
    flush();
    var handler = typeof requestHandler === 'function';
    if (scriptError) return { ready: false, error: scriptError, handler: handler };
    if (!inited) return { ready: false, handler: handler };
    var declared = inited.sources != null ? inited.sources : inited;
    if (!declared) return { ready: false, error: 'no sources declared', handler: handler };
    return {
      ready: true,
      sources: collectDeclaredSources(declared),
      handler: handler,
    };
  }

  function normalizeUrl(value) {
    if (typeof value !== 'string' || value.length > 2048 || !/^https?:/i.test(value)) {
      return { error: 'source returned no address' };
    }
    return { url: value };
  }

  function runScript() {
    if (scriptLoaded) return;
    scriptLoaded = true;
    try {
      (0, eval)(safeHost('module', 'lx://script'));
      flush();
    } catch (error) {
      scriptError = 'source did not start';
    }
  }

  globalThis.__lx = {
    /** Evaluates the classic script and reports its declared musicUrl capabilities. */
    load: function () {
      runScript();
      return JSON.stringify(sourceSnapshot());
    },
    /** Drives timers and microtask-friendly steps while waiting for `inited`. */
    step: function () {
      return JSON.stringify(sourceSnapshot());
    },
    /** Explicit probe entry point; same shape as step(), used by the host importer. */
    probe: function () {
      runScript();
      flush();
      return JSON.stringify(sourceSnapshot());
    },
    /** Starts one musicUrl lookup. Answer: {url}, {error} or {pending:true}. */
    musicUrl: function (inputJson) {
      runScript();
      pendingUrl = null;
      var input;
      try {
        input = JSON.parse(inputJson);
      } catch (error) {
        return JSON.stringify({ error: 'bad request' });
      }
      if (typeof requestHandler !== 'function') return JSON.stringify({ error: 'no request handler' });
      try {
        // Official preload calls events.request.call(globalThis.lx, ...), so
        // scripts using this.utils / this.request inside the handler keep working.
        var answer = requestHandler.call(globalThis.lx, {
          source: input.source,
          action: 'musicUrl',
          info: { type: input.quality, musicInfo: input.musicInfo },
        });
        if (answer && typeof answer.then === 'function') {
          answer.then(
            function (value) { pendingUrl = normalizeUrl(value); },
            function () { pendingUrl = { error: 'source failed' }; },
          );
          return JSON.stringify({ pending: true });
        }
        return JSON.stringify(normalizeUrl(answer));
      } catch (error) {
        return JSON.stringify({ error: 'source failed' });
      }
    },
    /** Reads the result of a pending lookup; also drives timers. */
    musicResult: function () {
      flush();
      return pendingUrl ? JSON.stringify(pendingUrl) : 'null';
    },
  };
})();
