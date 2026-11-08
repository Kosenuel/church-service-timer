package org.kosenuel.churchservicetimer

import android.app.Activity
import android.content.Context
import android.print.PrintAttributes
import android.print.PrintManager
import android.print.PrintDocumentAdapter
import android.print.PageRange
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.webkit.WebView
import android.webkit.WebViewClient

class ServiceSheetPrinter {
    private var document: WebView? = null
    fun print(activity: Activity, name: String, html: String) {
        require(html.length <= 2_000_000)
        check(document == null) { "Finish the current print job first" }
        val view = WebView(activity)
        document = view
        view.settings.javaScriptEnabled = false
        view.settings.allowFileAccess = false
        view.settings.allowContentAccess = false
        view.settings.blockNetworkLoads = true
        view.webViewClient = object : WebViewClient() {
            private var submitted = false
            override fun onPageFinished(webView: WebView, url: String) {
                if (submitted) return
                if (activity.isFinishing) { document = null; webView.destroy(); return }
                submitted = true
                val manager = activity.getSystemService(Context.PRINT_SERVICE) as PrintManager
                val delegate = webView.createPrintDocumentAdapter(name)
                val adapter = object : PrintDocumentAdapter() {
                    override fun onStart() = delegate.onStart()
                    override fun onLayout(old: PrintAttributes?, next: PrintAttributes?, signal: CancellationSignal?, callback: LayoutResultCallback?, extras: Bundle?) = delegate.onLayout(old, next, signal, callback, extras)
                    override fun onWrite(pages: Array<out PageRange>?, destination: ParcelFileDescriptor?, signal: CancellationSignal?, callback: WriteResultCallback?) = delegate.onWrite(pages, destination, signal, callback)
                    override fun onFinish() { delegate.onFinish(); document = null; webView.destroy() }
                }
                manager.print(name, adapter, PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A4).build())
            }
        }
        view.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
    }
}
