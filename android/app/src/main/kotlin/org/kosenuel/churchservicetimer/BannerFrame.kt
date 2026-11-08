package org.kosenuel.churchservicetimer

data class BannerFrame(val left: Float, val top: Float, val right: Float, val bottom: Float)

/** Uniform scale then centered crop; neither axis is stretched independently. */
fun bannerFrame(width: Int, height: Int): BannerFrame {
    require(width > 0 && height > 0)
    val scale = maxOf(600f / width, 200f / height)
    val w = width * scale
    val h = height * scale
    return BannerFrame((600f - w) / 2f, (200f - h) / 2f, (600f + w) / 2f, (200f + h) / 2f)
}
