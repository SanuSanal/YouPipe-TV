package com.youpipe.tv

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Google's own sign-in page in a WebView, landing on youtube.com (docs/account.md). The user types their credentials
 * into Google's page with the remote; once youtube.com loads, the activity hands back the session cookie, which
 * CookieManager can read although the auth cookies are HttpOnly. Back steps back in the page, then cancels.
 */
class SignInActivity : Activity() {
    private lateinit var web: WebView
    private var done = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CookieManager.getInstance().setAcceptCookie(true)
        web = WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            setBackgroundColor(Color.WHITE)
            CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
            webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) = check(url)
            }
        }
        val hint = TextView(this).apply {
            text = "Sign in to YouTube on Google's page. Press Back to cancel."
            textSize = 16f
            setTextColor(Color.parseColor("#F1F1F1"))
            setBackgroundColor(Color.parseColor("#0F0F0F"))
            gravity = Gravity.CENTER_VERTICAL
            setPadding(48, 20, 48, 20)
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(hint, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            addView(web, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        })
        web.requestFocus()
        web.loadUrl(LOGIN_URL)
    }

    private fun check(url: String) {
        val host = Uri.parse(url).host ?: return
        if (done || (host != "www.youtube.com" && host != "m.youtube.com")) return
        val cookie = CookieManager.getInstance().getCookie("https://www.youtube.com") ?: return
        // Signed out, youtube.com loads without the SAPISID cookies; keep waiting.
        if (!cookie.contains("SAPISID=")) return
        done = true
        CookieManager.getInstance().flush()
        setResult(RESULT_OK, Intent().putExtra(EXTRA_COOKIE, cookie))
        finish()
    }

    @Deprecated("Activity.onBackPressed")
    override fun onBackPressed() {
        if (web.canGoBack()) web.goBack() else super.onBackPressed()
    }

    override fun onDestroy() {
        web.destroy()
        super.onDestroy()
    }

    companion object {
        const val EXTRA_COOKIE = "cookie"

        // The same page YouPipe opens on phones: Google's sign-in, continuing to youtube.com.
        private const val LOGIN_URL =
            "https://accounts.google.com/ServiceLogin?service=youtube&uilel=3&passive=true" +
                "&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26app%3Ddesktop%26hl%3Den" +
                "%26next%3Dhttps%253A%252F%252Fwww.youtube.com%252F&hl=en"
    }
}
