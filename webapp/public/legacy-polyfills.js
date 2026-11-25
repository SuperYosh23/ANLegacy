// Polyfills and error reporting for the iOS app's embedded web view.
//
// The phone runs iOS 9, whose WebKit is missing a fair number of things the
// app takes for granted. The most serious is fetch: Safari only gained it in
// 10.1, so every API call in the app would fail with "fetch is not defined"
// and nothing would ever load.
//
// The polyfills are deliberately small and only cover what the app actually
// uses. Anything missing that is not needed here is left alone rather than
// half-implemented.
//
// The error reporting at the bottom posts uncaught errors to the phone, which
// logs them. Without it a JavaScript error on the phone is invisible: the page
// just stays blank, and there is no crash and no console to read.

(function () {
  'use strict';

  // --- globalThis ------------------------------------------------------------
  // Safari only gained globalThis in 12.1, and the app's bundle refers to it
  // directly - a bare reference to an identifier that does not exist is a
  // ReferenceError, which kills the whole script and leaves the page blank.
  //
  // The typeof check is safe on an undeclared identifier: typeof never throws
  // for an unknown name.
  if (typeof globalThis === 'undefined') {
    window.globalThis = window;
  }

  // --- fetch -----------------------------------------------------------------
  // A small XMLHttpRequest-backed fetch. Only the parts the app uses are
  // supported: a URL, optional method, headers and body; the response is
  // read as JSON when the content type says so, and as text otherwise.
  if (typeof window.fetch !== 'function') {
    window.fetch = function (input, init) {
      init = init || {};
      var url = typeof input === 'string' ? input : (input && input.url);
      var method = (init.method || (input && input.method) || 'GET').toUpperCase();
      var headers = init.headers || {};

      return new Promise(function (resolve, reject) {
        var xhr = new XMLHttpRequest();
        xhr.open(method, url, true);
        xhr.withCredentials = !!init.credentials;

        Object.keys(headers).forEach(function (key) {
          try { xhr.setRequestHeader(key, headers[key]); } catch (e) {}
        });

        xhr.onload = function () {
          var type = xhr.getResponseHeader('Content-Type') || '';
          var body = xhr.responseText;
          resolve({
            ok: xhr.status >= 200 && xhr.status < 300,
            status: xhr.status,
            statusText: xhr.statusText,
            headers: {
              get: function (name) { return xhr.getResponseHeader(name); }
            },
            json: function () {
              try { return Promise.resolve(JSON.parse(body)); }
              catch (e) { return Promise.reject(e); }
            },
            text: function () { return Promise.resolve(body); },
            blob: function () { return Promise.resolve(body); }
          });
        };
        xhr.onerror = function () {
          reject(new TypeError('Network request failed: ' + url));
        };
        xhr.ontimeout = function () {
          reject(new TypeError('Network request timed out: ' + url));
        };
        xhr.onabort = function () {
          reject(new TypeError('Network request aborted: ' + url));
        };

        xhr.send(init.body || null);
      });
    };
  }

  // --- Object.entries / Object.values / getOwnPropertyDescriptors -----------
  // ES2017, so Safari 10.1 and later. iOS 9 has none of them.
  if (!Object.entries) {
    Object.entries = function (object) {
      var out = [];
      if (object == null) return out;
      Object.keys(Object(object)).forEach(function (key) {
        out.push([key, object[key]]);
      });
      return out;
    };
  }
  if (!Object.values) {
    Object.values = function (object) {
      var out = [];
      if (object == null) return out;
      Object.keys(Object(object)).forEach(function (key) {
        out.push(object[key]);
      });
      return out;
    };
  }
  if (!Object.getOwnPropertyDescriptors) {
    Object.getOwnPropertyDescriptors = function (object) {
      var out = {};
      if (object == null) return out;
      Object.keys(Object(object)).forEach(function (key) {
        out[key] = Object.getOwnPropertyDescriptor(object, key);
      });
      return out;
    };
  }
  if (!Object.fromEntries) {
    Object.fromEntries = function (entries) {
      var out = {};
      (entries || []).forEach(function (pair) {
        if (!pair) return;
        out[pair[0]] = pair[1];
      });
      return out;
    };
  }
  if (!Object.hasOwn) {
    Object.hasOwn = function (object, key) {
      return object != null && Object.prototype.hasOwnProperty.call(object, key);
    };
  }

  // --- Promise.allSettled / Promise.any ---------------------------------------
  // ES2020 and ES2021. iOS 9 has neither.
  if (!Promise.allSettled) {
    Promise.allSettled = function (promises) {
      return Promise.all((promises || []).map(function (promise) {
        return Promise.resolve(promise).then(
          function (value) { return { status: 'fulfilled', value: value }; },
          function (reason) { return { status: 'rejected', reason: reason }; }
        );
      }));
    };
  }
  if (!Promise.any) {
    Promise.any = function (promises) {
      return new Promise(function (resolve, reject) {
        var errors = [];
        var left = (promises || []).length;
        if (!left) {
          reject(new Error('All promises were rejected'));
          return;
        }
        (promises || []).forEach(function (promise, index) {
          Promise.resolve(promise).then(resolve, function (reason) {
            errors[index] = reason;
            left -= 1;
            if (!left) reject(errors);
          });
        });
      });
    };
  }

  // --- queueMicrotask ---------------------------------------------------------
  // Safari 12.1. The app guards its own use of it, but a stub keeps any
  // library that reaches for it working.
  if (!window.queueMicrotask) {
    window.queueMicrotask = function (callback) {
      Promise.resolve().then(callback);
    };
  }

  // --- URLSearchParams -------------------------------------------------------
  if (typeof window.URLSearchParams !== 'function') {
    window.URLSearchParams = function (init) {
      this._pairs = [];
      if (typeof init === 'string') {
        init.replace(/^\?/, '').split('&').forEach(function (pair) {
          if (!pair) return;
          var parts = pair.split('=');
          this.append(decodeURIComponent(parts[0]), decodeURIComponent(parts[1] || ''));
        }, this);
      } else if (init && typeof init === 'object') {
        var self = this;
        Object.keys(init).forEach(function (key) {
          self.append(key, init[key]);
        });
      }
    };
    window.URLSearchParams.prototype.append = function (key, value) {
      this._pairs.push([String(key), String(value)]);
    };
    window.URLSearchParams.prototype.get = function (key) {
      for (var i = 0; i < this._pairs.length; i++) {
        if (this._pairs[i][0] === key) return this._pairs[i][1];
      }
      return null;
    };
    window.URLSearchParams.prototype.getAll = function (key) {
      var out = [];
      this._pairs.forEach(function (p) { if (p[0] === key) out.push(p[1]); });
      return out;
    };
    window.URLSearchParams.prototype.has = function (key) {
      return this.get(key) !== null;
    };
    window.URLSearchParams.prototype.set = function (key, value) {
      this.delete(key);
      this.append(key, value);
    };
    window.URLSearchParams.prototype.delete = function (key) {
      this._pairs = this._pairs.filter(function (p) { return p[0] !== key; });
    };
    window.URLSearchParams.prototype.toString = function () {
      return this._pairs.map(function (p) {
        return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]);
      }).join('&');
    };
    window.URLSearchParams.prototype.forEach = function (fn, self) {
      this._pairs.forEach(function (p) { fn.call(self, p[1], p[0], this); }, this);
    };
  }

  // --- String.prototype.padStart / padEnd ------------------------------------
  if (!String.prototype.padStart) {
    String.prototype.padStart = function (length, pad) {
      var text = String(this);
      pad = pad === undefined ? ' ' : String(pad);
      while (text.length < length) text = pad + text;
      return text.length > length ? text.slice(text.length - length) : text;
    };
  }
  if (!String.prototype.padEnd) {
    String.prototype.padEnd = function (length, pad) {
      var text = String(this);
      pad = pad === undefined ? ' ' : String(pad);
      while (text.length < length) text += pad;
      return text.length > length ? text.slice(0, length) : text;
    };
  }

  // --- Array.prototype.flatMap / flat ----------------------------------------
  if (!Array.prototype.flatMap) {
    Array.prototype.flatMap = function (fn, self) {
      return [].concat.apply([], this.map(function (v, i) {
        return fn.call(self, v, i, this);
      }));
    };
  }
  if (!Array.prototype.flat) {
    Array.prototype.flat = function (depth) {
      if (depth === undefined) depth = 1;
      var self = this;
      return this.reduce(function (acc, value) {
        if (Object.prototype.toString.call(value) === '[object Array]') {
          return acc.concat(depth > 0 ? value.flat(depth - 1) : value);
        }
        acc.push(value);
        return acc;
      }, []);
    };
  }

  // --- ResizeObserver --------------------------------------------------------
  // Safari only gained this in 13.1. The app uses it to track element sizes.
  // A stub that never fires is better than a ReferenceError, but the app does
  // depend on it for layout in a few places, so this fires once on the next
  // frame with the element's current box, which is enough for a first paint.
  if (typeof window.ResizeObserver !== 'function') {
    window.ResizeObserver = function (callback) {
      this._callback = callback;
      this._elements = [];
    };
    window.ResizeObserver.prototype.observe = function (element) {
      this._elements.push(element);
      var self = this;
      window.setTimeout(function () {
        if (!element.getBoundingClientRect) return;
        var box = element.getBoundingClientRect();
        try {
          self._callback([{ target: element, contentRect: box }], self);
        } catch (e) {}
      }, 0);
    };
    window.ResizeObserver.prototype.unobserve = function (element) {
      this._elements = this._elements.filter(function (e) { return e !== element; });
    };
    window.ResizeObserver.prototype.disconnect = function () {
      this._elements = [];
    };
  }
  // --- Error reporting -------------------------------------------------------
  // Post anything that goes wrong to the phone, which writes it to the app's
  // log. A blank page with no log entry is the hardest kind of bug to chase.
  //
  // Messages and stacks are sent separately and both are bounded. A minified
  // bundle's stack is thousands of characters of opaque frame names, and
  // sending it whole buried the one line that mattered - the error message -
  // under pages of noise.
  var clip = function (text, max) {
    if (text == null) return '';
    text = String(text);
    return text.length > max ? text.slice(0, max) + '...' : text;
  };

  var report = function (kind, message, extra) {
    try {
      var xhr = new XMLHttpRequest();
      xhr.open('POST', '/api/log', true);
      xhr.setRequestHeader('Content-Type', 'application/json');
      xhr.send(JSON.stringify({
        kind: kind,
        message: clip(message, 400),
        extra: clip(extra, 400),
      }));
    } catch (e) {}
  };

  // The first few frames of a stack, with the newlines flattened so the whole
  // thing arrives on one line.
  var frames = function (error) {
    if (!error || !error.stack) return '';
    return String(error.stack).split('\n').slice(0, 4).join(' | ');
  };

  window.addEventListener('error', function (event) {
    var target = event.target;
    if (target && target !== window && target.tagName === 'SCRIPT') {
      report('script', 'failed to load ' + (target.src || '(inline)'));
      return;
    }
    report('error', event.message, (event.filename || '') + ':' + (event.lineno || 0));
  });

  window.addEventListener('unhandledrejection', function (event) {
    var reason = event.reason;
    var message = (reason && reason.message) ? reason.message : String(reason);
    report('promise', message, frames(reason));
  });

  var originalError = window.console && window.console.error;
  if (originalError) {
    window.console.error = function () {
      var args = Array.prototype.slice.call(arguments);
      var first = args[0];
      // An Error carries its message; anything else is stringified.
      var message = (first && first.message) ? first.message
                    : (first && first.stack) ? first.stack
                    : args.map(function (a) {
                        return (a && a.message) ? a.message : String(a);
                      }).join(' ');
      var extra = frames(first);
      if (!extra && args.length > 1) {
        extra = args.slice(1).map(function (a) { return String(a); }).join(' ');
      }
      report('console', message, extra);
      originalError.apply(window.console, arguments);
    };
  }
})();
