package com.hanko.mobile

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * A home-screen entry, one per theme (see AndroidManifest.xml): opens
 * MainActivity and finishes at once, before drawing anything. Re-tapping the
 * icon resumes the existing task, as with any launcher activity.
 */
open class IconTrampoline : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(Intent(this, MainActivity::class.java))
        finish()
        // No transition: the trampoline itself should never be seen.
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }
}

class IconPaper : IconTrampoline()
class IconDark : IconTrampoline()
class IconBlue : IconTrampoline()
