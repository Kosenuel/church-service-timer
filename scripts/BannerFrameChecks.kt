import org.kosenuel.churchservicetimer.bannerFrame
import org.kosenuel.churchservicetimer.BannerFrame

fun main() {
    val cases = listOf(
        Triple(1200, 400, BannerFrame(0f, 0f, 600f, 200f)),
        Triple(400, 1200, BannerFrame(0f, -800f, 600f, 1000f)),
        Triple(800, 800, BannerFrame(0f, -200f, 600f, 400f)),
        Triple(2400, 400, BannerFrame(-300f, 0f, 900f, 200f)),
        Triple(60, 20, BannerFrame(0f, 0f, 600f, 200f))
    )
    for ((width, height, expected) in cases) {
        check(bannerFrame(width, height) == expected) { "Wrong centered crop for $width x $height" }
    }
    check(runCatching { bannerFrame(0, 200) }.isFailure)
    check(runCatching { bannerFrame(600, -1) }.isFailure)
    println("7 banner crop geometry checks passed.")
}
