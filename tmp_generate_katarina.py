from pathlib import Path
from PIL import Image

SRC = Path(r"C:\Users\user\Desktop\Assets\Katarina\Katarina standing_raw.jpg")
DEST = Path(r"C:\Users\user\CascadeProjects\Project PVP\assets\characters\katarina\katarina_standing.tres")

img = Image.open(SRC).convert("RGBA")
max_height = 512
if img.height > max_height:
    ratio = max_height / img.height
    new_size = (int(img.width * ratio), max_height)
    img = img.resize(new_size, Image.Resampling.LANCZOS)

data = ", ".join(str(b) for b in img.tobytes())
content = f"""[gd_resource type=\"ImageTexture\" load_steps=2 format=3]

[sub_resource type=\"Image\" id=\"Image_1\"]
data = {{
\"data\": PackedByteArray({data}),
\"format\": \"RGBA8\",
\"height\": {img.height},
\"mipmaps\": false,
\"width\": {img.width}
}}

[resource]
image = SubResource(\"Image_1\")
"""
DEST.write_text(content)
print("Wrote", DEST)
