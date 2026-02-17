# Prompts Runeterra-inspirados (para sprites PixelLab)



Objetivo: gerar personagens **originais** com “DNA visual” forte, inspirados em regiões/temas de Runeterra (LoL) sem copiar campeões específicos.



## Regra de ouro (anti-genérico)



Sempre inclua:



- 1 **prop assinatura** (arma/artefato)

- 1 **emblema** (símbolo/heráldica/totem)

- 1 **assimetria** (um ombro/luva/capa diferente)

- 1 **material** bem descrito (aço polido, couro gasto, jade, quitina, etc.)

- 1 **efeito** discreto (brilho, fumaça, areia, névoa, faíscas)



Formato recomendado para `--description`:



`<classe>, <prop assinatura>, <emblema>, <assimetria>, <materiais>, <paleta>, <efeito>, <traço de rosto>`



## Lore packs prontos (use com `--lore`)



`demacia`, `noxus`, `piltover`, `zaun`, `ionia`, `shurima`, `freljord`, `shadow_isles`, `targon`, `bilgewater`, `ixtal`, `void`



Exemplo:



`python engine/tools/pixellab_pipeline.py generate --id noxus_reaper --name Reaper --description executioner+with+two-handed+axe,+black+iron+mask,+torn+crimson+cape,+war+banner+sigil,+scarred+face --preset iconic_side_128 --lore noxus --tries 3 --no-animations`



## Prompts (copiar e colar)



### Demacia (radiant high fantasy)



- Paladino Juramentado: `paladin+knight, radiant+steel+halberd, lion+heraldry+cloak+emblem, single+golden+pauldron, polished+steel+and+white+tabard, blue+and+gold+palette, subtle+holy+glow, stern+face+with+scar`

- Caçadora de Magos: `elite+hunter, anti-magic+chains+weapon, crest+brooch+emblem, asymmetrical+hood+and+shoulder+cape, leather+straps+and+steel+plates, white+blue+muted, faint+anti-magic+spark, focused+eyes`



### Noxus (brutal empire)



- Executor: `executioner, massive+two-handed+axe, crimson+war+sigil+on+banner, single+spiked+pauldron, dark+iron+and+scarlet+cloth, black+red+palette, dust+and+embers, grim+face`

- Gladiadora de Arena: `arena+fighter, hooked+spear, iron+ring+emblem+on+belt, one+arm+armored+one+arm+bare, dark+steel+and+leather, red+accents, sweat+shine, confident+smirk`



### Piltover (clean hextech)



- Inventor Hextech: `hextech+inventor, gauntlet+with+blue+hex-crystal, cog+emblem+pin, one+mechanical+bracer, brass+and+tailored+coat, blue+gold+palette, clean+spark+particles, bright+eyes`

- Atiradora de Precisão: `markswoman, long+rifle+with+hextech+core, city+crest+badge, asymmetrical+shoulder+holster, polished+leather+and+brass, teal+blue+accents, thin+energy+trails, calm+expression`



### Zaun (chemtech grime)



- Alquimista Mutante: `chemtech+alchemist, backpack+with+green+vials, hazard+symbol+emblem, respirator+mask+and+one+metal+arm, patched+cloth+and+rusty+metal, sickly+green+palette, toxic+smoke, tired+eyes`

- Caçador Subterrâneo: `undercity+hunter, chain+hook+weapon, graffiti+tag+emblem, one+shoulder+pad+one+bare, oily+leather+and+scrap+metal, dark+green+accents, neon+glow, sharp+gaze`



### Ionia (spirit + martial)



- Espadachim Espiritual: `spirit+swordsman, curved+blade+with+paper+talisman, blossom+charm+emblem, asymmetrical+flowing+sleeve, silk+wraps+and+wood, pastel+pink+teal, drifting+petals, serene+eyes`

- Monge Guardião: `monk+guardian, staff+with+spirit+bead, temple+seal+emblem, one+arm+bandaged+one+arm+braced, cloth+wraps+and+bronze, soft+warm+palette, subtle+aura, calm+face`



### Shurima (ancient desert)



- Mago das Areias: `sand+mage, sun-disc+staff, golden+scarab+emblem, one+shoulder+gold+plate, linen+wraps+and+gold+ornaments, warm+gold+palette, swirling+sand, glowing+eyes`

- Guardião de Ruínas: `desert+sentinel, khopesh+blade, sun-disc+crest+emblem, asymmetrical+cape+torn, sandstone+armor+and+gold, ochre+palette, dust+trail, stoic+face`



### Freljord (ice + tribal)



- Berserker do Gelo: `ice+berserker, huge+ice+axe, bear+totem+emblem, one+fur+pauldron, fur+and+rough+leather+and+ice, cold+blue+palette, breath+mist, fierce+eyes`

- Xamã das Runas: `rune+shaman, staff+with+ice+crystal, carved+rune+stone+emblem, asymmetrical+antler+helm, fur+robes+and+bone, icy+blue+white, faint+runic+glow, weathered+face`



### Shadow Isles (cursed undead)



- Cavaleiro Espectral: `spectral+knight, corroded+sword+with+chains, ruined+crest+emblem, one+broken+shoulder+plate, rusted+armor+and+torn+shroud, green+ghostly+palette, black+mist, hollow+eyes`

- Necromante Errante: `necromancer, lantern+with+souls, skull+seal+emblem, asymmetrical+ragged+cloak, decayed+cloth+and+bone, dark+green+glow, drifting+wisps, masked+face`



### Targon (celestial)



- Guardiã Estelar: `celestial+warrior, spear+with+starlight+tip, constellation+emblem+on+cape, one+armored+gauntlet, bronze+gold+armor+and+cloth, deep+blue+gold, cosmic+sparkles, determined+eyes`

- Oráculo Lunar: `moon+oracle, crescent+blade+or+staff, moon+sigil+emblem, asymmetrical+hood, silver+and+cloth, violet+blue+palette, soft+moon+glow, calm+face`



### Bilgewater (pirate)



- Caçador de Monstros Marinhos: `sea+monster+hunter, harpoon+gun, shark-tooth+emblem, one+hook+hand, weathered+leather+and+rope, navy+brown+palette, sea+spray, scarred+grin`

- Pistoleira do Porto: `pirate+gunslinger, dual+pistols, anchor+emblem+badge, asymmetrical+coat+tails, salt-stained+coat+and+leather, dark+teal+red, smoke+puffs, confident+smirk`



### Ixtal (jungle elemental)



- Guardião de Jade: `jungle+guardian, obsidian+blade, serpent+glyph+emblem, one+feathered+pauldron, jade+and+obsidian+and+cloth, green+gold+palette, leaf+swirl, focused+eyes`

- Elementalista da Selva: `elementalist, staff+with+gem+core, sun+glyph+emblem, asymmetrical+vine+wraps, stone+jewelry+and+silk, emerald+palette, subtle+wind+or+water+effect, calm+face`



### Void (alien horror)



- Predador Quitinoso: `void+predator, scythe+claws, distorted+rune+emblem, asymmetrical+spikes, chitin+plates, purple+magenta+palette, bioluminescent+glow, menacing+eyes`

- Cultista Corrompido: `void+cultist, jagged+staff, void+sigil+emblem, one+mutated+arm, torn+robes+and+chitin+growths, dark+purple, leaking+energy, masked+face`



## Fontes (visão geral de inspiração regional)



- Discussão comunitária sobre inspirações culturais/estéticas por região (Demacia/Noxus/Piltover/Zaun/Targon/Ixtal/Freljord/Bilgewater): https://www.reddit.com/r/loreofleague/comments/w1lcsh/runeterras_regions_inspiration/

- Discussão comunitária semelhante (contexto adicional): https://www.reddit.com/r/loreofleague/comments/rdb2gb/does_anyone_know_which_realworld_cultures_the/



