from pathlib import Path
from PIL import Image

SRC = Path(r"C:\Users\user\Desktop\Assets\Katarina\Katarina standing_raw.jpg")
DEST_DIR = Path(r"C:\Users\user\CascadeProjects\Project PVP\assets\characters\katarina")
PNG_OUT = DEST_DIR / "katarina_clean.png"
TRES_OUT = DEST_DIR / "katarina_clean.tres"

bg_color = (167, 167, 167)
tolerance = 12

img = Image.open(SRC).convert("RGBA")
pixels = img.load()
width, height = img.size

for y in range(height):
    for x in range(width):
        r, g, b, a = pixels[x, y]
        if abs(r - bg_color[0]) <= tolerance and abs(g - bg_color[1]) <= tolerance and abs(b - bg_color[2]) <= tolerance:
            pixels[x, y] = (r, g, b, 0)

bbox = img.getbbox()
if bbox:
    img = img.crop(bbox)

max_height = 512
if img.height > max_height:
    ratio = max_height / img.height
    img = img.resize((int(img.width * ratio), max_height), Image.Resampling.LANCZOS)

img.save(PNG_OUT)

raw = img.tobytes()
byte_list = ", ".join(str(b) for b in raw)
content = f"""[gd_resource type=\"ImageTexture\" load_steps=2 format=3]

[sub_resource type=\"Image\" id=\"Image_1\"]
data = {{
\"data\": PackedByteArray({byte_list}),
\"format\": \"RGBA8\",
\"height\": {img.height},
\"mipmaps\": false,
\"width\": {img.width}
}}

[resource]
image = SubResource(\"Image_1\")
"""
TRES_OUT.write_text(content)
print("Generated", PNG_OUT, "and", TRES_OUT, "size", img.size)
