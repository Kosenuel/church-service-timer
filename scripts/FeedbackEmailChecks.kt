import org.kosenuel.cuekeeper.FeedbackEmail
import java.net.URLDecoder

fun main() {
    val subject = "Timer & mode + Réponse?"
    val body = "Contact: operator@example.com\nMessage: a+b &bcc=other@example.com #tag 🙏"
    val uri = FeedbackEmail.uri(subject, body)
    check(uri.startsWith("mailto:kosenuel@gmail.com?"))
    val pairs = uri.substringAfter('?').split('&').associate { val p = it.split('=', limit = 2); p[0] to URLDecoder.decode(p[1], "UTF-8") }
    check(pairs == mapOf("subject" to subject, "body" to body))
    check(!uri.contains('+') && !uri.contains('\n') && !uri.contains('#'))
    check(runCatching { FeedbackEmail.uri("Title\nBcc: other@example.com", body) }.isFailure)
    check(runCatching { FeedbackEmail.uri("a".repeat(513), body) }.isFailure)
    check(runCatching { FeedbackEmail.uri(subject, "x".repeat(12001)) }.isFailure)
    println("6 email hand-off encoding and validation checks passed.")
}
