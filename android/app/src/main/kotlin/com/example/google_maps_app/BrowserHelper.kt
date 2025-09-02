package com.example.google_maps_app

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper

class BrowserHelper {
    companion object {
        private var currentActivity: Activity? = null

        fun setCurrentActivity(activity: Activity) {
            currentActivity = activity
        }

        fun closeInAppBrowser() {
            Handler(Looper.getMainLooper()).post {
                try {
                    // Try to finish the current activity
                    currentActivity?.let { activity ->
                        // Clear any WebView state if present
                        activity.findViewById<android.webkit.WebView>(android.R.id.content)?.let { webView ->
                            webView.stopLoading()
                            webView.loadUrl("about:blank")
                            webView.clearCache(true)
                            webView.clearHistory()
                            webView.evaluateJavascript("""
                                window.close();
                                window.location.href = 'about:blank';
                                history.pushState(null, '', 'about:blank');
                            """.trimIndent(), null)
                        }
                        
                        // Force finish all activities in the task
                        activity.finishAffinity()
                        activity.overridePendingTransition(0, 0)
                        
                        // Post delayed check to ensure activity is finished
                        Handler(Looper.getMainLooper()).postDelayed({
                            if (activity.isFinishing.not()) {
                                activity.finish()
                                activity.overridePendingTransition(0, 0)
                            }
                        }, 100)
                    }
                    
                    // Clear the reference
                    currentActivity = null
                } catch (e: Exception) {
                    android.util.Log.e("BrowserHelper", "Error closing browser: ${e.message}")
                    // Try one last time to finish the activity
                    try {
                        currentActivity?.finish()
                        currentActivity = null
                    } catch (e2: Exception) {
                        android.util.Log.e("BrowserHelper", "Final attempt to close browser failed: ${e2.message}")
                    }
                }
            }
        }
    }
}