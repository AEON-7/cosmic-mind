#!/bin/sh
# Patch Quartz components for branding and better visual behavior:

# Copy branding assets if available
STATIC_SRC="/static-assets"
STATIC_DEST="/app/quartz/quartz/static"
if [ -d "$STATIC_SRC" ]; then
  for f in favicon.ico favicon-16x16.png favicon-32x32.png favicon-48x48.png apple-touch-icon.png icon-192.png icon-512.png logo.png og-image.png og-image-social.png; do
    [ -f "$STATIC_SRC/$f" ] && cp "$STATIC_SRC/$f" "$STATIC_DEST/$f" && echo "[PATCH] Copied $f to static/"
  done
fi

# Patch Quartz graph component for better visual behavior:
# 1. Inverse label scaling on zoom (labels stay readable, don't overlap)
# 2. Increased collision radius (nodes spread out more)
# 3. Tuned layout config (repelForce, linkDistance, fontSize)
#
# Run inside the watcher/builder container after Quartz init.
# These patches apply to quartz-engine volume.

GRAPH_SCRIPT="/app/quartz/quartz/components/scripts/graph.inline.ts"
LAYOUT="/app/quartz/quartz.layout.ts"

if [ ! -f "$GRAPH_SCRIPT" ]; then
  echo "[PATCH] Quartz not initialized yet, skipping"
  exit 0
fi

# Patch 1: Increase collision radius
node -e "
const fs = require('fs');
let c = fs.readFileSync('$GRAPH_SCRIPT', 'utf8');
const old = '.force(\"collide\", forceCollide<NodeData>((n) => nodeRadius(n)).iterations(3))';
const rep = '.force(\"collide\", forceCollide<NodeData>((n) => nodeRadius(n) + 15).iterations(3))';
if (c.includes(old)) { c = c.replace(old, rep); fs.writeFileSync('$GRAPH_SCRIPT', c); console.log('[PATCH] Collision radius increased'); }
else { console.log('[PATCH] Collision already patched or not found'); }
"

# Patch 2: Inverse label scaling on zoom
node -e "
const fs = require('fs');
let c = fs.readFileSync('$GRAPH_SCRIPT', 'utf8');
if (c.includes('labelScale')) { console.log('[PATCH] Label scaling already patched'); process.exit(0); }
const old = \`          // zoom adjusts opacity of labels too
          const scale = transform.k * opacityScale
          let scaleOpacity\`;
const rep = \`          // zoom adjusts opacity of labels too
          const scale = transform.k * opacityScale

          // Scale labels inversely so they stay readable at any zoom level
          const labelScale = (1 / scale) / transform.k
          for (const n of nodeRenderData) {
            n.label.scale.set(labelScale, labelScale)
          }
          let scaleOpacity\`;
if (c.includes(old)) { c = c.replace(old, rep); fs.writeFileSync('$GRAPH_SCRIPT', c); console.log('[PATCH] Label scaling patched'); }
else { console.log('[PATCH] Label scaling target not found'); }
"

# Patch 3: Ensure labels are visible at default zoom (especially on mobile)
# Default formula: (scale - 1) / 3.75 = near-zero at 1x zoom = invisible labels
# Fix: set minimum opacity of 0.6 so titles always show
node -e "
const fs = require('fs');
let c = fs.readFileSync('$GRAPH_SCRIPT', 'utf8');
const old = 'let scaleOpacity = Math.max((scale - 1) / 3.75, 0)';
const rep = 'let scaleOpacity = Math.max((scale - 1) / 3.75, 0.6)';
if (c.includes(old)) { c = c.replace(old, rep); fs.writeFileSync('$GRAPH_SCRIPT', c); console.log('[PATCH] Label opacity minimum set to 0.6'); }
else if (c.includes(rep)) { console.log('[PATCH] Label opacity already patched'); }
else { console.log('[PATCH] Label opacity target not found'); }
"

# Patch 4: Support per-page OG images via frontmatter `image` field
# If a note has `image: path/to/image.png` in frontmatter, use it for og:image
# Otherwise fall back to the default /static/og-image.png
HEAD_TSX="/app/quartz/quartz/components/Head.tsx"
node -e "
const fs = require('fs');
let c = fs.readFileSync('$HEAD_TSX', 'utf8');
if (c.includes('frontmatter?.image')) { console.log('[PATCH] OG image frontmatter already patched'); process.exit(0); }
const old = 'const ogImageDefaultPath = \`https://\${cfg.baseUrl}/static/og-image.png\`';
const rep = [
  '// Use frontmatter image if available, otherwise default OG image',
  'const frontmatterImage = fileData.frontmatter?.image',
  '  ? \`https://\${cfg.baseUrl}/\${fileData.frontmatter.image}\`',
  '  : null',
  'const ogImageDefaultPath = frontmatterImage ?? \`https://\${cfg.baseUrl}/static/og-image.png\`',
].join('\n    ');
if (c.includes(old)) { c = c.replace(old, rep); fs.writeFileSync('$HEAD_TSX', c); console.log('[PATCH] OG image frontmatter support added'); }
else { console.log('[PATCH] OG image target not found in Head.tsx'); }
"

# Patch 5: Enhanced node sizing — hub nodes stand out dramatically
# Default: 2 + sqrt(numLinks) = barely visible difference
# New: 3 + numLinks^0.6 * 1.5 = hubs (10+ links) are 3-4x larger than leaf nodes
node -e "
const fs = require('fs');
let c = fs.readFileSync('$GRAPH_SCRIPT', 'utf8');
const old = \`  function nodeRadius(d: NodeData) {
    const numLinks = graphData.links.filter(
      (l) => l.source.id === d.id || l.target.id === d.id,
    ).length
    return 2 + Math.sqrt(numLinks)
  }\`;
const rep = \`  function nodeRadius(d: NodeData) {
    const numLinks = graphData.links.filter(
      (l) => l.source.id === d.id || l.target.id === d.id,
    ).length
    // Enhanced sizing: leaf=3px, moderate(5 links)=8px, hub(20 links)=15px
    return 3 + Math.pow(numLinks, 0.6) * 1.5
  }\`;
if (c.includes(old)) { c = c.replace(old, rep); fs.writeFileSync('$GRAPH_SCRIPT', c); console.log('[PATCH] Node sizing enhanced'); }
else { console.log('[PATCH] Node sizing target not found (may already be patched)'); }
"

# Patch 6: Link width varies by connection density of endpoints
# Default: all links width:1. New: thicker links between well-connected nodes
node -e "
const fs = require('fs');
let c = fs.readFileSync('$GRAPH_SCRIPT', 'utf8');
if (c.includes('linkWidth')) { console.log('[PATCH] Link width already patched'); process.exit(0); }
const old = '.stroke({ alpha: l.alpha, width: 1, color: l.color })';
const rep = '.stroke({ alpha: l.alpha, width: Math.min(0.6 + Math.pow(Math.min(graphData.links.filter((ll) => ll.source.id === linkData.source.id || ll.target.id === linkData.source.id).length, graphData.links.filter((ll) => ll.source.id === linkData.target.id || ll.target.id === linkData.target.id).length), 0.4) * 0.5, 3), color: l.color })';
if (c.includes(old)) { c = c.replace(old, rep); fs.writeFileSync('$GRAPH_SCRIPT', c); console.log('[PATCH] Link width scaling added'); }
else { console.log('[PATCH] Link width target not found'); }
"

# Patch 7: Tune layout graph config for larger vault (50+ nodes)
# - Local graph: wider spread, bigger fonts for readability
# - Global graph: stronger repulsion to prevent clustering, wider link distance
node -e "
const fs = require('fs');
let c = fs.readFileSync('$LAYOUT', 'utf8');
// Local graph
c = c.replace(/localGraph:\s*\{[^}]+\}/s, \`localGraph: {
        depth: 2,
        scale: 1.2,
        repelForce: 2.5,
        centerForce: 0.4,
        linkDistance: 70,
        fontSize: 0.45,
        opacityScale: 1.5,
        showTags: false,
        focusOnHover: true,
      }\`);
// Global graph
c = c.replace(/globalGraph:\s*\{[^}]+\}/s, \`globalGraph: {
        depth: -1,
        scale: 0.85,
        repelForce: 2,
        centerForce: 0.05,
        linkDistance: 100,
        fontSize: 0.3,
        opacityScale: 1.5,
        showTags: false,
        focusOnHover: true,
        enableRadial: true,
      }\`);
fs.writeFileSync('$LAYOUT', c);
console.log('[PATCH] Layout graph config tuned for larger vault');
"

echo "[PATCH] All patches complete"
