# Tile art

Reserved for the final tile artwork (later milestone).

The prototype draws its tiles in code (`scripts/puzzle/tile.gd`) using
StyleBoxFlat panels and a letter label, so no textures are required yet. When
real art arrives, `Tile.setup()` is the single place that needs to swap the
code-drawn placeholder for a texture.
