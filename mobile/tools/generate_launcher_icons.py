from PIL import Image
from pathlib import Path

src = Path(r"c:\Users\ganta\OneDrive\Desktop\Marketing-Exectives\mobile\assets\branding\app_icon.png")
img = Image.open(src).convert("RGBA")

android = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
base = Path(r"c:\Users\ganta\OneDrive\Desktop\Marketing-Exectives\mobile\android\app\src\main\res")
for folder, size in android.items():
    out = base / folder / "ic_launcher.png"
    resized = img.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(out, "PNG")
    print("wrote", out)

# iOS common sizes if assets exist
ios_dir = Path(r"c:\Users\ganta\OneDrive\Desktop\Marketing-Exectives\mobile\ios\Runner\Assets.xcassets\AppIcon.appiconset")
ios_sizes = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}
if ios_dir.exists():
    for name, size in ios_sizes.items():
        out = ios_dir / name
        img.resize((size, size), Image.Resampling.LANCZOS).save(out, "PNG")
        print("wrote", out)

master = Path(r"c:\Users\ganta\OneDrive\Desktop\Marketing-Exectives\mobile\assets\branding\app_icon_1024.png")
img.resize((1024, 1024), Image.Resampling.LANCZOS).save(master, "PNG")
print("done")
