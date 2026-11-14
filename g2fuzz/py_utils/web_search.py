"""ALFRED: free web sources for the web stall mutator. No keys, no paid services:
- wikipedia:     MediaWiki search, then the plain text and outside links of new articles
- nvd:           NVD's CVE API (keyword search): vulnerability descriptions and their reference links
- stackexchange: Stack Overflow questions (search/advanced, with bodies)
- github:        GitHub issue search (titles and bodies)
- links:         pages linked from documents already read (the ledger's frontier), fetched only where the site's
                 robots.txt allows it
Each source returns Doc objects whose text is already there, except Wikipedia's search hits (article() fetches the
text of new ones). Rate limits raise Cooling(source, secs); other failures raise WebError. Requests to one host
are at least HOST_GAP seconds apart.

Every request also takes a turn from web_limit (shared by all campaigns on Tempest when G2F_WEB_LIMIT_DIR is set): a
turn too far away raises Cooling instead of sending, and every rate-limit answer is shared, so all of Tempest keeps
to each API's published limits (web_limit.INTERVALS).

G2F_WEB_TEST_BASE (tests only, e.g. http://127.0.0.1:8080) sends every request to that server instead, keeping
the path and query, so tests run without the internet.
"""
import gzip
import html
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser
import zlib
from html.parser import HTMLParser

try:
    from py_utils import web_limit
except ImportError:   # imported from inside py_utils
    import web_limit

UA = "alfred-g2fuzz/1.0 (university fuzzing research)"
UA_TOKEN = "alfred-g2fuzz"
TIMEOUT = 15
MAX_BYTES = 2000000
HOST_GAP = 1.0
SOURCES = ("wikipedia", "nvd", "stackexchange", "github", "links")
API = {
    "wikipedia": "https://en.wikipedia.org/w/api.php",
    "nvd": "https://services.nvd.nist.gov/rest/json/cves/2.0",
    "stackexchange": "https://api.stackexchange.com/2.3/search/advanced",
    "github": "https://api.github.com/search/issues",
}
# what the links source skips: other sources' sites, and files that aren't text
SKIP_HOSTS = ("wikipedia.org", "wikimedia.org", "wikidata.org", "nvd.nist.gov", "stackoverflow.com",
              "stackexchange.com", "github.com", "twitter.com", "x.com", "facebook.com", "youtube.com",
              "linkedin.com", "reddit.com", "web.archive.org")
SKIP_EXT = (".pdf", ".zip", ".gz", ".tgz", ".xz", ".bz2", ".7z", ".rar", ".exe", ".dmg", ".iso", ".png", ".jpg",
            ".jpeg", ".gif", ".bmp", ".tif", ".tiff", ".svg", ".ico", ".mp3", ".mp4", ".ogg", ".wav", ".avi",
            ".mov", ".ttf", ".otf", ".woff", ".woff2", ".pcap", ".icc", ".ps", ".doc", ".docx", ".ppt", ".xls")


class WebError(Exception):
    pass


class Cooling(Exception):
    def __init__(self, source, secs, why):
        super().__init__("%s: %s (cooling %d s)" % (source, why, secs))
        self.source, self.secs = source, secs


class Doc:
    def __init__(self, url, title, source, text="", links=()):
        self.url, self.title, self.source, self.text, self.links = url, title, source, text, list(links)

    def __repr__(self):
        return "Doc(%r, %r, %d chars)" % (self.source, self.url, len(self.text))


_last = {}       # host -> time of the last request
_robots = {}     # scheme://host -> RobotFileParser (or None: fetch failed, treat as allowed)


def _route(url):
    base = os.environ.get("G2F_WEB_TEST_BASE")
    if not base:
        return url
    p = urllib.parse.urlsplit(url)
    b = urllib.parse.urlsplit(base)
    return urllib.parse.urlunsplit((b.scheme, b.netloc, p.path, p.query, ""))


def http_get(url, accept="*/*"):
    """GET url -> (status, headers, body bytes). Follows redirects; body cut at MAX_BYTES; gzip undone.
    Takes a shared turn first (web_limit): raises Cooling if it's too far away."""
    key = web_limit.key_for(url)   # the real host, before a test's routing
    if web_limit.take(key) is None:
        raise Cooling(web_limit.source_of(key), max(30, int(web_limit.wait_left(key))),
                      "shared limit (all campaigns on Tempest)")
    url = _route(url)
    host = urllib.parse.urlsplit(url).netloc
    gap = 0 if os.environ.get("G2F_WEB_TEST_BASE") else HOST_GAP
    wait = gap - (time.time() - _last.get(host, 0))
    if wait > 0:
        time.sleep(wait)
    _last[host] = time.time()
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": accept, "Accept-Encoding": "gzip"})
    try:
        resp = urllib.request.urlopen(req, timeout=TIMEOUT)
        status, headers = resp.status, resp.headers
    except urllib.error.HTTPError as e:
        resp, status, headers = e, e.code, e.headers
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise WebError("%s: %s" % (url, e))
    try:
        body = resp.read(MAX_BYTES + 1)[:MAX_BYTES]
    except OSError as e:
        raise WebError("%s: %s" % (url, e))
    finally:
        resp.close()
    if (headers.get("Content-Encoding") or "").lower() == "gzip":
        try:
            body = gzip.decompress(body)
        except (OSError, EOFError, zlib.error):
            body = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(body)   # cut at MAX_BYTES: what there is
    return status, headers, body


def get_json(url, source):
    status, headers, body = http_get(url, "application/json")
    if status in (403, 429, 503):
        reset = headers.get("X-RateLimit-Reset") or headers.get("Retry-After")
        secs = 60
        if reset and reset.isdigit():
            secs = max(30, int(reset) - int(time.time())) if int(reset) > 10 ** 9 else max(30, int(reset))
        secs = min(secs, 3600)
        web_limit.cool(source if source in web_limit.INTERVALS else web_limit.key_for(url), secs)   # for all
        raise Cooling(source, secs, "HTTP %d" % status)
    if status != 200:
        raise WebError("%s: HTTP %d" % (source, status))
    try:
        return json.loads(body.decode("utf-8", "replace"))
    except ValueError as e:
        raise WebError("%s: bad JSON (%s)" % (source, e))


# --- HTML to text ---------------------------------------------------------------------------------------------
class _Text(HTMLParser):
    SKIP = {"script", "style", "noscript", "nav", "header", "footer", "svg", "form", "button", "select"}
    BLOCK = {"p", "div", "li", "ul", "ol", "br", "tr", "table", "section", "article", "pre", "blockquote", "dd",
             "dt", "dl", "h1", "h2", "h3", "h4", "h5", "h6", "caption", "figcaption", "td", "th"}

    def __init__(self, base):
        super().__init__(convert_charrefs=True)
        self.base, self.out, self.skip, self.links, self.title = base, [], 0, [], ""
        self._a = None
        self._in_title = False

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skip += 1
        elif tag in self.BLOCK:
            self.out.append("\n")
        if tag == "title":
            self._in_title = True
        if tag == "a":
            href = dict(attrs).get("href")
            if href and not href.startswith(("#", "javascript:", "mailto:")):
                self._a = [urllib.parse.urljoin(self.base, href), ""]

    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skip:
            self.skip -= 1
        elif tag in self.BLOCK:
            self.out.append("\n")
        if tag == "title":
            self._in_title = False
        if tag == "a" and self._a:
            self.links.append((self._a[0], self._a[1].strip()))
            self._a = None

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        if self.skip:
            return
        self.out.append(data)
        if self._a is not None:
            self._a[1] += data


def html_to_text(markup, base=""):
    """-> (text, title, links [(url, anchor text)]). Script, style and navigation dropped; one line per block."""
    p = _Text(base)
    try:
        p.feed(markup)
        p.close()
    except Exception:   # broken markup: keep what was read
        pass
    lines = (re.sub(r"[ \t\r\f\v]+", " ", line).strip() for line in "".join(p.out).split("\n"))
    text = "\n".join(line for line in lines if line)
    return text, html.unescape(p.title.strip()), p.links


# --- the sources ----------------------------------------------------------------------------------------------
def _q(params):
    return urllib.parse.urlencode(params, quote_via=urllib.parse.quote)


def search_wikipedia(query, n=5):
    data = get_json(API["wikipedia"] + "?" + _q({"action": "query", "list": "search", "srsearch": query,
                                                  "srlimit": n, "format": "json", "formatversion": 2}),
                    "wikipedia")
    hits = (data.get("query") or {}).get("search") or []
    return [Doc("https://en.wikipedia.org/wiki/" + urllib.parse.quote(h["title"].replace(" ", "_")), h["title"],
                "wikipedia") for h in hits if h.get("title")]


def wikipedia_article(doc):
    """Fills doc.text and doc.links (outside links) from the article's plain text."""
    title = urllib.parse.unquote(doc.url.rsplit("/wiki/", 1)[-1]).replace("_", " ")
    data = get_json(API["wikipedia"] + "?" + _q({"action": "query", "prop": "extracts|extlinks", "explaintext": 1,
                                                  "exsectionformat": "wiki", "ellimit": 100, "redirects": 1,
                                                  "titles": title, "format": "json", "formatversion": 2}),
                    "wikipedia")
    pages = (data.get("query") or {}).get("pages") or []
    if pages:
        doc.text = pages[0].get("extract") or ""
        doc.links = [(l.get("url") or l.get("*") or "", "") for l in pages[0].get("extlinks") or []]
        doc.links = [(u if not u.startswith("//") else "https:" + u, a) for u, a in doc.links if u]
    return doc


def search_nvd(query, n=5):
    data = get_json(API["nvd"] + "?" + _q({"keywordSearch": query, "resultsPerPage": n}), "nvd")
    docs = []
    for v in data.get("vulnerabilities") or []:
        cve = v.get("cve") or {}
        desc = next((d.get("value", "") for d in cve.get("descriptions") or [] if d.get("lang") == "en"), "")
        if cve.get("id") and desc:
            links = [(r.get("url", ""), "") for r in cve.get("references") or [] if r.get("url")]
            docs.append(Doc("https://nvd.nist.gov/vuln/detail/" + cve["id"], cve["id"], "nvd",
                            cve["id"] + ": " + desc, links))
    return docs


def search_stackexchange(query, n=5):
    data = get_json(API["stackexchange"] + "?" + _q({"order": "desc", "sort": "relevance", "q": query,
                                                      "site": "stackoverflow", "pagesize": n,
                                                      "filter": "withbody"}), "stackexchange")
    if data.get("error_id"):
        web_limit.cool("stackexchange", 3600)
        raise Cooling("stackexchange", 3600, data.get("error_name", "error"))
    docs = []
    for it in data.get("items") or []:
        text, _, links = html_to_text(it.get("body", ""), it.get("link", ""))
        title = html.unescape(it.get("title", ""))
        docs.append(Doc(it.get("link", ""), title, "stackexchange", title + "\n" + text, links))
    # the API asks clients to wait (backoff) and allows 300 requests a day per address without a key
    if data.get("backoff") or (data.get("quota_remaining") is not None and data["quota_remaining"] < 5):
        cool = Cooling("stackexchange", 3600 if (data.get("quota_remaining") or 0) < 5 else int(data["backoff"]),
                       "backoff/quota")
        web_limit.cool("stackexchange", cool.secs)
        cool.docs = [d for d in docs if d.url]
        raise cool
    return [d for d in docs if d.url]


def search_github(query, n=5):
    data = get_json(API["github"] + "?" + _q({"q": query + " in:title,body", "per_page": n}), "github")
    docs = []
    for it in data.get("items") or []:
        body = it.get("body") or ""
        links = [(u, "") for u in re.findall(r"https?://[^\s)>\]\"']+", body)]
        docs.append(Doc(it.get("html_url", ""), it.get("title", ""), "github",
                        (it.get("title", "") + "\n" + body)[:20000], links))
    return [d for d in docs if d.url]


SEARCH = {"wikipedia": search_wikipedia, "nvd": search_nvd, "stackexchange": search_stackexchange,
          "github": search_github}


def search(source, query, n=5):
    return SEARCH[source](query, n)


# --- plain pages (the links source) ---------------------------------------------------------------------------
def allowed(url):
    """robots.txt says this client may fetch url (no robots.txt, or a 404: yes; 401/403 or a server error: no)."""
    p = urllib.parse.urlsplit(url)
    root = "%s://%s" % (p.scheme, p.netloc)
    if root not in _robots:
        rp = urllib.robotparser.RobotFileParser()
        try:
            status, _, body = http_get(root + "/robots.txt", "text/plain")
        except WebError:
            status, body = 404, b""
        if status in (401, 403) or status >= 500:   # 5xx: try again in a later step
            rp.disallow_all = True
        elif status >= 400:
            rp.allow_all = True
        else:
            rp.parse(body.decode("utf-8", "replace").splitlines())
        _robots[root] = rp
    return _robots[root].can_fetch(UA_TOKEN, url)


def fetchable(url):
    p = urllib.parse.urlsplit(url)
    host = p.netloc.lower()
    return (p.scheme in ("http", "https") and host and not any(host == h or host.endswith("." + h) for h in SKIP_HOSTS)
            and not p.path.lower().endswith(SKIP_EXT))


def fetch_page(url):
    """A web page as a Doc (html or plain text only), or None: robots.txt says no, or it isn't text."""
    if not fetchable(url) or not allowed(url):
        return None
    status, headers, body = http_get(url, "text/html,text/plain;q=0.9")
    ctype = (headers.get("Content-Type") or "").lower()
    if status != 200 or not (ctype.startswith("text/html") or ctype.startswith("text/plain")
                             or ctype.startswith("application/xhtml")):
        return None
    charset = re.search(r"charset=([\w-]+)", ctype)
    raw = body.decode(charset.group(1) if charset else "utf-8", "replace")
    if ctype.startswith("text/plain"):
        return Doc(url, url.rsplit("/", 1)[-1], "links", raw)
    text, title, links = html_to_text(raw, url)
    return Doc(url, title or url, "links", text, links)
