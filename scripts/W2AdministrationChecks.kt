import org.kosenuel.churchservicetimer.W2Administration as Admin

private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
private var checks = 0
private fun verify(value: Boolean) { check(value); checks++ }
private fun rejects(block: () -> Unit) {
    var rejected = false
    try { block() } catch (_: IllegalArgumentException) { rejected = true }
    verify(rejected)
}

fun main() {
    val exact: Map<String, Any> = mapOf("supported" to true, "firmware" to "HD_W2 V6.02.232", "pwdComplexity" to 1)
    verify(Admin.supported(exact))
    verify(!Admin.supported(exact - "pwdComplexity"))
    verify(!Admin.supported(exact + ("pwdComplexity" to 0)))
    verify(!Admin.supported(exact + ("pwdComplexity" to 2)))
    verify(!Admin.supported(exact + ("firmware" to "HD_W2 V6.02.233")))
    verify(!Admin.supported(exact + ("supported" to false)))
    verify(Admin.WIFI_COMMAND == 39 && Admin.DEVICE_PASSWORD_COMMAND == 49)
    verify(hex(Admin.ssidBody("TEST_WIFI")) == "0800000400000009544553545f57494649")
    verify(Admin.ssidBody("1234").size == 12)
    verify(Admin.ssidBody("ABCDEFGHIJKLMNOP").size == 24)
    rejects { Admin.ssidBody("abc") }
    rejects { Admin.ssidBody("A".repeat(17)) }
    rejects { Admin.ssidBody("TEST WIFI") }
    rejects { Admin.ssidBody("TÉST") }
    val password = "TestAB12".toCharArray()
    val wifi = Admin.wifiPasswordBody(password)
    verify(hex(wifi) == "08000005000000085465737441423132")
    val lock = Admin.devicePasswordBody(password)
    // Digest independently computed with Python hashlib from the recovered suffix.
    verify(hex(lock) == "04020010c41ed3c6c692541b5e3abd3f28840eb9")
    verify(password.contentEquals("TestAB12".toCharArray()))
    wifi.fill(0); lock.fill(0); password.fill('\u0000')
    for (invalid in listOf("", "short", "A".repeat(17), "aaaaaaaa", "abcdefgh", "98765432", "Test AB1", "Test\u0000AB1", "TéstAB12")) {
        rejects { Admin.devicePasswordBody(invalid.toCharArray()) }
        rejects { Admin.wifiPasswordBody(invalid.toCharArray()) }
    }
    verify(Admin.wifiPasswordBody("Test!AB12".toCharArray()).size == 17)
    println("W2 administration: $checks checks passed; no transport executed.")
}
