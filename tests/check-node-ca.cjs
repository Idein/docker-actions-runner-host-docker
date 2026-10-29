// Run using the runner's embedded Node, not a separately installed setup-node.
const assert = require("node:assert/strict");
const { createHash, X509Certificate } = require("node:crypto");
const fs = require("node:fs");
const tls = require("node:tls");

const [major, minor, patch] = process.versions.node.split(".").map(Number);
assert.ok(major === 24 && (minor > 22 || (minor === 22 && patch >= 1)),
  `runner Node must be >=24.22.1 within Node 24: ${process.version}`);
const forbidden = new Set([
  "8d417db2dd8bf5e3084d1e3f196d583849d81bdd4c00c70b9d39369e96b8c782",
  "bd153ed7b0434f6886b17bce8bbe84ed340c7132d702a8f4fa318f756ecbd6f3"
]);
// The runner itself (.NET), git, curl and docker use the OS bundle, not Node's store.
const osBundle = "/etc/ssl/certs/ca-certificates.crt";
const stores = {
  "Node default": tls.getCACertificates("default"),
  [osBundle]: fs.readFileSync(osBundle, "utf8").match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) ?? [],
};
for (const [name, pems] of Object.entries(stores)) {
  const roots = pems.map((pem) => new X509Certificate(pem));
  assert.ok(roots.some((cert) => cert.subject.includes("CN=Amazon Root CA 1")),
    `${name} retains Amazon Root CA 1`);
  for (const cert of roots) {
    const key = cert.publicKey.export({ type: "spki", format: "der" });
    const hash = createHash("sha256").update(key).digest("hex");
    assert.ok(!forbidden.has(hash), `${name}: distrusted root key: ${cert.subject}`);
  }
  console.log(`${name}: ${roots.length} CAs; affected root keys absent`);
}
console.log(`${process.execPath}: ${process.version}`);
