extends RefCounted # Generates the generic human NPC's complete two-dimensional character texture at runtime without any 3D character model assets.
class_name GenericHumanBillboardTexture # Exposes deterministic reusable texture construction for the generic human billboard actor.

const TEXTURE_WIDTH: int = 48 # Defines the horizontal source resolution used by the low-resolution human character texture.
const TEXTURE_HEIGHT: int = 80 # Defines the vertical source resolution used by the complete head-to-foot human silhouette.
const TRANSPARENT: Color = Color(0.0, 0.0, 0.0, 0.0) # Defines fully transparent background pixels around the character silhouette.
const OUTLINE: Color = Color(0.055, 0.045, 0.04, 1.0) # Defines the dark silhouette edge that keeps the human readable against varied world backgrounds.
const HAIR: Color = Color(0.13, 0.085, 0.045, 1.0) # Defines the generic character's dark brown hair colour.
const SKIN: Color = Color(0.72, 0.50, 0.34, 1.0) # Defines the generic character's skin tone for face, neck, and hands.
const SHIRT: Color = Color(0.28, 0.36, 0.42, 1.0) # Defines the muted blue-grey upper garment colour.
const SHIRT_SHADOW: Color = Color(0.19, 0.255, 0.31, 1.0) # Defines darker garment pixels that give the flat billboard some readable volume.
const TROUSERS: Color = Color(0.19, 0.18, 0.16, 1.0) # Defines the generic character's dark trouser colour.
const BOOTS: Color = Color(0.10, 0.075, 0.055, 1.0) # Defines the dark footwear used at the bottom of the silhouette.
const EYE: Color = Color(0.035, 0.03, 0.028, 1.0) # Defines the compact facial eye pixels.

static func create_texture() -> Texture2D: # Builds and returns one complete transparent pixel-art human texture suitable for a billboard material.
    var image: Image = Image.create(TEXTURE_WIDTH, TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8) # Allocates a small RGBA image whose transparent pixels can define the character silhouette.
    image.fill(TRANSPARENT) # Clears the complete source image so only explicitly drawn human pixels remain visible.
    _fill_rect(image, 17, 66, 6, 10, OUTLINE) # Draws the left boot outline at the bottom of the character silhouette.
    _fill_rect(image, 27, 66, 6, 10, OUTLINE) # Draws the right boot outline with matching proportions.
    _fill_rect(image, 18, 66, 5, 8, BOOTS) # Fills the left boot interior while retaining a dark edge around it.
    _fill_rect(image, 27, 66, 5, 8, BOOTS) # Fills the right boot interior while retaining its outline.
    _fill_rect(image, 17, 48, 7, 20, OUTLINE) # Draws the left trouser leg outline from hip to boot.
    _fill_rect(image, 26, 48, 7, 20, OUTLINE) # Draws the right trouser leg outline from hip to boot.
    _fill_rect(image, 18, 48, 6, 18, TROUSERS) # Fills the left trouser leg with the dark cloth colour.
    _fill_rect(image, 26, 48, 6, 18, TROUSERS) # Fills the right trouser leg with matching cloth.
    _fill_rect(image, 13, 28, 22, 23, OUTLINE) # Draws the complete torso and shoulder outline as one readable blocky silhouette.
    _fill_rect(image, 14, 29, 20, 20, SHIRT) # Fills the upper body with the generic muted shirt colour.
    _fill_rect(image, 14, 43, 20, 6, SHIRT_SHADOW) # Adds a darker lower-shirt band that separates torso from the trouser silhouette.
    _fill_rect(image, 8, 31, 7, 18, OUTLINE) # Draws the left arm outline hanging beside the torso.
    _fill_rect(image, 34, 31, 7, 18, OUTLINE) # Draws the right arm outline hanging beside the torso.
    _fill_rect(image, 9, 32, 5, 15, SHIRT) # Fills the left sleeve and arm garment area.
    _fill_rect(image, 35, 32, 5, 15, SHIRT) # Fills the right sleeve and arm garment area.
    _fill_rect(image, 9, 47, 5, 5, OUTLINE) # Draws a small dark border around the left hand.
    _fill_rect(image, 35, 47, 5, 5, OUTLINE) # Draws a matching border around the right hand.
    _fill_rect(image, 10, 47, 4, 4, SKIN) # Fills the left hand with skin colour.
    _fill_rect(image, 35, 47, 4, 4, SKIN) # Fills the right hand with skin colour.
    _fill_rect(image, 20, 24, 8, 6, OUTLINE) # Draws the neck outline connecting head and shirt.
    _fill_rect(image, 21, 24, 6, 5, SKIN) # Fills the visible neck area.
    _fill_rect(image, 15, 7, 18, 19, OUTLINE) # Draws the complete head silhouette and dark edge.
    _fill_rect(image, 16, 10, 16, 15, SKIN) # Fills the central face area with skin colour.
    _fill_rect(image, 15, 7, 18, 7, HAIR) # Draws the main top hair mass across the forehead and crown.
    _fill_rect(image, 15, 11, 4, 8, HAIR) # Extends hair down the left temple for a less geometric head shape.
    _fill_rect(image, 29, 10, 4, 8, HAIR) # Extends hair down the right temple symmetrically.
    _fill_rect(image, 20, 16, 2, 2, EYE) # Places the left eye as a compact dark pixel cluster.
    _fill_rect(image, 27, 16, 2, 2, EYE) # Places the right eye at the matching face height.
    _fill_rect(image, 23, 21, 4, 1, Color(0.34, 0.17, 0.12, 1.0)) # Adds a restrained mouth line so the generic face remains readable at close range.
    var texture: ImageTexture = ImageTexture.create_from_image(image) # Converts the completed transparent image into the runtime Texture2D consumed by the billboard material.
    return texture # Returns the generated character texture without introducing an authored 3D model or external character asset.

static func _fill_rect(image: Image, start_x: int, start_y: int, width: int, height: int, colour: Color) -> void: # Fills one clamped rectangular pixel region used to assemble the blocky human silhouette.
    var end_x: int = mini(start_x + width, image.get_width()) # Clamps the requested horizontal extent to valid image columns.
    var end_y: int = mini(start_y + height, image.get_height()) # Clamps the requested vertical extent to valid image rows.
    var safe_start_x: int = maxi(start_x, 0) # Prevents negative rectangle origins from indexing outside the image.
    var safe_start_y: int = maxi(start_y, 0) # Prevents negative vertical origins from indexing outside the image.
    for pixel_y: int in range(safe_start_y, end_y): # Visits every valid row belonging to the requested rectangle.
        for pixel_x: int in range(safe_start_x, end_x): # Visits every valid column belonging to the current rectangle row.
            image.set_pixel(pixel_x, pixel_y, colour) # Writes the requested colour directly into the deterministic source texture pixel.
