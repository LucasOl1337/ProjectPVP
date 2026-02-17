from __future__ import annotations



import argparse

import base64

import hashlib

import json

import os

import re

import subprocess

import sys

import time

import urllib.error

import urllib.request

from pathlib import Path

from typing import Any



try:

    from PIL import Image

except Exception:

    Image = None



try:

    sys.stdout.reconfigure(line_buffering=True)

except Exception:

    pass





def _sleep_heartbeat(seconds: int, label: str) -> None:

    end = time.time() + max(0, int(seconds))

    while time.time() < end:

        left = int(max(0.0, end - time.time()))

        print(f"waiting={label} left_s={left}", flush=True)

        time.sleep(min(1.0, max(0.0, end - time.time())))





UUID_RE = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")





PRESETS: dict[str, dict[str, Any]] = {

    "premium_side_128": {

        "n_directions": 8,

        "size": 128,

        "view": "side",

        "outline": "single color black outline",

        "shading": "detailed shading",

        "detail": "high detail",

        "ai_freedom": 140,

        "auto_custom_proportions": True,

        "proportions": '{"type": "preset", "name": "heroic"}',

        "auto_traits": True,

        "description_prefix": "high-quality dark-fantasy pixel art character sprite for a 2D PvP arena, full-body, strong iconic silhouette, adult heroic proportions (not chibi)",

        "description_suffix": "crisp pixels, no blur, no anti-aliasing, 1-2px dark outline, high-contrast 3-tone shading, rich materials (leather/metal/cloth), readable at small size, avoid faceless mannequin, avoid generic simple outfit",

    },

    "iconic_side_128": {

        "n_directions": 8,

        "size": 128,

        "view": "side",

        "outline": "selective outline",

        "shading": "detailed shading",

        "detail": "high detail",

        "ai_freedom": 210,

        "auto_custom_proportions": True,

        "proportions": '{"type": "preset", "name": "heroic"}',

        "auto_traits": True,

        "description_prefix": "hand-crafted pixel art character sprite (not AI-smoothed), full-body, iconic silhouette, adult proportions (not chibi), expressive face/eyes, dynamic pose with attitude, distinct head silhouette (hat/helm/hair), one signature prop, one emblem, one asymmetry, limited palette (2 main colors + 1 accent glow)",

        "description_suffix": "crisp pixel clusters, no blur, no anti-aliasing, no 3D render, no painterly soft gradients, 1-2px outline where needed, hue-shifted shadows, subtle dithering, strong contrast, readable at small size, clear materials (leather/metal/cloth), avoid plain clothing, avoid generic defaults, avoid featureless hooded cloak unless explicitly requested",

    },

    "pvp_archer_side_128": {

        "n_directions": 8,

        "size": 128,

        "view": "side",

        "outline": "selective outline",

        "shading": "detailed shading",

        "detail": "high detail",

        "ai_freedom": 240,

        "auto_custom_proportions": True,

        "proportions": '{"type": "preset", "name": "heroic"}',

        "auto_traits": True,

        "role": "archer",

        "description_prefix": "pixel art character sprite, full-body, iconic silhouette, readable at 128px, 8-direction side view",

        "description_suffix": "crisp pixel clusters, no blur, no anti-aliasing, 1-2px outline, strong 3-tone shading",

    },

    "fast_side_96": {

        "n_directions": 8,

        "size": 96,

        "view": "side",

        "outline": "single color black outline",

        "shading": "medium shading",

        "detail": "medium detail",

        "ai_freedom": 320,

        "proportions": '{"type": "preset", "name": "stylized"}',

        "description_prefix": "game-ready pixel art character, full-body",

        "description_suffix": "crisp pixels, no blur",

    },

}





LORE_MOOD: dict[str, list[str]] = {

    "noxus": [

        "brutal confidence",

        "grim determination",

        "predatory stance",

        "battle-hardened menace",

    ],

    "piltover": [

        "precise confidence",

        "clever smug grin",

        "measured duelist poise",

        "inventor swagger",

    ],

    "zaun": [

        "unstable jittery energy",

        "toxic paranoia",

        "reckless alchemist focus",

        "hunched survivor attitude",

    ],

    "ionia": [

        "serene but lethal calm",

        "spiritual focus",

        "graceful discipline",

        "mystic composure",

    ],

}





LORE_POSE: dict[str, list[str]] = {

    "noxus": [

        "wide aggressive stance, weapon heavy and grounded",

        "forward lean, shoulders squared, ready to strike",

        "resting weapon on shoulder, contemptuous glare",

    ],

    "piltover": [

        "fencer stance, rapier forward, off-hand with gadget",

        "confident upright posture, coat tails flowing",

        "mid-step duel flourish, precise footwork",

    ],

    "zaun": [

        "hunched posture, one arm guarding canisters",

        "half-turn with toxic vapor trail, twitchy pose",

        "bracing under weight of backpack tubes, ready to sprint",

    ],

    "ionia": [

        "light stance, blade angled, sleeve flowing like wind",

        "calm guard posture, talismans fluttering",

        "balanced footwork, petals circling around",

    ],

}





LORE_POSE_ARCHER: dict[str, list[str]] = {

    "noxus": [

        "aggressive aiming stance, bow drawn to the limit",

        "forward lean, arrow nocked, ready to release",

    ],

    "piltover": [

        "confident aiming stance, crossbow held forward, coat tails flowing",

        "upright posture, precision aim, gadget grip steady",

    ],

    "zaun": [

        "hunched aiming stance, twitchy aim, toxic vapor trail",

        "braced posture, heavy chem-bow drawn, unstable energy",

    ],

    "ionia": [

        "calm aiming stance, bow drawn smoothly, talismans fluttering",

        "balanced footwork, serene aim, petals circling",

    ],

}





def _dedupe_phrases(items: list[str]) -> list[str]:

    out: list[str] = []

    seen: set[str] = set()

    for it in items:

        key = re.sub(r"\s+", " ", (it or "").strip().lower())

        if not key or key in seen:

            continue

        seen.add(key)

        out.append(it)

    return out





def _lore_mood(lore_key: str, seed: str) -> str:

    key = (lore_key or "").strip().lower()

    if key in LORE_MOOD:

        return _pick(seed + ":mood:" + key, LORE_MOOD[key], 1)[0]

    return ""





def _lore_pose(lore_key: str, seed: str, role: str = "") -> str:

    key = (lore_key or "").strip().lower()

    role_key = (role or "").strip().lower()

    if role_key == "archer" and key in LORE_POSE_ARCHER:

        return _pick(seed + ":pose_archer:" + key, LORE_POSE_ARCHER[key], 1)[0]

    if key in LORE_POSE:

        return _pick(seed + ":pose:" + key, LORE_POSE[key], 1)[0]

    return ""





LORE_TRAITS: dict[str, list[str]] = {

    "demacia": [

        "lion crest",

        "winged shoulder motif",

        "radiant sigil brooch",

        "polished kite shield",

        "blue-white tabard",

        "sunlit gold filigree",

        "oath scroll sealed on belt",

    ],

    "noxus": [

        "trifarix-like tri-blade sigil",

        "crimson war banner on back",

        "dark iron jaw mask",

        "spiked pauldron silhouette",

        "hooked weapon haft",

        "scarred veteran face",

        "battle trophy tags",

    ],

    "piltover": [

        "glowing blue hex-crystal core",

        "monocle with luminous lens",

        "clockwork shoulder drone",

        "brass filigree trim",

        "tailored longcoat",

        "precision tool belt",

        "gear emblem pin",

    ],

    "zaun": [

        "respirator with cracked goggles",

        "glass tubes backpack",

        "leaking neon-green vial",

        "hazard stencil emblem",

        "oily ragged coat",

        "chemtech canister belt",

        "burn scars and grime",

    ],

    "ionia": [

        "paper talisman strips",

        "blossom charm emblem",

        "fox or spirit half-mask",

        "braided hair silhouette",

        "flowing asymmetrical sleeve",

        "bamboo sheath",

        "petal wind swirl",

    ],

    "shurima": [

        "sun disc emblem",

        "scarab jewelry",

        "golden sandstone trim",

        "linen wraps",

        "khopesh silhouette",

        "sand swirl effect",

        "royal collar",

    ],

    "freljord": [

        "fur mantle silhouette",

        "antler or horn helm",

        "ice-blue runes",

        "bear totem emblem",

        "frosted axe head",

        "breath mist",

        "bone charms",

    ],

    "shadow_isles": [

        "spectral chains",

        "lantern with trapped wisps",

        "corroded crest",

        "torn shroud",

        "ghostly green glow",

        "hollow eyes",

        "black mist trailing",

    ],

    "targon": [

        "constellation emblem",

        "sun-moon dual motif",

        "bronze-gold sacred armor",

        "star-speckled cloak",

        "celestial halo glow",

        "astral spear tip",

        "mountain pilgrim wraps",

    ],

    "bilgewater": [

        "shark-tooth talisman",

        "salt-stained coat",

        "rope harness",

        "sea monster trophy",

        "hook hand silhouette",

        "pistol + cutlass",

        "sea spray highlights",

    ],

    "ixtal": [

        "jade and obsidian jewelry",

        "geometric glyph patterns",

        "feathered pauldron",

        "serpent glyph emblem",

        "vine wraps",

        "humid sheen",

        "elemental leaf swirl",

    ],

    "void": [

        "chitin plates",

        "asymmetrical spikes",

        "bioluminescent veins",

        "distorted rune sigil",

        "alien jaw silhouette",

        "purple-magenta glow",

        "unnatural limb shape",

    ],

}





STYLE_PACKS: dict[str, list[str]] = {

    "lol_ashe": [

        "theme: iceborn archer royalty",

        "head: crown/tiara silhouette",

        "palette: icy blue + white + silver",

        "weapon: frosted bow limbs + crystalline arrowhead",

        "detail: fur-lined cloak trim",

    ],

    "lol_varus": [

        "theme: corrupted darkin archer",

        "weapon: organic spiked bow with purple-red glow",

        "detail: vein-like tendrils of corruption",

        "palette: deep purple + crimson + black",

    ],

    "lol_vayne": [

        "theme: remorseless monster hunter",

        "head: red-tinted goggles/glasses silhouette",

        "weapon: wrist-mounted crossbow that shoots bolts",

        "palette: navy/black + red + silver",

    ],

    "lol_kindred": [

        "theme: mythic death-mask archer",

        "head: carved mask face, eerie calm",

        "weapon: spiritwood bow with runes",

        "palette: bone white + charcoal + teal glow",

    ],

    "lol_quinn": [

        "theme: elite ranger-knight scout",

        "weapon: repeater crossbow that shoots bolts",

        "motif: bird companion silhouette (eagle)",

        "palette: brown leather + steel + off-white",

    ],

    "lol_twitch": [

        "theme: plague scavenger",

        "head: cracked goggles silhouette",

        "weapon: chem-powered crossbow with toxin chamber",

        "palette: moss green + rust + neon green",

    ],

    "style_desert_nomad": [

        "theme: desert nomad archer",

        "head: wrapped scarf + goggles silhouette",

        "palette: sand + bronze + turquoise glow",

        "weapon: heavy warbow with wrapped grip",

    ],

    "style_samurai_archer": [

        "theme: disciplined samurai archer",

        "head: crested kabuto-like helmet silhouette",

        "palette: ink black + bone white + red accent",

        "weapon: tall asymmetric longbow",

    ],

    "style_cyber_sniper": [

        "theme: cybernetic sniper archer",

        "head: visor mask with glowing eye slit",

        "palette: graphite + neon cyan + magenta accent",

        "weapon: rail-crossbow that shoots bolts",

    ],

    "style_tribal_beast": [

        "theme: primal beast-hunter archer",

        "head: beast skull mask silhouette",

        "palette: dark brown + bone + ember orange",

        "weapon: bone-and-wood bow with oversized arrowhead",

    ],

}





SHAPE_PACKS: dict[str, list[str]] = {

    "lanky": [

        "BODY: very tall and lanky",

        "PROPORTIONS: small head, long legs, narrow torso",

        "SILHOUETTE: thin waist, long coat tails",

    ],

    "bulky": [

        "BODY: bulky and wide",

        "PROPORTIONS: big shoulders, thick arms, short legs",

        "SILHOUETTE: heavy upper-body mass",

    ],

    "compact": [

        "BODY: short and compact",

        "PROPORTIONS: big boots and gloves, stocky torso",

        "SILHOUETTE: chunky silhouette",

    ],

    "longcoat": [

        "BODY: slender",

        "PROPORTIONS: long legs, narrow shoulders",

        "SILHOUETTE: longcoat with split tails",

    ],

    "hunched": [

        "BODY: hunched",

        "PROPORTIONS: forward-leaning posture, uneven shoulders",

        "SILHOUETTE: backpack/tubes create top-heavy shape",

    ],

}





def _lore_traits(lore_key: str, seed: str) -> list[str]:

    key = (lore_key or "").strip().lower()

    if not key or key not in LORE_TRAITS:

        return []

    return _pick(seed + ":lore:" + key, LORE_TRAITS[key], 2)





def _style_traits(style_key: str, seed: str) -> list[str]:

    raw = (style_key or "").strip().lower()

    if not raw:

        return []

    keys = [k.strip() for k in re.split(r"[|,]", raw) if k.strip()]

    out: list[str] = []

    for idx, key in enumerate(keys):

        if key in {"mix", "random"}:

            available = sorted(STYLE_PACKS.keys())

            if not available:

                continue

            chosen = _pick(seed + f":style_pick:{idx}", available, 1)[0]

            pack = STYLE_PACKS.get(chosen, [])

            out += _pick(seed + f":style:{chosen}:{idx}", pack, min(2, len(pack)))

        else:

            pack = STYLE_PACKS.get(key, [])

            out += _pick(seed + f":style:{key}:{idx}", pack, min(2, len(pack)))

    out = _dedupe_phrases(out)

    return out[:3]





def _shape_traits(shape_key: str, seed: str) -> list[str]:

    raw = (shape_key or "").strip().lower()

    if not raw:

        return []

    keys = [k.strip() for k in re.split(r"[|,]", raw) if k.strip()]

    out: list[str] = []

    for idx, key in enumerate(keys):

        if key in {"mix", "random"}:

            available = sorted(SHAPE_PACKS.keys())

            if not available:

                continue

            chosen = _pick(seed + f":shape_pick:{idx}", available, 1)[0]

            pack = SHAPE_PACKS.get(chosen, [])

            out += _pick(seed + f":shape:{chosen}:{idx}", pack, min(2, len(pack)))

        else:

            pack = SHAPE_PACKS.get(key, [])

            out += _pick(seed + f":shape:{key}:{idx}", pack, min(2, len(pack)))

    out = _dedupe_phrases(out)

    return out[:2]





LORE_HEAD: dict[str, list[str]] = {

    "noxus": ["crested helmet silhouette", "spiked crown silhouette", "dark iron jaw mask"],

    "piltover": ["top hat silhouette", "monocle on one eye", "slick hair silhouette"],

    "zaun": ["respirator with cracked goggles", "hood + half-mask silhouette", "very tall hat silhouette"],

    "ionia": ["fox or spirit half-mask", "braided hair silhouette", "asymmetrical flowing sleeve"],

}





LORE_FACE: dict[str, list[str]] = {

    "noxus": ["scarred veteran face", "asymmetric scar across cheek", "harsh expression"],

    "piltover": ["clever smug grin", "distinct eyebrows and visible eyes", "monocle on one eye"],

    "zaun": ["cracked goggles", "stylized mask with glowing eyes", "burn scars and grime"],

    "ionia": ["serene eyes", "stylized mask with glowing eyes", "calm expression"],

}





LORE_PALETTE: dict[str, list[str]] = {

    "noxus": ["limited palette: black + iron + crimson glow", "high contrast rim light"],

    "piltover": ["limited palette: navy + brass + blue glow", "bright clean rim light"],

    "zaun": ["limited palette: soot + rust + neon green glow", "sickly green underlight"],

    "ionia": ["limited palette: muted cloth + pale petals + soft teal glow", "gentle moon rim light"],

}





LORE_PACKS: dict[str, dict[str, str]] = {

    "demacia": {

        "prefix": "Runeterra Demacia-inspired, radiant high-fantasy kingdom, noble knightly aesthetic, polished steel, white cloth, blue accents, sunlit gold filigree, heraldry and banners",

        "suffix": "signature emblem on cloak or shield, clean silhouette, disciplined posture, holy light accent, no modern tech",

    },

    "noxus": {

        "prefix": "Runeterra Noxus-inspired, brutal expansionist empire vibe, dark iron, crimson accents, angular armor, spiked details, war banners, battle-worn cloth",

        "suffix": "one intimidating asymmetry (single pauldron / torn cape), harsh expression, utilitarian gear, no shiny paladin look",

    },

    "piltover": {

        "prefix": "Runeterra Piltover-inspired, clean hextech metropolis vibe, refined steampunk + arcane technology, brass, polished leather, tailored coats, glowing blue hex-crystal",

        "suffix": "precise gadgets, elegant silhouette, inventor charm, bright rim light, no grime",

    },

    "zaun": {

        "prefix": "Runeterra Zaun-inspired, undercity chemtech vibe, industrial grime, toxic green glow, patched clothes, respirator mask, tubes and canisters, rusty metal",

        "suffix": "one leaking vial, one scar or burn mark, unstable energy, gritty silhouette",

    },

    "ionia": {

        "prefix": "Runeterra Ionia-inspired, spiritual nature + martial arts vibe, flowing fabrics, layered wraps, curved blade or staff, pastel petals, serene aura",

        "suffix": "one spirit motif (mask / charm / paper talisman), graceful stance, minimal armor",

    },

    "shurima": {

        "prefix": "Runeterra Shurima-inspired, ancient desert empire vibe, gold and sandstone, sun disc motifs, ornate jewelry, linen wraps, warm sunlit palette",

        "suffix": "one sand magic effect, one royal crest, regal silhouette, no frost colors",

    },

    "freljord": {

        "prefix": "Runeterra Freljord-inspired, harsh arctic tribes vibe, fur, horn, ice-blue glow, rough leather, heavy boots, runic carvings",

        "suffix": "breath mist, snow on shoulders, brutal cold-proof silhouette, no delicate fabrics",

    },

    "shadow_isles": {

        "prefix": "Runeterra Shadow Isles-inspired, cursed ruins vibe, ghostly green mist, corroded armor, torn shroud cloth, spectral chains",

        "suffix": "hollow eyes or skull mask, eerie glow, undead vibe, decayed materials",

    },

    "targon": {

        "prefix": "Runeterra Targon-inspired, celestial mountain culture vibe, bronze + gold, star patterns, sun/moon motifs, sacred armor, cosmic glow",

        "suffix": "one constellation emblem, divine aura, heroic silhouette, clean celestial lighting",

    },

    "bilgewater": {

        "prefix": "Runeterra Bilgewater-inspired, pirate port vibe, salt-stained coat, rope, hooks, sea-monster trophies, pistols or cutlass, weathered leather",

        "suffix": "one nautical talisman, gritty grin, asymmetrical gear, sea spray highlights",

    },

    "ixtal": {

        "prefix": "Runeterra Ixtal-inspired, hidden jungle civilization vibe, jade and obsidian, geometric glyphs, feathers, vines, elemental nature magic",

        "suffix": "one serpent or sun glyph, humid sheen, wild-but-regal silhouette",

    },

    "void": {

        "prefix": "Runeterra Void-inspired, alien horror vibe, unnatural anatomy accents, purple-magenta glow, chitin plates, asymmetrical spikes, distorted runes",

        "suffix": "menacing silhouette, eerie bioluminescence, unsettling proportions, not cute",

    },

}





def _apply_lore(description: str, lore_key: str | None) -> str:

    base = (description or "").strip()

    key = (lore_key or "").strip().lower()

    if not key:

        return base

    pack = LORE_PACKS.get(key)

    if not pack:

        raise ValueError(f"lore pack desconhecido: {lore_key}")

    prefix = pack.get("prefix", "").strip()

    suffix = pack.get("suffix", "").strip()

    parts = [p for p in [prefix, base, suffix] if p]

    return ", ".join(parts)





def _sanitize_description(text: str) -> str:

    s = (text or "").strip()

    s = re.sub(r"\b(make it|non-generic|not generic|avoid generic)\b", "", s, flags=re.IGNORECASE)

    s = re.sub(r"\s+", " ", s)

    s = s.strip().strip(",")

    return s





def _pick(seed: str, options: list[str], n: int) -> list[str]:

    if not options or n <= 0:

        return []

    h = hashlib.sha256(seed.encode("utf-8")).digest()

    out: list[str] = []

    used: set[int] = set()

    i = 0

    while len(out) < min(n, len(options)) and i < 64:

        idx = h[i] % len(options)

        i += 1

        if idx in used:

            continue

        used.add(idx)

        out.append(options[idx])

    return out





def _uniqueness_traits(seed: str, lore_key: str = "", role: str = "") -> list[str]:

    wizard = [

        "crescent-moon hat pin",

        "floating rune orb",

        "glowing arcane tattoos on one forearm",

        "tattered spellbook chained to belt",

        "staff topped with cracked crystal",

        "small familiar perched on shoulder",

        "masked face with glowing eyes",

        "layered robe with ornate trim",

    ]

    ranger = [

        "asymmetric quiver",

        "bow with glowing string",

        "cape clasp emblem",

        "arm guard bracer",

        "belt pouches",

        "hood + half-mask",

        "trophy charm on belt",

    ]

    warrior = [

        "single shoulder pauldron",

        "battle-worn cape",

        "scar across cheek",

        "distinctive helmet crest",

        "rune-etched sword",

        "round shield with emblem",

        "chainmail + leather mix",

    ]

    rogue = [

        "dual daggers",

        "dark hood with mask",

        "throwing knives bandolier",

        "one glowing earring",

        "torn scarf",

        "sleek silhouette",

        "smoke vial on belt",

    ]



    archer = [

        "fingerless draw glove",

        "arm guard bracer",

        "arrow quiver with visible fletching",

        "nocked arrow with glowing tip",

        "ranged stance, bowstring pulled",

        "focused eyes and sharp expression",

        "cloak tails flowing from movement",

    ]



    accessories = [

        "asymmetric cloak",

        "torn scarf",

        "rune-embroidered sash",

        "bandolier with small potions",

        "spiked shoulder pauldron",

        "glowing charm amulet",

        "leather bracers",

        "belt with large buckle",

        "fingerless gloves",

        "boots with metal tips",

    ]

    patterns = [

        "subtle rune pattern",

        "geometric trim",

        "stitched patches",

        "ornate embroidery",

        "weathered fabric texture",

    ]

    weapon_bits = [

        "weapon with glowing crystal",

        "weapon with cloth wrap",

        "weapon with metallic guard",

        "weapon with arcane sigil",

    ]



    bow_weapons = [

        "oversized recurve bow",

        "heavy warbow",

        "repeating crossbow",

        "hand crossbow",

        "hextech bolt-bow that shoots arrows",

        "chemtech pressure-bow that shoots arrows",

        "spiritwood bow with paper talismans",

        "shoulder-mounted mini-ballista that shoots arrows",

    ]



    bow_details = [

        "weapon dominates the silhouette",

        "weapon held forward in hands (not on back)",

        "bowstring drawn with arrow nocked",

        "thick readable bow limbs",

        "bright bowstring highlight",

        "big thematic bow grip",

        "oversized arrowhead",

        "distinct fletching shape",

        "quiver shape readable from far",

    ]



    emblems = [

        "emblem: arrowhead insignia",

        "emblem: gear crest",

        "emblem: crescent moon glyph",

        "emblem: skull mark",

        "emblem: wing sigil",

        "emblem: hazard triangle",

        "emblem: rune circle",

    ]



    personality = [

        "cocky smirk",

        "grim determination",

        "cold calm stare",

        "reckless grin",

        "haunted eyes",

        "playful confidence",

        "predatory focus",

    ]



    head_silhouette = [

        "very tall hat silhouette",

        "crested helmet silhouette",

        "spiked crown silhouette",

        "high ponytail silhouette",

        "braided hair silhouette",

        "hood + half-mask silhouette",

        "top hat silhouette",

        "slick hair silhouette",

    ]

    face_bits = [

        "distinct eyebrows and visible eyes",

        "asymmetric scar across cheek",

        "stylized mask with glowing eyes",

        "monocle on one eye",

        "cracked goggles",

        "harsh expression",

        "calm expression",

        "serene eyes",

    ]

    render_bits = [

        "render: strong 3-tone shading",

        "render: high contrast rim light",

        "render: hue-shifted shadows",

        "render: subtle dithering",

    ]





    s = seed.lower()

    kit: list[str] = []



    role_key = (role or "").strip().lower()

    if role_key == "archer" or any(k in s for k in ["archer", "ranger", "bow", "crossbow", "arrow", "quiver"]):

        kit = archer

    elif any(k in s for k in ["wizard", "mage", "sorcer", "arcane", "warlock"]):

        kit = wizard

    elif any(k in s for k in ["ranger", "archer", "bow", "hunt"]):

        kit = ranger

    elif any(k in s for k in ["knight", "warrior", "paladin", "soldier"]):

        kit = warrior

    elif any(k in s for k in ["rogue", "assassin", "thief"]):

        kit = rogue



    traits: list[str] = []

    if kit:

        traits += _pick(seed + ":k", kit, 1)

    traits += _lore_traits(lore_key, seed)

    traits += _pick(seed + ":em", emblems, 1)

    if role_key == "archer":

        weapon = _pick(seed + ":bw", bow_weapons, 1)

        if weapon:

            traits.append(f"weapon: {weapon[0]}")

        traits += _pick(seed + ":bd", bow_details, 1)

        traits += _pick(seed + ":pp", personality, 1)

        traits += _pick(seed + ":acc", accessories, 1)

        traits += _pick(seed + ":arch", archer, 1)

    else:

        traits += _pick(seed + ":w", weapon_bits, 1)

    lk = (lore_key or "").strip().lower()

    if lk in LORE_HEAD:

        head = _pick(seed + ":lh", LORE_HEAD[lk], 1)

    else:

        head = _pick(seed + ":h", head_silhouette, 1)

    if head:

        traits.append(f"head: {head[0]}")

    if lk in LORE_FACE:

        face = _pick(seed + ":lf", LORE_FACE[lk], 1)

    else:

        face = _pick(seed + ":f", face_bits, 1)

    if face:

        traits.append(f"face: {face[0]}")

    if lk in LORE_PALETTE:

        pal = _pick(seed + ":lc", LORE_PALETTE[lk], 1)

    else:

        pal = []

    if pal:

        traits.append(f"palette: {pal[0]}")

    traits += _pick(seed + ":r", render_bits, 1)

    return traits





def _custom_proportions(seed: str) -> str:

    h = hashlib.sha256(seed.encode("utf-8")).digest()



    presets = [

        (

            "lanky",

            {

                "head_size": (0.80, 1.10),

                "arms_length": (0.95, 1.25),

                "legs_length": (1.05, 1.35),

                "shoulder_width": (0.65, 0.95),

                "hip_width": (0.55, 0.85),

            },

        ),

        (

            "bulky",

            {

                "head_size": (0.85, 1.20),

                "arms_length": (0.75, 1.05),

                "legs_length": (0.75, 1.05),

                "shoulder_width": (1.10, 1.45),

                "hip_width": (0.95, 1.25),

            },

        ),

        (

            "compact",

            {

                "head_size": (0.95, 1.30),

                "arms_length": (0.70, 0.95),

                "legs_length": (0.70, 0.95),

                "shoulder_width": (0.80, 1.05),

                "hip_width": (0.85, 1.15),

            },

        ),

        (

            "heroic",

            {

                "head_size": (0.85, 1.15),

                "arms_length": (0.75, 1.05),

                "legs_length": (0.85, 1.15),

                "shoulder_width": (0.75, 1.15),

                "hip_width": (0.70, 1.05),

            },

        ),

        (

            "slender",

            {

                "head_size": (0.80, 1.05),

                "arms_length": (0.85, 1.15),

                "legs_length": (0.95, 1.25),

                "shoulder_width": (0.65, 0.90),

                "hip_width": (0.55, 0.80),

            },

        ),

    ]



    name, ranges = presets[h[0] % len(presets)]



    def r(i: int, lo: float, hi: float) -> float:

        return lo + (h[i] / 255.0) * (hi - lo)



    data = {

        "type": "custom",

        "head_size": round(r(1, *ranges["head_size"]), 2),

        "arms_length": round(r(2, *ranges["arms_length"]), 2),

        "legs_length": round(r(3, *ranges["legs_length"]), 2),

        "shoulder_width": round(r(4, *ranges["shoulder_width"]), 2),

        "hip_width": round(r(5, *ranges["hip_width"]), 2),

    }

    return json.dumps(data, ensure_ascii=False)





def _build_description(

    base_description: str,

    preset: dict[str, Any],

    seed: str = "",

    lore_key: str = "",

    style_key: str = "",

    shape_key: str = "",

) -> str:

    base = (base_description or "").strip().strip(",")

    prefix = str(preset.get("description_prefix") or "").strip().strip(",")

    suffix = str(preset.get("description_suffix") or "").strip().strip(",")



    traits: list[str] = []

    if preset.get("auto_traits"):

        traits = _uniqueness_traits(seed or base or prefix, lore_key=lore_key, role=str(preset.get("role") or ""))



    style_traits = _style_traits(style_key, seed or base or prefix)



    shape_traits = _shape_traits(shape_key, seed or base or prefix)



    def key_of(t: str) -> str:

        s = (t or "").strip()

        if not s:

            return ""

        up = s.upper()

        if up.startswith("PROPORTIONS:"):

            return "PROPORTIONS"

        if up.startswith("SILHOUETTE:"):

            return "SILHOUETTE"

        return s.split(":", 1)[0].strip().lower()



    locked = {key_of(t) for t in (style_traits + shape_traits) if key_of(t)}

    if locked:

        traits = [t for t in traits if key_of(t) not in locked]



    role = str(preset.get("role") or "")

    mood = _lore_mood(lore_key, seed or base or prefix)

    pose = _lore_pose(lore_key, seed or base or prefix, role=role)



    traits_text = ", ".join(_dedupe_phrases(traits)).strip()

    parts = [

        prefix,

        base,

        f"mood: {mood}" if mood else "",

        f"pose: {pose}" if pose else "",

        ", ".join(shape_traits) if shape_traits else "",

        ", ".join(style_traits) if style_traits else "",

        traits_text,

        suffix,

    ]

    return ", ".join(_dedupe_phrases([p for p in parts if p]))





def _load_trae_pixellab_config() -> tuple[str, str] | None:

    appdata = os.environ.get("APPDATA")

    if not appdata:

        return None

    cfg_path = Path(appdata) / "Trae" / "User" / "mcp.json"

    if not cfg_path.exists():

        return None

    data = json.loads(cfg_path.read_text(encoding="utf-8"))

    server = (data.get("mcpServers") or {}).get("pixellab")

    if not isinstance(server, dict):

        return None

    url = str(server.get("url") or "").strip()

    headers = server.get("headers") or {}

    auth = str(headers.get("Authorization") or "").strip()

    if not url or not auth:

        return None

    return url, auth





def _load_pixellab_auth() -> tuple[str, str]:

    cfg = _load_trae_pixellab_config()

    if cfg:

        return cfg

    url = os.environ.get("PIXELLAB_MCP_URL", "https://api.pixellab.ai/mcp").strip()

    token = os.environ.get("PIXELLAB_TOKEN", "").strip()

    if not token:

        raise SystemExit(

            "PIXELLAB_TOKEN não definido e config do Trae não encontrada (APPDATA/Trae/User/mcp.json)."

        )

    return url, f"Bearer {token}"





def _parse_sse_messages(text: str) -> list[Any]:

    out: list[Any] = []

    for line in text.splitlines():

        line = line.strip()

        if not line.startswith("data:"):

            continue

        payload = line[len("data:") :].strip()

        if not payload:

            continue

        try:

            parsed = json.loads(payload)

        except json.JSONDecodeError:

            continue

        if isinstance(parsed, list):

            out.extend(parsed)

        else:

            out.append(parsed)

    return out





def _extract_jsonrpc_messages(body: str) -> list[dict[str, Any]]:

    s = body.strip()

    if not s:

        return []

    if s.startswith("{") or s.startswith("["):

        try:

            parsed = json.loads(s)

        except json.JSONDecodeError:

            return []

        if isinstance(parsed, list):

            return [p for p in parsed if isinstance(p, dict)]

        if isinstance(parsed, dict):

            return [parsed]

        return []

    msgs = _parse_sse_messages(body)

    return [m for m in msgs if isinstance(m, dict)]





class McpClient:

    def __init__(self, url: str, authorization: str, protocol_version: str = "2025-03-26") -> None:

        self.url = url

        self.authorization = authorization

        self.protocol_version = protocol_version



    def _headers(self) -> dict[str, str]:

        return {

            "Authorization": self.authorization,

            "Accept": "application/json, text/event-stream",

            "Content-Type": "application/json",

        }



    def _post(self, payload: dict[str, Any]) -> tuple[int, str]:

        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")

        req = urllib.request.Request(self.url, method="POST", headers=self._headers(), data=data)

        try:

            with urllib.request.urlopen(req, timeout=90) as resp:

                return int(resp.status), resp.read().decode("utf-8", errors="replace")

        except urllib.error.HTTPError as e:

            body = e.read().decode("utf-8", errors="replace") if e.fp else ""

            return int(e.code), body



    def initialize(self) -> None:

        payload = {

            "jsonrpc": "2.0",

            "id": 1,

            "method": "initialize",

            "params": {

                "protocolVersion": self.protocol_version,

                "clientInfo": {"name": "project-pvp", "version": "1.0"},

                "capabilities": {"tools": {}, "resources": {}, "prompts": {}, "logging": {}},

            },

        }

        status, body = self._post(payload)

        if status < 200 or status >= 300:

            raise RuntimeError(f"initialize HTTP {status}: {body[:400]}")

        messages = _extract_jsonrpc_messages(body)

        if not any(m.get("id") == 1 and isinstance(m.get("result"), dict) for m in messages):

            raise RuntimeError(f"initialize sem result: {body[:400]}")

        self._post({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})



    def tools_list(self) -> list[dict[str, Any]]:

        status, body = self._post({"jsonrpc": "2.0", "id": 2, "method": "engine/tools/list", "params": {}})

        if status < 200 or status >= 300:

            raise RuntimeError(f"engine/tools/list HTTP {status}: {body[:400]}")

        messages = _extract_jsonrpc_messages(body)

        for m in messages:

            if m.get("id") == 2 and isinstance(m.get("result"), dict):

                tools = m["result"].get("tools")

                if isinstance(tools, list):

                    return [t for t in tools if isinstance(t, dict)]

        raise RuntimeError(f"engine/tools/list sem tools: {body[:400]}")



    def tools_call(self, name: str, arguments: dict[str, Any], call_id: int) -> dict[str, Any]:

        payload = {

            "jsonrpc": "2.0",

            "id": call_id,

            "method": "engine/tools/call",

            "params": {"name": name, "arguments": arguments},

        }

        status, body = self._post(payload)

        if status < 200 or status >= 300:

            raise RuntimeError(f"engine/tools/call {name} HTTP {status}: {body[:400]}")

        messages = _extract_jsonrpc_messages(body)

        for m in messages:

            if m.get("id") == call_id:

                if isinstance(m.get("result"), dict):

                    return m["result"]

                if m.get("error"):

                    raise RuntimeError(f"engine/tools/call {name} error: {m['error']}")

        raise RuntimeError(f"engine/tools/call {name} sem resposta id={call_id}: {body[:400]}")





def _result_text(result: dict[str, Any]) -> str:

    parts: list[str] = []

    content = result.get("content")

    if isinstance(content, list):

        for item in content:

            if isinstance(item, dict) and item.get("type") == "text" and isinstance(item.get("text"), str):

                parts.append(item["text"])

    return "\n".join(parts).strip()





def _create_character_with_retry(client: McpClient, create_args: dict[str, Any], timeout_s: int = 600) -> str:

    started = time.time()

    call_id = 10

    last_text = ""

    while time.time() - started < timeout_s:

        create = client.tools_call("create_character", create_args, call_id)

        call_id += 1

        text = _result_text(create)

        last_text = text

        created_id = _first_uuid(text)

        if created_id:

            return created_id

        if "Rate limit exceeded" in text or "Maximum concurrent" in text:

            _sleep_heartbeat(20, "pixellab_rate_limit")

            continue

        _sleep_heartbeat(5, "pixellab_retry")

    raise RuntimeError(f"create_character sem id após retry: {last_text[:400]}")





def _first_uuid(text: str) -> str:

    m = UUID_RE.search(text or "")

    return m.group(0) if m else ""





def _download(url: str, out_path: Path) -> None:

    out_path.parent.mkdir(parents=True, exist_ok=True)

    req = urllib.request.Request(url, method="GET")

    with urllib.request.urlopen(req, timeout=60) as resp:

        out_path.write_bytes(resp.read())





def _jobs_dir() -> Path:

    d = Path("engine") / "tools" / "_cache" / "pixellab_jobs" / "pixellab" / "jobs"

    d.mkdir(parents=True, exist_ok=True)

    return d





def _is_zip_file(path: Path) -> bool:

    try:

        b = path.read_bytes()

    except OSError:

        return False

    return len(b) >= 4 and b[0:2] == b"PK"





def _download_zip_when_ready(url: str, out_path: Path, timeout_s: int) -> None:

    def sleep_heartbeat(seconds: int | float, label: str) -> None:

        end = time.time() + float(seconds)

        while time.time() < end:

            left = max(0.0, end - time.time())

            print(f"waiting={label} left_s={int(left)}", flush=True)

            time.sleep(min(0.8, left))



    started = time.time()

    last_err: str | None = None

    while time.time() - started < timeout_s:

        try:

            _download(url, out_path)

            if _is_zip_file(out_path):

                return

            last_err = "conteúdo não é ZIP (provavelmente ainda gerando)"

        except urllib.error.HTTPError as e:

            if e.code not in (404, 423):

                raise

            retry_after = e.headers.get("Retry-After")

            if retry_after and retry_after.isdigit():

                wait_s = max(1, int(retry_after))

                print(f"download_not_ready=http_{e.code} retry_after_s={wait_s}")

                while wait_s > 0 and time.time() - started < timeout_s:

                    step = min(10, wait_s)

                    sleep_heartbeat(step, f"retry_after_http_{e.code}")

                    wait_s -= step

                continue

            last_err = f"HTTP {e.code}"

            print(f"download_not_ready={last_err}")

        sleep_heartbeat(3, "polling")

    raise TimeoutError(f"timeout baixando ZIP: {last_err or 'sem detalhes'}")





def _try_download_zip(url: str, out_path: Path) -> bool:

    try:

        _download(url, out_path)

        return _is_zip_file(out_path)

    except urllib.error.HTTPError as e:

        if e.code in (404, 423):

            return False

        raise

    except KeyboardInterrupt:

        return False

    except Exception:

        return False





def _write_job(char_id: str, payload: dict[str, Any]) -> Path:

    job_path = _jobs_dir() / f"{char_id}.json"

    job_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

    return job_path





def _read_job(char_id: str) -> dict[str, Any]:

    job_path = _jobs_dir() / f"{char_id}.json"

    return json.loads(job_path.read_text(encoding="utf-8"))





def _ensure_character_tres(char_id: str, display_name: str) -> Path:

    data_dir = Path("data") / "characters"

    data_dir.mkdir(parents=True, exist_ok=True)

    data_path = data_dir / f"{char_id}.tres"

    if data_path.exists():

        return data_path



    safe_display_name = (display_name or char_id).strip() or char_id

    safe_display_name = safe_display_name.replace('"', '\\"')

    asset_base = f"res://visuals/assets/characters/{char_id}/pixellab/"

    projectile = "res://visuals/assets/characters/arrow/custom/crystal_arrow.png"

    tres = "\n".join(

        [

            '[gd_resource type="Resource" script_class="CharacterData" load_steps=3 format=3]',

            "",

            '[ext_resource type="Script" path="res://engine/scripts/characters/character_data.gd" id="1"]',

            f'[ext_resource type="Texture2D" path="{projectile}" id="2"]',

            "",

            "[resource]",

            'script = ExtResource("1")',

            f'id = "{char_id}"',

            f'display_name = "{safe_display_name}"',

            f'asset_base_path = "{asset_base}"',

            "sprite_scale = Vector2(3.6, 3.6)",

            'projectile_texture = ExtResource("2")',

            "",

        ]

    )

    data_path.write_text(tres, encoding="utf-8")

    return data_path





def _score_rotation_png(path: Path) -> float:

    if not path.exists():

        return 0.0

    if Image is None:

        return float(path.stat().st_size)

    img = Image.open(path).convert("RGBA")

    w, h = img.size

    px = img.getdata()

    opaque = []

    xs = []

    ys = []

    for i, (r, g, b, a) in enumerate(px):

        if a <= 0:

            continue

        x = i % w

        y = i // w

        xs.append(x)

        ys.append(y)

        opaque.append((r, g, b))

    if not opaque:

        return 0.0

    area_frac = len(opaque) / float(w * h)

    minx, maxx = min(xs), max(xs)

    miny, maxy = min(ys), max(ys)

    box_area = float((maxx - minx + 1) * (maxy - miny + 1))

    box_frac = box_area / float(w * h)

    stride = max(1, len(opaque) // 20000)

    colors = set(opaque[::stride])

    color_count = min(len(colors), 512)

    lums = []

    for (r, g, b) in opaque[::stride]:

        lums.append(0.2126 * r + 0.7152 * g + 0.0722 * b)

    mean = sum(lums) / max(1, len(lums))

    var = sum((v - mean) ** 2 for v in lums) / max(1, len(lums))

    contrast = (var ** 0.5) / 64.0

    score = 120.0 * area_frac + 80.0 * box_frac + 12.0 * (color_count ** 0.5) + 120.0 * contrast

    return float(score)





def cmd_submit(

    client: McpClient,

    char_id: str,

    name: str,

    description: str,

    preset_name: str,

    no_animations: bool,

    lore: str | None = None,

    style: str | None = None,

    shape: str | None = None,

) -> int:

    preset_name = (preset_name or "").strip() or "premium_side_128"

    preset = PRESETS.get(preset_name, PRESETS["premium_side_128"])

    base = _apply_lore(_sanitize_description(description), lore)

    desc = _build_description(

        base,

        preset,

        seed=f"{char_id}:{name}",

        lore_key=str(lore or ""),

        style_key=str(style or ""),

        shape_key=str(shape or ""),

    )

    create_args: dict[str, Any] = {

        "description": desc,

        "name": name,

        "n_directions": int(preset.get("n_directions", 8)),

        "size": int(preset.get("size", 128)),

        "view": str(preset.get("view", "side")),

        "outline": preset.get("outline"),

        "shading": preset.get("shading"),

        "detail": preset.get("detail"),

        "ai_freedom": float(preset.get("ai_freedom", 250)),

        "proportions": _custom_proportions(f"{char_id}:{name}")

        if preset.get("auto_custom_proportions")

        else str(preset.get("proportions")),

    }

    character_id = _create_character_with_retry(client, create_args, timeout_s=900)



    animation_jobs: list[dict[str, Any]] = []

    if not no_animations:

        animation_jobs = [

            {"animation_name": "walk", "template_animation_id": "walking-6-frames", "action_description": "walk cycle"},

            {"animation_name": "running", "template_animation_id": "running-8-frames", "action_description": "run cycle"},

            {"animation_name": "dash_magic", "template_animation_id": "running-slide", "action_description": "fast dash"},

            {"animation_name": "aiming", "template_animation_id": "fight-stance-idle-8-frames", "action_description": "aiming stance"},

            {"animation_name": "jumping-1", "template_animation_id": "jumping-1", "action_description": "jump start"},

            {"animation_name": "jumping-2", "template_animation_id": "jumping-2", "action_description": "jump in air"},

            {"animation_name": "throw-object", "template_animation_id": "throw-object", "action_description": "shoot motion"},

            {"animation_name": "lead-jab", "template_animation_id": "lead-jab", "action_description": "melee strike"},

            {"animation_name": "taking-punch", "template_animation_id": "taking-punch", "action_description": "hurt reaction"},

            {"animation_name": "falling-back-death", "template_animation_id": "falling-back-death", "action_description": "death fall"},

            {"animation_name": "roundhouse-kick", "template_animation_id": "roundhouse-kick", "action_description": "ultimate attack"},

        ]



    toolset = {t.get("name"): t for t in client.tools_list()}

    anim_schema = toolset.get("animate_character", {})

    enums = (((anim_schema.get("inputSchema") or {}).get("properties") or {}).get("template_animation_id") or {}).get(

        "description", ""

    )

    allowed = set()

    m = re.search(r"Available: `(.+)`$", str(enums))

    if m:

        allowed = set(x.strip() for x in m.group(1).split("`, `"))

    for idx, job in enumerate(animation_jobs):

        templ = job["template_animation_id"]

        if allowed and templ not in allowed:

            continue

        try:

            client.tools_call(

                "animate_character",

                {

                    "character_id": character_id,

                    "template_animation_id": templ,

                    "action_description": job["action_description"],

                    "animation_name": job["animation_name"],

                },

                20 + idx,

            )

        except Exception:

            pass



    preview = client.tools_call("get_character", {"character_id": character_id}, 150)

    preview_text = _result_text(preview)



    job = {

        "char_id": char_id,

        "character_id": character_id,

        "name": name,

        "description": desc,

        "lore": (lore or "").strip().lower(),

        "style": (style or "").strip().lower(),

        "shape": (shape or "").strip().lower(),

        "preset": preset_name,

        "no_animations": bool(no_animations),

        "created_at": int(time.time()),

        "status_preview": preview_text,

    }

    job_path = _write_job(char_id, job)

    print(f"submitted_char_id={char_id}", flush=True)

    print(f"character_id={character_id}", flush=True)

    print(f"job_file={job_path.as_posix()}", flush=True)

    return 0





def cmd_import(client: McpClient, char_id: str) -> int:

    job = _read_job(char_id)

    character_id = str(job.get("character_id") or "").strip()

    if not character_id:

        raise RuntimeError(f"job sem character_id: {char_id}")



    zip_url = f"https://api.pixellab.ai/mcp/characters/{character_id}/download"

    zip_out = Path("engine") / "tools" / "_cache" / "pixellab_jobs" / "pixellab" / f"{char_id}.zip"

    ok = _try_download_zip(zip_url, zip_out)

    if not ok:

        print(f"not_ready_char_id={char_id} character_id={character_id}", flush=True)

        return 1



    subprocess.check_call([

        sys.executable,

        "engine/tools/pixellab_import.py",

        str(zip_out),

        "--name",

        char_id,

        "--variant",

        "pixellab",

        "--force",

    ])

    _ensure_character_tres(char_id, str(job.get("name") or char_id))

    asset_dir = Path("assets") / "characters" / char_id / "pixellab"

    score = _score_rotation_png(asset_dir / "rotations" / "south.png")

    job["imported_at"] = int(time.time())

    job["asset_dir"] = asset_dir.as_posix()

    job["qa_score"] = float(score)

    _write_job(char_id, job)

    print(f"imported=assets/characters/{char_id}/pixellab", flush=True)

    print(f"qa_score={score:.2f}", flush=True)

    return 0





def cmd_import_pending(client: McpClient) -> int:

    jobs = sorted(_jobs_dir().glob("*.json"))

    imported = 0

    pending = 0

    for job_path in jobs:

        char_id = job_path.stem

        rc = cmd_import(client, char_id)

        if rc == 0:

            imported += 1

        else:

            pending += 1

    print(f"imported_count={imported} pending_count={pending}", flush=True)

    return 0





def _copytree_overwrite(src: Path, dst: Path) -> None:

    import shutil



    if dst.exists():

        shutil.rmtree(dst)

    shutil.copytree(src, dst)





def cmd_generate_best(

    client: McpClient,

    base_id: str,

    name: str,

    description: str,

    preset: str,

    lore: str | None,

    style: str | None,

    shape: str | None,

    tries: int,

    timeout_s: int,

    interval_s: int,

    no_animations: bool,

    min_score: float,

) -> int:

    base_id = base_id.strip()

    tries = max(1, int(tries))

    min_score = float(min_score)

    timeout_per = max(300, int(timeout_s) // tries)

    imported: list[tuple[str, float]] = []



    for i in range(tries):

        vid = f"{base_id}__v{i+1}"

        cmd_submit(client, vid, f"{name} v{i+1}", description, preset, no_animations, lore=lore, style=style, shape=shape)



        started = time.time()

        while time.time() - started < timeout_per:

            rc = cmd_import(client, vid)

            if rc == 0:

                job = _read_job(vid)

                score = float(job.get("qa_score") or 0.0)

                imported.append((vid, score))

                print(f"candidate={vid} qa_score={score:.2f}", flush=True)

                break

            _sleep_heartbeat(max(1, int(interval_s)), "generate_poll")



    if not imported:

        raise TimeoutError("Nenhum candidato importado dentro do timeout")



    imported.sort(key=lambda x: x[1], reverse=True)

    best_id, best_score = imported[0]



    src = Path("assets") / "characters" / best_id / "pixellab"

    dst = Path("assets") / "characters" / base_id / "pixellab"

    _copytree_overwrite(src, dst)

    _ensure_character_tres(base_id, str(name or base_id))

    print(f"best_variant={best_id}", flush=True)

    print(f"best_score={best_score:.2f}", flush=True)

    print(f"published=assets/characters/{base_id}/pixellab", flush=True)



    if min_score > 0 and best_score < min_score:

        print(f"warning=best_score_below_threshold threshold={min_score:.2f}", flush=True)

    return 0





def cmd_publish_best(base_id: str, tries: int) -> int:

    base_id = base_id.strip()

    tries = max(1, int(tries))

    imported: list[tuple[str, float]] = []

    for i in range(tries):

        vid = f"{base_id}__v{i+1}"

        try:

            job = _read_job(vid)

        except Exception:

            continue

        score = float(job.get("qa_score") or 0.0)

        asset_dir = Path("assets") / "characters" / vid / "pixellab"

        if not asset_dir.exists():

            continue

        imported.append((vid, score))



    if not imported:

        raise RuntimeError("Nenhuma variação importada encontrada para publicar")



    imported.sort(key=lambda x: x[1], reverse=True)

    best_id, best_score = imported[0]

    src = Path("assets") / "characters" / best_id / "pixellab"

    dst = Path("assets") / "characters" / base_id / "pixellab"

    _copytree_overwrite(src, dst)

    _ensure_character_tres(base_id, base_id)

    print(f"best_variant={best_id}", flush=True)

    print(f"best_score={best_score:.2f}", flush=True)

    print(f"published=assets/characters/{base_id}/pixellab", flush=True)

    return 0





def cmd_submit_batch(

    client: McpClient,

    base_id: str,

    name: str,

    description: str,

    preset: str,

    lore: str | None,

    style: str | None,

    styles: str | None,

    shape: str | None,

    shapes: str | None,

    count: int,

    no_animations: bool,

) -> int:

    base_id = base_id.strip()

    count = max(1, int(count))

    style_list = [

        s.strip()

        for s in re.split(r"[|,]", (styles or "").strip())

        if s.strip()

    ]

    shape_list = [

        s.strip()

        for s in re.split(r"[|,]", (shapes or "").strip())

        if s.strip()

    ]

    ids: list[str] = []

    for i in range(count):

        vid = f"{base_id}__v{i+1}"

        ids.append(vid)

        chosen_style = style_list[i % len(style_list)] if style_list else style

        chosen_shape = shape_list[i % len(shape_list)] if shape_list else shape

        cmd_submit(

            client,

            vid,

            f"{name} v{i+1}",

            description,

            preset,

            no_animations,

            lore=lore,

            style=chosen_style,

            shape=chosen_shape,

        )

    print(f"submitted_count={len(ids)}", flush=True)

    return 0





def cmd_import_batch(

    client: McpClient,

    base_id: str,

    count: int,

    timeout_s: int,

    interval_s: int,

) -> int:

    base_id = base_id.strip()

    count = max(1, int(count))

    timeout_s = max(1, int(timeout_s))

    interval_s = max(1, int(interval_s))



    ids = [f"{base_id}__v{i+1}" for i in range(count)]

    pending = set(ids)

    started = time.time()

    imported: list[str] = []

    while pending and time.time() - started < timeout_s:

        progressed = False

        for vid in list(sorted(pending)):

            try:

                rc = cmd_import(client, vid)

            except FileNotFoundError:

                rc = 1

            if rc == 0:

                pending.remove(vid)

                imported.append(vid)

                progressed = True

        if pending and not progressed:

            _sleep_heartbeat(interval_s, "import_batch")



    print(f"imported_count={len(imported)}", flush=True)

    print(f"pending_count={len(pending)}", flush=True)

    if pending:

        for vid in sorted(pending):

            print(f"pending={vid}", flush=True)

        return 2

    return 0





def _decode_b64(data: str, out_path: Path) -> None:

    out_path.parent.mkdir(parents=True, exist_ok=True)

    out_path.write_bytes(base64.b64decode(data))





def cmd_list_tools(client: McpClient) -> int:

    tools = client.tools_list()

    for t in tools:

        print(t.get("name"))

    return 0





def cmd_tool_schema(client: McpClient, tool_name: str) -> int:

    tools = client.tools_list()

    for t in tools:

        if t.get("name") == tool_name:

            print(json.dumps(t, indent=2, ensure_ascii=False))

            return 0

    print(f"Tool não encontrada: {tool_name}")

    return 2





def cmd_get_character(client: McpClient, character_id: str) -> int:

    res = client.tools_call("get_character", {"character_id": character_id}, 99)

    text = _result_text(res)

    print(text or json.dumps(res, indent=2, ensure_ascii=False))

    return 0





def _poll_character_ready(client: McpClient, character_id: str, timeout_s: int) -> dict[str, Any]:

    started = time.time()

    call_id = 300

    while True:

        res = client.tools_call("get_character", {"character_id": character_id}, call_id)

        call_id += 1

        text = _result_text(res)

        if "Status:" in text and "Processing" in text:

            pass



        needed = {

            "walk",

            "running",

            "dash_magic",

            "aiming",

            "jumping-1",

            "jumping-2",

            "throw-object",

            "lead-jab",

            "taking-punch",

            "falling-back-death",

            "roundhouse-kick",

        }

        present = set()

        for line in text.splitlines():

            line = line.strip()

            if line.startswith("-") and "(" in line and "]" in line:

                continue

            if line.startswith("-"):

                name = line.lstrip("- ").strip()

                name = name.split("(", 1)[0].strip()

                if name:

                    present.add(name)

        if "**Animations:**" in text and "None yet" not in text and needed.issubset(present):

            return {"result": res, "text": text}

        if time.time() - started >= timeout_s:

            raise TimeoutError("Timeout esperando personagem ficar pronto")

        time.sleep(10)





def cmd_create_and_import(

    client: McpClient,

    char_id: str,

    name: str,

    description: str,

    timeout_s: int,

    preset_name: str,

    no_animations: bool,

    lore: str | None = None,

    style: str | None = None,

    shape: str | None = None,

) -> int:

    preset_name = (preset_name or "").strip() or "premium_side_128"

    preset = PRESETS.get(preset_name, PRESETS["premium_side_128"])

    base = _apply_lore(_sanitize_description(description), lore)

    desc = _build_description(

        base,

        preset,

        seed=f"{char_id}:{name}",

        lore_key=str(lore or ""),

        style_key=str(style or ""),

        shape_key=str(shape or ""),

    )

    create_args: dict[str, Any] = {

        "description": desc,

        "name": name,

        "n_directions": int(preset.get("n_directions", 8)),

        "size": int(preset.get("size", 128)),

        "view": str(preset.get("view", "side")),

        "outline": preset.get("outline"),

        "shading": preset.get("shading"),

        "detail": preset.get("detail"),

        "ai_freedom": float(preset.get("ai_freedom", 250)),

        "proportions": _custom_proportions(f"{char_id}:{name}")

        if preset.get("auto_custom_proportions")

        else str(preset.get("proportions")),

    }

    created_id = _create_character_with_retry(client, create_args, timeout_s=900)

    print(f"character_id={created_id}")



    animation_jobs: list[dict[str, Any]] = []

    if not no_animations:

        animation_jobs = [

            {

                "animation_name": "walk",

                "template_animation_id": "walking-6-frames",

                "action_description": "walk cycle, readable footwork, steady posture",

            },

            {

                "animation_name": "running",

                "template_animation_id": "running-8-frames",

                "action_description": "run cycle, energetic but controlled, readable silhouette",

            },

            {

                "animation_name": "dash_magic",

                "template_animation_id": "running-slide",

                "action_description": "fast dash, low body, strong forward motion, brief afterimage feel",

            },

            {

                "animation_name": "aiming",

                "template_animation_id": "fight-stance-idle-8-frames",

                "action_description": "aiming stance, steady and readable, minimal movement",

            },

            {

                "animation_name": "jumping-1",

                "template_animation_id": "jumping-1",

                "action_description": "jump start, quick takeoff, readable pose",

            },

            {

                "animation_name": "jumping-2",

                "template_animation_id": "jumping-2",

                "action_description": "jump in air, floating pose, readable silhouette",

            },

            {

                "animation_name": "throw-object",

                "template_animation_id": "throw-object",

                "action_description": "shooting / throwing motion, clean readable arc",

            },

            {

                "animation_name": "lead-jab",

                "template_animation_id": "lead-jab",

                "action_description": "quick melee strike, sharp readable motion",

            },

            {

                "animation_name": "taking-punch",

                "template_animation_id": "taking-punch",

                "action_description": "hurt reaction, readable impact pose",

            },

            {

                "animation_name": "falling-back-death",

                "template_animation_id": "falling-back-death",

                "action_description": "death fall, readable collapse",

            },

            {

                "animation_name": "roundhouse-kick",

                "template_animation_id": "roundhouse-kick",

                "action_description": "ultimate attack, big readable motion",

            },

        ]



    toolset = {t.get("name"): t for t in client.tools_list()}

    anim_schema = toolset.get("animate_character", {})

    enums = (((anim_schema.get("inputSchema") or {}).get("properties") or {}).get("template_animation_id") or {}).get(

        "description", ""

    )

    allowed = set()

    m = re.search(r"Available: `(.+)`$", str(enums))

    if m:

        allowed = set(x.strip() for x in m.group(1).split("`, `"))

    for idx, job in enumerate(animation_jobs):

        templ = job["template_animation_id"]

        if allowed and templ not in allowed:

            continue

        try:

            client.tools_call(

                "animate_character",

                {

                    "character_id": created_id,

                    "template_animation_id": templ,

                    "action_description": job["action_description"],

                    "animation_name": job["animation_name"],

                },

                20 + idx,

            )

            print(f"queued_animation={job['animation_name']} template={templ}")

        except Exception as e:

            print(f"queue_failed={job['animation_name']} template={templ} error={e}")



    preview = client.tools_call("get_character", {"character_id": created_id}, 150)

    preview_text = _result_text(preview)

    if preview_text:

        lines = preview_text.splitlines()

        print("status_preview_begin")

        for line in lines[:35]:

            print(line)

        print("status_preview_end")



    ready = _poll_character_ready(client, created_id, timeout_s=timeout_s) if animation_jobs else {"result": preview, "text": preview_text}

    zip_url = f"https://api.pixellab.ai/mcp/characters/{created_id}/download"



    zip_out = Path("engine") / "tools" / "_cache" / "pixellab_jobs" / "pixellab" / f"{char_id}.zip"

    _download_zip_when_ready(zip_url, zip_out, timeout_s=timeout_s)



    subprocess.check_call([

        "python",

        "engine/tools/pixellab_import.py",

        str(zip_out),

        "--name",

        char_id,

        "--variant",

        "pixellab",

        "--force",

    ])

    print(f"imported=assets/characters/{char_id}/pixellab")

    return 0





def main() -> None:

    parser = argparse.ArgumentParser()

    sub = parser.add_subparsers(dest="cmd", required=True)



    sub.add_parser("list-tools")



    sub.add_parser("list-presets")

    sub.add_parser("list-lore")

    sch = sub.add_parser("tool-schema")

    sch.add_argument("--tool", required=True)



    getc = sub.add_parser("get-character")

    getc.add_argument("--character-id", required=True)



    sub.add_parser("list-styles")

    sub.add_parser("list-shapes")



    submit = sub.add_parser("submit")

    submit.add_argument("--id", required=True)

    submit.add_argument("--name", required=True)

    submit.add_argument("--description", required=True)

    submit.add_argument("--preset", default="premium_side_128")

    submit.add_argument("--lore", default="")

    submit.add_argument("--style", default="")

    submit.add_argument("--shape", default="")

    submit.add_argument("--no-animations", action="store_true")



    imp = sub.add_parser("import")

    imp.add_argument("--id", required=True)



    sub.add_parser("import-pending")



    watch = sub.add_parser("import-watch")

    watch.add_argument("--id", required=True)

    watch.add_argument("--timeout", type=int, default=1800)

    watch.add_argument("--interval", type=int, default=20)



    gen = sub.add_parser("generate")

    gen.add_argument("--id", required=True)

    gen.add_argument("--name", required=True)

    gen.add_argument("--description", required=True)

    gen.add_argument("--preset", default="premium_side_128")

    gen.add_argument("--lore", default="")

    gen.add_argument("--style", default="")

    gen.add_argument("--shape", default="")

    gen.add_argument("--tries", type=int, default=3)

    gen.add_argument("--timeout", type=int, default=2400)

    gen.add_argument("--interval", type=int, default=20)

    gen.add_argument("--no-animations", action="store_true")

    gen.add_argument("--min-score", type=float, default=0.0)



    sb = sub.add_parser("submit-batch")

    sb.add_argument("--id", required=True)

    sb.add_argument("--name", required=True)

    sb.add_argument("--description", required=True)

    sb.add_argument("--preset", default="premium_side_128")

    sb.add_argument("--lore", default="")

    sb.add_argument("--style", default="")

    sb.add_argument("--styles", default="")

    sb.add_argument("--shape", default="")

    sb.add_argument("--shapes", default="")

    sb.add_argument("--count", type=int, default=10)

    sb.add_argument("--no-animations", action="store_true")



    ib = sub.add_parser("import-batch")

    ib.add_argument("--id", required=True)

    ib.add_argument("--count", type=int, default=10)

    ib.add_argument("--timeout", type=int, default=2400)

    ib.add_argument("--interval", type=int, default=20)



    cc = sub.add_parser("create-import")

    cc.add_argument("--id", required=True)

    cc.add_argument("--name", required=True)

    cc.add_argument("--description", required=True)

    cc.add_argument("--timeout", type=int, default=1800)

    cc.add_argument("--preset", default="premium_side_128")

    cc.add_argument("--lore", default="")

    cc.add_argument("--style", default="")

    cc.add_argument("--shape", default="")

    cc.add_argument("--no-animations", action="store_true")



    pub = sub.add_parser("publish-best")

    pub.add_argument("--id", required=True)

    pub.add_argument("--tries", type=int, default=3)



    args = parser.parse_args()



    if args.cmd in {"create-import", "submit", "generate", "submit-batch"}:

        args.name = str(args.name).replace("+", " ")

        args.description = str(args.description).replace("+", " ")

    url, auth = _load_pixellab_auth()

    client = McpClient(url=url, authorization=auth)

    client.initialize()



    if args.cmd == "list-tools":

        raise SystemExit(cmd_list_tools(client))

    if args.cmd == "list-presets":

        for k in sorted(PRESETS.keys()):

            print(k)

        return

    if args.cmd == "list-lore":

        for k in sorted(LORE_PACKS.keys()):

            print(k)

        return

    if args.cmd == "list-styles":

        print("mix")

        for k in sorted(STYLE_PACKS.keys()):

            print(k)

        return

    if args.cmd == "list-shapes":

        print("mix")

        for k in sorted(SHAPE_PACKS.keys()):

            print(k)

        return

    if args.cmd == "tool-schema":

        raise SystemExit(cmd_tool_schema(client, args.tool))

    if args.cmd == "get-character":

        raise SystemExit(cmd_get_character(client, args.character_id))

    if args.cmd == "submit":

        raise SystemExit(

            cmd_submit(

                client,

                args.id,

                args.name,

                args.description,

                args.preset,

                bool(args.no_animations),

                lore=str(args.lore or ""),

                style=str(args.style or ""),

                shape=str(args.shape or ""),

            )

        )

    if args.cmd == "import":

        raise SystemExit(cmd_import(client, args.id))

    if args.cmd == "import-pending":

        raise SystemExit(cmd_import_pending(client))

    if args.cmd == "import-watch":

        started = time.time()

        while time.time() - started < int(args.timeout):

            rc = cmd_import(client, args.id)

            if rc == 0:

                raise SystemExit(0)

            _sleep_heartbeat(max(1, int(args.interval)), "import_watch")

        raise SystemExit(2)

    if args.cmd == "generate":

        raise SystemExit(

            cmd_generate_best(

                client,

                args.id,

                args.name,

                args.description,

                args.preset,

                str(args.lore or ""),

                str(args.style or ""),

                str(args.shape or ""),

                int(args.tries),

                int(args.timeout),

                int(args.interval),

                bool(args.no_animations),

                float(args.min_score),

            )

        )

    if args.cmd == "submit-batch":

        raise SystemExit(

            cmd_submit_batch(

                client,

                args.id,

                args.name,

                args.description,

                args.preset,

                str(args.lore or ""),

                str(args.style or ""),

                str(args.styles or ""),

                str(args.shape or ""),

                str(args.shapes or ""),

                int(args.count),

                bool(args.no_animations),

            )

        )

    if args.cmd == "import-batch":

        raise SystemExit(

            cmd_import_batch(

                client,

                args.id,

                int(args.count),

                int(args.timeout),

                int(args.interval),

            )

        )

    if args.cmd == "create-import":

        raise SystemExit(

            cmd_create_and_import(

                client,

                args.id,

                args.name,

                args.description,

                args.timeout,

                args.preset,

                bool(args.no_animations),

                lore=str(args.lore or ""),

                style=str(args.style or ""),

                shape=str(args.shape or ""),

            )

        )

    if args.cmd == "publish-best":

        raise SystemExit(cmd_publish_best(args.id, int(args.tries)))





if __name__ == "__main__":

    main()

