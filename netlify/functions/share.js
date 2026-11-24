// Makes a Facebook-friendly preview page for one product: /p/<product id>
// People are sent straight on to the real product page. Uses only the public anon key.
const SUPABASE_URL = "https://rdxpzlkidihnxkodovro.supabase.co";
const ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJkeHB6bGtpZGlobnhrb2RvdnJvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM1NzMyOTMsImV4cCI6MjEwOTE0OTI5M30.8i1N_oxhW7LK2NBA47usV9m6ibZ0FygMonb9Zn9Gb4k";
const BUCKET = "shop-images";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const peso = n => { n = Number(n) || 0; const whole = Math.abs(n - Math.round(n)) < 0.005; return "\u20B1" + n.toLocaleString("en-PH", { minimumFractionDigits: whole ? 0 : 2, maximumFractionDigits: 2 }); };
const pub = path => SUPABASE_URL + "/storage/v1/object/public/" + BUCKET + "/" + String(path).split("/").map(encodeURIComponent).join("/");
const rest = async q => {
  const r = await fetch(SUPABASE_URL + "/rest/v1/" + q, { headers: { apikey: ANON_KEY, Authorization: "Bearer " + ANON_KEY } });
  if (!r.ok) throw new Error("rest " + r.status);
  return r.json();
};

exports.handler = async event => {
  const q = event.queryStringParameters || {};
  const id = String(q.id || "");
  const v = String(q.v || "").replace(/[^a-z0-9]/gi, "").slice(0, 16);
  const host = (event.headers && (event.headers["x-forwarded-host"] || event.headers.host)) || "";
  const origin = host ? "https://" + host : "";
  const home = origin + "/#shop";
  let p = null, shop = "Ayapana Online Shop";
  try {
    if (UUID.test(id)) {
      const rows = await rest("products?id=eq." + id + "&active=eq.true&select=name,price,description,category,images,image_path,updated_at&limit=1");
      p = rows[0] || null;
      const st = await rest("settings?id=eq.1&select=shop_name&limit=1").catch(() => []);
      if (st[0] && st[0].shop_name) shop = st[0].shop_name;
    }
  } catch (e) { p = null; }

  const target = p ? origin + "/#product/" + id : home;
  let title = shop, desc = "Bags, wallets and more.", image = "", imgMeta = "";
  if (p) {
    title = p.name + " - " + peso(p.price);
    desc = (p.description || "").replace(/\s+/g, " ").trim().slice(0, 200) || (p.category ? p.category + " at " + shop : "Available at " + shop);
    const first = (p.images && p.images[0]) || p.image_path;
    const ver = v || String(Date.parse(p.updated_at) || "");
    try {
      const head = await fetch(pub("share/" + id + ".jpg"), { method: "HEAD" });
      if (head.ok) { image = pub("share/" + id + ".jpg") + "?v=" + ver; imgMeta = '<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">'; }
    } catch (e) {}
    if (!image && first) image = pub(first) + "?v=" + ver;
  }
  const url = p ? origin + "/p/" + id : origin + "/";
  const html = '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
    "<title>" + esc(title) + "</title>" +
    '<meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<meta name="description" content="' + esc(desc) + '">' +
    '<meta property="og:type" content="' + (p ? "product" : "website") + '">' +
    '<meta property="og:site_name" content="' + esc(shop) + '">' +
    '<meta property="og:title" content="' + esc(title) + '">' +
    '<meta property="og:description" content="' + esc(desc) + '">' +
    '<meta property="og:url" content="' + esc(url) + '">' +
    (image ? '<meta property="og:image" content="' + esc(image) + '">' + imgMeta + '<meta name="twitter:card" content="summary_large_image">' : "") +
    '<meta http-equiv="refresh" content="0;url=' + esc(target) + '">' +
    "</head><body><p><a href=\"" + esc(target) + '">Open ' + esc(p ? p.name : shop) + "</a></p>" +
    "<script>location.replace(" + JSON.stringify(target).replace(/</g, "\\u003c") + ")</script></body></html>";
  return { statusCode: 200, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=300" }, body: html };
};
