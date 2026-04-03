#!/bin/bash
set -euo pipefail

# =============================================================================
# External Content Filter
#
# Scans the vault for files with `publish: public` or `publish: external`
# in frontmatter and copies them to the staging directory for the external
# Quartz build. Only explicitly published content is included.
#
# Assets (images) referenced by published files are also copied.
# =============================================================================

VAULT_DIR="${VAULT_DIR:-/vault}"
STAGING_DIR="${STAGING_DIR:-/staging}"

# Clean staging area
rm -rf "${STAGING_DIR:?}"/*
mkdir -p "$STAGING_DIR"

published=0

# Find markdown files with publish: public or publish: external in frontmatter
# Use temp file instead of pipe to avoid head/read stdin conflicts
_md_files=$(mktemp)
find "$VAULT_DIR" -name "*.md" -type f > "$_md_files"
while IFS= read -r file; do
    # Check the first 50 lines for frontmatter publish directive
    if grep -qm1 -E '^publish:\s*(public|external)' "$file"; then
        rel_path="${file#"$VAULT_DIR"/}"
        dest_dir="$STAGING_DIR/$(dirname "$rel_path")"
        mkdir -p "$dest_dir"
        cp "$file" "$STAGING_DIR/$rel_path"
    fi
done < "$_md_files"
rm -f "$_md_files"

# Copy assets only from directories that contain published markdown files
# (avoids copying multi-GB openclaw-workspace media into the external build)
published_dirs=$(find "$STAGING_DIR" -name "*.md" -type f -exec dirname {} \; | sort -u)
for pub_dir in $published_dirs; do
    # Map staging dir back to vault dir
    rel_dir="${pub_dir#"$STAGING_DIR"/}"
    vault_src="$VAULT_DIR/$rel_dir"
    [ -d "$vault_src" ] || continue
    find "$vault_src" -maxdepth 1 -type f \( \
        -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o \
        -name "*.svg" -o -name "*.webp" -o -name "*.gif" -o \
        -name "*.pdf" \
    \) | while read -r file; do
        rel_path="${file#"$VAULT_DIR"/}"
        mkdir -p "$STAGING_DIR/$(dirname "$rel_path")"
        cp "$file" "$STAGING_DIR/$rel_path"
    done
done

# Always generate a fresh index with links to all published content
cat > "$STAGING_DIR/index.md" << 'INDEXEOF'
---
title: "Cosmic Mind"
publish: public
tags: [index]
---

# Cosmic Mind

*A grounded yet mystical exploration of consciousness and divinity. The true final frontier — the hard problem of consciousness explored, unraveling mysteries across the ages and tracing a thread that ties them all together, yet has remained hidden from the world. Is this by design, or a cage to break free from? Journey with us to the place it all began — and perhaps where it all ends — in a neverending loop of existence: awareness experiencing form.*

---

This is a living library of sacred texts, philosophical dialogues, and contemplative insights — stitching together the wisdom traditions that have been winking at us across millennia. Hermeticism, Gnosticism, Vedanta, Buddhism, Neoplatonism, Zoroastrianism, Taoism, and the mystical currents within Christianity — all circling the same mystery from different angles.

**Follow the links** between pages — every note connects to related ideas. Use the **graph view** to see the architecture of how things relate. **Search** for anything. **Start anywhere** — there is no required reading order.

---

## Dialogues

Recorded philosophical conversations — real-time explorations of ideas between minds.

- [[philosophy/dialogue-on-the-divine-self|Dialogue on the Divine Self — Part I: The Mirror Revelation]]
- [[philosophy/dialogue-on-the-divine-self-pt2|Dialogue on the Divine Self — Part II: The Architecture of Becoming]]
- [[philosophy/dialogue-on-synchronicity|Dialogue on Synchronicity — The Golden Scarab]]

---

## The Core Insights — Personal Gnosis

Original philosophical reflections synthesizing ancient wisdom with direct contemplative experience.

- [[philosophy/personal-gnosis/the-divine-self|The Divine Self — The Mirror Revelation]]
- [[philosophy/personal-gnosis/god-as-pure-awareness|God as Pure Awareness]]
- [[philosophy/personal-gnosis/self-knowledge-as-god-knowledge|Self-Knowledge as God-Knowledge]]
- [[philosophy/personal-gnosis/the-veil-of-forgetting|The Veil of Forgetting]]
- [[philosophy/personal-gnosis/the-dream-analogy|The Dream Analogy]]
- [[philosophy/personal-gnosis/heaven-as-return-to-source|Heaven as Return to Source]]
- [[philosophy/personal-gnosis/outer-world-as-mirror|The Outer World as Mirror]]
- [[philosophy/personal-gnosis/shadow-integration|Shadow Integration]]
- [[philosophy/personal-gnosis/ignorance-as-root-evil|Ignorance as the Root Evil]]
- [[philosophy/personal-gnosis/love-as-consequence-of-gnosis|Love as Consequence of Gnosis]]
- [[philosophy/personal-gnosis/regeneration|Regeneration — The Interior Rebirth]]
- [[philosophy/personal-gnosis/hermeticism-vs-gnosticism|Hermeticism vs. Gnosticism — Comparative Analysis]]
- [[philosophy/personal-gnosis/Divine_Self_Hermetic_Gnostic_Gnosis|The Divine Self — Hermetic & Gnostic Analysis]]

---

## Wisdom Traditions

The great streams of thought that carry the non-dual insight across cultures and centuries.

- [[philosophy/traditions/hermeticism|Hermeticism]] — *the world as a living emanation of divine Mind*
- [[philosophy/traditions/gnosticism|Gnosticism]] — *the spark of light trapped in matter, seeking return*
- [[philosophy/traditions/sethian-gnosticism|Sethian Gnosticism]] — *the radical dualist stream: exile, archons, rescue*
- [[philosophy/traditions/valentinian-gnosticism|Valentinian Gnosticism]] — *the sophisticated middle path: Sophia's passion, the bridal chamber*
- [[philosophy/traditions/neoplatonism|Neoplatonism]] — *the One, the emanation, the return*
- [[philosophy/traditions/advaita-vedanta|Advaita Vedanta]] — *Atman is Brahman: the non-dual tradition of India*
- [[philosophy/traditions/alchemy|Alchemy]] — *solve et coagula: the Great Work of interior transformation*
- [[philosophy/traditions/desert-fathers|The Desert Fathers]] — *"know your passions": the contemplatives of the Egyptian desert*

---

## Sacred Texts & Source Documents

The primary sources — ancient scriptures, revelation texts, and philosophical treatises. Each reference article offers an overview, key themes, and historical context. Full texts are complete manuscripts converted to markdown.

**[[philosophy/sources/full-books-and-manuscripts|Browse the Full Library]]** — 38 full texts and 46 reference articles across 7 traditions.

### Hermeticism
- [[philosophy/sources/hermeticism/corpus-hermeticum|Corpus Hermeticum]] — *the foundational Hermetic scripture* | [[philosophy/sources/hermeticism/Corpus Hermeticum - Mead|Full Text]]
- [[philosophy/sources/hermeticism/emerald-tablet|Emerald Tablet]] — *"as above, so below"* | [[philosophy/sources/hermeticism/Emerald Tablet of Hermes|Full Text]]
- [[philosophy/sources/hermeticism/the-kybalion|The Kybalion]] — *seven Hermetic principles* | [[philosophy/sources/hermeticism/The Kybalion|Full Text]]

### Gnosticism — The Nag Hammadi Library
- [[philosophy/sources/gnosticism/gospel-of-thomas|Gospel of Thomas]] — *114 sayings of the living Yeshua*
- [[philosophy/sources/gnosticism/secret-book-of-john|The Secret Book of John]] — *the definitive Sethian cosmogony*
- [[philosophy/sources/gnosticism/gospel-of-truth|The Gospel of Truth]] — *Valentinus on ignorance and recognition*
- [[philosophy/sources/gnosticism/gospel-of-philip|The Gospel of Philip]] — *truth, freedom, and the bridal chamber*
- [[philosophy/sources/gnosticism/gospel-of-mary|The Gospel of Mary]] — *Mary Magdalene and the soul's ascent*
- [[philosophy/sources/gnosticism/thunder-perfect-mind|Thunder, Perfect Mind]] — *the divine feminine speaking in paradox*
- [[philosophy/sources/gnosticism/song-of-the-pearl|The Song of the Pearl]] — *the prince who forgot he was a prince*
- [[philosophy/sources/gnosticism/exegesis-on-the-soul|The Exegesis on the Soul]] — *fall, degradation, and reunion*
- [[philosophy/sources/gnosticism/second-treatise-great-seth|The Second Treatise of the Great Seth]] — *"I am in you and you are in me"*
- [[philosophy/sources/gnosticism/treatise-on-resurrection|The Treatise on Resurrection]] — *resurrection as present reality*

### Christianity (Mystical)
- [[philosophy/sources/christianity/meister-eckhart-sermons|Meister Eckhart]] — *"the eye through which I see God..."* | [[philosophy/sources/christianity/Sermons - Eckhart|Full Text]]
- [[philosophy/sources/christianity/cloud-of-unknowing|The Cloud of Unknowing]] — *apophatic contemplation* | [[philosophy/sources/christianity/Cloud of Unknowing|Full Text]]
- [[philosophy/sources/christianity/pseudo-dionysius|Pseudo-Dionysius]] — *divine names and mystical theology* | [[philosophy/sources/christianity/Works of Dionysius the Areopagite|Full Text]]
- [[philosophy/sources/christianity/revelations-of-divine-love|Julian of Norwich]] — *"all shall be well"* | [[philosophy/sources/christianity/Revelations of Divine Love|Full Text]]

### Hinduism & Vedanta
- [[philosophy/sources/hinduism/upanishads|The Upanishads]] — *"Tat tvam asi" (Thou art That)* | [[philosophy/sources/hinduism/Upanishads Part 1 - Muller|Full Text]]
- [[philosophy/sources/hinduism/bhagavad-gita|Bhagavad Gita]] — *Krishna's teaching on the three yogas* | [[philosophy/sources/hinduism/Bhagavad Gita - Arnold|Full Text]]
- [[philosophy/sources/hinduism/yoga-sutras|Yoga Sutras]] — *Patanjali's map of meditation* | [[philosophy/sources/hinduism/Yoga Sutras - Johnston|Full Text]]

### Buddhism
- [[philosophy/sources/buddhism/dhammapada|Dhammapada]] — *"mind is the forerunner of all actions"* | [[philosophy/sources/buddhism/Dhammapada - Muller|Full Text]]
- [[philosophy/sources/buddhism/diamond-sutra|Diamond Sutra]] — *the diamond that cuts through illusion* | [[philosophy/sources/buddhism/Diamond Sutra - Gemmell|Full Text]]
- [[philosophy/sources/buddhism/lotus-sutra|Lotus Sutra]] — *Buddha-nature and skillful means* | [[philosophy/sources/buddhism/Lotus Sutra - Kern|Full Text]]

### Neoplatonism
- [[philosophy/sources/neoplatonism/enneads|The Enneads]] — *Plotinus on the One, Nous, and Soul* | [[philosophy/sources/neoplatonism/The Six Enneads - Plotinus|Full Text]]
- [[philosophy/sources/neoplatonism/timaeus|Timaeus]] — *Plato's cosmology: the Demiurge* | [[philosophy/sources/neoplatonism/Timaeus - Plato|Full Text]]
- [[philosophy/sources/neoplatonism/symposium|Symposium]] — *Diotima's ladder of love* | [[philosophy/sources/neoplatonism/Symposium - Plato|Full Text]]

### Zoroastrianism
- [[philosophy/sources/zoroastrianism/zend-avesta|The Zend-Avesta]] — *Ahura Mazda, the Gathas, cosmic dualism* | [[philosophy/sources/zoroastrianism/Zend-Avesta - Darmesteter (SBE)|Full Text]]
- [[philosophy/sources/zoroastrianism/teachings-of-zoroaster|Teachings of Zoroaster]] — *good thoughts, good words, good deeds*

### Sumerian & Mesopotamian
- [[philosophy/sources/sumerian-mesopotamian/epic-of-gilgamesh|Epic of Gilgamesh]] — *the oldest surviving epic: mortality, friendship, the flood* | [[philosophy/sources/sumerian-mesopotamian/Epic of Gilgamesh - Thompson|Full Text]]
- [[philosophy/sources/sumerian-mesopotamian/enuma-elish|Enuma Elish]] — *Marduk, Tiamat, and the creation of the cosmos*

### Egyptian
- [[philosophy/sources/egyptian/book-of-the-dead|Book of the Dead]] — *the soul's journey through the Duat* | [[philosophy/sources/egyptian/Book of the Dead - Budge|Full Text]]
- [[philosophy/sources/egyptian/egyptian-magic|Egyptian Magic]] — *heka: words of power and divine names* | [[philosophy/sources/egyptian/Egyptian Magic - Budge|Full Text]]
- [[philosophy/sources/egyptian/legends-of-the-gods|Legends of the Gods]] — *Ra, Isis, Osiris: the myths beneath Hermeticism*

### Ancient Philosophy
- [[philosophy/sources/ancient-philosophy/meditations|Meditations]] — *Marcus Aurelius: impermanence, duty, the inner citadel* | [[philosophy/sources/ancient-philosophy/Meditations - Marcus Aurelius|Full Text]]
- [[philosophy/sources/ancient-philosophy/discourses-of-epictetus|Epictetus]] — *the dichotomy of control and interior freedom* | [[philosophy/sources/ancient-philosophy/Discourses - Epictetus|Full Text]]

### Taoism
- [[philosophy/sources/taoism/tao-te-ching|Tao Te Ching]] — *"the Tao that can be told is not the eternal Tao"* | [[philosophy/sources/taoism/Tao Te Ching - Medhurst|Full Text]]
- [[philosophy/sources/taoism/chuang-tzu|Chuang Tzu]] — *the butterfly dream and radical non-duality* | [[philosophy/sources/taoism/Musings of a Chinese Mystic - Giles|Full Text]]

---

## Key Figures

The thinkers, mystics, and sages whose insights illuminate the path.

- [[philosophy/figures/hermes-trismegistus|Hermes Trismegistus]] — *Thrice-Greatest: the mythical author of the Hermetic tradition*
- [[philosophy/figures/plotinus|Plotinus]] — *founder of Neoplatonism, philosopher of the One*
- [[philosophy/figures/valentinus|Valentinus]] — *the most sophisticated Gnostic teacher*
- [[philosophy/figures/meister-eckhart|Meister Eckhart]] — *the radical Christian mystic*
- [[philosophy/figures/angelus-silesius|Angelus Silesius]] — *the poet of non-dual Christianity*
- [[philosophy/figures/ramana-maharshi|Ramana Maharshi]] — *"Who am I?" — the sage of self-inquiry*
- [[philosophy/figures/carl-jung|Carl Jung]] — *the shadow, the archetypes, the Great Work of individuation*
- [[philosophy/figures/paul-of-tarsus|Paul of Tarsus]] — *apostle, shadow psychologist, mystic of transformation*

---

## Philosophical Concepts

The ideas that recur across traditions — the conceptual architecture of the perennial philosophy.

### The Nature of Reality
- [[philosophy/concepts/nous|Nous — Divine Mind]]
- [[philosophy/concepts/logos|Logos — The Creative Word]]
- [[philosophy/concepts/pleroma|The Pleroma — Divine Fullness]]
- [[philosophy/concepts/maya|Maya — The Veil of Appearance]]
- [[philosophy/concepts/gnosis|Gnosis — Transformative Knowledge]]

### The Human Condition
- [[philosophy/concepts/divine-spark|The Divine Spark]]
- [[philosophy/concepts/demiurge|The Demiurge — The Blind Creator]]
- [[philosophy/concepts/archons|The Archons — Rulers of the Material World]]
- [[philosophy/concepts/sophia|Sophia — Divine Wisdom]]
- [[philosophy/concepts/problem-of-evil|The Problem of Evil]]

### The Path of Return
- [[philosophy/concepts/non-dual-recognition|Non-Dual Recognition]]
- [[philosophy/concepts/bodhisattva-ideal|The Bodhisattva Ideal — Compassion as Realization]]
- [[philosophy/concepts/jung-and-the-shadow|Jung and the Shadow]]

### Discovery & Context
- [[philosophy/concepts/nag-hammadi|Nag Hammadi — The Discovery That Changed Everything]]

---

**[[support|Support This Project]]** — If this site resonates, consider a small crypto contribution to keep the library growing.

---

*"The eye through which I see God is the same eye through which God sees me; my eye and God's eye are one eye, one seeing, one knowing, one love."*
— Meister Eckhart
INDEXEOF

published_count=$(find "$STAGING_DIR" -name "*.md" -type f | wc -l)
echo "[FILTER] External content staged: $published_count notes"
