(() => {
  // src/slugger.js
  var STRIP = /[^\p{L}\p{N}\p{M} _-]/gu;
  function slug(value) {
    return String(value).toLowerCase().replace(STRIP, "").replace(/ /g, "-");
  }
  var Slugger = class {
    constructor() {
      this.occurrences = /* @__PURE__ */ new Map();
    }
    /** 같은 문서 안의 중복 슬러그에 -1, -2… 를 붙인다. */
    slug(value) {
      const base = slug(value);
      let result = base;
      while (this.occurrences.has(result)) {
        const n = (this.occurrences.get(base) ?? 0) + 1;
        this.occurrences.set(base, n);
        result = `${base}-${n}`;
      }
      this.occurrences.set(result, 0);
      return result;
    }
  };

  // src/generated/octicons.js
  var octicons_default = {
    "link": '<path d="m7.775 3.275 1.25-1.25a3.5 3.5 0 1 1 4.95 4.95l-2.5 2.5a3.5 3.5 0 0 1-4.95 0 .751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018 1.998 1.998 0 0 0 2.83 0l2.5-2.5a2.002 2.002 0 0 0-2.83-2.83l-1.25 1.25a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042Zm-4.69 9.64a1.998 1.998 0 0 0 2.83 0l1.25-1.25a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042l-1.25 1.25a3.5 3.5 0 1 1-4.95-4.95l2.5-2.5a3.5 3.5 0 0 1 4.95 0 .751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018 1.998 1.998 0 0 0-2.83 0l-2.5 2.5a1.998 1.998 0 0 0 0 2.83Z"></path>',
    "info": '<path d="M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"></path>',
    "light-bulb": '<path d="M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.084-.1-.173-.205-.268-.32C3.201 7.75 2.5 6.766 2.5 5.25 2.5 2.31 4.863 0 8 0s5.5 2.31 5.5 5.25c0 1.516-.701 2.5-1.328 3.259-.095.115-.184.22-.268.319-.207.245-.383.453-.541.681-.208.3-.33.565-.37.847a.751.751 0 0 1-1.485-.212c.084-.593.337-1.078.621-1.489.203-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75ZM5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5ZM6 15.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1-.75-.75Z"></path>',
    "report": '<path d="M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Zm7 2.25v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 9a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"></path>',
    "alert": '<path d="M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"></path>',
    "stop": '<path d="M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6a.749.749 0 0 1-.22.53l-4.25 4.25A.749.749 0 0 1 11 16H5a.749.749 0 0 1-.53-.22L.22 11.53A.749.749 0 0 1 0 11V5c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"></path>'
  };

  // src/postprocess.js
  var HEADINGS = "h1, h2, h3, h4, h5, h6";
  function addHeadingAnchors(root2) {
    root2.querySelectorAll("a.anchor").forEach((a) => a.remove());
    const slugger = new Slugger();
    const outline = [];
    for (const heading of root2.querySelectorAll(HEADINGS)) {
      const text = heading.textContent.trim();
      const id = slugger.slug(text);
      heading.id = id;
      const anchor = root2.ownerDocument.createElement("a");
      anchor.className = "anchor";
      anchor.setAttribute("aria-hidden", "true");
      anchor.href = `#${id}`;
      const icon = root2.ownerDocument.createElement("span");
      icon.className = "octicon octicon-link";
      anchor.append(icon);
      heading.prepend(anchor);
      outline.push({ level: Number(heading.tagName[1]), text, id });
    }
    return outline;
  }
  var ALERTS = {
    NOTE: { title: "Note", icon: "info" },
    TIP: { title: "Tip", icon: "light-bulb" },
    IMPORTANT: { title: "Important", icon: "report" },
    WARNING: { title: "Warning", icon: "alert" },
    CAUTION: { title: "Caution", icon: "stop" }
  };
  var ALERT_MARKER = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*(?:\n|$)/;
  function transformAlerts(root2) {
    const doc2 = root2.ownerDocument;
    for (const quote of root2.querySelectorAll("blockquote")) {
      const first = quote.firstElementChild;
      if (!first || first.tagName !== "P") continue;
      const textNode = first.firstChild;
      if (!textNode || textNode.nodeType !== 3) continue;
      const match = ALERT_MARKER.exec(textNode.nodeValue);
      if (!match) continue;
      const { title, icon } = ALERTS[match[1]];
      const alert = doc2.createElement("div");
      alert.className = `markdown-alert markdown-alert-${match[1].toLowerCase()}`;
      alert.setAttribute("dir", "auto");
      const titleEl = doc2.createElement("p");
      titleEl.className = "markdown-alert-title";
      titleEl.setAttribute("dir", "auto");
      titleEl.innerHTML = `<svg class="octicon octicon-${icon} mr-2" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">${octicons_default[icon] ?? ""}</svg>`;
      titleEl.append(doc2.createTextNode(title));
      alert.append(titleEl);
      textNode.nodeValue = textNode.nodeValue.slice(match[0].length);
      if (!first.textContent.trim() && !first.querySelector("*")) first.remove();
      while (quote.firstChild) alert.append(quote.firstChild);
      quote.replaceWith(alert);
    }
  }
  function markTaskLists(root2) {
    for (const input of root2.querySelectorAll('li > input[type="checkbox"]')) {
      const li = input.parentElement;
      if (li.firstElementChild !== input) continue;
      li.classList.add("task-list-item");
      input.classList.add("task-list-item-checkbox");
      li.parentElement?.classList.add("contains-task-list");
    }
  }
  var SHORTCODE = /:([a-z0-9_+-]+):/gi;
  var SKIP_EMOJI_IN = /* @__PURE__ */ new Set(["PRE", "CODE", "SCRIPT", "STYLE", "TEXTAREA", "KBD"]);
  function replaceEmoji(root2, map) {
    if (!map) return 0;
    const doc2 = root2.ownerDocument;
    const walker = doc2.createTreeWalker(root2, 4, {
      acceptNode(node) {
        if (!node.nodeValue.includes(":")) return 2;
        for (let el = node.parentElement; el && el !== root2; el = el.parentElement) {
          if (SKIP_EMOJI_IN.has(el.tagName)) return 2;
        }
        return 1;
      }
    });
    let replaced = 0;
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const node of nodes) {
      const next = node.nodeValue.replace(SHORTCODE, (whole, name) => {
        const emoji = map[name];
        if (!emoji) return whole;
        replaced += 1;
        return emoji;
      });
      if (next !== node.nodeValue) node.nodeValue = next;
    }
    return replaced;
  }
  function convertSpecialBlocks(root2) {
    const doc2 = root2.ownerDocument;
    for (const code of root2.querySelectorAll("pre > code.language-mermaid")) {
      const div = doc2.createElement("div");
      div.className = "mermaid";
      div.dataset.source = code.textContent;
      div.textContent = code.textContent;
      code.parentElement.replaceWith(div);
    }
    for (const code of root2.querySelectorAll("pre > code.language-math")) {
      const div = doc2.createElement("div");
      div.className = "cmarks-math-block";
      div.dataset.source = code.textContent;
      div.textContent = code.textContent;
      code.parentElement.replaceWith(div);
    }
  }
  function collectStats(root2) {
    return {
      codeBlocks: root2.querySelectorAll("pre > code").length,
      images: root2.querySelectorAll("img").length,
      headings: root2.querySelectorAll(HEADINGS).length
    };
  }

  // src/loaders.js
  var ASSETS = "cmarks-local://assets/";
  var pending = /* @__PURE__ */ new Map();
  function loadScript(rel) {
    if (pending.has(rel)) return pending.get(rel);
    const promise = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = ASSETS + rel;
      script.onload = () => resolve();
      script.onerror = () => reject(new Error(`load failed: ${rel}`));
      document.head.append(script);
    });
    pending.set(rel, promise);
    return promise;
  }
  function loadStyle(rel) {
    const href = ASSETS + rel;
    if (document.querySelector(`link[href="${href}"]`)) return;
    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = href;
    document.head.append(link);
  }
  var SPECIAL_LANGUAGES = /* @__PURE__ */ new Set(["mermaid", "math"]);
  async function highlightCode(root2, { enabled = true } = {}) {
    const hljs = window.hljs;
    if (!hljs || !enabled) return 0;
    const blocks = [...root2.querySelectorAll('pre > code[class*="language-"]')].filter((code) => !code.classList.contains("hljs"));
    const languageOf = (code) => [...code.classList].find((c) => c.startsWith("language-"))?.slice(9).toLowerCase();
    async function highlight(code) {
      const lang = languageOf(code);
      if (!lang || SPECIAL_LANGUAGES.has(lang)) return;
      if (!hljs.getLanguage(lang)) {
        try {
          await loadScript(`vendor/hljs/languages/${lang}.min.js`);
        } catch {
          return;
        }
      }
      if (!hljs.getLanguage(lang)) return;
      hljs.highlightElement(code);
    }
    if (blocks.length <= 20) {
      for (const code of blocks) await highlight(code);
      return blocks.length;
    }
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        observer.unobserve(entry.target);
        highlight(entry.target);
      }
    }, { rootMargin: "400px 0px" });
    for (const code of blocks) observer.observe(code);
    return blocks.length;
  }
  var INLINE_MATH = /\$\$[\s\S]+?\$\$|\$[^\s$][^$\n]*?\$/;
  async function renderMath(root2) {
    const blocks = [...root2.querySelectorAll(".cmarks-math-block:not([data-rendered])")];
    if (blocks.length === 0 && !INLINE_MATH.test(root2.textContent)) return false;
    loadStyle("vendor/katex/katex.min.css");
    await loadScript("vendor/katex/katex.min.js");
    await loadScript("vendor/katex/auto-render.min.js");
    for (const div of blocks) {
      window.katex.render(div.dataset.source ?? div.textContent, div, { displayMode: true, throwOnError: false });
      div.dataset.rendered = "1";
    }
    window.renderMathInElement(root2, {
      delimiters: [
        { left: "$$", right: "$$", display: true },
        { left: "$", right: "$", display: false }
      ],
      ignoredTags: ["script", "noscript", "style", "textarea", "pre", "code", "a", "kbd"],
      ignoredClasses: ["cmarks-math-block", "cmarks-frontmatter", "katex"],
      throwOnError: false
    });
    return true;
  }
  async function renderMermaid(root2, { rerender = false } = {}) {
    const nodes = [...root2.querySelectorAll(rerender ? ".mermaid" : ".mermaid:not([data-processed])")];
    if (nodes.length === 0) return false;
    await loadScript("vendor/mermaid/mermaid.min.js");
    const dark = matchMedia("(prefers-color-scheme: dark)").matches;
    window.mermaid.initialize({ startOnLoad: false, theme: dark ? "dark" : "default", securityLevel: "strict" });
    for (const node of nodes) {
      node.removeAttribute("data-processed");
      node.textContent = node.dataset.source ?? node.textContent;
    }
    await window.mermaid.run({ nodes, suppressErrors: true });
    return true;
  }
  async function ensureEmoji() {
    if (!window.cmarksEmoji) await loadScript("vendor/emoji.js");
    return window.cmarksEmoji ?? {};
  }

  // node_modules/.pnpm/morphdom@2.7.8/node_modules/morphdom/dist/morphdom-esm.js
  var DOCUMENT_FRAGMENT_NODE = 11;
  function morphAttrs(fromNode, toNode) {
    var toNodeAttrs = toNode.attributes;
    var attr;
    var attrName;
    var attrNamespaceURI;
    var attrValue;
    var fromValue;
    if (toNode.nodeType === DOCUMENT_FRAGMENT_NODE || fromNode.nodeType === DOCUMENT_FRAGMENT_NODE) {
      return;
    }
    for (var i = toNodeAttrs.length - 1; i >= 0; i--) {
      attr = toNodeAttrs[i];
      attrName = attr.name;
      attrNamespaceURI = attr.namespaceURI;
      attrValue = attr.value;
      if (attrNamespaceURI) {
        attrName = attr.localName || attrName;
        fromValue = fromNode.getAttributeNS(attrNamespaceURI, attrName);
        if (fromValue !== attrValue) {
          if (attr.prefix === "xmlns") {
            attrName = attr.name;
          }
          fromNode.setAttributeNS(attrNamespaceURI, attrName, attrValue);
        }
      } else {
        fromValue = fromNode.getAttribute(attrName);
        if (fromValue !== attrValue) {
          fromNode.setAttribute(attrName, attrValue);
        }
      }
    }
    var fromNodeAttrs = fromNode.attributes;
    for (var d = fromNodeAttrs.length - 1; d >= 0; d--) {
      attr = fromNodeAttrs[d];
      attrName = attr.name;
      attrNamespaceURI = attr.namespaceURI;
      if (attrNamespaceURI) {
        attrName = attr.localName || attrName;
        if (!toNode.hasAttributeNS(attrNamespaceURI, attrName)) {
          fromNode.removeAttributeNS(attrNamespaceURI, attrName);
        }
      } else {
        if (!toNode.hasAttribute(attrName)) {
          fromNode.removeAttribute(attrName);
        }
      }
    }
  }
  var range;
  var NS_XHTML = "http://www.w3.org/1999/xhtml";
  var doc = typeof document === "undefined" ? void 0 : document;
  var HAS_TEMPLATE_SUPPORT = !!doc && "content" in doc.createElement("template");
  var HAS_RANGE_SUPPORT = !!doc && doc.createRange && "createContextualFragment" in doc.createRange();
  function createFragmentFromTemplate(str) {
    var template = doc.createElement("template");
    template.innerHTML = str;
    return template.content.childNodes[0];
  }
  function createFragmentFromRange(str) {
    if (!range) {
      range = doc.createRange();
      range.selectNode(doc.body);
    }
    var fragment = range.createContextualFragment(str);
    return fragment.childNodes[0];
  }
  function createFragmentFromWrap(str) {
    var fragment = doc.createElement("body");
    fragment.innerHTML = str;
    return fragment.childNodes[0];
  }
  function toElement(str) {
    str = str.trim();
    if (HAS_TEMPLATE_SUPPORT) {
      return createFragmentFromTemplate(str);
    } else if (HAS_RANGE_SUPPORT) {
      return createFragmentFromRange(str);
    }
    return createFragmentFromWrap(str);
  }
  function compareNodeNames(fromEl, toEl) {
    var fromNodeName = fromEl.nodeName;
    var toNodeName = toEl.nodeName;
    var fromCodeStart, toCodeStart;
    if (fromNodeName === toNodeName) {
      return true;
    }
    fromCodeStart = fromNodeName.charCodeAt(0);
    toCodeStart = toNodeName.charCodeAt(0);
    if (fromCodeStart <= 90 && toCodeStart >= 97) {
      return fromNodeName === toNodeName.toUpperCase();
    } else if (toCodeStart <= 90 && fromCodeStart >= 97) {
      return toNodeName === fromNodeName.toUpperCase();
    } else {
      return false;
    }
  }
  function createElementNS(name, namespaceURI) {
    return !namespaceURI || namespaceURI === NS_XHTML ? doc.createElement(name) : doc.createElementNS(namespaceURI, name);
  }
  function moveChildren(fromEl, toEl) {
    var curChild = fromEl.firstChild;
    while (curChild) {
      var nextChild = curChild.nextSibling;
      toEl.appendChild(curChild);
      curChild = nextChild;
    }
    return toEl;
  }
  function syncBooleanAttrProp(fromEl, toEl, name) {
    if (fromEl[name] !== toEl[name]) {
      fromEl[name] = toEl[name];
      if (fromEl[name]) {
        fromEl.setAttribute(name, "");
      } else {
        fromEl.removeAttribute(name);
      }
    }
  }
  var specialElHandlers = {
    OPTION: function(fromEl, toEl) {
      var parentNode = fromEl.parentNode;
      if (parentNode) {
        var parentName = parentNode.nodeName.toUpperCase();
        if (parentName === "OPTGROUP") {
          parentNode = parentNode.parentNode;
          parentName = parentNode && parentNode.nodeName.toUpperCase();
        }
        if (parentName === "SELECT" && !parentNode.hasAttribute("multiple")) {
          if (fromEl.hasAttribute("selected") && !toEl.selected) {
            fromEl.setAttribute("selected", "selected");
            fromEl.removeAttribute("selected");
          }
          parentNode.selectedIndex = -1;
        }
      }
      syncBooleanAttrProp(fromEl, toEl, "selected");
    },
    /**
     * The "value" attribute is special for the <input> element since it sets
     * the initial value. Changing the "value" attribute without changing the
     * "value" property will have no effect since it is only used to the set the
     * initial value.  Similar for the "checked" attribute, and "disabled".
     */
    INPUT: function(fromEl, toEl) {
      syncBooleanAttrProp(fromEl, toEl, "checked");
      syncBooleanAttrProp(fromEl, toEl, "disabled");
      if (fromEl.value !== toEl.value) {
        fromEl.value = toEl.value;
      }
      if (!toEl.hasAttribute("value")) {
        fromEl.removeAttribute("value");
      }
    },
    TEXTAREA: function(fromEl, toEl) {
      var newValue = toEl.value;
      if (fromEl.value !== newValue) {
        fromEl.value = newValue;
      }
      var firstChild = fromEl.firstChild;
      if (firstChild) {
        var oldValue = firstChild.nodeValue;
        if (oldValue == newValue || !newValue && oldValue == fromEl.placeholder) {
          return;
        }
        firstChild.nodeValue = newValue;
      }
    },
    SELECT: function(fromEl, toEl) {
      if (!toEl.hasAttribute("multiple")) {
        var selectedIndex = -1;
        var i = 0;
        var curChild = fromEl.firstChild;
        var optgroup;
        var nodeName;
        while (curChild) {
          nodeName = curChild.nodeName && curChild.nodeName.toUpperCase();
          if (nodeName === "OPTGROUP") {
            optgroup = curChild;
            curChild = optgroup.firstChild;
            if (!curChild) {
              curChild = optgroup.nextSibling;
              optgroup = null;
            }
          } else {
            if (nodeName === "OPTION") {
              if (curChild.hasAttribute("selected")) {
                selectedIndex = i;
                break;
              }
              i++;
            }
            curChild = curChild.nextSibling;
            if (!curChild && optgroup) {
              curChild = optgroup.nextSibling;
              optgroup = null;
            }
          }
        }
        fromEl.selectedIndex = selectedIndex;
      }
    }
  };
  var ELEMENT_NODE = 1;
  var DOCUMENT_FRAGMENT_NODE$1 = 11;
  var TEXT_NODE = 3;
  var COMMENT_NODE = 8;
  function noop() {
  }
  function defaultGetNodeKey(node) {
    if (node) {
      return node.getAttribute && node.getAttribute("id") || node.id;
    }
  }
  function morphdomFactory(morphAttrs2) {
    return function morphdom2(fromNode, toNode, options) {
      if (!options) {
        options = {};
      }
      if (typeof toNode === "string") {
        if (fromNode.nodeName === "#document" || fromNode.nodeName === "HTML") {
          var toNodeHtml = toNode;
          toNode = doc.createElement("html");
          toNode.innerHTML = toNodeHtml;
        } else if (fromNode.nodeName === "BODY") {
          var toNodeBody = toNode;
          toNode = doc.createElement("html");
          toNode.innerHTML = toNodeBody;
          var bodyElement = toNode.querySelector("body");
          if (bodyElement) {
            toNode = bodyElement;
          }
        } else {
          toNode = toElement(toNode);
        }
      } else if (toNode.nodeType === DOCUMENT_FRAGMENT_NODE$1) {
        toNode = toNode.firstElementChild;
      }
      var getNodeKey = options.getNodeKey || defaultGetNodeKey;
      var onBeforeNodeAdded = options.onBeforeNodeAdded || noop;
      var onNodeAdded = options.onNodeAdded || noop;
      var onBeforeElUpdated = options.onBeforeElUpdated || noop;
      var onElUpdated = options.onElUpdated || noop;
      var onBeforeNodeDiscarded = options.onBeforeNodeDiscarded || noop;
      var onNodeDiscarded = options.onNodeDiscarded || noop;
      var onBeforeElChildrenUpdated = options.onBeforeElChildrenUpdated || noop;
      var skipFromChildren = options.skipFromChildren || noop;
      var addChild = options.addChild || function(parent, child) {
        return parent.appendChild(child);
      };
      var childrenOnly = options.childrenOnly === true;
      var fromNodesLookup = /* @__PURE__ */ Object.create(null);
      var keyedRemovalList = [];
      function addKeyedRemoval(key) {
        keyedRemovalList.push(key);
      }
      function walkDiscardedChildNodes(node, skipKeyedNodes) {
        if (node.nodeType === ELEMENT_NODE) {
          var curChild = node.firstChild;
          while (curChild) {
            var key = void 0;
            if (skipKeyedNodes && (key = getNodeKey(curChild))) {
              addKeyedRemoval(key);
            } else {
              onNodeDiscarded(curChild);
              if (curChild.firstChild) {
                walkDiscardedChildNodes(curChild, skipKeyedNodes);
              }
            }
            curChild = curChild.nextSibling;
          }
        }
      }
      function removeNode(node, parentNode, skipKeyedNodes) {
        if (onBeforeNodeDiscarded(node) === false) {
          return;
        }
        if (parentNode) {
          parentNode.removeChild(node);
        }
        onNodeDiscarded(node);
        walkDiscardedChildNodes(node, skipKeyedNodes);
      }
      function indexTree(node) {
        if (node.nodeType === ELEMENT_NODE || node.nodeType === DOCUMENT_FRAGMENT_NODE$1) {
          var curChild = node.firstChild;
          while (curChild) {
            var key = getNodeKey(curChild);
            if (key) {
              fromNodesLookup[key] = curChild;
            }
            indexTree(curChild);
            curChild = curChild.nextSibling;
          }
        }
      }
      indexTree(fromNode);
      function handleNodeAdded(el) {
        onNodeAdded(el);
        var curChild = el.firstChild;
        while (curChild) {
          var nextSibling = curChild.nextSibling;
          var key = getNodeKey(curChild);
          if (key) {
            var unmatchedFromEl = fromNodesLookup[key];
            if (unmatchedFromEl && compareNodeNames(curChild, unmatchedFromEl)) {
              curChild.parentNode.replaceChild(unmatchedFromEl, curChild);
              morphEl(unmatchedFromEl, curChild);
            } else {
              handleNodeAdded(curChild);
            }
          } else {
            handleNodeAdded(curChild);
          }
          curChild = nextSibling;
        }
      }
      function cleanupFromEl(fromEl, curFromNodeChild, curFromNodeKey) {
        while (curFromNodeChild) {
          var fromNextSibling = curFromNodeChild.nextSibling;
          if (curFromNodeKey = getNodeKey(curFromNodeChild)) {
            addKeyedRemoval(curFromNodeKey);
          } else {
            removeNode(
              curFromNodeChild,
              fromEl,
              true
              /* skip keyed nodes */
            );
          }
          curFromNodeChild = fromNextSibling;
        }
      }
      function morphEl(fromEl, toEl, childrenOnly2) {
        var toElKey = getNodeKey(toEl);
        if (toElKey) {
          delete fromNodesLookup[toElKey];
        }
        if (!childrenOnly2) {
          var beforeUpdateResult = onBeforeElUpdated(fromEl, toEl);
          if (beforeUpdateResult === false) {
            return;
          } else if (beforeUpdateResult instanceof HTMLElement) {
            fromEl = beforeUpdateResult;
            indexTree(fromEl);
          }
          morphAttrs2(fromEl, toEl);
          onElUpdated(fromEl);
          if (onBeforeElChildrenUpdated(fromEl, toEl) === false) {
            return;
          }
        }
        if (fromEl.nodeName !== "TEXTAREA") {
          morphChildren(fromEl, toEl);
        } else {
          specialElHandlers.TEXTAREA(fromEl, toEl);
        }
      }
      function morphChildren(fromEl, toEl) {
        var skipFrom = skipFromChildren(fromEl, toEl);
        var curToNodeChild = toEl.firstChild;
        var curFromNodeChild = fromEl.firstChild;
        var curToNodeKey;
        var curFromNodeKey;
        var fromNextSibling;
        var toNextSibling;
        var matchingFromEl;
        outer: while (curToNodeChild) {
          toNextSibling = curToNodeChild.nextSibling;
          curToNodeKey = getNodeKey(curToNodeChild);
          while (!skipFrom && curFromNodeChild) {
            fromNextSibling = curFromNodeChild.nextSibling;
            if (curToNodeChild.isSameNode && curToNodeChild.isSameNode(curFromNodeChild)) {
              curToNodeChild = toNextSibling;
              curFromNodeChild = fromNextSibling;
              continue outer;
            }
            curFromNodeKey = getNodeKey(curFromNodeChild);
            var curFromNodeType = curFromNodeChild.nodeType;
            var isCompatible = void 0;
            if (curFromNodeType === curToNodeChild.nodeType) {
              if (curFromNodeType === ELEMENT_NODE) {
                if (curToNodeKey) {
                  if (curToNodeKey !== curFromNodeKey) {
                    if (matchingFromEl = fromNodesLookup[curToNodeKey]) {
                      if (fromNextSibling === matchingFromEl) {
                        isCompatible = false;
                      } else {
                        fromEl.insertBefore(matchingFromEl, curFromNodeChild);
                        if (curFromNodeKey) {
                          addKeyedRemoval(curFromNodeKey);
                        } else {
                          removeNode(
                            curFromNodeChild,
                            fromEl,
                            true
                            /* skip keyed nodes */
                          );
                        }
                        curFromNodeChild = matchingFromEl;
                        curFromNodeKey = getNodeKey(curFromNodeChild);
                      }
                    } else {
                      isCompatible = false;
                    }
                  }
                } else if (curFromNodeKey) {
                  isCompatible = false;
                }
                isCompatible = isCompatible !== false && compareNodeNames(curFromNodeChild, curToNodeChild);
                if (isCompatible) {
                  morphEl(curFromNodeChild, curToNodeChild);
                }
              } else if (curFromNodeType === TEXT_NODE || curFromNodeType == COMMENT_NODE) {
                isCompatible = true;
                if (curFromNodeChild.nodeValue !== curToNodeChild.nodeValue) {
                  curFromNodeChild.nodeValue = curToNodeChild.nodeValue;
                }
              }
            }
            if (isCompatible) {
              curToNodeChild = toNextSibling;
              curFromNodeChild = fromNextSibling;
              continue outer;
            }
            if (curFromNodeKey) {
              addKeyedRemoval(curFromNodeKey);
            } else {
              removeNode(
                curFromNodeChild,
                fromEl,
                true
                /* skip keyed nodes */
              );
            }
            curFromNodeChild = fromNextSibling;
          }
          if (curToNodeKey && (matchingFromEl = fromNodesLookup[curToNodeKey]) && compareNodeNames(matchingFromEl, curToNodeChild)) {
            if (!skipFrom) {
              addChild(fromEl, matchingFromEl);
            }
            morphEl(matchingFromEl, curToNodeChild);
          } else {
            var onBeforeNodeAddedResult = onBeforeNodeAdded(curToNodeChild);
            if (onBeforeNodeAddedResult !== false) {
              if (onBeforeNodeAddedResult) {
                curToNodeChild = onBeforeNodeAddedResult;
              }
              if (curToNodeChild.actualize) {
                curToNodeChild = curToNodeChild.actualize(fromEl.ownerDocument || doc);
              }
              addChild(fromEl, curToNodeChild);
              handleNodeAdded(curToNodeChild);
            }
          }
          curToNodeChild = toNextSibling;
          curFromNodeChild = fromNextSibling;
        }
        cleanupFromEl(fromEl, curFromNodeChild, curFromNodeKey);
        var specialElHandler = specialElHandlers[fromEl.nodeName];
        if (specialElHandler) {
          specialElHandler(fromEl, toEl);
        }
      }
      var morphedNode = fromNode;
      var morphedNodeType = morphedNode.nodeType;
      var toNodeType = toNode.nodeType;
      if (!childrenOnly) {
        if (morphedNodeType === ELEMENT_NODE) {
          if (toNodeType === ELEMENT_NODE) {
            if (!compareNodeNames(fromNode, toNode)) {
              onNodeDiscarded(fromNode);
              morphedNode = moveChildren(fromNode, createElementNS(toNode.nodeName, toNode.namespaceURI));
            }
          } else {
            morphedNode = toNode;
          }
        } else if (morphedNodeType === TEXT_NODE || morphedNodeType === COMMENT_NODE) {
          if (toNodeType === morphedNodeType) {
            if (morphedNode.nodeValue !== toNode.nodeValue) {
              morphedNode.nodeValue = toNode.nodeValue;
            }
            return morphedNode;
          } else {
            morphedNode = toNode;
          }
        }
      }
      if (morphedNode === toNode) {
        onNodeDiscarded(fromNode);
      } else {
        if (toNode.isSameNode && toNode.isSameNode(morphedNode)) {
          return;
        }
        morphEl(morphedNode, toNode, childrenOnly);
        if (keyedRemovalList) {
          for (var i = 0, len = keyedRemovalList.length; i < len; i++) {
            var elToRemove = fromNodesLookup[keyedRemovalList[i]];
            if (elToRemove) {
              removeNode(elToRemove, elToRemove.parentNode, false);
            }
          }
        }
      }
      if (!childrenOnly && morphedNode !== fromNode && fromNode.parentNode) {
        if (morphedNode.actualize) {
          morphedNode = morphedNode.actualize(fromNode.ownerDocument || doc);
        }
        fromNode.parentNode.replaceChild(morphedNode, fromNode);
      }
      return morphedNode;
    };
  }
  var morphdom = morphdomFactory(morphAttrs);
  var morphdom_esm_default = morphdom;

  // src/reload.js
  function fnv1a(text) {
    let hash = 2166136261;
    for (let i = 0; i < text.length; i += 1) {
      hash ^= text.charCodeAt(i);
      hash = Math.imul(hash, 16777619) >>> 0;
    }
    return hash.toString(16);
  }
  function prepareArticle(article, { emoji = null } = {}) {
    const outline = addHeadingAnchors(article);
    transformAlerts(article);
    markTaskLists(article);
    if (emoji) replaceEmoji(article, emoji);
    convertSpecialBlocks(article);
    for (const child of article.children) child.dataset.cmarksSrc = fnv1a(child.outerHTML);
    return outline;
  }
  function morphArticle(root2, next) {
    const changed = /* @__PURE__ */ new Set();
    morphdom_esm_default(root2, next, {
      childrenOnly: true,
      onBeforeElUpdated(from, to) {
        if (from.parentNode === root2) {
          if (from.dataset.cmarksSrc && from.dataset.cmarksSrc === to.dataset.cmarksSrc) return false;
          changed.add(from);
        }
        return true;
      },
      onNodeAdded(node) {
        if (node.parentNode === root2 && node.nodeType === 1) changed.add(node);
        return node;
      }
    });
    return [...changed];
  }
  function viewportAnchor(root2) {
    for (const heading of root2.querySelectorAll("h1, h2, h3, h4, h5, h6")) {
      const rect = heading.getBoundingClientRect();
      if (rect.bottom > 0) return { id: heading.id, top: rect.top };
    }
    for (const block of root2.children) {
      const rect = block.getBoundingClientRect();
      if (rect.bottom > 0) return { src: block.dataset.cmarksSrc, top: rect.top };
    }
    return null;
  }
  function restoreAnchor(root2, anchor, scrollBy2 = window.scrollBy.bind(window)) {
    if (!anchor) return false;
    let el = null;
    if (anchor.id) el = root2.ownerDocument.getElementById(anchor.id);
    else if (anchor.src) el = [...root2.children].find((b) => b.dataset.cmarksSrc === anchor.src) ?? null;
    if (!el) return false;
    const delta = el.getBoundingClientRect().top - anchor.top;
    if (Math.abs(delta) > 1) scrollBy2(0, delta);
    return true;
  }

  // src/find.js
  var HIGHLIGHT_ALL = "cmarks-find";
  var HIGHLIGHT_CURRENT = "cmarks-find-current";
  var SKIP = /* @__PURE__ */ new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEXTAREA"]);
  function collectText(root2) {
    const doc2 = root2.ownerDocument;
    const walker = doc2.createTreeWalker(root2, 4, {
      acceptNode(node) {
        for (let el = node.parentElement; el && el !== root2; el = el.parentElement) {
          if (SKIP.has(el.tagName)) return 2;
          if (el.tagName === "DETAILS" && !el.open && !node.parentElement.closest("summary")) return 2;
        }
        return 1;
      }
    });
    const nodes = [];
    let text = "";
    while (walker.nextNode()) {
      const node = walker.currentNode;
      nodes.push({ node, start: text.length, end: text.length + node.nodeValue.length });
      text += node.nodeValue;
    }
    return { text, nodes };
  }
  function locate(nodes, offset) {
    let lo = 0;
    let hi = nodes.length - 1;
    while (lo < hi) {
      const mid = lo + hi >> 1;
      if (nodes[mid].end <= offset) lo = mid + 1;
      else hi = mid;
    }
    return nodes[lo];
  }
  function makeRange(doc2, nodes, start, end) {
    const from = locate(nodes, start);
    const to = locate(nodes, Math.max(start, end - 1));
    const range2 = doc2.createRange();
    range2.setStart(from.node, start - from.start);
    range2.setEnd(to.node, end - to.start);
    return range2;
  }
  var Finder = class {
    constructor(root2) {
      this.root = root2;
      this.ranges = [];
      this.index = -1;
      this.query = "";
      this.options = {};
      const highlights = globalThis.CSS?.highlights;
      if (highlights && typeof globalThis.Highlight === "function") {
        this.all = new Highlight();
        this.current = new Highlight();
        this.current.priority = 1;
        highlights.set(HIGHLIGHT_ALL, this.all);
        highlights.set(HIGHLIGHT_CURRENT, this.current);
      }
    }
    search(query, options = {}) {
      this.clear(true);
      this.query = query;
      this.options = options;
      if (!query) return this.result();
      const { text, nodes } = collectText(this.root);
      let haystack = options.caseSensitive ? text : text.toLowerCase();
      let needle = options.caseSensitive ? query : query.toLowerCase();
      if (haystack.length !== text.length) {
        haystack = text;
        needle = query;
      }
      const doc2 = this.root.ownerDocument;
      let from = 0;
      while (needle && (from = haystack.indexOf(needle, from)) !== -1) {
        this.ranges.push(makeRange(doc2, nodes, from, from + needle.length));
        from += needle.length;
      }
      this.index = this.ranges.length ? this.firstVisibleIndex() : -1;
      this.apply();
      this.reveal();
      return this.result();
    }
    next() {
      return this.step(1);
    }
    prev() {
      return this.step(-1);
    }
    step(delta) {
      if (!this.ranges.length) return this.result();
      this.index = (this.index + delta + this.ranges.length) % this.ranges.length;
      this.apply();
      this.reveal();
      return this.result();
    }
    clear(reset = true) {
      this.all?.clear();
      this.current?.clear();
      if (reset) {
        this.ranges = [];
        this.index = -1;
        this.query = "";
      }
    }
    result() {
      return { count: this.ranges.length, index: this.index };
    }
    firstVisibleIndex() {
      if (typeof this.ranges[0]?.getBoundingClientRect !== "function") return 0;
      const i = this.ranges.findIndex((r) => r.getBoundingClientRect().bottom >= 0);
      return i === -1 ? 0 : i;
    }
    apply() {
      if (!this.all) return;
      this.all.clear();
      for (const range2 of this.ranges) this.all.add(range2);
      this.current.clear();
      if (this.index >= 0) this.current.add(this.ranges[this.index]);
    }
    reveal() {
      const range2 = this.ranges[this.index];
      if (!range2 || typeof range2.getBoundingClientRect !== "function" || typeof globalThis.innerHeight !== "number") return;
      const rect = range2.getBoundingClientRect();
      if (rect.top < 0 || rect.bottom > innerHeight) {
        scrollBy({ top: rect.top - innerHeight / 3, behavior: "instant" });
      }
    }
  };

  // src/app.js
  var bridge = window.webkit?.messageHandlers?.cmarks;
  var post = (message) => {
    try {
      bridge?.postMessage(message);
    } catch {
    }
  };
  var config = (() => {
    try {
      return JSON.parse(document.documentElement.dataset.config || "{}");
    } catch {
      return {};
    }
  })();
  var root = document.getElementById("doc");
  var finder = new Finder(root);
  var SHORTCODE_PRESENT = /:[a-z0-9_+-]+:/i;
  async function emojiTableFor(article) {
    if (config.emoji === false || !SHORTCODE_PRESENT.test(article.textContent)) return null;
    return ensureEmoji();
  }
  async function enhance(reason) {
    const t0 = performance.now();
    const jobs = [highlightCode(root, { enabled: config.highlight !== false })];
    if (config.math !== false) jobs.push(renderMath(root).catch((e) => post({ type: "error", where: "math", message: String(e) })));
    if (config.mermaid !== false) jobs.push(renderMermaid(root).catch((e) => post({ type: "error", where: "mermaid", message: String(e) })));
    await Promise.all(jobs);
    post({ type: "enhanced", reason, ms: performance.now() - t0 });
  }
  root.addEventListener("click", (event) => {
    const anchor = event.target.closest("a[href]");
    if (!anchor || !(event.metaKey || event.altKey)) return;
    if (anchor.getAttribute("href")?.startsWith("#")) return;
    event.preventDefault();
    event.stopPropagation();
    post({ type: "link", href: anchor.href, newTab: event.metaKey && !event.altKey, newSplit: event.altKey });
  }, true);
  function wireBanner() {
    root.querySelector("#cmarks-load-full")?.addEventListener("click", () => post({ type: "loadFull" }), { once: true });
  }
  async function initialLoad() {
    const t0 = performance.now();
    wireBanner();
    const outline = prepareArticle(root, { emoji: await emojiTableFor(root) });
    post({ type: "outline", items: outline });
    post({ type: "ready", reason: "load", ms: performance.now() - t0, ...collectStats(root) });
    scrollToFragment();
    await enhance("load");
  }
  async function morph(html) {
    const t0 = performance.now();
    const anchor = viewportAnchor(root);
    const next = document.createElement("article");
    next.className = root.className;
    next.innerHTML = html;
    const outline = prepareArticle(next, { emoji: await emojiTableFor(next) });
    const changed = morphArticle(root, next);
    wireBanner();
    post({ type: "outline", items: outline });
    post({ type: "ready", reason: "reload", ms: performance.now() - t0, changedBlocks: changed.length, ...collectStats(root) });
    await enhance("reload");
    restoreAnchor(root, anchor);
    if (finder.query) finder.search(finder.query, finder.options);
    return { changedBlocks: changed.length };
  }
  function scrollToFragment() {
    const id = decodeURIComponent(location.hash.slice(1));
    if (!id) return;
    document.getElementById(id)?.scrollIntoView({ block: "start" });
  }
  function scrollInfo() {
    const max = Math.max(1, document.documentElement.scrollHeight - innerHeight);
    return { y: scrollY, ratio: Math.min(1, scrollY / max), heading: activeHeadingID() };
  }
  function activeHeadingID() {
    let active = null;
    for (const heading of root.querySelectorAll("h1, h2, h3, h4, h5, h6")) {
      if (heading.getBoundingClientRect().top <= 8) active = heading.id;
      else break;
    }
    return active;
  }
  var suppressScrollUntil = 0;
  window.cmarks = {
    config,
    post,
    morph,
    scrollTo({ y }) {
      suppressScrollUntil = performance.now() + 400;
      window.scrollTo(0, y);
    },
    scrollToAnchor(id) {
      suppressScrollUntil = performance.now() + 400;
      document.getElementById(id)?.scrollIntoView({ block: "start" });
    },
    getScroll: scrollInfo,
    /** 설정 변경 즉시 반영. 본문 폭은 다시 렌더하지 않고 스타일만 바꾼다. */
    setConfig(next) {
      Object.assign(config, next);
      if ("contentMaxWidth" in next) {
        root.style.maxWidth = next.contentMaxWidth ? `${next.contentMaxWidth}px` : "none";
      }
    },
    find: {
      search: (query, options) => finder.search(query, options),
      next: () => finder.next(),
      prev: () => finder.prev(),
      clear: () => finder.clear()
    }
  };
  var scrollTimer = 0;
  addEventListener("scroll", () => {
    if (performance.now() < suppressScrollUntil) return;
    clearTimeout(scrollTimer);
    scrollTimer = setTimeout(() => post({ type: "scroll", ...scrollInfo() }), 150);
  }, { passive: true });
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
    if (config.mermaid !== false) renderMermaid(root, { rerender: true }).catch(() => {
    });
  });
  initialLoad();
})();
