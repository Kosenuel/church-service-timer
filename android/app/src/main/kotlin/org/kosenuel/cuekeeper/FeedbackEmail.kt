package org.kosenuel.cuekeeper

import java.net.URLEncoder

/** An email composer hand-off, never a delivery receipt or background send. */
object FeedbackEmail {
    const val RECIPIENT = "kosenuel@gmail.com"
    fun uri(subject: String, body: String): String {
        require(subject.isNotBlank() && subject.length <= 512 && !subject.contains('\r') && !subject.contains('\n')) { "Invalid feedback title" }
        require(body.isNotBlank() && body.length <= 12000) { "Invalid feedback message" }
        fun encode(value: String) = URLEncoder.encode(value, "UTF-8").replace("+", "%20")
        return "mailto:$RECIPIENT?subject=${encode(subject)}&body=${encode(body)}"
    }
}
